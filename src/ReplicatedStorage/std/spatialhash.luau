--!optimize 2
--!native
--!strict
--
-- Uniform-grid spatial hash for fast neighbor queries over thousands of points. Turns the
-- O(N^2) "every dust checks every dust" into O(N * k): each point only looks in its own
-- cell and the 26 around it. Cell size should be >= the query radius, so a point's whole
-- neighborhood lives in that 3x3x3 block.
--
-- Bucket lists are pooled and reused every rebuild, so steady-state runs allocation-free.

local SpatialHash = {}
SpatialHash.__index = SpatialHash

-- Cell coords are packed into a single integer key. OFFSET shifts negatives positive;
-- STRIDE must exceed the world span measured in cells (±~500 cells = a ±500*cell world).
local OFFSET = 512
local STRIDE = 1024
local STRIDE2 = STRIDE * STRIDE

local function cellKey(cx: number, cy: number, cz: number): number
	return (cx + OFFSET) + (cy + OFFSET) * STRIDE + (cz + OFFSET) * STRIDE2
end

export type SpatialHash = typeof(setmetatable(
	{} :: {
		inv: number,
		buckets: { [number]: { number } },
		used: { number }, -- keys touched since the last rebuild
		pool: { { number } }, -- recycled id-lists
	},
	SpatialHash
))

function SpatialHash.new(cellSize: number): SpatialHash
	return setmetatable({
		inv = 1 / cellSize,
		buckets = {},
		used = {},
		pool = {},
	}, SpatialHash)
end

-- Recycle last rebuild's lists, then clear. Call once before re-inserting all points.
function SpatialHash.beginFrame(self: SpatialHash)
	local buckets = self.buckets
	local pool = self.pool
	for _, key in self.used do
		local arr = buckets[key]
		if arr then
			table.clear(arr)
			pool[#pool + 1] = arr
			buckets[key] = nil
		end
	end
	table.clear(self.used)
end

function SpatialHash.insert(self: SpatialHash, id: number, x: number, y: number, z: number)
	local inv = self.inv
	local key = cellKey(math.floor(x * inv), math.floor(y * inv), math.floor(z * inv))
	local arr = self.buckets[key]
	if not arr then
		local pool = self.pool
		local m = #pool
		if m > 0 then
			arr = pool[m]
			pool[m] = nil
		else
			arr = {}
		end
		self.buckets[key] = arr
		self.used[#self.used + 1] = key
	end
	arr[#arr + 1] = id
end

-- Fill `out` with candidate ids in the 3x3x3 cell block around (x,y,z); returns the count.
-- The caller filters by actual distance. `out` is reused across calls, so only indices
-- 1..count are valid after each call.
function SpatialHash.queryInto(self: SpatialHash, x: number, y: number, z: number, out: { number }): number
	local inv = self.inv
	local cx = math.floor(x * inv)
	local cy = math.floor(y * inv)
	local cz = math.floor(z * inv)
	local buckets = self.buckets
	local count = 0
	for dx = -1, 1 do
		for dy = -1, 1 do
			for dz = -1, 1 do
				local arr = buckets[cellKey(cx + dx, cy + dy, cz + dz)]
				if arr then
					for i = 1, #arr do
						count += 1
						out[count] = arr[i]
					end
				end
			end
		end
	end
	return count
end

return SpatialHash
