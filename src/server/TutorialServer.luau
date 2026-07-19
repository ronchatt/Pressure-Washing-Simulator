--!strict

-- Persists only whether the lightweight onboarding has been dismissed or
-- completed. Tutorial presentation and milestones remain client-side.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataManager = require(script.Parent:WaitForChild("DataManager"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local TutorialStateRequest = remotes:WaitForChild("TutorialStateRequest") :: RemoteEvent
local TutorialStateChanged = remotes:WaitForChild("TutorialStateChanged") :: RemoteEvent
local TutorialCompleteRequest = remotes:WaitForChild("TutorialCompleteRequest") :: RemoteEvent

local TutorialServer = {}
local initialized = false

local function sendState(player: Player)
	local data = DataManager:GetData(player)
	if data == nil then return false end
	player:SetAttribute("TutorialCompleted", data.TutorialCompleted == true)
	TutorialStateChanged:FireClient(player, { Completed = data.TutorialCompleted == true })
	return true
end

function TutorialServer:Init()
	if initialized then return end
	initialized = true
	TutorialStateRequest.OnServerEvent:Connect(function(player)
		task.spawn(function()
			for _ = 1, 100 do
				if sendState(player) then return end
				task.wait(0.1)
			end
		end)
	end)
	TutorialCompleteRequest.OnServerEvent:Connect(function(player)
		if DataManager:IsTutorialCompleted(player) then sendState(player); return end
		if DataManager:CompleteTutorial(player) then
			TutorialStateChanged:FireClient(player, { Completed = true })
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		player:SetAttribute("TutorialCompleted", nil)
	end)
end

return TutorialServer
