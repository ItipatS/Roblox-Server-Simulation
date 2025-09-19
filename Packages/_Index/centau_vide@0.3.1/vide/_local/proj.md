```lua
local root = vide.root
local source = vide.source
local derive = vide.derive
local create = vide.create

local function Counter()
    local count = source(0)

    local text = derive(function()
        return tostring(count)
    end)

    return create "TextButton" {
        Text = function()
            return "count: " .. text()
        end,

        Activated = function()
            count(count() + 1)
        end
    }
end

local app, destroy = root(Counter)
```

```lua
local function Inventory(props: { Items: () -> Array<Item> })
    return create "Frame" {
        indexes(props.Items, function(item, i)
            return ItemDisplay {
                Item = item,
                LayoutOrder = i
            }
        end)
    }
end

local items = source {} :: () -> Array<Item>

root(function()
    return Inventory {
        Items = items
    }
end)
```

```lua
local value = source(10)

root(function()
    local anim = spring(value)

    return create "TextLabel" {
        Text = anim
    }
end)
```
