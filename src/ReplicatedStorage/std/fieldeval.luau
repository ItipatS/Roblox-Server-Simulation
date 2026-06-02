--!optimize 2
--!native
--!strict
--
-- Client-side presentation field. The whole point: instead of streaming per-particle
-- motion, the server broadcasts only the *mode* (and one-shot events like a splash),
-- and every client reconstructs a coherent field as a pure function of:
--     slot index  +  workspace:GetServerTimeNow()  +  active events
-- Because the clock is server-synced, all clients agree without sending positions.
-- Coherent (neighbours correlate) is what makes it read as "controlled" — and it's
-- also why it's nearly free on the wire.
--
-- Two water modes share this evaluator, differing only by a per-mode profile:
--   Ocean — rolling waves, deeper layers, a bow-wave bulge under each player.
--   Shore — calm shallow water; walking sheds footstep splashes, jumping a bigger one.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local Modes = require(script.Parent.modes)
local config = require(script.Parent.config)
local layout = require(script.Parent.layout)

local M = {}

-- Current mode (mirrors the server). Default Drift = server streams positions.
M.mode = Modes.Drift :: number

-- Hunt mode: leader (predator) positions, streamed from the server and written here by
-- the client Leaders system. The dust read this array to flee them. Index = leader id.
M.leaders = {} :: { Vector3 }

-- Spread mode: per-slot heat (0..1), written by the client Spread system from the streamed
-- u8 channel. This is server-authoritative emergent state — not a formula.
M.heat = {} :: { number }

-- ---- Layout ----------------------------------------------------------------
-- All geometry scales with the live dust count (formulas in std.layout) so density holds
-- as dust is added/removed. Recomputed by setCount(); the server uses the same formulas.
local LAYERS = layout.OCEAN_LAYERS
local LAYER_GAP = layout.OCEAN_LAYER_GAP
local TOP_Y = layout.OCEAN_TOP_Y
local SPACING = layout.OCEAN_SPACING

local TOTAL, PER_LAYER, COLS, ROWS, HALF_X, HALF_Z
local WALL_N, WALL_SP, WALL_HALF, WALL_CY
local FLOCK_HALF, FLOCK_Y0, FLOCK_Y1
local function recomputeLayout(n: number)
	TOTAL = n
	PER_LAYER, COLS, ROWS = layout.ocean(n)
	HALF_X = (COLS - 1) * SPACING * 0.5
	HALF_Z = (ROWS - 1) * SPACING * 0.5

	WALL_N = layout.wallN(n)
	WALL_SP = layout.WALL_SPACING
	WALL_HALF = layout.wallHalf(n)
	WALL_CY = layout.WALL_FLOOR + WALL_HALF

	FLOCK_HALF = layout.flockHalf(n)
	FLOCK_Y0 = layout.FLOCK_FLOOR
	FLOCK_Y1 = layout.FLOCK_FLOOR + layout.flockHeight(n)
end
recomputeLayout(config.MAX_DUST)

-- ---- Shared wave / ripple shape --------------------------------------------
local WAVE_K = 0.16 -- spatial frequency
local WAVE_W = 1.15 -- temporal frequency (rad/s)

local RIPPLE_SPEED = 26 -- studs/s the ring travels outward
local RIPPLE_K = 0.55 -- crest tightness
local RIPPLE_WIDTH = 8 -- studs, gaussian band around the ring
local RIPPLE_LIFE = 1.7 -- seconds before it fully decays
local RIPPLE_AMP = 3.4 -- base splash height (scaled per-ripple by .amp)

-- Player bulge (Ocean): a mound that leads the character in their movement direction.
local WAKE_AMP = 3.0
local WAKE_SIGMA = 4.0
local WAKE_R2 = (WAKE_SIGMA * 3) * (WAKE_SIGMA * 3)
local WAKE_LEAD = 0.16

-- Wall shockwave: a hit sends a ring across the curtain that bursts dust out along the
-- normal (Z) and recolors the front into a hue gradient by distance from the hit.
local WALL_RING_SPEED = 7 -- studs/s the shell expands (slow + majestic)
local WALL_RING_WIDTH = 7 -- studs, band around the front
local WALL_RING_LIFE = 4.5 -- seconds the shockwave lingers (well past the 1.7s splash)
local WALL_RING_AMP = 4 -- how far dust bursts out of the block
local WALL_SPREAD = 3 -- in-plane radial shove right at the hit point
local WALL_SPREAD_SIGMA = 6
local WALL_SPREAD_LIFE = 0.6
local WALL_HUE_SCALE = 0.03 -- hue cycles per stud of distance -> gradient banding
local WALL_BASE = Color3.fromRGB(228, 230, 236) -- untinted resting block
local MAX_RIPPLE_LIFE = math.max(RIPPLE_LIFE, WALL_RING_LIFE) -- prune horizon for both

