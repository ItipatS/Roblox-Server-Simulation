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
local DustData = cts.DustData
local DustState = cts.DustState
local DustDrag = cts.DustDrag

local Character = cts.Character
local PlayerTag = cts.Player

local DUST_SPEED = 2
local SIM_TICK_HZ = 20
local SIM_TICK = 1 / SIM_TICK_HZ
local WARP_AREA_SIZE = 100
local PLAYER_PUSH_RADIUS = 5
local PLAYER_PUSH_FORCE = 10
local STOP_Y_MIN = 0.5
local STOP_Y_MAX = 15
local EPS = 1e-4

local last_accum = 0

local dustQuery = world
    :query(Transform, DustData, DustState, DustDrag)
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

local function buildPlayerCache(): { [Player]: { pos: Vector3, speed: number } }
    local cached = {}
    for _, char in characters do
        local player: Player? = nil
        -- you might have a better mapping between Character & Player
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
                local speed = humanoid.MoveDirection.Magnitude * humanoid.WalkSpeed
                cached[player] = {
                    pos = root.Position,
                    speed = speed,
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

    for e, transform, data, state, drag in dustQuery do
        local cf = transform.new
        local pos = cf.Position
        local lastPos = pos

        -- Drag vs free drift
        if drag.draggerUserId and drag.targetPos then
            -- authoritative drag
            local targetPos = drag.targetPos
            local alpha = math.clamp(step_dt * 10, 0, 1)
            pos = pos:Lerp(targetPos, alpha)
            state.isFleeing = true
            state.fleeTimer = math.max(state.fleeTimer, 2)
        else
            -- free drift + gravity
            local dir = cf.LookVector
            pos += dir * DUST_SPEED * step_dt
            pos += Vector3.new(0, -0.5 * step_dt, 0)

            -- vertical bounce
            if pos.Y < STOP_Y_MIN then
                pos = Vector3.new(pos.X, STOP_Y_MIN, pos.Z)
            elseif pos.Y > STOP_Y_MAX then
                pos = Vector3.new(pos.X, STOP_Y_MAX, pos.Z)
            end

            -- warp edges
            local x, xWarped = wrapAxis(pos.X)
            local z, zWarped = wrapAxis(pos.Z)
            pos = Vector3.new(x, pos.Y, z)
            if xWarped or zWarped then
                lastPos = pos
            end
        end

        -- Player push & flee
        for _, info in pairs(playerCache) do
            local dist = (info.pos - pos).Magnitude
            if dist < PLAYER_PUSH_RADIUS and info.speed > 10 then
                local pushStrength = math.clamp(info.speed / 16, 0, PLAYER_PUSH_FORCE)
                local pushDir = (pos - info.pos).Unit
                local delta = pushDir * pushStrength * step_dt
                pos += delta

                state.isFleeing = true
                state.fleeTimer = math.max(state.fleeTimer, 2)
            end
        end

        -- Update flee timer
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

        -- write back to ECS
        if (pos - lastPos).Magnitude > EPS then
            transform.new = CFrame.new(pos, cf.LookVector)
            -- push dp to shared PendingMovements mailbox
            mailbox.push(cts.PendingMovements, {
                id = e,
                dp = pos - lastPos,
            })
        end

        -- store updated components (only needed if you mutated tables, but we did)
        world:set(e, Transform, transform)
        world:set(e, DustState, state)
    end
end

scheduler.SYSTEM(dustSystem, phases.GameLogic)

return {}
