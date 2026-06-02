-- StarterPlayerScripts/systems/Leaders.luau
--!optimize 2
--!strict
--
-- Client half of Hunt mode. Receives the streamed leader positions, smooths them, drives
-- the visible predator parts, and writes them into FieldEval.leaders so the dust (in
-- move.luau) flee them. Only the dozens of leaders cross the wire; the 3000 followers are
-- pure client computation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local blink = require(ReplicatedStorage.ClientNet)
local std = ReplicatedStorage.std
local config = require(std.config)
local Modes = require(std.modes)
local FieldEval = require(std.fieldeval)
local scheduler = require(std.scheduler)

local N = config.LEADER_COUNT

local folder = Instance.new("Folder")
folder.Name = "Leaders"
folder.Parent = workspace

local parts = table.create(N)
local targets = table.create(N) -- latest streamed position per leader
local current = FieldEval.leaders -- smoothed positions; shared with the dust sampler

local function makeLeaderPart(): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.Neon
	p.Size = Vector3.new(2.4, 2.4, 2.4)
	p.Color = Color3.fromRGB(255, 80, 60)
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1 -- shown only in Hunt mode
	p.Parent = folder
	return p
end

for i = 1, N do
	parts[i] = makeLeaderPart()
end

blink.LeaderState.On(function(positions)
	for i = 1, #positions do
		targets[i] = positions[i]
		if current[i] == nil then
			current[i] = positions[i] -- seed so the first frame doesn't lerp from origin
		end
	end
end)

local function leaderRender(dt: number)
	local hunt = FieldEval.mode == Modes.Hunt
	local a = math.clamp(dt * 14, 0, 1)
	for i = 1, N do
		local part = parts[i]
		if not hunt then
			if part.Transparency ~= 1 then
				part.Transparency = 1
			end
		else
			local tgt = targets[i]
			if tgt then
				local cur = (current[i] or tgt):Lerp(tgt, a)
				current[i] = cur
				part.Position = cur
				part.Transparency = 0
			end
		end
	end
end

scheduler.SYSTEM(leaderRender)

return {}
