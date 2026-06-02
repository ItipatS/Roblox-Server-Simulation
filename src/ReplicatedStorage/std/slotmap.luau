--!strict
-- Client-side mirror of server dust slots: slot index -> client ECS entity.
-- Populated on SpawnDust, read by the dense delta handler (move.luau).
-- Slot identity is assigned once on the server and is stable for a dust's lifetime,
-- which is what lets the per-tick delta stream omit entity ids entirely.

local slots: { [number]: any } = {}

local slotmap = {}

function slotmap.set(slot: number, e: any)
	slots[slot] = e
end

function slotmap.get(slot: number): any
	return slots[slot]
end

-- Wipe the whole mapping (used when the dust field is rebuilt at a new count).
function slotmap.clear()
	table.clear(slots)
end

slotmap.map = slots

return slotmap
