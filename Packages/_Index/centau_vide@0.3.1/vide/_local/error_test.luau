local vide = require "src/init"
local mount = vide.mount
local root = vide.root
local create = vide.create
local source = vide.source
local derive = vide.derive
local effect = vide.effect
local cleanup = vide.cleanup
local indexes = vide.indexes

-- vide.mount(function()
--     local outer = source {
--         source(1),
--         source(2)
--     }

--     effect(function()
--         local v = outer()[1]()
--         print(v)
--     end)

--     outer()[1](100)
-- end)

vide.mount(function()
    local list = source { 1, 2, 3 }

    local children = indexes(list, function(item, i)
        return derive(function()
            return item()
        end)
    end)

    local extra = derive(function()
        return list()
    end)

    list { 2, 3, 4 }
end)
