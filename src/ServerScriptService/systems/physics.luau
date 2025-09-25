--!optimize 2
--!native
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local std = ReplicatedStorage.std
local world = require(std.world)
local cts = require(std.components)
local scheduler = require(std.scheduler)
local phases = require(std.phases)

local Transform = cts.Transform
local Velocity = cts.Velocity
local Gravity = cts.Gravity
local Knockback = cts.Knockback
local Collider = cts.Collider
local Grounded = cts.Grounded
local Mob = cts.Mob

-- =================== constants ===================
local GRAVITY_ACC          = -196.2              -- Roblox default
local TERMINAL_VY          = -200.0
local STEP_MAX_Y           = 0.5                 -- max “snap up” to ground (studs)
local GROUND_PROBE_UP      = 1.0                 -- start a little above feet
local GROUND_PROBE_DOWN    = 5.0                 -- how far we probe downward
local SKIN_WIDTH           = 0.05                -- small separation to avoid sinking
local GRID_SIZE            = 16                  -- spatial hashing cell size
local RESOLVE_ITERATIONS   = 1                   -- simple positional solve passes
local MAX_NEIGHBOR_CELLS   = 1                   -- 3x3 neighborhood

-- =================== helpers ===================
local function setPosPreserveRot(cf: CFrame, p: Vector3): CFrame
    -- Recompose with original orientation (no roll loss)
    -- CFrame.fromMatrix expects basis axes; Roblox LookVector is +Z (forward).
    return CFrame.fromMatrix(p, cf.RightVector, cf.UpVector, cf.LookVector)
end

local function moveBy(cf: CFrame, dp: Vector3): CFrame
    return setPosPreserveRot(cf, cf.Position + dp)
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.FilterDescendantsInstances = {} -- set externally if you want to ignore some things
groundParams.IgnoreWater = true

local function raycastGround(origin: Vector3, down: number): RaycastResult?
    return workspace:Raycast(origin, Vector3.new(0, -down, 0), groundParams)
end

-- =================== spatial grid ===================
local spatialGrid: {[string]: {number}} = {}
local function gridKey(x: number, z: number): string
    return string.format("%d,%d", x, z)
end

local function clearSpatialGrid()
    for k in spatialGrid do
        spatialGrid[k] = nil
    end
end

local function addToGrid(e: number, p: Vector3)
    local gx, gz = math.floor(p.X / GRID_SIZE), math.floor(p.Z / GRID_SIZE)
    local key = gridKey(gx, gz)
    local bin = spatialGrid[key]
    if not bin then
        bin = {}
        spatialGrid[key] = bin
    end
    bin[#bin+1] = e
end

local function getNearby(entityPos: Vector3): {number}
    local gx, gz = math.floor(entityPos.X / GRID_SIZE), math.floor(entityPos.Z / GRID_SIZE)
    local list = table.create(32)
    for dx = -MAX_NEIGHBOR_CELLS, MAX_NEIGHBOR_CELLS do
        for dz = -MAX_NEIGHBOR_CELLS, MAX_NEIGHBOR_CELLS do
            local bin = spatialGrid[gridKey(gx+dx, gz+dz)]
            if bin then
                for i = 1, #bin do 
                    list[#list+1] = bin[i] 
                end
            end
        end
    end
    return list
end

-- =================== queries ===================
local qGravity   = world:query(Transform, Gravity):with(Mob):cached()
local qXZ        = world:query(Transform, Velocity):with(Mob):cached()
local qKnockback = world:query(Transform, Knockback):with(Mob):cached()
local qColliders = world:query(Transform, Collider):with(Mob):cached()

-- =================== systems ===================

-- 1) Apply gravity (vertical integration only)
local function gravitySystem(dt: number)
    for e, tf, g in qGravity do
        if g.enabled ~= false then
            g.vy = math.max((g.vy or 0) + GRAVITY_ACC * dt, TERMINAL_VY)
            tf.new = moveBy(tf.new, Vector3.new(0, (g.vy or 0) * dt, 0))
        end
        -- clear grounded tag for now; grounding step will add it back if applicable
        if world:has(e, Grounded) then
            world:remove(e, Grounded)
        end
    end
end

-- 2) Integrate horizontal velocity (and optional y if you store it in Velocity)
local function integrateXZSystem(dt: number)
    for _, tf, vel in qXZ do
        local v = vel.v
        if v and (v.X ~= 0 or v.Z ~= 0 or v.Y ~= 0) then
            tf.new = moveBy(tf.new, v * dt)
        end
    end
