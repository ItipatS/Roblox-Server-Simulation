local blink = require(game.ReplicatedStorage.net)
local textLabel = script.Parent

blink.Firefly.On(function(Normal, Common, Uncommon, Rare, Epic, Legendary)
    local displayText = string.format(
        "Dust Spawn Counts:\nNormal: %d\nCommon: %d\nUncommon: %d\nRare: %d\nEpic: %d\nLegendary: %d",
        Normal, Common, Uncommon, Rare, Epic, Legendary
    )
    textLabel.Text = displayText
	
end)