--!optimize 2
--!native
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local blink = require(ReplicatedStorage.net)
local std = ReplicatedStorage.std
local world = require(std.world)
local ref = require(std.ref)

local cts = require(std.components)
local Model = cts.Model
local Transform = cts.Transform
local DustData = cts.DustData
-- Query: entities that have a Roblox model and a Transform
local moved_models = world:query(Model, Transform, DustData):cached()

-- ---------- Smooth interpolation state ----------
-- For each entity we keep a small state machine:
-- prev -> next over 'span' seconds, with alpha advancing each frame.
type Smooth = {
    prev: CFrame,
    next: CFrame,
    rendered: CFrame,  -- last frame’s output
    alpha: number,     -- [0..1]
    span: number,      -- seconds to complete the blend
}

local smooth: { [number]: Smooth } = {}

-- Pick a blend time ~ network period (12 Hz ~= 0.083s).
-- A bit longer is nicer; tweak to taste.
local TARGET_SPAN = 0.10   -- 100 ms
local MIN_SPAN    = 1/120  -- never 0; avoids huge alpha steps
local MAX_SPAN    = 0.25   -- don't smear too long
local WOBBLE_INTENSITY = 0.5
local TELEPORT_DIST_SQ = 30 * 30

local function wobbleOffset(timeoffset)
    local t = tick() + timeoffset
            local wobble = Vector3.new(
                math.sin(t * 1.5),
                math.cos(t * 2) * 0.5,
                math.sin(t * 1.2)
            ) * WOBBLE_INTENSITY
    return CFrame.new(wobble)
end

local function beginBlend(e: number, serverCF: CFrame)
    local s = smooth[e]
    if not s then
        -- first time: no pop
        s = {
            prev = serverCF,
            next = serverCF,
            rendered = serverCF,
            alpha = 1,
            span = TARGET_SPAN,
        }
        smooth[e] = s
        return
    end

    local start = s.rendered
    local dist = (serverCF.Position - start.Position).Magnitude

    -- if jump is huge (warp / teleport), cancel interpolation
    local distSq = (serverCF.Position - start.Position).Magnitude ^ 2
    if distSq > TELEPORT_DIST_SQ then
        s.prev     = serverCF
        s.next     = serverCF
        s.rendered = serverCF
        s.alpha    = 1
        s.span     = TARGET_SPAN
        return
    end

    -- normal smooth blend
    s.prev = start
    s.next = serverCF

    local span = TARGET_SPAN
    if dist > 10 then
        span = math.clamp(TARGET_SPAN * 1.5, MIN_SPAN, MAX_SPAN)
    end

    s.span  = math.clamp(span, MIN_SPAN, MAX_SPAN)
    s.alpha = 0
end

local function stepBlend(e: number, dt: number): CFrame?
    local s = smooth[e]
    if not s then return nil end
    -- advance
    if s.alpha < 1 then
        -- normalize dt by span, clamp so big hitches don’t overshoot badly
        local da = math.clamp(dt / s.span, 0, 0.5)
        s.alpha = math.min(1, s.alpha + da)
    end
    -- CFrame:Lerp blends pos+rot (slerp-like)
    local out = s.prev:Lerp(s.next, s.alpha)
    s.rendered = out
    return out
end

-- Helper: ensure a Transform component exists with a .new CFrame
local function ensureTransform(e: number): {new: CFrame}
    local t = world:get(e, Transform)
    if t == nil then
        -- initialize with identity if missing (should be rare)
        t = { new = CFrame.new() }
        world:set(e, Transform, t)
    elseif t.new == nil then
        -- normalize shape if someone set Transform = CFrame by mistake
        t = { new = (t :: any) :: CFrame }
        world:set(e, Transform, t)
    end
    return t :: {new: CFrame}
end

-- --- Network handlers (register once) ---

-- Delta updates: [{ id: number, dp: Vector3 }, ...]
blink.UpdateTransformDelta.On(function(payload)
    for _, entry in payload do
        local e = ref("server-" .. tostring(entry.id))

        -- authoritatively advance ECS Transform
        local t = ensureTransform(e)
        t.new = t.new + entry.dp

        -- start a smooth blend FROM current rendered TO new server pose
        beginBlend(e, t.new)
    end
end)

-- Full updates: [{ id: number, dp: Vector3 }, ...]
blink.UpdateTransformFull.On(function(payload)
    for _, entry in payload do
        local e = ref("server-" .. tostring(entry.id))
        local cf = if entry.r
            then CFrame.new(entry.dp) * CFrame.Angles(0, entry.r, 0)
            else CFrame.new(entry.dp)

        local t = ensureTransform(e)
        t.new = cf

        beginBlend(e, cf)
    end
end)

-- ---------- 60 Hz presentation ----------
local RENDER_HZ = 60
local RENDER_DT = 1 / RENDER_HZ
local acc = 0

local function present(dt: number)
    acc += dt
    if acc < RENDER_DT then return end
    acc = 0

    for e, model, transform, dustData in moved_models do
        local m = (model :: Model)
        if m and m.PrimaryPart then
            local cf = stepBlend(e, RENDER_DT)
            if cf then
                m.PrimaryPart.CFrame = cf * wobbleOffset(dustData.timeoffset)
            end
        end
    end
end

local scheduler = require(std.scheduler)
scheduler.SYSTEM(present)

return 0
