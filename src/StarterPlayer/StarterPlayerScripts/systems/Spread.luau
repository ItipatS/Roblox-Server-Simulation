-- StarterPlayerScripts/systems/Spread.luau
--!optimize 2
--!strict
--
-- Client half of Spread mode: receive the dense heat stream and drop it into
-- FieldEval.heat, which move.luau reads to color the fire. No neighbor math here — the
-- emergence all happened server-side; the client just renders the state it's handed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local blink = require(ReplicatedStorage.ClientNet)
local FieldEval = require(ReplicatedStorage.std.fieldeval)

local heat = FieldEval.heat

blink.UpdateHeat.On(function(packet)
	local base = packet.base
	local arr = packet.heat
	for i = 1, #arr do
		heat[base + i - 1] = arr[i] / 255
	end
end)

return {}
