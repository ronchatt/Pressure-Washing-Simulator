--!strict

-- Controls the hand-authored StarterGui.PetUI. Each manual pet button should
-- either be named with its pet ID or have a string PetID attribute.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function waitForDescendant(root: Instance, name: string, timeout: number): Instance?
	local deadline = os.clock() + timeout
	repeat
		local candidate = root:FindFirstChild(name, true)
		if candidate then
			return candidate
		end
		task.wait(0.1)
	until os.clock() >= deadline
	return nil
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local petGuiInstance = playerGui:WaitForChild("PetUI", 10)
if petGuiInstance == nil or not petGuiInstance:IsA("ScreenGui") then
	warn(string.format(
		"Type mismatch: PlayerGui.PetUI found %s; expected ScreenGui.",
		petGuiInstance and petGuiInstance.ClassName or "nil (not found)"
	))
	return
end
local petGui = petGuiInstance
local inventoryFrameInstance = waitForDescendant(petGui, "Frame", 10)
if inventoryFrameInstance == nil
	or (not inventoryFrameInstance:IsA("Frame") and not inventoryFrameInstance:IsA("ScrollingFrame"))
then
	warn(string.format(
		"Type mismatch: PlayerGui.PetUI.Frame found %s; expected Frame or ScrollingFrame.",
		inventoryFrameInstance and inventoryFrameInstance.ClassName or "nil (not found)"
	))
	return
end
local inventoryFrame = inventoryFrameInstance :: GuiObject

-- Prefer the final authored name. During this transition, migrate the current
-- TextButton automatically so Studio and the controller agree on OpenPets.
local openPetsInstance = waitForDescendant(inventoryFrame, "OpenPets", 1)
if openPetsInstance == nil then
	openPetsInstance = waitForDescendant(inventoryFrame, "TextButton", 2)
		or waitForDescendant(petGui, "OpenPets", 1)
		or waitForDescendant(petGui, "TextButton", 2)

	-- Last-resort compatibility for manually renamed/nested buttons.
	if openPetsInstance == nil then
		for _, descendant in petGui:GetDescendants() do
			if descendant:IsA("GuiButton") then
				local lowerName = string.lower(descendant.Name)
				local lowerText = if descendant:IsA("TextButton") then string.lower(descendant.Text) else ""
				if string.find(lowerName, "pet", 1, true)
					or string.find(lowerName, "open", 1, true)
					or string.find(lowerText, "pet", 1, true)
				then
					openPetsInstance = descendant
					break
				end
			end
		end
	end
	if openPetsInstance then
		openPetsInstance.Name = "OpenPets"
	end
end
if openPetsInstance == nil or (not openPetsInstance:IsA("TextButton") and not openPetsInstance:IsA("ImageButton")) then
	warn(string.format(
		"Type mismatch: PlayerGui.PetUI.Frame.OpenPets found %s; expected TextButton or ImageButton.",
		openPetsInstance and openPetsInstance.ClassName or "nil (not found)"
	))
	return
end
local openPetsButton = openPetsInstance :: GuiButton

local closePetsButton: GuiButton? = nil
for _, descendant in inventoryFrame:GetDescendants() do
	if descendant:IsA("GuiButton") and descendant ~= openPetsButton then
		local action = descendant:GetAttribute("Action")
		local lowerName = string.lower(descendant.Name)
		local lowerText = if descendant:IsA("TextButton") then string.lower(descendant.Text) else ""
		if action == "ClosePets"
			or action == "Close"
			or string.find(lowerName, "close", 1, true)
			or lowerName == "x"
			or lowerText == "close"
			or lowerText == "x"
		then
			closePetsButton = descendant
			break
		end
	end
end

local originalVisibility: {[GuiObject]: boolean} = {}
for _, descendant in inventoryFrame:GetDescendants() do
	if descendant:IsA("GuiObject") then
		originalVisibility[descendant] = descendant.Visible
	end
end
local originalBackgroundTransparency = inventoryFrame.BackgroundTransparency
local popupOpen = false

