--!strict
-- Central tuning knobs, shared by server and client (lives in ReplicatedStorage so the
-- client reads the exact same values the server spawned with).
--
-- MAX_DUST is the single source of truth for the particle count. Edit it here only:
--   * server Spawn.luau spawns exactly this many (slots 0..MAX_DUST-1, contiguous)
--   * client fieldeval.luau lays the ocean out for the same count
-- The no-id dense-slot replication scheme is count-agnostic, so raising/lowering this
-- needs no other changes — add or remove dust freely.
return table.freeze({
	MAX_DUST = 3000,

	-- Hunt mode: number of server-simulated predator boids. Their roaming bounds (and the
	-- dust cloud / wall cube / ocean area) are all count-scaled in std.layout.
	LEADER_COUNT = 32,
})
