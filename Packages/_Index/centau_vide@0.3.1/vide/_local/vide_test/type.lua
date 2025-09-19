--!strict

local path = game.ReplicatedStorage.packages.vide
local vide = require(path)
type State<T> = vide.State<T>
type Prop<T> = vide.Prop<T>
local create = vide.create
local apply = vide.apply
local wrap = vide.wrap
local watch = vide.watch
local derive = vide.derive
local foreach = vide.foreach
local match = vide.match
local spring = vide.spring
local Layout = vide.Layout
local Children = vide.Children
local Event = vide.Event
local Changed = vide.Changed
local Bind = vide.Bind
local Created = vide.Created

local function Bouncy(p: any)
    local U = UDim2.fromScale(0.2, 0.2)
    local V = UDim2.fromScale(0.4, 0.4)

    local size = wrap(U)
    local sprung: any = spring(size, 3, .3)

    --watch(function()
      --  warn(sprung.value)
   -- end)

    local frame = create("Frame") {
        Name = "SpringTest",

        Size = sprung,
        [Layout] = p[Layout],

        [Event.MouseEnter] = function()
            print("entered")
            size.value = V
        end,

        [Event.MouseLeave] = function()
            print("left")
            size.value = U
        end
    }

    print(sprung)

    return frame
end

local bouncy = Bouncy {
    [Layout] = {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5)
    }
}

create("ScreenGui") {
    Parent = game.Players.LocalPlayer.PlayerGui,

    [Children] = {
        bouncy
    }
}

return 1
