```lua
local external_children: Source<Array<Instance>> = require(...)




```

```lua
local items = source {} :: () -> Array<Item>
local selected = source() :: () -> Item?

local function Inventory()
    return Frame {
        Children = indexes(items, function(item)
            return Slot {
                Selected = function()
                    return selected() == item()
                end
            }
        end)
    }
end

return root(Inventory)
```
