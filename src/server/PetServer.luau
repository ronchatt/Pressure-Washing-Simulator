--!strict

-- Server-authoritative egg hatching, inventory, and pet multiplier state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DataManager = require(script.Parent:WaitForChild("DataManager"))
local MonetizationManager = require(script.Parent:WaitForChild("MonetizationManager"))
local SharedPetData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SharedPetData"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local HatchEggRequest = remotes:WaitForChild("HatchEggRequest") :: RemoteEvent
local PetHatched = remotes:WaitForChild("PetHatched") :: RemoteEvent
local EquipPetRequest = remotes:WaitForChild("EquipPetRequest") :: RemoteEvent
local PetInventoryChanged = remotes:WaitForChild("PetInventoryChanged") :: RemoteEvent
local PetInventoryRequest = remotes:WaitForChild("PetInventoryRequest") :: RemoteEvent

local PetServer = {}
local initialized = false
local rng = Random.new()

local function contains(pets: {string}, petName: string): boolean
	for _, ownedPet in pets do
		if ownedPet == petName then
			return true
		end
	end
	return false
end

local function choosePet(): string
	local totalWeight = 0
	for _, petID in SharedPetData.PetOrder do
		totalWeight += SharedPetData.Pets[petID].Weight
	end

	local roll = rng:NextNumber(0, totalWeight)
	local runningWeight = 0
	for _, petID in SharedPetData.PetOrder do
		runningWeight += SharedPetData.Pets[petID].Weight
		if roll <= runningWeight then
			return petID
		end
	end

	return SharedPetData.PetOrder[#SharedPetData.PetOrder]
end

local function applyPetSpeed(player: Player)
	local data = DataManager:GetData(player)
	local pet = data and data.EquippedPet and SharedPetData.Pets[data.EquippedPet]
	local speedMultiplier = pet and pet.SpeedMult or 1
	player:SetAttribute("PetSpeedMultiplier", speedMultiplier)
	player:SetAttribute("PetCashMultiplier", pet and pet.CashMult or 1)

	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		MonetizationManager:ApplyWalkSpeed(player)
	end
end

local function syncInventory(player: Player)
	local data = DataManager:GetData(player)
	if data == nil then
		return
	end

	PetInventoryChanged:FireClient(player, {
		OwnedPets = data.OwnedPets,
		EquippedPet = data.EquippedPet,
	})
end

local function ensureEggPrompt()
	local artistBase = Workspace:FindFirstChild("Base")
	local incubator = artistBase and (artistBase:FindFirstChild("Egg") or artistBase:FindFirstChild("Egg holder"))
	if incubator == nil then
		local environment = Workspace:FindFirstChild("EnvironmentFixtures")
		local fallbackBase = environment and environment:FindFirstChild("Base")
		incubator = fallbackBase and fallbackBase:FindFirstChild("EggIncubator")
	end
	if incubator == nil then
		warn("PetServer could not find Workspace.Base.Egg")
		return
	end

	local promptParent: BasePart? = nil
	if incubator:IsA("Model") then
		promptParent = incubator.PrimaryPart or incubator:FindFirstChildWhichIsA("BasePart", true)
	elseif incubator:IsA("BasePart") then
		promptParent = incubator
	end
	if promptParent == nil then
		return
	end
	local existingPrompt = promptParent:FindFirstChild("EggPrompt")
	if existingPrompt ~= nil and existingPrompt:IsA("ProximityPrompt") then
		existingPrompt.ActionText = "Buy Egg"
		existingPrompt.ObjectText = string.format("Pet Egg ($%d)", SharedPetData.EggCost)
		return
	elseif existingPrompt ~= nil then
		existingPrompt:Destroy()
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "EggPrompt"
	prompt.ActionText = "Buy Egg"
	prompt.ObjectText = string.format("Pet Egg ($%d)", SharedPetData.EggCost)
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = promptParent
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid")
		applyPetSpeed(player)
	end)

	task.spawn(function()
		for _ = 1, 100 do
			if DataManager:GetData(player) ~= nil then
				applyPetSpeed(player)
				syncInventory(player)
				return
			end
			task.wait(0.1)
		end
	end)
end

function PetServer:Init()
	if initialized then
		return
	end
	initialized = true

	ensureEggPrompt()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end

	HatchEggRequest.OnServerEvent:Connect(function(player)
		local data = DataManager:GetData(player)
		if data == nil then
			return
		end
		if SharedPetData.EggCost > 0 and not DataManager:DeductCash(player, SharedPetData.EggCost) then
			return
		end

		local petID = choosePet()
		table.insert(data.OwnedPets, petID)
		PetHatched:FireClient(player, petID)
		syncInventory(player)
	end)

	EquipPetRequest.OnServerEvent:Connect(function(player, petID)
		if typeof(petID) ~= "string" then
			return
		end

		local data = DataManager:GetData(player)
		if data == nil or SharedPetData.Pets[petID] == nil or not contains(data.OwnedPets, petID) then
			return
		end

		data.EquippedPet = petID
		applyPetSpeed(player)
		syncInventory(player)
	end)

	PetInventoryRequest.OnServerEvent:Connect(syncInventory)
end

return PetServer
