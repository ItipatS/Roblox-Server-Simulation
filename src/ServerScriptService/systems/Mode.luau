--ServerScriptService/Systems/Mode.luau
--!optimize 2
--!strict
--
-- Server is the authority on the active presentation mode. It owns the mode, validates
-- client requests, and broadcasts changes. It also detects player actions (jump) and
-- emits one-shot field events (splash) — each is a single broadcast, not per-particle.
--
-- Network.luau requires this module to decide whether to stream positions at all: in any
-- non-Drift mode the client reconstructs the field locally, so the server goes silent on
-- the delta channel.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local blink = require(game:GetService("ServerScriptService").ServerNet)
local Modes = require(ReplicatedStorage.std.modes)
local layout = require(ReplicatedStorage.std.layout)
local DustCount = require(script.Parent.DustCount)

local M = {}

local currentMode = Modes.Drift
local pendingResync = false -- set when returning to Drift so Network re-anchors clients

-- Network reads these ----------------------------------------------------------
function M.getMode(): number
	return currentMode
end

function M.streamPositions(): boolean
	return currentMode == Modes.Drift
end

-- True exactly once after a switch back to Drift (Network forces a full snapshot then).
function M.consumeResync(): boolean
	if pendingResync then
		pendingResync = false
		return true
	end
	return false
end

-- Called when the dust field is rebuilt at a new count, so Network drops its stale
-- per-slot baseline and re-anchors clients on the next Drift streaming tick.
function M.flagResync()
	pendingResync = true
end

-- Mode switching ---------------------------------------------------------------
local function isValid(id: number): boolean
	return id == Modes.Drift
		or id == Modes.Ocean
		or id == Modes.Wall
		or id == Modes.Shore
		or id == Modes.Hunt
		or id == Modes.Spread
end

local function setMode(id: number)
	if not isValid(id) or id == currentMode then
		return
	end
	currentMode = id
	if id == Modes.Drift then
		pendingResync = true -- clients have been rendering locally; re-sync server state
	end
	blink.SetMode.FireAll(id)
end

blink.RequestSetMode.On(function(_player: Player, id: number)
	setMode(id)
end)

-- Player actions -> field events ----------------------------------------------
local SPLASH = 0

local function fireSplash(char: Model)
	if currentMode ~= Modes.Ocean and currentMode ~= Modes.Shore then
		return
	end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		blink.FieldEvent.FireAll({ kind = SPLASH, origin = root.Position })
	end
end

local function hookCharacter(char: Model)
	local humanoid = char:FindFirstChildOfClass("Humanoid")
		or char:WaitForChild("Humanoid", 5) :: Humanoid?
	if not humanoid then
		return
	end
	;(humanoid :: Humanoid).Jumping:Connect(function(active: boolean)
		if active then
			fireSplash(char)
		end
	end)
end

local function hookPlayer(player: Player)
	-- new joiner gets the current mode (SetMode.FireAll only reaches present players)
	blink.SetMode.Fire(player, currentMode)
	if player.Character then
		hookCharacter(player.Character)
	end
	player.CharacterAdded:Connect(hookCharacter)
end

for _, player in Players:GetPlayers() do
	hookPlayer(player)
end
Players.PlayerAdded:Connect(hookPlayer)

-- Wall hits ------------------------------------------------------------------
-- In Wall mode, a player reaching the curtain plane fires a hit (kind 1) at their
-- (x, y) on the wall. Rate-limited per player so walking into it pulses shockwaves
-- instead of spamming every frame.
local HIT = 1
local HIT_DIST = 3.5 -- studs of slack around the block that count as a hit
local HIT_CD = 0.9 -- seconds between hits per player (slow shockwaves shouldn't stack)
local lastHit: { [Player]: number } = {}

RunService.Heartbeat:Connect(function()
	if currentMode ~= Modes.Wall then
		return
	end
	local nowt = os.clock()
	local wallHalf = layout.wallHalf(DustCount.n) -- cube grows with the dust count
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char then
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = char:FindFirstChildOfClass("Humanoid")
			-- only pulse while the player is actually moving against the wall, not just
			-- standing in it
			local moving = hum ~= nil and (hum :: Humanoid).MoveDirection.Magnitude > 0.1
			if root and moving then
				local p = root.Position
				-- cube is centered on X = Z = 0
				if math.abs(p.Z) < wallHalf + HIT_DIST and math.abs(p.X) < wallHalf + 1 then
					if nowt - (lastHit[player] or 0) >= HIT_CD then
						lastHit[player] = nowt
						-- full 3D contact point so the shockwave is spherical through the block
						blink.FieldEvent.FireAll({ kind = HIT, origin = p })
					end
				end
			end
		end
	end
end)

return M
