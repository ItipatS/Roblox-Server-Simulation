local count = game.ReplicatedStorage:WaitForChild("count")

local text = script.Parent

count.Changed:Connect(function(value)
	text.Text = "Entities Count: " .. value
end)