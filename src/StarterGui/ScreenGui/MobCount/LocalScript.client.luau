local label = script.Parent
local replicated = game:GetService("ReplicatedStorage")
local count = replicated:WaitForChild("Count")

count.Changed:Connect(function(value)
	label.Text = "Mob Count :" .. value
end)
