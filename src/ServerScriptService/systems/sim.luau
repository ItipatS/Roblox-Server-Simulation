-- ServerScriptService/Systems/DustSim.luau
--!optimize 2
--!native
--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local std = ReplicatedStorage.std
local world = require(std.world)
local cts = require(std.components)
local scheduler = require(std.scheduler)
local phases = require(std.phases)
local mailbox = require(std.mailbox)

local Dust = cts.Dust
local Transform = cts.Transform
local Direction = cts.Direction
local DustData = cts.DustData
local DustState = cts.DustState
local DustDrag = cts.DustDrag
local Velocity = cts.Velocity

local Character = cts.Character
local PlayerTag = cts.Player

local DUST_SPEED = 2
local SIM_TICK_HZ = 20
local SIM_TICK = 1 / SIM_TICK_HZ
local WARP_AREA_SIZE = 50
local PLAYER_PUSH_RADIUS = 5
local PLAYER_PUSH_FORCE = 10
local STOP_Y_MIN = .75
local STOP_Y_MAX = 15

local FLEE_ANTICIPATION = .5
local FLEE_RADIUS        = 10
local MIN_FLEE_SPEED     = 10
local NEIGHBOR_FLEE_RADIUS = 5

local EPS = 1e-4

local newFleers = table.create(128)

local last_accum = 0

local dustQuery = world
    :query(Transform, DustData, DustState, DustDrag, Velocity, Direction)
    :with(Dust)
    :cached()

local characters = world
    :query(Character)
    :with(PlayerTag)
    :cached()

local function wrapAxis(v: number): (number, boolean)
    local range = WARP_AREA_SIZE * 2
    if v > WARP_AREA_SIZE then
        return v - range, true
    elseif v < -WARP_AREA_SIZE then
        return v + range, true
    end
    return v, false
end

local function buildPlayerCache(): { [Player]: { pos: Vector3, speed: number, vel: Vector3 } }
    local cached = {}
    for _, char in characters do
        local player: Player? = nil
        for _, p in Players:GetPlayers() do
            if p.Character == char then
                player = p
                break
            end
        end

        if player then
            local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if root and humanoid then
                local moveDir = humanoid.MoveDirection
                local speed = moveDir.Magnitude * humanoid.WalkSpeed
                local vel = moveDir * humanoid.WalkSpeed -- direction + speed

                cached[player] = {
                    pos   = root.Position,
                    speed = speed,
                    vel   = vel,
                }
            end
        end
    end
    return cached
end


