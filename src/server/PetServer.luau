--!strict

-- Server-authoritative egg hatching, inventory, and pet multiplier state.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
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
local lastHatchAt: {[Player]: number} = {}
local HATCH_COOLDOWN = 1.5

local function migratePetData(data: any)
	local rawPets = data.OwnedPets :: {any}
	local migrated = {}
	local oldEquipped = data.EquippedPet
	local migratedEquipped: string? = nil
	for _, entry in rawPets do
		local uid: string?
		local petID: string?
		if typeof(entry) == "string" then
			petID = entry
			uid = HttpService:GenerateGUID(false)
		elseif typeof(entry) == "table" then
			petID = if typeof(entry.PetID) == "string" then entry.PetID else nil
			uid = if typeof(entry.UID) == "string" then entry.UID else HttpService:GenerateGUID(false)
		end
		if uid and petID and SharedPetData.Pets[petID] then
			table.insert(migrated, { UID = uid, PetID = petID })
			if oldEquipped == uid or (migratedEquipped == nil and oldEquipped == petID) then
				migratedEquipped = uid
			end
		end
	end
	data.OwnedPets = migrated
	data.EquippedPet = migratedEquipped
end

local function findOwnedPet(data: any, uid: string): any?
	for _, ownedPet in data.OwnedPets do
		if ownedPet.UID == uid then return ownedPet end
	end
	return nil
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
	local ownedPet = data and data.EquippedPet and findOwnedPet(data, data.EquippedPet)
	local pet = ownedPet and SharedPetData.Pets[ownedPet.PetID]
	local speedMultiplier = pet and pet.SpeedMult or 1
	player:SetAttribute("PetSpeedMultiplier", speedMultiplier)
	player:SetAttribute("PetCashMultiplier", pet and pet.CashMult or 1)
	player:SetAttribute("EquippedPetID", ownedPet and ownedPet.PetID or nil)
	player:SetAttribute("EquippedPetUID", ownedPet and ownedPet.UID or nil)

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
	migratePetData(data)

	PetInventoryChanged:FireClient(player, {
		OwnedPets = table.clone(data.OwnedPets),
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
			local data = DataManager:GetData(player)
			if data ~= nil then
				migratePetData(data)
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
		local now = os.clock()
		if now - (lastHatchAt[player] or 0) < HATCH_COOLDOWN then
			PetHatched:FireClient(player, { Success = false, Message = "The incubator is still resetting." })
			return
		end
		lastHatchAt[player] = now
		if not DataManager:DeductCash(player, SharedPetData.EggCost) then
			PetHatched:FireClient(player, { Success = false, Message = "You need $" .. SharedPetData.EggCost .. " to hatch an egg." })
			return
		end

		local petID = choosePet()
		local ownedPet = { UID = HttpService:GenerateGUID(false), PetID = petID }
		table.insert(data.OwnedPets, ownedPet)
		PetHatched:FireClient(player, { Success = true, Pet = ownedPet })
		syncInventory(player)
	end)

	EquipPetRequest.OnServerEvent:Connect(function(player, petUID)
		local data = DataManager:GetData(player)
		if data == nil then return end
		if petUID == nil or petUID == "" then
			data.EquippedPet = nil
		elseif typeof(petUID) == "string" and findOwnedPet(data, petUID) ~= nil then
			data.EquippedPet = petUID
		else
			return
		end
		applyPetSpeed(player)
		syncInventory(player)
	end)

	PetInventoryRequest.OnServerEvent:Connect(syncInventory)
	Players.PlayerRemoving:Connect(function(player) lastHatchAt[player] = nil end)
end

return PetServer
