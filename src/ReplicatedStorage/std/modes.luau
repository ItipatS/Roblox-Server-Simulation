--!strict
-- Shared mode enum. Server and client must agree on these ids; they travel over the
-- wire as a u8 (see Net.blink SetMode / RequestSetMode).
local Modes = {
	Drift = 0, -- default server-driven drift sim (streams positions)
	Ocean = 1, -- client-computed wave field, depth layers, bulge under player, jump splash
	Wall = 2, -- shockwave curtain: player hits send gradient shockwaves
	Shore = 3, -- shallow water: walking + jumping spread splashes
	Hunt = 4, -- server-simulated predator flock; dust flee them (leaders + followers)
	Spread = 5, -- server-authoritative contagion: per-dust state spreads via neighbors
}

local names: { [number]: string } = {
	[0] = "Drift",
	[1] = "Ocean",
	[2] = "Wall",
	[3] = "Shore",
	[4] = "Hunt",
	[5] = "Spread",
}

return table.freeze({
	Drift = Modes.Drift,
	Ocean = Modes.Ocean,
	Wall = Modes.Wall,
	Shore = Modes.Shore,
	Hunt = Modes.Hunt,
	Spread = Modes.Spread,
	names = names,
})
