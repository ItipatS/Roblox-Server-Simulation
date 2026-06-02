local world = require(script.Parent.world)
local jecs = require(game:GetService("ReplicatedStorage").ecs)
local refs: {[any]: jecs.Entity} = {}

local function fini(key): () -> ()
	return function()
		refs[key] = nil
	end
end

local function noop() end

local function ref(key): (jecs.Entity, () -> ())
	if not key then
		return world:entity(), noop
	end
	local e = refs[key]
	if not e then
		e = world:entity()
		refs[key] = e
	end
	-- Cannot cache handles because they will get invalidated
	return e, fini(key)
end

-- Callable table: ref(key) works as before, ref.clear() drops the whole key->entity
-- cache. Needed on dust rebuild, where the server recycles entity ids (which truncate
-- to the same u16 on the wire) and old cached entries would resolve to dead entities.
local api = setmetatable({
	clear = function()
		table.clear(refs)
	end,
}, {
	__call = function(_, key)
		return ref(key)
	end,
})

return (api :: any)
