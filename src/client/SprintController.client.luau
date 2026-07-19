--!strict

-- Hold either Shift key to sprint. The server applies the final movement speed
-- so pet and gamepass multipliers stack consistently and remain authoritative.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local SprintStateRequest = ReplicatedStorage
	:WaitForChild("Remotes")
	:WaitForChild("SprintStateRequest") :: RemoteEvent

local sprinting = false

local function setSprinting(enabled: boolean)
	if sprinting == enabled then
		return
	end
	sprinting = enabled
	SprintStateRequest:FireServer(enabled)
end

UserInputService.InputBegan:Connect(function(input, _gameProcessed)
	-- Shift Lock may mark Shift as processed; sprint should still respond.
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		setSprinting(true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		setSprinting(false)
	end
end)

UserInputService.WindowFocusReleased:Connect(function()
	setSprinting(false)
end)

player.CharacterAdded:Connect(function()
	sprinting = false
	SprintStateRequest:FireServer(false)
end)
