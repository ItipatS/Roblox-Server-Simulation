-- StarterPlayerScripts/systems/Mode.luau
--!optimize 2
--!strict
--
-- Client mode plumbing: applies server mode broadcasts to the local field evaluator,
-- turns field events into ripples, and builds the on-screen mode buttons that ask the
-- server to switch. The server is the authority — the button only sends a request.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local blink = require(ReplicatedStorage.ClientNet)
local std = ReplicatedStorage.std
local FieldEval = require(std.fieldeval)
local Modes = require(std.modes)

-- ---- Network -> local field ------------------------------------------------
-- SetMode is SingleSync (one listener); the combined handler is registered below,
-- once `refresh` exists, so it can both apply the mode and update the button highlight.

blink.FieldEvent.On(function(payload)
	if payload.kind == 0 then -- ocean/shore jump splash (ground plane; y ignored)
		FieldEval.addRipple(payload.origin, 1.3)
	elseif payload.kind == 1 then -- wall hit: full 3D point in the block
		FieldEval.addRipple(payload.origin, 1.5)
	end
end)

-- ---- Mode button UI --------------------------------------------------------
local ACTIVE = Color3.fromRGB(64, 156, 240)
local IDLE = Color3.fromRGB(40, 44, 54)

local ENTRIES = {
	{ id = Modes.Drift, label = "Drift" },
	{ id = Modes.Ocean, label = "Ocean" },
	{ id = Modes.Shore, label = "Shore" },
	{ id = Modes.Wall, label = "Wall" },
	{ id = Modes.Hunt, label = "Hunt" },
	{ id = Modes.Spread, label = "Spread" },
}

local buttons: { [number]: TextButton } = {}

local function refresh(activeId: number)
	for id, btn in buttons do
		btn.BackgroundColor3 = if id == activeId then ACTIVE else IDLE
	end
end

local function buildUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "ModeUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -24)
	bar.Size = UDim2.fromOffset(110 * #ENTRIES + 12, 56)
	bar.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	bar.BackgroundTransparency = 0.25
	bar.BorderSizePixel = 0
	bar.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = bar

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = bar

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = bar

	for _, entry in ENTRIES do
		local btn = Instance.new("TextButton")
		btn.Name = entry.label
		btn.Size = UDim2.fromOffset(100, 40)
		btn.BackgroundColor3 = IDLE
		btn.BorderSizePixel = 0
		btn.AutoButtonColor = true
		btn.Text = entry.label
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 18
		btn.TextColor3 = Color3.fromRGB(235, 240, 248)
		btn.Parent = bar

		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 8)
		bc.Parent = btn

		btn.Activated:Connect(function()
			blink.RequestSetMode.Fire(entry.id)
		end)

		buttons[entry.id] = btn
	end

	gui.Parent = playerGui
	refresh(FieldEval.mode)
end

-- Server confirms a switch (and replays current mode to late joiners): apply it and
-- update the highlight. Single listener for the SingleSync SetMode event.
blink.SetMode.On(function(id: number)
	FieldEval.setMode(id)
	refresh(id)
end)

buildUI()

return {}
