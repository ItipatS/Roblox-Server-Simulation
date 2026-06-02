--ServerScripterService/Systems/Network.luau
--!optimize 2
--!native
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local blink = require(game:GetService("ServerScriptService").ServerNet)
local std = ReplicatedStorage.std

local world = require(std.world)
local cts = require(std.components)
local scheduler = require(std.scheduler)
local phases = require(std.phases)
local mailbox = require(std.mailbox)
local Mode = require(script.Parent.Mode)

-- Network constants
local TICK_HZ = 12
local TICK = 1 / TICK_HZ
local FULL_SYNC_INTERVAL = 5
local MAX_BATCH_SIZE = 64

-- Delta quantization.
-- Each axis is sent as an i8 in fixed-point STEP-sized steps, so the dust id is
-- never transmitted: deltas are written densely in slot order and the client maps
-- slot -> entity from the spawn payload. STEP 0.02 -> ~2cm resolution, +/-2.54 studs
-- of motion per network tick (well above any real per-tick displacement).
local STEP = 0.02
local INV_STEP = 1 / STEP
local CHUNK = 256 -- slots per unreliable packet: 256 * 3 = 768 B, under the ~900 B cap
local WARP_THRESH = 25 -- a per-axis jump larger than this is an edge wrap -> send absolute

local lastFullSync = 0
local last_accum = 0

-- Per-slot send state. `lastSent` is the position the client has effectively
-- integrated from prior deltas; diffing against it both accumulates motion since the
-- last send and carries the sub-step quantization residual, so deltas never drift.
local lastSent: { [number]: Vector3 } = {}
local scratchPos: { [number]: Vector3 } = {}
local scratchEnt: { [number]: number } = {}
local warpFull = table.create(64)

local ToSendStateFull = table.create(128)
local ToSendState = table.create(MAX_BATCH_SIZE)

local dustQuery = world:query(cts.Transform, cts.Slot):with(cts.Dust):cached()
local stated_mob = world:query(cts.DustState):with(cts.Dust):cached()

local function flush(ev, arr)
	if #arr > 0 then
		ev.FireAll(arr)
		table.clear(arr)
	end
end

local function sendDeltas()
	table.clear(scratchPos)
	table.clear(scratchEnt)
	table.clear(warpFull)

	local maxSlot = -1
	for e, transform, slot in dustQuery do
		scratchPos[slot] = transform.new.Position
		scratchEnt[slot] = e
		if slot > maxSlot then
			maxSlot = slot
		end
	end
	if maxSlot < 0 then
		return
	end

	for base = 0, maxSlot, CHUNK do
		local hi = math.min(base + CHUNK - 1, maxSlot)
		local deltas = table.create((hi - base + 1) * 3)
		local di = 0
		for slot = base, hi do
			local pos = scratchPos[slot]
			if pos then
				local last = lastSent[slot]
				if not last then
					last = pos
					lastSent[slot] = pos
				end
				local dx = pos.X - last.X
				local dy = pos.Y - last.Y
				local dz = pos.Z - last.Z
				if
					dx > WARP_THRESH
					or dx < -WARP_THRESH
					or dy > WARP_THRESH
					or dy < -WARP_THRESH
					or dz > WARP_THRESH
					or dz < -WARP_THRESH
				then
					-- edge wrap / teleport: i8 can't carry it; send an absolute and zero the delta
					warpFull[#warpFull + 1] = { id = scratchEnt[slot], dp = pos }
					lastSent[slot] = pos
					deltas[di + 1] = 0
					deltas[di + 2] = 0
					deltas[di + 3] = 0
				else
					local qx = math.clamp(math.round(dx * INV_STEP), -127, 127)
					local qy = math.clamp(math.round(dy * INV_STEP), -127, 127)
					local qz = math.clamp(math.round(dz * INV_STEP), -127, 127)
					deltas[di + 1] = qx
					deltas[di + 2] = qy
					deltas[di + 3] = qz
					-- advance by the quantized amount so the residual carries to next tick
					lastSent[slot] = Vector3.new(last.X + qx * STEP, last.Y + qy * STEP, last.Z + qz * STEP)
				end
			else
				-- gap in the slot range (shouldn't happen for a contiguous field)
				deltas[di + 1] = 0
				deltas[di + 2] = 0
				deltas[di + 3] = 0
			end
			di += 3
		end
		blink.UpdateTransformDelta.FireAll({ base = base, deltas = deltas })
	end

	if #warpFull > 0 then
		blink.UpdateTransformFull.FireAll(warpFull)
		table.clear(warpFull)
	end
end

local function networkSystem(dt: number)
	lastFullSync += dt
	last_accum += dt

	if last_accum < TICK then
		return
	end
	last_accum = 0

	if not Mode.streamPositions() then
		-- A presentation mode (e.g. Ocean) owns visuals; clients render the field
		-- locally from slot + synced clock, so we send nothing on the position channel.
		return
	end

	if Mode.consumeResync() then
		-- Returning to Drift: clients were rendering locally and the server sim kept
		-- drifting. Drop the delta baseline and force a full snapshot this tick.
		table.clear(lastSent)
		lastFullSync = FULL_SYNC_INTERVAL
	end

	sendDeltas()

	-- State updates (reliable) — only fleeing dust, low volume
	table.clear(ToSendState)
	mailbox.drain(cts.PendingStates, function(item)
		if not item then
			return
		end
		ToSendState[#ToSendState + 1] = item
		if #ToSendState >= MAX_BATCH_SIZE then
			flush(blink.UpdateDustState, ToSendState)
		end
	end)
	flush(blink.UpdateDustState, ToSendState)

	-- Periodic absolute snapshot (reliable) to clear any accumulated drift.
	if lastFullSync >= FULL_SYNC_INTERVAL then
		lastFullSync = 0

		local fullBatch = table.create(128)
		for e, transform, slot in dustQuery do
			local pos = transform.new.Position
			lastSent[slot] = pos -- rebase so deltas resume from the corrected position
			fullBatch[#fullBatch + 1] = { id = e, dp = pos }
			if #fullBatch >= 128 then
				blink.UpdateTransformFull.FireAll(fullBatch)
				table.clear(fullBatch)
			end
		end
		if #fullBatch > 0 then
			blink.UpdateTransformFull.FireAll(fullBatch)
		end

		table.clear(ToSendStateFull)
		for e, state in stated_mob do
			ToSendStateFull[#ToSendStateFull + 1] = {
				id = e,
				isFleeing = state.isFleeing,
				fleeTimer = state.fleeTimer,
			}
			if #ToSendStateFull >= 128 then
				blink.UpdateDustState.FireAll(ToSendStateFull)
				table.clear(ToSendStateFull)
			end
		end
		flush(blink.UpdateDustState, ToSendStateFull)
	end
end

scheduler.SYSTEM(networkSystem, phases.NetworkDelta)

return {}
