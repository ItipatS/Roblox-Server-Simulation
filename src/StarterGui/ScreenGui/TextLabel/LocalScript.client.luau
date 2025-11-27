local blink = require(game.ReplicatedStorage.ClientNet)
local textLabel = script.Parent

blink.Firefly.On(function(payload)
    local displayText = string.format(
        "Dust Spawn Counts:\nNormal: %d\nCommon: %d\nUncommon: %d\nRare: %d\nEpic: %d\nLegendary: %d",
        payload.Normal, payload.Common, payload.Uncommon, payload.Rare, payload.Epic, payload.Legendary
    )
    textLabel.Text = displayText
	
end)