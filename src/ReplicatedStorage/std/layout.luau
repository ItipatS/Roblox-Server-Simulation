--!strict
-- Count-aware geometry, shared by the client (fieldeval) and the server (Mode wall hits,
-- Leaders boid bounds). Areas scale with the particle count so density stays ~constant as
-- you add/remove dust — instead of cramming 7000 dust into a fixed 16-stud box.

local M = {}

-- Ocean / Shore: OCEAN_LAYERS stacked square sheets at fixed spacing, so the sheet area
-- grows with count.
M.OCEAN_LAYERS = 4
M.OCEAN_SPACING = 3.0 -- target studs between dust on a sheet
M.OCEAN_TOP_Y = 3.5 -- surface height (lowered so you wade in it, not under the sky)
M.OCEAN_LAYER_GAP = 1.0 -- studs between depth sheets

function M.ocean(n: number): (number, number, number)
	local perLayer = math.ceil(n / M.OCEAN_LAYERS)
	local cols = math.ceil(math.sqrt(perLayer))
	local rows = math.ceil(perLayer / cols)
	return perLayer, cols, rows
end

-- Wall: a dense N×N×N cube at fixed spacing, centered on X/Z = 0 and sitting on WALL_FLOOR
-- — so the cube grows with count instead of getting denser.
M.WALL_SPACING = 2
M.WALL_FLOOR = 1
function M.wallN(n: number): number
	return math.ceil(n ^ (1 / 3))
end
function M.wallHalf(n: number): number
	return (M.wallN(n) - 1) * M.WALL_SPACING * 0.5
end

-- Hunt: a scattered cloud whose extent grows with the cube root of count (constant
-- volumetric density). The same box bounds the server's boids, so predators always cover
-- the cloud. Constants chosen so n = 3000 reproduces the old 45-half / 25-tall cloud.
M.FLOCK_FLOOR = 3
local FLOCK_A = 3.12 -- half-width per cbrt(n)
local FLOCK_B = 1.73 -- height per cbrt(n)
function M.flockHalf(n: number): number
	return FLOCK_A * n ^ (1 / 3)
end
function M.flockHeight(n: number): number
	return FLOCK_B * n ^ (1 / 3)
end

-- Spread (contagion): a dense scattered slab — wide in X/Z, shallow in Y — so a wildfire
-- front sweeps across it legibly from above. Positions are STATIC and derived from slot,
-- so the server hashes them and the client renders them with no position on the wire;
-- only the emergent per-dust heat is streamed.
M.SPREAD_SPACING = 1.6 -- target mean spacing -> sets the slab size for the count
M.SPREAD_HEIGHT = 6 -- slab thickness (Y)
M.SPREAD_FLOOR = 2
M.SPREAD_RADIUS = 3.5 -- contagion neighbor radius (also the hash cell size)

function M.spreadHalf(n: number): number
	-- n points at SPREAD_SPACING in a slab of height SPREAD_HEIGHT -> square half-extent
	local area = n * M.SPREAD_SPACING ^ 3 / M.SPREAD_HEIGHT
	return 0.5 * math.sqrt(area)
end

-- Deterministic pseudo-random in [0,1).
local function hash01(seed: number): number
	local s = math.sin(seed * 12.9898) * 43758.5453
	return s - math.floor(s)
end
M.hash01 = hash01

-- Resting position of a spread dust. Pure function of slot + count, so the server (for the
-- hash) and the client (for rendering) place it identically.
function M.spreadHome(slot: number, n: number): Vector3
	local half = M.spreadHalf(n)
	local s = slot + 1
	local x = (hash01(s) * 2 - 1) * half
	local z = (hash01(s * 1.37 + 11.1) * 2 - 1) * half
	local y = M.SPREAD_FLOOR + hash01(s * 2.71 + 3.3) * M.SPREAD_HEIGHT
	return Vector3.new(x, y, z)
end

return M
