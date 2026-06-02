-- ServerScriptService/Systems/DustSpawn.luau
--!optimize 2
--!native
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local std = ReplicatedStorage.std

local world = require(std.world)
local cts = require(std.components)
local config = require(std.config)

local Firefly = require(std.firefly)
local blink = require(game:GetService("ServerScriptService").ServerNet)
local Mode = require(script.Parent.Mode)
local DustCount = require(script.Parent.DustCount)

local Dust = cts.Dust
local Transform = cts.Transform
local Velocity = cts.Velocity
local Direction = cts.Direction
local DustData = cts.DustData
local DustState = cts.DustState
local DustDrag = cts.DustDrag
local Slot = cts.Slot

local SPAWN_AREA_SIZE = 100
local CEILING_HEIGHT = 15
local MIN_DUST = 100
local MAX_DUST_CAP = 8000

-- Live dust count (starts from config, changes at runtime via the control UI).
local dustCount = config.MAX_DUST

local count = {
    Normal = 0,
    Common = 0,
    Uncommon = 0,
    Rare = 0,
    Epic = 0,
    Legendary = 0,
}

local function randomDrift()
    return Vector3.new(
        math.random() * 1 - .5,
        math.random() * 0.25,
        math.random() * 1 - .5
    ).Unit
end

local function randomSpawnPos(): Vector3
    return Vector3.new(
        math.random(-SPAWN_AREA_SIZE/2, SPAWN_AREA_SIZE/2),
        math.random(0, CEILING_HEIGHT),
        math.random(-SPAWN_AREA_SIZE/2, SPAWN_AREA_SIZE/2)
    )
end

local dustQuery = world
    :query(Transform, DustData)
    :with(Dust)
    :cached()

-- Build the spawn payload from the *current* ECS state (so late joiners and rebuilds
-- both send live positions). rarity is the string the Blink field expects, and
-- timeoffset is read back from DustData where buildField stored it.
local function makeBatch()
    local batch = table.create(dustCount)
    for e, transform, data in dustQuery do
        local d = data :: any
        batch[#batch+1] = {
            id     = e,
            slot   = world:get(e, Slot),
            pos    = transform.new.Position,
            rarity = d.rarity,
            timeoffset = d.timeoffset or 0,
        }
    end
    return batch
end

local function resetCounts()
    for k in count do
        count[k] = 0
    end
end

-- Spawn `n` dust (slots 0..n-1, contiguous — the dense scheme needs no ids).
local function buildField(n: number)
    resetCounts()
    DustCount.n = n -- so Mode/Leaders scale their geometry to the live count
    for i = 1, n do
        local e = world:entity()
        local pos = randomSpawnPos()
        local slot = i - 1
        local rarity = Firefly.chooseRarity()

        world:add(e, Dust)
        world:set(e, Slot, slot)
        world:set(e, Velocity, 2)
        world:set(e, Direction, randomDrift())
        world:set(e, Transform, { new = CFrame.new(pos) })
        -- timeoffset lives on DustData so the resend path (makeBatch) has it; the
        -- shared type only declares `rarity`, so cast to set the extra field.
        world:set(e, DustData, ({ rarity = rarity, timeoffset = math.random() } :: any))
        world:set(e, DustState, {
            isFleeing = false,
            fleeTimer = 0,
        })
        world:set(e, DustDrag, {
            draggerUserId = nil,
            targetPos = nil,
        })

        count[rarity] += 1
    end
end

local function clearField()
    local toDelete = {}
    for e in dustQuery do
        toDelete[#toDelete+1] = e
    end
    for _, e in toDelete do
        world:delete(e)
    end
    resetCounts()
end

local initialized = false

-- ---- Runtime dust-count control (one controller, first-come-first-serve) -----
local controller: Player? = nil

local function controlPayload()
    return { holder = if controller then controller.Name else "", count = dustCount }
end

local function broadcastControl()
    blink.ControlState.FireAll(controlPayload())
end

local function rebuild(n: number)
    dustCount = n
    clearField()
    buildField(n)
    Mode.flagResync() -- positions changed; Network re-anchors clients on the next Drift tick
    blink.RebuildDust.FireAll(n) -- clients tear down old models first...
    blink.SpawnDust.FireAll(makeBatch()) -- ...then receive the fresh field
    blink.Firefly.FireAll(count)
end

blink.RequestControl.On(function(player: Player, claim: number)
    if claim == 1 then
        if controller == nil then
            controller = player
            broadcastControl()
        end
    else
        if controller == player then
            controller = nil
            broadcastControl()
        end
    end
end)

blink.RequestDustCount.On(function(player: Player, n: number)
    if player ~= controller then
        return -- only the controller may change the count
    end
    n = math.clamp(n, MIN_DUST, MAX_DUST_CAP)
    if n == dustCount then
        return
    end
    rebuild(n)
    broadcastControl()
end)

-- ---- Joining ---------------------------------------------------------------
local function onPlayer(player: Player)
    if not initialized then
        initialized = true
        buildField(dustCount)
        blink.SpawnDust.FireAll(makeBatch())
    else
        blink.SpawnDust.Fire(player, makeBatch())
    end
    blink.Firefly.Fire(player, count)
    blink.ControlState.Fire(player, controlPayload())
end

-- Catch players already connected before this script ran (Studio team test / fast
-- joins) — PlayerAdded never fires for them, which made later players get dust only
-- sometimes.
for _, player in Players:GetPlayers() do
    onPlayer(player)
end
Players.PlayerAdded:Connect(onPlayer)

Players.PlayerRemoving:Connect(function(player)
    if controller == player then
        controller = nil
        broadcastControl()
    end
end)

return {}
