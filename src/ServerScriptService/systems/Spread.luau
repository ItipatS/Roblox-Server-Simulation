-- ServerScriptService/Systems/Spread.luau
--!optimize 2
--!native
--!strict
--
-- Server-authoritative contagion. Every dust holds its own state (heat + fuel) and reacts
-- to its NEIGHBORS via the spatial hash — a genuine N-body interaction no client formula
-- could reproduce. A forest-fire model: an unburnt dust with a hot neighbor catches,
-- ramps up while it burns through its fuel, then cools to an ember. The result is a ragged
-- travelling front that follows the field's actual density and leaves a trail — the tells
-- that say "this is tracked, not rendered." Only the heat scalar is streamed (positions
-- are a static formula); watching that data flow IS the demonstration.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local std = ReplicatedStorage.std

local blink = require(game:GetService("ServerScriptService").ServerNet)
local scheduler = require(std.scheduler)
local layout = require(std.layout)
local Modes = require(std.modes)
local SpatialHash = require(std.spatialhash)
local Mode = require(script.Parent.Mode)
local DustCount = require(script.Parent.DustCount)

local SIM_HZ = 15
local SIM_DT = 1 / SIM_HZ
local RADIUS = layout.SPREAD_RADIUS
local R2 = RADIUS * RADIUS

local IGNITE_THRESH = 0.55 -- neighbor heat needed to catch (higher -> slower front)
local CATCH_RATE = 1.2 -- how fast a burning dust ramps to full heat (lower -> slower front)
local BURN_RATE = 0.55 -- fuel consumed per second while burning
local COOL_RATE = 0.7 -- heat lost per second once fuel is gone
local REGROW_RATE = 0.06 -- fuel regrows slowly so the field can burn again
local PLAYER_IGNITE_R = 7 -- players set fire to dust within this radius
local PIR2 = PLAYER_IGNITE_R * PLAYER_IGNITE_R
local CHUNK = 512 -- heat values per unreliable packet (<900 B)

local hash = SpatialHash.new(RADIUS)
local px: { number } = {}
local py: { number } = {}
local pz: { number } = {}
local heat: { number } = {} -- 0..1
local fuel: { number } = {} -- 0..1
local nheat: { number } = {} -- next-frame heat (double buffered)
local neigh = table.create(512)

local count = -1

-- (Re)build the static field + hash for a new dust count. Positions never change, so the
-- hash is built once here, not per tick.
local function rebuild(n: number)
	count = n
	hash:beginFrame()
	for slot = 0, n - 1 do
		local home = layout.spreadHome(slot, n)
		px[slot], py[slot], pz[slot] = home.X, home.Y, home.Z
		heat[slot] = 0
		fuel[slot] = 1
		hash:insert(slot, home.X, home.Y, home.Z)
	end
end

local acc = 0
local function spreadSystem(dt: number)
	acc += dt
	if acc < SIM_DT then
		return
	end
	local step = acc
	acc = 0
	if Mode.getMode() ~= Modes.Spread then
		return
	end

	local n = DustCount.n
	if n ~= count then
		rebuild(n)
	end

	-- ignition: players set nearby dust alight (uses the hash for the lookup)
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local rp = root.Position
			local c = hash:queryInto(rp.X, rp.Y, rp.Z, neigh)
			for k = 1, c do
				local j = neigh[k]
				local dx, dy, dz = px[j] - rp.X, py[j] - rp.Y, pz[j] - rp.Z
				if dx * dx + dy * dy + dz * dz < PIR2 and fuel[j] > 0.2 then
					heat[j] = 1
				end
			end
		end
	end

	-- spread + burn + cool (synchronous update: read heat, write nheat)
	for slot = 0, n - 1 do
		local h = heat[slot]
		local f = fuel[slot]
		local x, y, z = px[slot], py[slot], pz[slot]

		-- hottest neighbor within the contagion radius
		local maxN = 0
		local c = hash:queryInto(x, y, z, neigh)
		for k = 1, c do
			local j = neigh[k]
			if j ~= slot then
				local dx, dy, dz = px[j] - x, py[j] - y, pz[j] - z
				if dx * dx + dy * dy + dz * dz < R2 then
					local hj = heat[j]
					if hj > maxN then
						maxN = hj
					end
				end
			end
		end

		if h > 0.05 then
			-- burning: consume fuel, climb to full, then cool once spent
			f -= BURN_RATE * step
			if f > 0 then
				h = math.min(1, h + CATCH_RATE * step)
			else
				f = 0
				h = math.max(0, h - COOL_RATE * step)
			end
		elseif f > 0.3 and maxN > IGNITE_THRESH then
			h = 0.1 -- a hot neighbor ignites us
		else
			f = math.min(1, f + REGROW_RATE * step) -- regrow fuel to burn again later
		end

		nheat[slot] = h
		fuel[slot] = f
	end

	for slot = 0, n - 1 do
		heat[slot] = nheat[slot]
	end

	-- stream the heat scalar densely (this is the server state crossing the wire)
	for base = 0, n - 1, CHUNK do
		local hi = math.min(base + CHUNK - 1, n - 1)
		local arr = table.create(hi - base + 1)
		for slot = base, hi do
			arr[#arr + 1] = math.clamp(math.floor(heat[slot] * 255 + 0.5), 0, 255)
		end
		blink.UpdateHeat.FireAll({ base = base, heat = arr })
	end
end

scheduler.SYSTEM(spreadSystem)

return {}
