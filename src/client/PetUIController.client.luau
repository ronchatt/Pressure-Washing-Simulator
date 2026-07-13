--!strict

-- Client-only hatching feedback and inventory display. Cash, RNG, ownership,
-- equipped state, and multipliers are all validated by PetServer.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local SharedPetData = require(ReplicatedStorage.Shared.SharedPetData)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local HatchEggRequest = remotes:WaitForChild("HatchEggRequest") :: RemoteEvent
local PetHatched = remotes:WaitForChild("PetHatched") :: RemoteEvent
local EquipPetRequest = remotes:WaitForChild("EquipPetRequest") :: RemoteEvent
local PetInventoryChanged = remotes:WaitForChild("PetInventoryChanged") :: RemoteEvent
local PetInventoryRequest = remotes:WaitForChild("PetInventoryRequest") :: RemoteEvent

local ownedPets: {string} = {}
local equippedPet: string? = nil

local gui = Instance.new("ScreenGui")
gui.Name = "PetUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

local openButton = Instance.new("TextButton")
openButton.AnchorPoint = Vector2.new(1, 1)
openButton.Position = UDim2.fromScale(0.97, 0.84)
openButton.Size = UDim2.fromOffset(128, 44)
openButton.BackgroundColor3 = Color3.fromRGB(137, 82, 173)
openButton.Text = "PETS"
openButton.TextColor3 = Color3.new(1, 1, 1)
openButton.TextSize = 16
openButton.Font = Enum.Font.GothamBold
openButton.Parent = gui
Instance.new("UICorner", openButton).CornerRadius = UDim.new(0, 10)

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(390, 380)
panel.BackgroundColor3 = Color3.fromRGB(35, 26, 48)
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(18, 12)
title.Size = UDim2.new(1, -36, 0, 42)
title.BackgroundTransparency = 1
title.Text = string.format("PET INVENTORY  •  EGG $%d", SharedPetData.EggCost)
title.TextColor3 = Color3.fromRGB(255, 233, 255)
title.TextSize = 18
title.Font = Enum.Font.GothamBold
title.Parent = panel

local list = Instance.new("ScrollingFrame")
list.Position = UDim2.fromOffset(16, 62)
list.Size = UDim2.new(1, -32, 1, -78)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 5
list.Parent = panel
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.Parent = list
layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	list.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 8)
end)

local function renderInventory()
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	if #ownedPets == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, 0, 0, 50)
		empty.BackgroundTransparency = 1
		empty.Text = "No pets yet — buy an egg at the incubator!"
		empty.TextColor3 = Color3.fromRGB(220, 205, 230)
		empty.TextSize = 15
		empty.Font = Enum.Font.GothamMedium
		empty.Parent = list
		return
	end

	for _, petID in ownedPets do
		local pet = SharedPetData.Pets[petID]
		if pet ~= nil then
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -4, 0, 58)
			row.BackgroundColor3 = Color3.fromRGB(67, 51, 86)
			row.Parent = list
			Instance.new("UICorner", row).CornerRadius = UDim.new(0, 9)

			local text = Instance.new("TextLabel")
			text.Position = UDim2.fromOffset(12, 5)
			text.Size = UDim2.new(1, -118, 1, -10)
			text.BackgroundTransparency = 1
			text.Text = string.format("%s (%s)\n%.1fx Cash  •  %.1fx Speed", pet.Name, pet.Rarity, pet.CashMult, pet.SpeedMult)
			text.TextColor3 = Color3.fromRGB(250, 244, 255)
			text.TextSize = 13
			text.Font = Enum.Font.GothamMedium
			text.TextXAlignment = Enum.TextXAlignment.Left
			text.Parent = row

			local equip = Instance.new("TextButton")
			equip.AnchorPoint = Vector2.new(1, 0.5)
			equip.Position = UDim2.new(1, -10, 0.5, 0)
			equip.Size = UDim2.fromOffset(94, 36)
			equip.BackgroundColor3 = equippedPet == petID and Color3.fromRGB(77, 159, 105) or Color3.fromRGB(108, 76, 146)
			equip.Text = equippedPet == petID and "EQUIPPED" or "EQUIP"
			equip.TextColor3 = Color3.new(1, 1, 1)
			equip.TextSize = 12
			equip.Font = Enum.Font.GothamBold
			equip.Parent = row
			Instance.new("UICorner", equip).CornerRadius = UDim.new(0, 8)
			equip.Activated:Connect(function()
				EquipPetRequest:FireServer(petID)
			end)
		end
	end
end

local hatchPopup = Instance.new("TextLabel")
hatchPopup.AnchorPoint = Vector2.new(0.5, 0.5)
hatchPopup.Position = UDim2.fromScale(0.5, 0.3)
hatchPopup.Size = UDim2.fromOffset(330, 90)
hatchPopup.BackgroundColor3 = Color3.fromRGB(63, 42, 84)
hatchPopup.TextColor3 = Color3.new(1, 1, 1)
hatchPopup.TextSize = 22
hatchPopup.Font = Enum.Font.GothamBold
hatchPopup.Visible = false
hatchPopup.Parent = gui
Instance.new("UICorner", hatchPopup).CornerRadius = UDim.new(0, 14)

openButton.Activated:Connect(function()
	panel.Visible = not panel.Visible
	if panel.Visible then
		PetInventoryRequest:FireServer()
	end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt.Name == "EggPrompt" then
		HatchEggRequest:FireServer()
	end
end)

PetHatched.OnClientEvent:Connect(function(petID)
	local pet = SharedPetData.Pets[petID]
	if pet == nil then
		return
	end

	hatchPopup.Text = string.format("YOU HATCHED A %s!\n%s", pet.Name:upper(), pet.Rarity)
	hatchPopup.Visible = true
	task.delay(3, function()
		hatchPopup.Visible = false
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
