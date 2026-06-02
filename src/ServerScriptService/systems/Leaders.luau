-- ServerScriptService/Systems/Leaders.luau
--!optimize 2
--!native
--!strict
--
-- The authoritative half of Hunt mode. The server fully simulates a small flock of
-- predator boids (separation / alignment / cohesion + wander + soft bounds) — genuinely
-- emergent and non-deterministic — and streams just their positions. Dozens of f16
-- vectors per tick is tiny, yet it drives the 3000 client-side dust. This is the bridge:
-- real server authority over a small set, scale handled cheaply on the client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local std = ReplicatedStorage.std

local blink = require(game:GetService("ServerScriptService").ServerNet)
local scheduler = require(std.scheduler)
local config = require(std.config)
local layout = require(std.layout)
local Modes = require(std.modes)
local Mode = require(script.Parent.Mode)
local DustCount = require(script.Parent.DustCount)

local N = config.LEADER_COUNT

-- Roaming box (half-width, floor, ceiling) — scales with the live dust count so the flock
-- always covers the cloud the client lays out from the same formula.
local function bounds(): (number, number, number)
	local n = DustCount.n
	local y0 = layout.FLOCK_FLOOR
	return layout.flockHalf(n), y0, y0 + layout.flockHeight(n)
end

local SIM_HZ = 20
local SIM_DT = 1 / SIM_HZ

-- boid tuning
local NEIGHBOR2 = 16 * 16
local SEP2 = 7 * 7
local MINSPEED = 9
local MAXSPEED = 22
local SEP_W = 1.6
local ALI_W = 1.0
local COH_W = 0.9
local WANDER = 7
local BOUND_STEER = 32

type Boid = { pos: Vector3, vel: Vector3 }
local boids: { Boid } = table.create(N)
local positions = table.create(N)

local function rr(a: number, b: number): number
	return a + math.random() * (b - a)
end

do
	local half, y0, y1 = bounds()
	for i = 1, N do
		boids[i] = {
			pos = Vector3.new(rr(-half, half), rr(y0, y1), rr(-half, half)),
			vel = Vector3.new(rr(-1, 1), rr(-0.3, 0.3), rr(-1, 1)).Unit * MINSPEED,
		}
	end
end

local function clampSpeed(v: Vector3): Vector3
	local m = v.Magnitude
	if m < 1e-4 then
		return v
	elseif m > MAXSPEED then
		return v * (MAXSPEED / m)
	elseif m < MINSPEED then
		return v * (MINSPEED / m)
	end
	return v
end

local acc = 0
local function leaderSystem(dt: number)
	acc += dt
	if acc < SIM_DT then
		return
	end
	local step = acc
	acc = 0
	if Mode.getMode() ~= Modes.Hunt then
		return -- only run the flock while Hunt is active
	end

	local half, y0, y1 = bounds()
	for i = 1, N do
		local bi = boids[i]
		local sep = Vector3.zero
		local ali = Vector3.zero
		local coh = Vector3.zero
		local n = 0
		for j = 1, N do
			if i ~= j then
				local off = bi.pos - boids[j].pos
				local d2 = off:Dot(off)
				if d2 < NEIGHBOR2 then
					ali += boids[j].vel
					coh += boids[j].pos
					n += 1
					if d2 < SEP2 and d2 > 1e-4 then
						sep += off / d2
					end
				end
			end
		end

		local steer = Vector3.zero
		if n > 0 then
			ali /= n
			coh = (coh / n) - bi.pos
			steer += sep * SEP_W + ali * ALI_W + coh * COH_W
		end
		steer += Vector3.new(rr(-1, 1), rr(-0.5, 0.5), rr(-1, 1)) * WANDER

		-- soft bounds: steer back toward the box
		if bi.pos.X > half then
			steer += Vector3.new(-BOUND_STEER, 0, 0)
		elseif bi.pos.X < -half then
			steer += Vector3.new(BOUND_STEER, 0, 0)
		end
		if bi.pos.Z > half then
			steer += Vector3.new(0, 0, -BOUND_STEER)
		elseif bi.pos.Z < -half then
			steer += Vector3.new(0, 0, BOUND_STEER)
		end
		if bi.pos.Y > y1 then
			steer += Vector3.new(0, -BOUND_STEER, 0)
		elseif bi.pos.Y < y0 then
			steer += Vector3.new(0, BOUND_STEER, 0)
		end

		bi.vel = clampSpeed(bi.vel + steer * step)
		bi.pos += bi.vel * step
	end

	for i = 1, N do
		positions[i] = boids[i].pos
	end
	blink.LeaderState.FireAll(positions)
end

scheduler.SYSTEM(leaderSystem)

return {}