-- Hunt mode: dust rest scattered in a cloud (geometry from layout) and flee leaders.
local FLOCK_R = 12 -- leader influence radius
local FLOCK_PUSH = 11 -- how hard dust are shoved away at point-blank
local FLOCK_BASE = Color3.fromRGB(120, 180, 255) -- calm cloud
local FLOCK_THREAT = Color3.fromRGB(255, 95, 60) -- flash as a leader bears down

-- ---- Per-mode profiles -----------------------------------------------------
type Profile = {
	waveAmp: number, -- base surface amplitude
	wake: boolean, -- bulge under players (Ocean) vs none (Shore)
	stride: number, -- studs of travel between footstep splashes (0 = none)
	footAmp: number, -- footstep ripple strength
	surface: Color3,
	deep: Color3,
	foam: Color3,
}

local PROFILE: { [number]: Profile } = {
	[Modes.Ocean] = {
		waveAmp = 2.2,
		wake = true,
		stride = 0,
		footAmp = 0,
		surface = Color3.fromRGB(46, 150, 230),
		deep = Color3.fromRGB(6, 26, 74),
		foam = Color3.fromRGB(225, 245, 255),
	},
	[Modes.Shore] = {
		waveAmp = 0.7,
		wake = false,
		stride = 3.5,
		footAmp = 0.6,
		surface = Color3.fromRGB(64, 196, 206),
		deep = Color3.fromRGB(20, 96, 126),
		foam = Color3.fromRGB(238, 250, 255),
	},
}
local function profileFor(): Profile
	return PROFILE[M.mode] or PROFILE[Modes.Ocean]
end

-- Ripples carry the full 3D origin. Ocean/Shore use the horizontal (X,Z) of it; Wall
-- uses all three for a spherical wave.
type Ripple = { o: Vector3, born: number, amp: number }
local ripples: { Ripple } = {}

type PlayerSample = { x: number, z: number, vx: number, vz: number }
local playerSamples: { PlayerSample } = {}
local prevPos: { [Player]: Vector3 } = {}
local distAccum: { [Player]: number } = {}

function M.now(): number
	return Workspace:GetServerTimeNow()
end

function M.setMode(id: number)
	M.mode = id
	table.clear(ripples) -- every switch starts with no lingering disturbances
end

-- Recompute the grid for a new dust count (runtime dust-count control).
function M.setCount(n: number)
	recomputeLayout(n)
end

