-- Quid
-- Ratchanon Suwatsiriphol

--!native
--!optimize 2

--[=[
	@class Quid
	A suitable uid for representing entity uniqueness. While providing version-detectability, k-sortability and human-readability
]=]

-- [Base64url](https://base64.guru/standards/base64url)
-- [RFC 4648](https://datatracker.ietf.org/doc/html/rfc4648)

-- stylua: ignore
local BASE_64_URL_CHARACTER = {
	"A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z",
	"a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z",
	"0","1","2","3","4","5","6","7","8","9", "-", "_"
}

-- stylua: ignore
local BASE_64_URL_VALUE_MAP = {} do
	for i, character in ipairs(BASE_64_URL_CHARACTER) do
		BASE_64_URL_VALUE_MAP[character] = i - 1
	end
end

local BASE_LENGTH = #BASE_64_URL_CHARACTER
local MAX_SAFE_INTEGER = 9007199254740991
local MASK_NORMALIZED_U32 = 4294967295 -- 2^32 - 1

--[=[
	@class Config
	A configuration object for quid generation
]=]
local DEFAULT_CONFIG = {}

--- :::tip
--- It's can be used as a number for comparing version and then apply to item / entity schema or data-transformation.
--- :::
---
--- @prop version number
--- @within Config
DEFAULT_CONFIG.version = game.PlaceVersion

--- :::tip
--- It's can be represent as a `machine-id`, `place-id`, `job-id`, etc. for better randomness.
--- But it depends on your entropy factory function too.
--- :::
---
--- @prop fingerprint string
--- @within Config
DEFAULT_CONFIG.fingerprint = `{game.GameId}:{game.PlaceId}:{game.JobId}`

--- @prop _counter number
--- @within Config
--- @private
DEFAULT_CONFIG._counter = 0

--- A factory function for produce unix-timestamp in milliseconds as a integer.
---
--- :::tip
--- You can `overwrite` this, and implement your own clock function.
--- :::
---
--- @function clock
--- @within Config
--- @return number -- A unix-timestamp in milliseconds as a integer.
DEFAULT_CONFIG.clock = function()
	return (workspace:GetServerTimeNow() * 1000) // 1
end

--- A factory function for produce random number between [0, 1]
---
--- :::tip
--- You can `overwrite` this, and implement your own entropy function.
--- :::
---
--- @function entropy
--- @within Config
--- @param version number
--- @param timestamp number
--- @param fingerprint string
--- @param counter number
--- @return number -- A random number between [0, 1]
DEFAULT_CONFIG.entropy = function(version: number, timestamp: number, fingerprint: string, counter: number)
	-- Implement randomness with using `math.random` (Weak entropy)
	return bit32.bxor(math.random() * MASK_NORMALIZED_U32, counter) / MASK_NORMALIZED_U32
end

export type Config = typeof(DEFAULT_CONFIG)

-- Bucket cache for generating quid improve performance
local cache_quid = table.create(3 + 8 + 15)

local function decode(integer_base: string): number
	local integer = 0
	local base = integer_base

	for i = 1, #base do
		local c = string.sub(base, i, i)
		local val = BASE_64_URL_VALUE_MAP[c]
		integer = integer * BASE_LENGTH + val
	end

	return integer
end

local function generate(config: Config, version: number?, timestamp: number?)
	local version = version or config.version
	local timestamp = timestamp or config.clock()

	version %= BASE_LENGTH ^ 3
	timestamp %= BASE_LENGTH ^ 8

	-- Version (Padding: 4)
	local version_state = version
	for i = 3, 1, -1 do
		local remainder = (version_state % BASE_LENGTH) // 1
		version_state = version_state // BASE_LENGTH
		cache_quid[i] = BASE_64_URL_CHARACTER[remainder + 1]
	end

	-- Timestamp (Padding: 8)
	local timestamp_state = timestamp
	for i = 11, 4, -1 do
		local remainder = (timestamp_state % BASE_LENGTH) // 1
		timestamp_state = timestamp_state // BASE_LENGTH
		cache_quid[i] = BASE_64_URL_CHARACTER[remainder + 1]
	end

	-- Uniqueness (Padding: 12)
	config._counter %= MAX_SAFE_INTEGER
	for i = 26, 12, -1 do
		-- pointer: [0, #BASE_64_URL_CHARACTER]
		local pointer = (
			#BASE_64_URL_CHARACTER
			* config.entropy(config.version, timestamp, config.fingerprint, config._counter) -- noise: [0, 1]
			// 1
		) + 1
		cache_quid[i] = BASE_64_URL_CHARACTER[pointer]
	end

	local quid = table.concat(cache_quid)
	table.clear(cache_quid)
	config._counter += 1

	return quid
end

local Quid = { config = DEFAULT_CONFIG }
Quid.__index = Quid

--- Generate a new quid with global config state
---
--- @within Quid
--- @param version number?
--- @param timestamp number?
--- @return string -- [quid](../docs/intro#-quids-data-structure)
function Quid.next(version: number?, timestamp: number?)
	return generate(DEFAULT_CONFIG, version, timestamp)
end

--- Parse a quid string into its components
---
--- @within Quid
--- @param quid string
--- @return number -- Version
--- @return number -- Timestamp
--- @return number -- Uniqueness
function Quid.parse(quid: string)
	local version = string.sub(quid, 1, 3)
	local timestamp = string.sub(quid, 4, 11)
	local uniqueness = string.sub(quid, 12, 26)

	-- stylua: ignore
	return
		decode(version), 
		decode(timestamp),
		decode(uniqueness)
end

--- Check if x is a valid [quid](../docs/intro#-quids-data-structure)
---
--- @within Quid
--- @param x any | string?
--- @return boolean
function Quid.is(x: any | string?): boolean
	-- stylua: ignore
	return 
		type(x) == "string" and 
		string.find(x, "^[A-Za-z0-9%-_]+$") ~= nil and
		#x == 26
end

--- Update a version of [quid](../docs/intro#-quids-data-structure)
---
--- @error "Invalid quid" -- quid is a base64url string and must be 28 characters
--- @within Quid
--- @param quid string
--- @param target_version number? -- If nil: increment +1 (Can be decrease or increase)
--- @return string -- Updated [quid](../docs/intro#-quids-data-structure)
--- @return number? -- Target version (If nil: not updated)
function Quid.update(quid: string, target_version: number?)
	if not Quid.is(quid) then error("Invalid quid") end

	local current_version = decode(string.sub(quid, 1, 3))
	local component = string.sub(quid, 4)
	local new_version = target_version or current_version + 1
	new_version %= BASE_LENGTH ^ 3

	-- Version (Padding: 4)
	local bucket = table.create(3)
	local version_state = new_version
	for i = 3, 1, -1 do
		local remainder = (version_state % BASE_LENGTH) // 1
		version_state = version_state // BASE_LENGTH
		bucket[i] = BASE_64_URL_CHARACTER[remainder + 1]
	end

	local updated_quid = table.concat(bucket) .. component
	local result_version = new_version ~= current_version and new_version or nil

	-- stylua: ignore
	return 
		updated_quid,
		result_version
end

--- Create a new quid object with custom config state
---
--- @within Quid
--- @param config Config?
--- @return Quid<Config> -- Quid object
function Quid.new(config: Config?)
	local self = setmetatable({}, Quid)
	self.config = config or DEFAULT_CONFIG
	self.config._counter = MAX_SAFE_INTEGER
		* self.config.entropy(self.config.version, self.config.clock(), self.config.fingerprint, self.config._counter)
		// 1

	return self
end

export type Quid = typeof(Quid)

--- Generate a new quid with local config state
---
--- @within Quid
--- @param version number?
--- @param timestamp number?
--- @return string -- [quid](../docs/intro#-quids-data-structure)
function Quid:Next(version: number?, timestamp: number?)
	local self = self :: Quid
	return generate(self.config, version, timestamp)
end

return Quid
