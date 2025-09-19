```lua
local count = wrap(0)

local text = derive(function(from)
    return "count: " .. from(count)
end)

watch(function(from)
    print "changed: " .. from(text)
end)

count.value += 1
```

```lua
-- wraps value in state object
local count = wrap(0)

-- derive new state that dynamically updates
-- when `count` changes
local text = derive(function(from)
    return "count: " .. from(count)
end)

-- alternatively you can do this which functions the same
-- as above, states are overloaded to return new states
local text = "count: " .. count

-- run a callback whenever `text` updates
watch(function(from)
    print "changed: " .. from(text)
end)

count.value += 1
```