local function dustSystem(dt: number)
    last_accum += dt
    if last_accum < SIM_TICK then return end

    local step_dt = last_accum
    last_accum = 0

    local playerCache = buildPlayerCache()
	table.clear(newFleers)

    for e, transform, data, state, drag, velocity, dir in dustQuery do
        local cf = transform.new
        local pos = cf.Position
        local lastPos = pos

        local speed = velocity or DUST_SPEED

		 --[[if drag.draggerUserId and drag.targetPos then
            -- Dragged by player
            local targetPos = drag.targetPos
            local alpha = math.clamp(step_dt * 10, 0, 1)
            pos = pos:Lerp(targetPos, alpha)

            state.isFleeing = true
            state.fleeTimer = math.max(state.fleeTimer, 2)
        else
		]]--
			----------------------------------------------------------------
			-- 1. Normal movement
			----------------------------------------------------------------

        -- Free drift
            pos += dir * speed * step_dt
            pos += Vector3.new(0, -0.5 * step_dt, 0) -- gravity

            ----------------------------------------------------------------
            -- 2. Soft speed cap (similar to old MAX_ALLOWED_SPEED logic)
            ----------------------------------------------------------------
            local MAX_ALLOWED_SPEED = 10
            if speed > MAX_ALLOWED_SPEED then
                speed = math.clamp(speed - step_dt * 10, MAX_ALLOWED_SPEED, speed)
                speed *= 0.5
            end

            ----------------------------------------------------------------
            -- 3. Vertical bounce
            ----------------------------------------------------------------
            if pos.Y < STOP_Y_MIN then
                dir = Vector3.new(dir.X, math.abs(dir.Y), dir.Z)
                pos = Vector3.new(pos.X, STOP_Y_MIN, pos.Z)
            elseif pos.Y > STOP_Y_MAX then
                dir = Vector3.new(dir.X, -math.abs(dir.Y), dir.Z)
                pos = Vector3.new(pos.X, STOP_Y_MAX, pos.Z)
            end

            ----------------------------------------------------------------
            -- 4. Warp edges
            ----------------------------------------------------------------
            local x, xWarped = wrapAxis(pos.X)
            local z, zWarped = wrapAxis(pos.Z)
            pos = Vector3.new(x, pos.Y, z)

        --end

        ----------------------------------------------------------------
        -- 5. Player push & flee (self only; neighbor chain is TODO)
        ----------------------------------------------------------------
        for _, info in pairs(playerCache) do
            -- vector from player -> dust
            local playerToDust = pos - info.pos
            local distNow = playerToDust.Magnitude

            -- predict where the player will be shortly
            local predictedPos   = info.pos + info.vel * FLEE_ANTICIPATION
            local playerToDustFuture = pos - predictedPos
            local distFuture = playerToDustFuture.Magnitude

            -- is the player actually moving TOWARDS this dust?
            -- (if dot > 0, velocity has a component along player->dust)
            local approaching = info.vel:Dot(playerToDust) > 0

            if approaching
                and info.speed > MIN_FLEE_SPEED
                and distFuture < FLEE_RADIUS
            then
                -- direction away from where the player is *heading*, not where they are now
                local fleeDir = playerToDustFuture.Unit
                dir = (dir + fleeDir * 0.6).Unit  -- blend a bit towards flee vector
                speed = math.max(speed, DUST_SPEED * 1.5)

                if not state.isFleeing then
                    state.isFleeing = true
                    state.fleeTimer = 2
                else
                    state.fleeTimer = math.max(state.fleeTimer, 2)
                end
            end

            if distNow < PLAYER_PUSH_RADIUS and info.speed > 10 then
                local pushStrength = math.clamp(info.speed / 16, 0, PLAYER_PUSH_FORCE)
                local pushDir = playerToDust.Unit

                local pushForce = pushDir * pushStrength * 5
                dir = (dir + pushForce).Unit
                speed = math.clamp(speed + pushStrength * 1.05, 0, 20)

                if not state.isFleeing then
                    state.isFleeing = true
                    state.fleeTimer = 2
                else
                    state.fleeTimer = math.max(state.fleeTimer, 2)
                end
            end
        end

        ----------------------------------------------------------------
        -- 6. Update flee timer & send state to network
        ----------------------------------------------------------------

        local dp = pos - lastPos

        transform.new = CFrame.lookAt(pos, pos + dir)

        if dp.Magnitude > EPS then
            mailbox.push(cts.PendingMovements, {
                id = e,
                dp = dp,
            })
        end

        if xWarped or zWarped then
            dp = Vector3.zero
        end

        if state.isFleeing then
            state.fleeTimer -= step_dt
            if state.fleeTimer <= 0 then
                state.isFleeing = false
                state.fleeTimer = 0
            end

            mailbox.push(cts.PendingStates, {
                id = e,
                isFleeing = state.isFleeing,
                fleeTimer = state.fleeTimer,
            })
        end

        world:set(e, Velocity, speed)
        world:set(e, Direction, dir)
        world:set(e, Transform, transform)
        world:set(e, DustState, state)
    end

	if #newFleers > 0 then
        for e, transform, data, state, drag, speed in dustQuery do
            if not state.isFleeing then
                local pos = transform.new.Position

                for _, src in ipairs(newFleers) do
                    local d = (pos - src.pos).Magnitude
                    if d < NEIGHBOR_FLEE_RADIUS then
                        state.isFleeing = true
                        state.fleeTimer = 1.5 + math.random() * 0.5

                        mailbox.push(cts.PendingStates, {
                            id = e,
                            isFleeing = state.isFleeing,
                            fleeTimer = state.fleeTimer,
                        })

                        world:set(e, cts.DustState, state)
                        break
                    end
                end
            end
        end
    end
end


scheduler.SYSTEM(dustSystem, phases.GameLogic)

return {}