function M.addRipple(origin: Vector3, amp: number?)
	ripples[#ripples + 1] = { o = origin, born = M.now(), amp = amp or 1 }
end

-- Drop expired ripples; cheap, called once per water frame.
function M.prune(now: number)
	local i = 1
	while i <= #ripples do
		if now - ripples[i].born > MAX_RIPPLE_LIFE then
			ripples[i] = ripples[#ripples]
			ripples[#ripples] = nil
		else
			i += 1
		end
	end
end

-- Refresh per-player samples (position + velocity) and, in Shore, shed footstep
-- splashes as players move. Called once per water frame.
function M.refreshPlayers(dt: number)
	table.clear(playerSamples)
	local prof = profileFor()
	local stride = prof.stride
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local p = root.Position
			local prev = prevPos[plr]
			local vx, vz = 0, 0
			if prev and dt > 0 then
				vx = (p.X - prev.X) / dt
				vz = (p.Z - prev.Z) / dt
			end
			if stride > 0 and prev then
				local mx = p.X - prev.X
				local mz = p.Z - prev.Z
				local acc = (distAccum[plr] or 0) + math.sqrt(mx * mx + mz * mz)
				while acc >= stride do
					M.addRipple(p, prof.footAmp)
					acc -= stride
				end
				distAccum[plr] = acc
			end
			prevPos[plr] = p
			playerSamples[#playerSamples + 1] = { x = p.X, z = p.Z, vx = vx, vz = vz }
		end
	end
end

-- Resolve a slot to its (column,row,layer) rest position. Pure function of slot.
local function restOf(slot: number): (number, number, number)
	local layer = slot // PER_LAYER
	if layer >= LAYERS then
		layer = LAYERS - 1
	end
	local idx = slot - layer * PER_LAYER
	local col = idx % COLS
	local row = idx // COLS
	-- Offset each depth sheet diagonally so stacked layers interleave instead of
	-- sharing the same (x,z) columns (which would read as ~1/LAYERS the particle count).
	local off = layer / LAYERS
	local x = -HALF_X + (col + off) * SPACING
	local z = -HALF_Z + (row + off) * SPACING
	return x, z, layer
end

-- Sample the water for one slot at time `now`. Returns world position + color.
function M.oceanSample(slot: number, now: number): (Vector3, Color3)
	local prof = profileFor()
	local waveAmp = prof.waveAmp

	local x, z, layer = restOf(slot)
	local layer01 = if LAYERS > 1 then layer / (LAYERS - 1) else 0
	local ampLayer = waveAmp * (1 - layer01 * 0.5)
	local phase = WAVE_W * now

	-- two crossing wave trains -> rolling, non-repetitive surface
	local h = (math.sin(x * WAVE_K + phase) + math.cos(z * WAVE_K * 0.9 - phase * 0.85)) * ampLayer * 0.5

	-- splash ripples ride on top as outward-moving crests (horizontal plane of the origin)
	for _, r in ripples do
		local age = now - r.born
		if age >= 0 and age <= RIPPLE_LIFE then
			local dx = x - r.o.X
			local dz = z - r.o.Z
			local dist = math.sqrt(dx * dx + dz * dz)
			local front = dist - age * RIPPLE_SPEED
			local env = math.exp(-(front * front) / (2 * RIPPLE_WIDTH * RIPPLE_WIDTH)) * (1 - age / RIPPLE_LIFE)
			h += RIPPLE_AMP * r.amp * (1 - layer01 * 0.4) * math.sin(front * RIPPLE_K) * env
		end
	end

	-- Ocean only: a bulge that leads the character in their movement direction
	if prof.wake then
		for _, pl in playerSamples do
			local wx = x - pl.x - pl.vx * WAKE_LEAD
			local wz = z - pl.z - pl.vz * WAKE_LEAD
			local r2 = wx * wx + wz * wz
			if r2 < WAKE_R2 then
				h += WAKE_AMP * (1 - layer01 * 0.4) * math.exp(-r2 / (2 * WAKE_SIGMA * WAKE_SIGMA))
			end
		end
	end

	local y = TOP_Y - layer * LAYER_GAP + h

	-- color: deeper layer -> darker; crest/splash height -> foam white
	local h01 = math.clamp(0.5 + h / (2 * waveAmp), 0, 1)
	local base = prof.surface:Lerp(prof.deep, layer01)
	local foam = math.clamp((h01 - 0.72) / 0.28, 0, 1) * (1 - layer01 * 0.6)
	local color = base:Lerp(prof.foam, foam)

	return Vector3.new(x, y, z), color
end

-- ---- Wall mode -------------------------------------------------------------
-- Resolve a slot to its rest position on the upright curtain. Pure function of slot.
local function wallRestOf(slot: number): (number, number, number)
	local n = WALL_N
	local ix = slot % n
	local iy = (slot // n) % n
	local iz = slot // (n * n)
	-- cube centered on (0, WALL_CY, 0)
	local x = -WALL_HALF + ix * WALL_SP
	local y = WALL_CY - WALL_HALF + iy * WALL_SP
	local z = -WALL_HALF + iz * WALL_SP
	return x, y, z
end

-- Sample the wall for one slot. The cube rests untinted and still; each hit (kind 1
-- FieldEvent, stored as a full 3D origin) sends a spherical shell expanding through the
-- block — dust is shoved radially outward from the hit point and the passing front
-- recolors into a hue gradient.
function M.wallSample(slot: number, now: number): (Vector3, Color3)
	local rx, ry, rz = wallRestOf(slot)
	local ox, oy, oz = 0, 0, 0
	local heat, heatDist = 0, 0

	for _, r in ripples do
		local age = now - r.born
		if age >= 0 and age <= WALL_RING_LIFE then
			local dx = rx - r.o.X
			local dy = ry - r.o.Y
			local dz = rz - r.o.Z
			local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

			-- expanding spherical shell
			local front = dist - age * WALL_RING_SPEED
			local env = math.exp(-(front * front) / (2 * WALL_RING_WIDTH * WALL_RING_WIDTH)) * (1 - age / WALL_RING_LIFE)
			local push = WALL_RING_AMP * r.amp * math.sin(front * RIPPLE_K) * env

			-- localized burst right at the hit point ("spread out at player")
			local sEnv = math.exp(-(dist * dist) / (2 * WALL_SPREAD_SIGMA * WALL_SPREAD_SIGMA))
				* math.max(0, 1 - age / WALL_SPREAD_LIFE)
			local spread = WALL_SPREAD * r.amp * sEnv

			-- both act radially outward from the hit point (3D)
			if dist > 0.001 then
				local inv = (push + spread) / dist
				ox += dx * inv
				oy += dy * inv
				oz += dz * inv
			end

			-- the strongest active front here drives the gradient recolor
			local e2 = env * r.amp
			if e2 > heat then
				heat = e2
				heatDist = dist
			end
		end
	end

	local grad = Color3.fromHSV((heatDist * WALL_HUE_SCALE) % 1, 0.9, 1)
	local color = WALL_BASE:Lerp(grad, math.clamp(heat, 0, 1))
	return Vector3.new(rx + ox, ry + oy, rz + oz), color
end

-- ---- Hunt mode -------------------------------------------------------------
-- Deterministic pseudo-random in [0,1) so every client scatters the cloud identically.
local function hash01(n: number): number
	local s = math.sin(n * 12.9898) * 43758.5453
	return s - math.floor(s)
end

-- A dust's resting spot in the cloud, with a gentle breathing bob so it's alive even
-- when no leader is near. Pure function of slot + time.
local function flockHome(slot: number, now: number): (number, number, number)
	local s = slot + 1
	local x = (hash01(s) * 2 - 1) * FLOCK_HALF
	local z = (hash01(s * 1.37 + 11.1) * 2 - 1) * FLOCK_HALF
	local y = FLOCK_Y0 + hash01(s * 2.71 + 3.3) * (FLOCK_Y1 - FLOCK_Y0)
	local ph = s * 0.7
	x += math.sin(now * 0.6 + ph) * 0.8
	y += math.sin(now * 0.8 + ph * 1.3) * 0.6
	z += math.cos(now * 0.5 + ph) * 0.8
	return x, y, z
end

-- Sample one dust in Hunt mode: rest position shoved away from every nearby leader
-- (read from M.leaders, streamed by the server). Color flashes toward threat as a
-- leader closes in.
function M.flockSample(slot: number, now: number): (Vector3, Color3)
	local hx, hy, hz = flockHome(slot, now)
	local px, py, pz = 0, 0, 0
	local threat = 0

	for _, L in M.leaders do
		local dx = hx - L.X
		local dy = hy - L.Y
		local dz = hz - L.Z
		local d2 = dx * dx + dy * dy + dz * dz
		if d2 < FLOCK_R * FLOCK_R then
			local d = math.sqrt(d2)
			if d < 0.001 then
				d = 0.001
			end
			local t = 1 - d / FLOCK_R
			local inv = (FLOCK_PUSH * t) / d -- normalize + scale by closeness
			px += dx * inv
			py += dy * inv
			pz += dz * inv
			if t > threat then
				threat = t
			end
		end
	end

	local color = FLOCK_BASE:Lerp(FLOCK_THREAT, math.clamp(threat, 0, 1))
	return Vector3.new(hx + px, hy + py, hz + pz), color
end

-- ---- Spread mode -----------------------------------------------------------
-- Position is a static formula (so it isn't streamed); the heat is the server-tracked
-- emergent data, read from M.heat. Color is a fire ramp by heat: dim cool base -> red ->
-- orange -> white-hot.
local SPREAD_BASE = Color3.fromRGB(26, 34, 58)
local SPREAD_EMBER = Color3.fromRGB(255, 70, 24)
local SPREAD_HOT = Color3.fromRGB(255, 246, 210)

local function fireColor(h: number): Color3
	if h <= 0 then
		return SPREAD_BASE
	elseif h < 0.5 then
		return SPREAD_BASE:Lerp(SPREAD_EMBER, h / 0.5)
	end
	return SPREAD_EMBER:Lerp(SPREAD_HOT, (h - 0.5) / 0.5)
end

function M.spreadSample(slot: number, now: number): (Vector3, Color3)
	local home = layout.spreadHome(slot, TOTAL)
	-- gentle client-only shimmer so the field is alive; doesn't affect the server's hash
	local ph = (slot + 1) * 0.7
	local pos = home
		+ Vector3.new(math.sin(now * 0.7 + ph) * 0.25, math.sin(now * 0.9 + ph) * 0.15, math.cos(now * 0.6 + ph) * 0.25)
	return pos, fireColor(M.heat[slot] or 0)
end

return M
