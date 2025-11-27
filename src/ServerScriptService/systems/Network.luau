--ServerScripterService/Systems/Network.luau
--!optimize 2
--!native
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local blink = require(game:GetService("ServerScriptService").ServerNet)
local std = ReplicatedStorage.std

local world = require(std.world)
local cts = require(std.components)
local scheduler = require(std.scheduler)
local phases = require(std.phases)
local mailbox = require(std.mailbox)

-- Network constants
local TICK_HZ = 12
local TICK = 1 / TICK_HZ
local FULL_SYNC_INTERVAL = 5
local MAX_BATCH_SIZE = 64

local lastFullSync = 0
local last_accum = 0
local ToSendMovementFull = table.create(128)
local ToSendStateFull = table.create(128)
local ToSendMovement = table.create(MAX_BATCH_SIZE)
local ToSendState    = table.create(MAX_BATCH_SIZE)

local moving_mobs = world:query(cts.Transform, cts.Velocity, cts.Size):with(cts.Dust):cached()
local stated_mob = world:query(cts.DustState):with(cts.Dust):cached()

local function flush(ev, arr)
    if #arr > 0 then 
        ev.FireAll(arr); 
        table.clear(arr) 
    end
end

-- Data store for movements
local function networkSystem(dt: number)
    lastFullSync += dt
    last_accum += dt

    if last_accum < TICK then return end

    last_accum = 0

    table.clear(ToSendMovement)
    mailbox.drain(cts.PendingMovements, function(item)
        if not item then return end
        ToSendMovement[#ToSendMovement+1] = item
        if #ToSendMovement >= MAX_BATCH_SIZE then
            flush(blink.UpdateTransformDelta, ToSendMovement)
        end
    end)

    flush(blink.UpdateTransformDelta, ToSendMovement)

    table.clear(ToSendState)
    mailbox.drain(cts.PendingStates, function(item)
        if not item then return end
        ToSendState[#ToSendState+1] = item
        if #ToSendState >= MAX_BATCH_SIZE then
            flush(blink.UpdateDustState, ToSendState)
        end
    end)
    flush(blink.UpdateDustState, ToSendState)

    -- Full sync logic
    if lastFullSync >= FULL_SYNC_INTERVAL then
        lastFullSync = 0
        
        table.clear(ToSendMovementFull)
        for mob, transform in moving_mobs do
            ToSendMovementFull[#ToSendMovementFull + 1] = { 
                id = mob,
                dp = transform.new.Position
            }
            if #ToSendMovementFull >= 128 then
			blink.UpdateTransformFull.FireAll(ToSendMovementFull)
			table.clear(ToSendMovementFull)
            end
        end

        table.clear(ToSendStateFull)
        for DustStateEntity, state in stated_mob do
            ToSendStateFull[#ToSendStateFull + 1] = {
                id = DustStateEntity,
                isFleeing = state.isFleeing,
                fleeTimer = state.fleeTimer,
            }
            if #ToSendStateFull >= 128 then
            blink.UpdateDustState.FireAll(ToSendStateFull)
            table.clear(ToSendStateFull)
            end
        end

        
        -- Send full state to correct any drift
		if #ToSendMovementFull > 0 then
        	blink.UpdateTransformFull.FireAll(ToSendMovementFull)
			table.clear(ToSendMovementFull)
        end

        if #ToSendStateFull then
            blink.UpdateDustState.FireAll(ToSendStateFull)
			table.clear(ToSendStateFull)
        end
    end
end

scheduler.SYSTEM(networkSystem, phases.NetworkDelta)

return {}