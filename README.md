# JECS Server Authoritative Dust Field – 1,500 Entities on Custom Net (Blink)

This project is a **JECS-only simulation** of thousands of “dust” / firefly particles, driven entirely by:

- **Pure ECS data** (no server-side Instances)
- **Custom networking** using **Blink**
- **Client-side rendering & effects**

Compared to my other JECS RPG/Mob demo (which leans on Roblox physics and replication), this project pushes the opposite direction:

> Turn Roblox into a pure data-sim and stream just the minimal deltas over a custom net layer.

With **1,500 dust entities**, the system runs at around **~200 KB/s network intake** (client), with smooth visuals and state changes.
# Demo Place
https://www.roblox.com/games/129984384759966/Server-Simulation
---
## Demo Video

[![Watch the video](https://img.youtube.com/vi/ooikRRlfHRs/0.jpg)](https://youtu.be/ooikRRlfHRs)
---
## Features
- **1,500+ dust entities** simulated server-side
- **Player interaction**
  - Dust flees from predicted player movement direction
  - Push reactions when players run through dust
  - Neighbor “panic spread” to nearby dust
- **Join-in-progress sync** using bulk batched data
- **Client-rendered visuals only**

## Architecture
- **Pure JECS server world**
  - No server Instances for dust; all data is ECS components
- **Blink-based networking**
  - `SpawnDust` – initial batch spawn
  - `UpdateTransformDelta` – movement deltas
  - `UpdateTransformFull` – periodic full syncs
  - `UpdateDustState` – flee state deltas
- **Mailbox pattern** for deferred, batched updates
  - Systems push `PendingMovements` and `PendingStates`
  - Networking drains and batches them every tick
- **Tick rates**
  - Simulation: **20 Hz**  
  - Networking: **12 Hz**  
  - Client Effects: **60 Hz**  
- **Client ECS mirror**
  - Client tracks `Dust`, `Transform`, `DustData`, `DustState`, `Model`
  - Drives color transitions and flee visuals

## Benefits
- Scales to thousands of live simulated entities
- Demonstrates custom netcode design (delta + snapshots)
- Clean separation of server simulation vs client rendering
- Data-driven rarity, visuals, and behavior
- Production-ready architecture patterns (mailbox, batching, drift correction)

---

