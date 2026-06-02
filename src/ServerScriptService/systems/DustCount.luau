-- ServerScriptService/Systems/DustCount.luau
--!strict
-- The live dust count, server-side. Spawn.luau sets it (on build/rebuild); Mode.luau and
-- Leaders.luau read it so their count-scaled geometry (wall cube, flock box) matches the
-- client's. A plain shared holder — it registers no system.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local config = require(ReplicatedStorage.std.config)

return {
	n = config.MAX_DUST,
}