end

-- 3) Apply knockback (additive positional)
local function knockbackSystem(dt: number)
    for e, tf, kb in qKnockback do
        tf.new = moveBy(tf.new, kb.force * dt)
        kb.remaining -= dt
        if kb.remaining <= 0 then
            world:unset(e, Knockback)
        end
    end
end

-- 4) Grounding (raycast down; snap up/down within small band; set vy=0)
local function groundingSystem(_dt: number)
    for e, tf, g in qGravity do
        local pos = tf.new.Position
        -- probe around feet (slightly above current pos)
        local origin = pos + Vector3.new(0, GROUND_PROBE_UP, 0)
        local res = raycastGround(origin, GROUND_PROBE_UP + GROUND_PROBE_DOWN)

        if res then
            -- accept hits on Terrain or BaseParts
            local inst = res.Instance
            if inst == workspace.Terrain or (inst and inst:IsA("BasePart")) then
                local hitY = res.Position.Y
                local targetY = hitY + SKIN_WIDTH
                local deltaY = targetY - pos.Y
                -- snap within band; if we fell through, bring us back up to surface
                if deltaY >= -STEP_MAX_Y and deltaY <= (GROUND_PROBE_DOWN + GROUND_PROBE_UP) then
                    tf.new = setPosPreserveRot(tf.new, Vector3.new(pos.X, targetY, pos.Z))
                    g.vy = 0
                    if not world:has(e, Grounded) then
                        world:set(e, Grounded, true)
                    end
                end
            end
        end
    end
end

-- 5) Dynamic sphere-sphere collisions (simple positional solve)
local function collisionSystem(_dt: number)
    clearSpatialGrid()
    -- bin all mobiles
    for e, tf, _ in qColliders do
        addToGrid(e, tf.new.Position)
    end

    -- single-pass positional correction with pair de-dup
    local handled: {[number]: true} = {}
    for e, tf, col in qColliders do
        local p = tf.new.Position
        local r = col.radius
        local neighbors = getNearby(p)

        for i = 1, #neighbors do
            local o = neighbors[i]
            if o ~= e then
                -- ensure each unordered pair is processed once
                local a, b = e, o
                if a > b then
                    a, b = b, a
                end
                local key = ("%d:%d"):format(a, b)
                if not handled[key] and world:has(o, Collider) then
                    handled[key] = true

                    local otf = world:get(o, Transform) :: any
                    local ocol = world:get(o, Collider)  :: any
                    if otf and ocol then
                        local op = otf.new.Position
                        local rr = r + ocol.radius
                        local delta = p - op
                        local dist2 = delta.X*delta.X + delta.Y*delta.Y + delta.Z*delta.Z
                        if dist2 > 0 then
                            local dist = math.sqrt(dist2)
                            if dist < rr then
                                local n = delta / dist
                                local push = (rr - dist) * 0.5 + SKIN_WIDTH
                                -- move both apart
                                p   = p   + n * push
                                op  = op  - n * push
                                tf.new  = setPosPreserveRot(tf.new,  p)
                                otf.new = setPosPreserveRot(otf.new, op)
                            end
                        else
                            -- perfectly overlapping positions; nudge deterministically
                            local n = Vector3.new(1, 0, 0)
                            local push = rr * 0.5 + SKIN_WIDTH
                            p  = p  + n * push
                            tf.new = setPosPreserveRot(tf.new, p)
                        end
                    end
                end
            end
        end
    end
end

-- (Optional) multiple iterations to reduce interpenetration
local function collisionSolve(dt: number)
    for _ = 1, RESOLVE_ITERATIONS do
        collisionSystem(dt)
    end
end


scheduler.SYSTEM(knockbackSystem, phases.Physics)
scheduler.SYSTEM(integrateXZSystem, phases.Physics)
scheduler.SYSTEM(gravitySystem, phases.PhysicsGravity)
scheduler.SYSTEM(groundingSystem,phases.PhysicsTerrain)
scheduler.SYSTEM(collisionSolve, phases.PhysicsCollision)

return {}