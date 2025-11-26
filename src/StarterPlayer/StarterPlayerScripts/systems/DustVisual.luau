-- ReplicatedStorage/Client/DustVisualSystem.luau
--!optimize 2
--!native
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FireflyConfig = require(ReplicatedStorage.std.firefly)

local blink = require(ReplicatedStorage.net)
local std   = ReplicatedStorage.std
local world = require(std.world)
local cts   = require(std.components)
local scheduler = require(std.scheduler)
local phases    = require(std.phases)
local ref   = require(std.ref)

local Dust      = cts.Dust
local Model     = cts.Model
local DustData  = cts.DustData
local DustState = cts.DustState

local dustQuery = world
    :query(Model, DustData, DustState)
    :with(Dust)
    :cached()

local RENDER_HZ = 60
local RENDER_DT = 1 / RENDER_HZ
local acc = 0

local function stepColor(data, dt: number)

    local ColorSequence = FireflyConfig.RARITY_COLOR_SEQUENCE[data.rarity] or {}

    if not ColorSequence or #ColorSequence == 0 then return end
    if #ColorSequence == 1 then
        data.CurrentColorIndex = 1
        return
    end

    data.ColorTimer += dt
    if data.ColorTimer >= data.ColorDuration then
        data.ColorTimer = 0
        data.ColorDuration = math.random(2, 5)
        data.CurrentColorIndex = ColorSequence[math.random(1, #ColorSequence)]
    end
end

local function dustVisualSystem(dt: number)
    acc += dt
    if acc < RENDER_DT then return end
    local step = acc
    acc = 0

    for e, model, data, state in dustQuery do
        local m = model :: Model
        local part = m.PrimaryPart
        if not part then continue end
        if not data then continue end

        stepColor(data, step)

        if state.isFleeing then
            part.Transparency = 1 -- no glow: invisible
        else
            part.Transparency = 0
            part.Color = data.CurrentColorIndex
        end
    end
end

blink.UpdateDustState.On(function(payload)
    for _, entry in payload do
        local e = ref("server-" .. tostring(entry.id))
        local state = world:get(e, DustState)
        if state then
            state.isFleeing = entry.isFleeing
            state.fleeTimer = entry.fleeTimer
        end
    end
end)

scheduler.SYSTEM(dustVisualSystem, phases.ClientEffects)
return {}
