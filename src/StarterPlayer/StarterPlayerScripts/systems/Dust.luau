-- ReplicatedStorage/Client/DustSpawnClient.luau
--!optimize 2
--!native
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local blink = require(ReplicatedStorage.net)
local std = ReplicatedStorage.std
local world = require(std.world)
local ref = require(std.ref)
local cts = require(std.components)
local FireflyConfig = require(std.firefly)

local Dust      = cts.Dust
local ModelComp = cts.Model
local Transform = cts.Transform
local DustData  = cts.DustData
local DustState = cts.DustState

local FireflyRarityByIndex = {
	[0] = "Normal",
	[1] = "Rare",
	[2] = "Epic",
	[3] = "Legendary",
}

local DustFolder = Instance.new("Folder")
DustFolder.Name = "Dusts"
DustFolder.Parent = workspace

local function createDustPart(): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Neon
	part.Size = Vector3.new(0.3, 0.3, 0.3)
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.CanQuery = false
	part.CanTouch = false
	return part
end

blink.SpawnDust.On(function(payload)
		local id      = payload.id
		local pos     = payload.pos :: Vector3
		local rIndex  = payload.rarity :: number
		local isFlee  = payload.flee :: boolean

		local rarityName = FireflyRarityByIndex[rIndex] or "Normal"
		local seq = FireflyConfig.getColorSequence(rarityName)

		local e = ref("server-" .. tostring(id))

		-- If this is a re-send (join-late or re-sync), avoid duplicating models
		local existingModel = world:get(e, ModelComp)
		if not existingModel then
			local part = createDustPart()
			part.Position = pos
			part.Color = seq[1] or Color3.new(1, 1, 1)

			local model = Instance.new("Model")
			model.Name = "Dust-" .. tostring(id)
			model.PrimaryPart = part
			part.Parent = model
			model.Parent = DustFolder

			world:set(e, Transform, { new = CFrame.new(pos) })
			world:set(e, ModelComp, model)
			world:add(e, Dust)
		else
			-- Just update position if we already had the entity
			local t = world:get(e, Transform) or { new = CFrame.new() }
			t.new = CFrame.new(pos)
			world:set(e, Transform, t)
		end

		-- Reuse DustData component, but enrich it on client for visuals
		world:set(e, DustData, {
			-- server cares only about rarity, client adds extra fields
			rarityIndex = rIndex,
			rarity      = rarityName,
			Color          = seq[1],
			CurrentColorIndex = 1,
			ColorTimer        = 0,
            ColorDuration     = math.random(2, 5),
		})

		-- State component: synced from server
		world:set(e, DustState, {
			isFleeing = isFlee,
			fleeTimer = 0, -- client can use this for visual easing if it wants
		})
end)


return 0
