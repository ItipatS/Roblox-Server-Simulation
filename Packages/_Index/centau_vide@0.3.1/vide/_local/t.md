--------------------------------------------------------------------------------------------------------------
-- vide/bind.lua
--------------------------------------------------------------------------------------------------------------

if not game then
    script = (require :: any) "test/wrap-require"
end

local graph = require(script.Parent.graph)
type Node<T> = graph.Node<T>
local get = graph.get
local setEffect = graph.setEffect

local throw = require(script.Parent.throw)
local flags = require(script.Parent.flags)

local WEAK_KEYS = { __mode = "k" }
local WEAK_VALUES = { __mode = "v" }

local function bindProperty(node: Node<unknown>, property: string)
    return function(instance: Instance)
        (instance :: any)[property] = get(node)
    end
end

local function bindChildren(node: Node<{ Instance }?>)
    local currentChildrenSet: { [Instance]: true } = {} -- cache of all children parented before update
    local newChildrenSet: { [Instance]: true } = {} -- cache of all children parented after update

    return function(parent: Instance)
        local newChildren = get(node) -- all (and only) children that should be parented after this update
        if newChildren and type(newChildren) ~= "table" then
            throw(`Cannot parent instance of type { type(newChildren) } `)
        end

        if newChildren then
            for _, child in next, newChildren do
                newChildrenSet[child] = true -- record child set from this update
                if not currentChildrenSet[child] then
                    child.Parent = parent -- if child wasn't already parented then parent it
                else 
                    currentChildrenSet[child] = nil -- remove child from cache if it was already in cache
                end
            end
        end

        for child in next, currentChildrenSet do
            child.Parent = nil -- unparent all children that weren't in the new children set
        end

        table.clear(currentChildrenSet) -- clear cache, preserve capacity
        currentChildrenSet, newChildrenSet = newChildrenSet, currentChildrenSet
    end
end

local function bindEvent(node: Node<(...unknown) -> ()>, event: RBXScriptSignal)
    local current: RBXScriptConnection? = nil
    return function(instance: Instance) 
        if current then
            current:Disconnect()
            current = nil
        end
        current = event:Connect(get(node))
    end
end

-- instances with bound properties will prevent gc of states bound
local boundStates: { [Instance]: { [Node<unknown>]: true } } = {}
setmetatable(boundStates :: any, WEAK_KEYS)

-- prevent gc of parented instances
local refs: { [Instance]: true } = {}

function bind(state: Node<any>, instance: Instance, mode: "Property"|"Children"|"Event", target: unknown?)
    local binding: (Instance) -> () = 
        if mode == "Property" then
            bindInstanceProperty(state, target :: string)
        elseif mode == "Children" then
            bindInstanceChildren(state :: Node<{ Instance }?>)
        elseif mode == "Event" then
            bindInstanceEvent(state, target :: RBXScriptSignal)
        else error("Unknown mode", 2)

    if flags.strict then
        local fn = binding
        local trace = debug.traceback("Error while setting instance property", 4)
        binding = function(key: Instance)
            local ok, err: string? = pcall(fn, key)
            if not ok then warn(trace .. err :: string) end
        end
    end

    binding(instance)
    setEffect(state, binding :: (unknown) -> (), instance)

    if not boundStates[instance] then
        local tmp = setmetatable({ instance }, WEAK_VALUES) -- TODO: find better solution to allowing gc
        local function ref()
            local instance = tmp[1]
            if not instance then return end
            if not instance.Parent then
                refs[instance] = nil
            else
                refs[instance] = true
            end
        end
        instance:GetPropertyChangedSignal("Parent"):Connect(ref)
        ref()
    end

    local instanceBoundStates = boundStates[instance]
    if instanceBoundStates then
       instanceBoundStates[state] = true
    else
        boundStates[instance] = { [state] = true }
    end
end

return bind
