# Server-Simulation — Thousands of Dust on a Custom Net (jecs + Blink)

A Roblox **networking-at-scale playground**: thousands of "dust" / firefly particles driven by a pure [jecs](https://github.com/ukendio/jecs) ECS world and streamed over a custom [Blink](https://github.com/1Axen/blink) net layer — no server Instances, client-rendered only.

It started as a bandwidth experiment and turned into a study of **where the line between "server-authoritative" and "client-reconstructed" should sit**, exploring that whole spectrum through a set of switchable *modes*.

## Demo
- Place: https://www.roblox.com/games/129984384759966/Server-Simulation
- Video: [![Watch the video](https://img.youtube.com/vi/ooikRRlfHRs/0.jpg)](https://youtu.be/ooikRRlfHRs)

## The bandwidth core

The baseline sim (Drift) streams every dust's position every tick. The work was getting that cheap:

- **No per-dust id on the wire.** Each dust gets a stable dense **slot** at spawn; deltas are written in slot order, so the client maps slot → entity from the spawn payload. The 2-byte id per dust just disappears.
- **int8 fixed-point deltas.** Per-axis movement is quantized to `i8` (2 cm steps) with residual carry, so 6-byte vectors become 3 bytes — and edge-wrap teleports route to a reliable absolute channel.
- **Position-diffing in the network layer** collapses the 20 Hz sim → 12 Hz net redundancy into one delta per dust per tick.

Result: **~200 KB/s → ~50 KB/s** per client at the original count, and it scales linearly with no per-dust overhead.

## The modes — a spectrum of "who knows what"

The same dust field renders under switchable modes, each a different answer to *what has to cross the wire*:

| Mode | Authority | On the wire | Cost |
|---|---|---|---|
| **Drift** | Server owns every dust's motion (drift, flee, push) | dense i8 position deltas | scales with count |
| **Ocean / Shore / Wall** | Nobody — pure `f(slot, GetServerTimeNow(), events)` | a mode id + tiny one-shot events | ~0, any count |
| **Hunt** | Server simulates a small **predator flock** (boids); dust flee them | ~dozens of leader positions | tiny |
| **Spread** | Server-authoritative **contagion**: per-dust state spreads via neighbors | dense per-dust heat (`u8`) | the emergent data itself |

The water/wall modes look coordinated and cost nothing because coherence comes from a **server-synced clock**, not from anyone tracking anything — every client computes the identical wave. Hunt is the "few authoritative leaders + many cheap followers" pattern. Spread is the opposite extreme: genuine N-body interaction (a forest-fire model) that **no client formula could reproduce**, so its state is computed server-side and streamed.

## Architecture

- **Pure jecs world** — no server Instances for dust; everything is ECS components, scheduled through a phase-based system runner.
- **Blink networking** — buffer-packed events, regenerated from `Net.blink` (never hand-edited). Unreliable deltas + reliable snapshots/state.
- **`std/` shared modules**
  - `layout.luau` — count-scaled geometry (every mode's area grows/shrinks with the live dust count) shared by client and server.
  - `fieldeval.luau` — client-side field reconstruction (waves, ripples, flock, fire color).
  - `spatialhash.luau` — pooled uniform-grid spatial hash for O(N·k) neighbor queries (the Spread sim).
  - `slotmap.luau` / `modes.luau` / `config.luau` — slot↔entity map, mode enum, central knobs.
- **Runtime dust-count control** — an in-game panel (single-controller, first-come-first-serve) respawns the field at a new count; geometry rescales on both ends.
- **Tick rates** — sim 20 Hz, net 12 Hz, client render 60 Hz.

## Tech
jecs (ECS) · Blink (networking IDL/codegen) · Rojo · Rokit (toolchain)

---

*This is an R&D sandbox — deliberately the "wrong tool for an easy job" to find out where each replication strategy actually pays off.*