local function setPopupVisible(visible: boolean)
	popupOpen = visible
	-- Keep the root visible because OpenPets is nested inside it. Collapse its
	-- other descendants and background instead of hiding the ancestor itself.
	inventoryFrame.Visible = true
	inventoryFrame.BackgroundTransparency = if visible then originalBackgroundTransparency else 1

	for guiObject, wasVisible in originalVisibility do
		if guiObject == openPetsButton or openPetsButton:IsDescendantOf(guiObject) then
			guiObject.Visible = true
		else
			guiObject.Visible = if visible then wasVisible else false
		end
	end

	if closePetsButton then
		closePetsButton.Visible = visible
		openPetsButton.Visible = not visible
	else
		-- Without a separate close button, OpenPets doubles as a toggle.
		openPetsButton.Visible = true
	end
end

local SharedPetData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SharedPetData"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local HatchEggRequest = remotes:WaitForChild("HatchEggRequest") :: RemoteEvent
local PetHatched = remotes:WaitForChild("PetHatched") :: RemoteEvent
local EquipPetRequest = remotes:WaitForChild("EquipPetRequest") :: RemoteEvent
local PetInventoryChanged = remotes:WaitForChild("PetInventoryChanged") :: RemoteEvent
local PetInventoryRequest = remotes:WaitForChild("PetInventoryRequest") :: RemoteEvent

local ownedPets: {string} = {}
local equippedPet: string? = nil
local petButtons: {[string]: GuiButton} = {}
local baseButtonText: {[GuiButton]: string} = {}

local statusLabel: TextLabel? = nil
local namedStatus = inventoryFrame:FindFirstChild("HatchResult", true)
if namedStatus and namedStatus:IsA("TextLabel") then
	statusLabel = namedStatus
else
	statusLabel = inventoryFrame:FindFirstChildWhichIsA("TextLabel", true)
end

local function petIDForButton(button: GuiButton): string?
	local attribute = button:GetAttribute("PetID")
	if typeof(attribute) == "string" and SharedPetData.Pets[attribute] ~= nil then
		return attribute
	end
	if SharedPetData.Pets[button.Name] ~= nil then
		return button.Name
	end
	local text = if button:IsA("TextButton") then button.Text else ""
	for petID in SharedPetData.Pets do
		if string.find(button.Name, petID, 1, true) or string.find(text, petID, 1, true) then
			return petID
		end
	end
	return nil
end

for _, descendant in inventoryFrame:GetDescendants() do
	if descendant:IsA("GuiButton") then
		local petID = petIDForButton(descendant)
		if petID then
			petButtons[petID] = descendant
			if descendant:IsA("TextButton") then
				baseButtonText[descendant] = descendant.Text
			end
			descendant.Activated:Connect(function()
				EquipPetRequest:FireServer(petID)
			end)
		end
	end
end

local function renderInventory()
	local ownedSet: {[string]: boolean} = {}
	for _, petID in ownedPets do
		ownedSet[petID] = true
	end

	for petID, button in petButtons do
		button.Visible = ownedSet[petID] == true
		button:SetAttribute("Equipped", equippedPet == petID)
		if button:IsA("TextButton") then
			local original = baseButtonText[button] or petID
			button.Text = if equippedPet == petID then original .. "  •  EQUIPPED" else original
		end
	end

	if not popupOpen then
		setPopupVisible(false)
	end
end

openPetsButton.Activated:Connect(function()
	if popupOpen and closePetsButton == nil then
		setPopupVisible(false)
	else
		setPopupVisible(true)
		PetInventoryRequest:FireServer()
	end
end)

if closePetsButton then
	closePetsButton.Activated:Connect(function()
		setPopupVisible(false)
	end)
else
	warn("PetUI has no Close/ClosePets/X button; OpenPets will toggle the popup instead.")
end

-- Start collapsed; inventory synchronization must not open the popup.
setPopupVisible(false)

ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt.Name == "EggPrompt" then
		HatchEggRequest:FireServer()
	end
end)

PetHatched.OnClientEvent:Connect(function(petID)
	local pet = SharedPetData.Pets[petID]
	if pet == nil or statusLabel == nil then
		return
	end

	local label = statusLabel :: TextLabel
	local previousText = label.Text
	label.Text = string.format("YOU HATCHED A %s!  •  %s", pet.Name:upper(), pet.Rarity)
	task.delay(3, function()
		if label.Parent ~= nil then
			label.Text = previousText
		end
	end)
end)

PetInventoryChanged.OnClientEvent:Connect(function(inventory)
	if typeof(inventory) ~= "table" then
		return
	end
	ownedPets = inventory.OwnedPets or {}
	equippedPet = inventory.EquippedPet
	renderInventory()
end)

PetInventoryRequest:FireServer()
