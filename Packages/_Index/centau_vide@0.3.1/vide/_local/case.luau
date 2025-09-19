local vide = require "src/init"
local source = vide.source
local effect = vide.effect
local untrack = vide.untrack
local cleanup = vide.cleanup
local mount = vide.mount

vide.strict = false

local cleaned = 0

local function Count()
    local count = source(0)

    effect(function()
        count()
        cleanup(function() cleaned += 1 end)
    end)

    return nil
end

local function App()
    local name = source "joe"

    effect(function()
        name()
        untrack(Count)
    end)

    name "bob"

    print(cleaned)
end

mount(App)
