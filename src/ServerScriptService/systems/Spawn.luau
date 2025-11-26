-- ServerScriptService/Systems/DustSpawn.luau
--!optimize 2
--!native
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local std = ReplicatedStorage.std

local world = require(std.world)
local cts = require(std.components)

local Firefly = require(std.firefly)
local blink = require(game:GetService("ServerScriptService").net) -- your Blink output

local Dust = cts.Dust
local Transform = cts.Transform
local DustData = cts.DustData
local DustState = cts.DustState
local DustDrag = cts.DustDrag

local MAX_DUST = 2500
local SPAWN_AREA_SIZE = 200
local CEILING_HEIGHT = 15

local function randomSpawnPos(): Vector3
    return Vector3.new(
        math.random(-SPAWN_AREA_SIZE/2, SPAWN_AREA_SIZE/2),
        math.random(0, CEILING_HEIGHT),
        math.random(-SPAWN_AREA_SIZE/2, SPAWN_AREA_SIZE/2)
    )
end

local initialized = false

local function initializeDustField()
    if initialized then return end
    initialized = true

    local spawnBatch = table.create(MAX_DUST)

    for _ = 1, MAX_DUST do
        local e = world:entity()
        local pos = randomSpawnPos()

        local rarity = Firefly:chooseRarity()

        world:add(e, Dust)
        world:set(e, Transform, { new = CFrame.new(pos) })
        world:set(e, DustData, {
            rarity = rarity,
        })
        world:set(e, DustState, {
            isFleeing = false,
            fleeTimer = 0,
        })
        world:set(e, DustDrag, {
            draggerUserId = nil,
            targetPos = nil,
        })

        -- For Blink spawn event
        spawnBatch[#spawnBatch+1] = {
            id = e,
            pos = pos,
            rarity = Firefly:rarityToIndex(rarity),
            flee = false,
        }
    end

    if #spawnBatch > 0 then
        blink.SpawnDust.FireAll(spawnBatch)
    end
end

local Players = game:GetService("Players")

local dustQuery = world
    :query(Transform, DustData, DustState)
    :with(Dust)
    :cached()

local function sendAllDustTo(player: Player)
    local batch = table.create(MAX_DUST)

    for e, transform, data, state in dustQuery do
        batch[#batch+1] = {
            id     = e,
            pos    = transform.new.Position,
            rarity = Firefly:rarityToIndex(data.rarity),
            flee   = state.isFleeing,
        }
    end

    if #batch > 0 then
        blink.SpawnDust.Fire(player, batch)
    end
end

Players.PlayerAdded:Connect(function(player)
    if not initialized then
        initializeDustField()
    else
        sendAllDustTo(player)
    end
end)

return {}
