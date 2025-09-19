```lua
-- pool.entities[i] corresponds to pool.values[i]
local pool = {
    entities = { 100, 101, 102, 103 }, -- 16 bytes per entity
    values = { "a", "b", "c", "d" }
}
```

```lua
-- pool.entities[(i // 3 + i % 3) + 1] corresponds to pool.values[i]
local pool = {
    entities = { vector(100, 101, 102), vector(103, 0, 0) }, -- 16/3 bytes per entity (5.33 bytes)
    values = { "a", "b", "c", "d" }
}
```
