-- ServerScriptService/Systems/DustDrag.luau
--!optimize 2
--!native
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local std = ReplicatedStorage.std

local world = require(std.world)
local cts = require(std.components)

local blink = require(game:GetService("ServerScriptService").ServerNet)

local DustDrag = cts.DustDrag

-- Pseudo API; adjust to your Blink server handler style.
blink.DustDrag.On(function(player, payload)
    local id = payload.id :: number
    local mode = payload.mode :: string -- "Start" | "Update" | "Stop"

    -- we assume entity id == network id
    local e = id
    local drag = world:get(e, DustDrag)

    if not drag then
        drag = { draggerUserId = nil, targetPos = nil }
    end

    if mode == "Start" then
        drag.draggerUserId = player.UserId
        drag.targetPos = nil
    elseif mode == "Update" then
        if drag.draggerUserId == player.UserId then
            drag.targetPos = Vector3.new(payload.pos.X, payload.pos.Y, payload.pos.Z)
        end
    elseif mode == "Stop" then
        if drag.draggerUserId == player.UserId then
            drag.draggerUserId = nil
            drag.targetPos = nil
        end
    end

    world:set(e, DustDrag, drag)
end)

return {}
