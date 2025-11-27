-- ReplicatedStorage/Client/DustVisualSystem.luau
--!optimize 2
--!native
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FireflyConfig = require(ReplicatedStorage.std.firefly)

local blink = require(ReplicatedStorage.ClientNet)
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

local function stepColor(data, part , dt: number)

    if not data.rarity then return end

    local rarityConfig = FireflyConfig.RARITY_COLOR_SEQUENCE[data.rarity]
    if not rarityConfig then return end

    local ColorSequence = rarityConfig[1] or {}
    if #ColorSequence == 0 then return end

    data.CurrentColorIndex  = data.CurrentColorIndex  or 1
    data.ColorTimer         = data.ColorTimer         or 0
    data.ColorBlendDuration = data.ColorBlendDuration or math.random(2, 5)
    data.Color              = data.Color              or ColorSequence[data.CurrentColorIndex]

    if data.rarity ~= "Legendary" then

        data.ColorTimer += dt

        if #ColorSequence > 1 then
            local nextIndex = data.CurrentColorIndex + 1
            if nextIndex > #ColorSequence then
                nextIndex = 1
            end

            local blendAlpha = math.clamp(
                data.ColorTimer / (data.ColorBlendDuration or math.random(2, 5)),
                0, 1
            )
            local fromColor = ColorSequence[data.CurrentColorIndex]
            local toColor = ColorSequence[nextIndex]

            data.Color = fromColor:Lerp(toColor, blendAlpha)

            if blendAlpha >= 1 then
                data.CurrentColorIndex = nextIndex
                data.ColorTimer = 0
                data.ColorBlendDuration = math.random(2, 5)
            end
        end
    else
        -- Rainbow: cycle hue smoothly
        local hue = tick() % 5 / 5
        data.Color = Color3.fromHSV(hue, 1, 1)
    end
    part.Color = data.Color
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

        stepColor(data, part, step)
        world:set(e, DustData, data)

        if state.isFleeing then
            part.Transparency = 0.5
        else
            part.Transparency = 0
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
            world:set(e, DustState, state)
        end
    end
end)

scheduler.SYSTEM(dustVisualSystem, phases.ClientEffects)
return {}
