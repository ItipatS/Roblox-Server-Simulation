-- StarterPlayerScripts/systems/DustControl.luau
--!optimize 2
--!strict
--
-- Runtime dust-count panel. Only one client controls the count at a time: you must
-- "Take Control" first (first-come-first-serve, enforced by the server). While you hold
-- it, -/+ adjust a pending value and Apply asks the server to respawn the field. Everyone
-- else sees the panel locked with the holder's name.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local blink = require(ReplicatedStorage.ClientNet)
local config = require(ReplicatedStorage.std.config)

local STEP = 250
local MIN_DUST = 100
local MAX_DUST = 8000

local ACTIVE = Color3.fromRGB(64, 156, 240)
local IDLE = Color3.fromRGB(40, 44, 54)
local DIM = Color3.fromRGB(28, 30, 36)
local TEXT = Color3.fromRGB(235, 240, 248)
local TEXT_DIM = Color3.fromRGB(120, 126, 138)

-- State mirrored from the server
local holder = "" -- controlling player's name, "" = free
local count = config.MAX_DUST -- live count on the server
local pending = config.MAX_DUST -- value the local UI is editing

local function amControlling(): boolean
	return holder ~= "" and holder == Players.LocalPlayer.Name
end

-- UI handles (filled by buildUI)
local valueLabel: TextLabel
local statusLabel: TextLabel
local minusBtn: TextButton
local plusBtn: TextButton
local applyBtn: TextButton
local controlBtn: TextButton

local function styleEnabled(btn: TextButton, enabled: boolean, activeColor: Color3?)
	btn.AutoButtonColor = enabled
	btn.BackgroundColor3 = if enabled then (activeColor or IDLE) else DIM
	btn.TextColor3 = if enabled then TEXT else TEXT_DIM
end

local function refresh()
	local mine = amControlling()
	local locked = holder ~= "" and not mine

	valueLabel.Text = tostring(pending)

	if holder == "" then
		statusLabel.Text = "control: free"
	elseif mine then
		statusLabel.Text = "you're in control"
	else
		statusLabel.Text = "locked by " .. holder
	end

	styleEnabled(minusBtn, mine)
	styleEnabled(plusBtn, mine)
	-- Apply is highlighted when there's an un-applied change
	styleEnabled(applyBtn, mine, if pending ~= count then ACTIVE else IDLE)

	controlBtn.Text = if mine then "Release" else "Take Control"
	-- can interact unless someone else holds it
	styleEnabled(controlBtn, not locked, if mine then ACTIVE else IDLE)
end

local function buildUI()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "DustControl"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -16, 0, 16)
	panel.Size = UDim2.fromOffset(210, 132)
	panel.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	panel.BackgroundTransparency = 0.2
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 16)
	title.BackgroundTransparency = 1
	title.Text = "DUST"
	title.Font = Enum.Font.GothamBold
	title.TextSize = 13
	title.TextColor3 = TEXT
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.LayoutOrder = 1
	title.Parent = panel

	-- stepper row: [-] value [+]
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 36)
	row.BackgroundTransparency = 1
	row.LayoutOrder = 2
	row.Parent = panel

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, 6)
	rowLayout.Parent = row

	local function makeButton(text: string, w: number, order: number, parent: Instance): TextButton
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.fromOffset(w, 36)
		btn.BackgroundColor3 = IDLE
		btn.BorderSizePixel = 0
		btn.Text = text
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 16
		btn.TextColor3 = TEXT
		btn.LayoutOrder = order
		btn.Parent = parent
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent = btn
		return btn
	end

	minusBtn = makeButton("−", 44, 1, row)
	valueLabel = Instance.new("TextLabel")
	valueLabel.Size = UDim2.fromOffset(78, 36)
	valueLabel.BackgroundColor3 = Color3.fromRGB(14, 15, 19)
	valueLabel.Text = tostring(pending)
	valueLabel.Font = Enum.Font.GothamBold
	valueLabel.TextSize = 18
	valueLabel.TextColor3 = TEXT
	valueLabel.LayoutOrder = 2
	valueLabel.Parent = row
	local vc = Instance.new("UICorner")
	vc.CornerRadius = UDim.new(0, 8)
	vc.Parent = valueLabel
	plusBtn = makeButton("+", 44, 3, row)

	applyBtn = makeButton("Apply", 188, 3, panel)
	applyBtn.Size = UDim2.new(1, 0, 0, 30)
	applyBtn.TextSize = 15

	controlBtn = makeButton("Take Control", 188, 4, panel)
	controlBtn.Size = UDim2.new(1, 0, 0, 30)
	controlBtn.TextSize = 15

	statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.new(1, 0, 0, 14)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "control: free"
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextSize = 12
	statusLabel.TextColor3 = TEXT_DIM
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.LayoutOrder = 5
	statusLabel.Parent = panel

	-- interactions
	minusBtn.Activated:Connect(function()
		if amControlling() then
			pending = math.clamp(pending - STEP, MIN_DUST, MAX_DUST)
			refresh()
		end
	end)
	plusBtn.Activated:Connect(function()
		if amControlling() then
			pending = math.clamp(pending + STEP, MIN_DUST, MAX_DUST)
			refresh()
		end
	end)
	applyBtn.Activated:Connect(function()
		if amControlling() and pending ~= count then
			blink.RequestDustCount.Fire(pending)
		end
	end)
	controlBtn.Activated:Connect(function()
		if amControlling() then
			blink.RequestControl.Fire(0) -- release
		elseif holder == "" then
			blink.RequestControl.Fire(1) -- claim
		end
	end)

	gui.Parent = playerGui
	refresh()
end

blink.ControlState.On(function(payload)
	local prevHolder = holder
	holder = payload.holder
	count = payload.count
	-- snap the editor to the live count when we (re)gain or lose control or it changes
	if pending ~= count and (not amControlling() or prevHolder == "") then
		pending = count
	end
	refresh()
end)

buildUI()

return {}
