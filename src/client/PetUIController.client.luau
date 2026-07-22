--!strict

-- Unique pet inventory, equip/unequip controls, and egg reveal presentation.
-- Pet ownership, RNG, costs, and multipliers remain server-authoritative.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local petGuiInstance = playerGui:WaitForChild("PetUI", 10)
if petGuiInstance == nil or not petGuiInstance:IsA("ScreenGui") then
	warn("PlayerGui.PetUI must be a ScreenGui.")
	return
end
local petGui = petGuiInstance
local inventoryInstance = petGui:WaitForChild("Frame", 10)
if inventoryInstance == nil or not inventoryInstance:IsA("GuiObject") then
	warn("PlayerGui.PetUI.Frame must be a GuiObject.")
	return
end
local inventoryFrame = inventoryInstance
local openInstance = petGui:FindFirstChild("OpenPets", true) or petGui:FindFirstChild("TextButton", true)
if openInstance == nil or not openInstance:IsA("GuiButton") then
	warn("PlayerGui.PetUI requires an OpenPets button.")
	return
end
local openPetsButton = openInstance
openPetsButton.Name = "OpenPets"
local closeInstance = inventoryFrame:FindFirstChild("ClosePets", true)
local closePetsButton = if closeInstance and closeInstance:IsA("GuiButton") then closeInstance else nil
local petList = inventoryFrame:FindFirstChildWhichIsA("ScrollingFrame", true)
if petList == nil then
	warn("PlayerGui.PetUI.Frame requires a ScrollingFrame.")
	return
end
petList.AutomaticCanvasSize = Enum.AutomaticSize.Y
petList.CanvasSize = UDim2.fromScale(0, 0)
local petListLayout = petList:FindFirstChildWhichIsA("UIListLayout")
if petListLayout then
	petListLayout.SortOrder = Enum.SortOrder.LayoutOrder
end

local SharedPetData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SharedPetData"))
local SharedUITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SharedUITheme"))
local UI_COLORS = SharedUITheme.Colors
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local HatchEggRequest = remotes:WaitForChild("HatchEggRequest") :: RemoteEvent
local PetHatched = remotes:WaitForChild("PetHatched") :: RemoteEvent
local EquipPetRequest = remotes:WaitForChild("EquipPetRequest") :: RemoteEvent
local PetInventoryChanged = remotes:WaitForChild("PetInventoryChanged") :: RemoteEvent
local PetInventoryRequest = remotes:WaitForChild("PetInventoryRequest") :: RemoteEvent

type OwnedPet = { UID: string, PetID: string }
local ownedPets: {OwnedPet} = {}
local equippedPetUID: string? = nil
local popupOpen = false

SharedUITheme.StylePanel(inventoryFrame, UI_COLORS.Purple)
local outline = inventoryFrame:FindFirstChildWhichIsA("UIStroke")
if outline then outline.Enabled = false end
SharedUITheme.StyleLauncher(openPetsButton, UI_COLORS.Purple, "PETS   >")
SharedUITheme.BindButtonMotion(openPetsButton, UI_COLORS.Purple)
if closePetsButton then
	SharedUITheme.BindButtonMotion(closePetsButton, UI_COLORS.Purple)
	local gradient = closePetsButton:FindFirstChildWhichIsA("UIGradient")
	if gradient then gradient.Enabled = false end
end

local function setPopupVisible(visible: boolean)
	popupOpen = visible
	inventoryFrame.Visible = visible
	openPetsButton.Visible = true
end

openPetsButton.Activated:Connect(function()
	setPopupVisible(not popupOpen)
	if not popupOpen then return end
	PetInventoryRequest:FireServer()
end)
if closePetsButton then closePetsButton.Activated:Connect(function() setPopupVisible(false) end) end

local statusInstance = inventoryFrame:FindFirstChild("HatchResult", true)
local statusLabel = if statusInstance and statusInstance:IsA("TextLabel") then statusInstance else nil
local emptyInstance = petList:FindFirstChild("EmptyState")
local emptyState = if emptyInstance and emptyInstance:IsA("TextLabel") then emptyInstance else nil

local template: TextButton? = nil
for _, child in petList:GetChildren() do
	if child:IsA("TextButton") and SharedPetData.Pets[child.Name] ~= nil then
		if template == nil then
			template = child:Clone()
			template.Parent = nil
		end
		child:Destroy()
	end
end

local countLabel = inventoryFrame:FindFirstChild("PetCount")
if countLabel == nil or not countLabel:IsA("TextLabel") then
	if countLabel then countLabel:Destroy() end
	countLabel = Instance.new("TextLabel")
	countLabel.Name = "PetCount"
	countLabel.AnchorPoint = Vector2.new(1, 0)
	countLabel.Position = UDim2.new(1, -56, 0, 61)
	countLabel.Size = UDim2.fromOffset(100, 22)
	countLabel.BackgroundTransparency = 1
	countLabel.TextXAlignment = Enum.TextXAlignment.Right
	countLabel.TextSize = 12
	countLabel.Font = Enum.Font.GothamBold
	countLabel.TextColor3 = UI_COLORS.MutedText
	countLabel.Parent = inventoryFrame
end
local petCountLabel = countLabel :: TextLabel

local function makeCard(ownedPet: OwnedPet, order: number)
	local definition = SharedPetData.Pets[ownedPet.PetID]
	if definition == nil then return end
	local button: TextButton
	if template then
		button = template:Clone()
	else
		button = Instance.new("TextButton")
		button.Size = UDim2.new(1, -4, 0, 80)
		Instance.new("UICorner", button).CornerRadius = UDim.new(0, 12)
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 14)
		padding.PaddingRight = UDim.new(0, 14)
		padding.Parent = button
		Instance.new("UIStroke", button)
	end
	local equipped = equippedPetUID == ownedPet.UID
	button.Name = "OwnedPet_" .. ownedPet.UID
	button:SetAttribute("PetUID", ownedPet.UID)
	button:SetAttribute("PetID", ownedPet.PetID)
	button.LayoutOrder = order
	button.Visible = true
	button.Active = true
	button.AutoButtonColor = true
	button.BackgroundColor3 = if equipped then UI_COLORS.Green:Lerp(UI_COLORS.Surface, 0.7) else UI_COLORS.Surface
	button.BorderSizePixel = 0
	button.TextColor3 = UI_COLORS.Text
	button.TextSize = 13
	button.TextWrapped = true
	button.TextXAlignment = Enum.TextXAlignment.Left
	button.Font = Enum.Font.GothamBold
	button.Text = string.format(
		"%s  •  %s%s\nCash +%d%%  •  Speed +%d%%\n%s",
		string.upper(definition.Name), string.upper(definition.Rarity), if equipped then "  •  EQUIPPED" else "",
		math.round((definition.CashMult - 1) * 100), math.round((definition.SpeedMult - 1) * 100),
		if equipped then "CLICK TO UNEQUIP" else "CLICK TO EQUIP"
	)
	local gradient = button:FindFirstChildWhichIsA("UIGradient")
	if gradient then gradient.Enabled = false end
	local stroke = button:FindFirstChildWhichIsA("UIStroke")
	if stroke then
		stroke.Enabled = true
		stroke.Color = if equipped then UI_COLORS.Green else definition.RarityColor
		stroke.Transparency = 0.24
	end
	button.Activated:Connect(function()
		EquipPetRequest:FireServer(if equipped then nil else ownedPet.UID)
	end)
	button.Parent = petList
end

local function renderInventory()
	for _, child in petList:GetChildren() do
		if child:IsA("GuiObject") and string.sub(child.Name, 1, 9) == "OwnedPet_" then child:Destroy() end
	end
	for order, ownedPet in ownedPets do makeCard(ownedPet, order) end
	petCountLabel.Text = tostring(#ownedPets) .. " OWNED"
	if emptyState then emptyState.Visible = #ownedPets == 0 end
end

-- Hatch overlay is deliberately generated at runtime because it is transient
-- and every rarity drives different reveal colors.
local overlay = Instance.new("CanvasGroup")
overlay.Name = "HatchOverlay"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.fromRGB(5, 10, 15)
overlay.BackgroundTransparency = 0.28
overlay.GroupTransparency = 1
overlay.Visible = false
overlay.ZIndex = 100
overlay.Parent = petGui
local reveal = Instance.new("Frame")
reveal.AnchorPoint = Vector2.new(0.5, 0.5)
reveal.Position = UDim2.fromScale(0.5, 0.5)
reveal.Size = UDim2.fromOffset(390, 270)
reveal.BackgroundColor3 = UI_COLORS.Panel
reveal.BorderSizePixel = 0
reveal.ZIndex = 101
reveal.Parent = overlay
Instance.new("UICorner", reveal).CornerRadius = UDim.new(0, 20)
local revealStroke = Instance.new("UIStroke")
revealStroke.Color = UI_COLORS.Purple
revealStroke.Thickness = 2
revealStroke.Parent = reveal
local egg = Instance.new("Frame")
egg.AnchorPoint = Vector2.new(0.5, 0)
egg.Position = UDim2.new(0.5, 0, 0, 28)
egg.Size = UDim2.fromOffset(96, 116)
egg.BackgroundColor3 = Color3.fromRGB(235, 242, 250)
egg.BorderSizePixel = 0
egg.ZIndex = 102
egg.Parent = reveal
Instance.new("UICorner", egg).CornerRadius = UDim.new(0.48, 0)
local eggScale = Instance.new("UIScale")
eggScale.Parent = egg
local revealTitle = Instance.new("TextLabel")
revealTitle.Position = UDim2.new(0, 18, 0, 158)
revealTitle.Size = UDim2.new(1, -36, 0, 32)
revealTitle.BackgroundTransparency = 1
revealTitle.TextColor3 = UI_COLORS.Text
revealTitle.TextSize = 24
revealTitle.Font = Enum.Font.GothamBold
revealTitle.ZIndex = 102
revealTitle.Parent = reveal
local revealDetails = Instance.new("TextLabel")
revealDetails.Position = UDim2.new(0, 18, 0, 195)
revealDetails.Size = UDim2.new(1, -36, 0, 52)
revealDetails.BackgroundTransparency = 1
revealDetails.TextColor3 = UI_COLORS.MutedText
revealDetails.TextSize = 14
revealDetails.TextWrapped = true
revealDetails.Font = Enum.Font.GothamMedium
revealDetails.ZIndex = 102
revealDetails.Parent = reveal

local hatching = false
local pendingResult: any = nil
local function animateHatch()
	overlay.Visible = true
	overlay.GroupTransparency = 1
	egg.BackgroundColor3 = Color3.fromRGB(235, 242, 250)
	egg.Rotation = 0
	eggScale.Scale = 0.35
	revealStroke.Color = UI_COLORS.Purple
	revealTitle.Text = "HATCHING..."
	revealTitle.TextColor3 = UI_COLORS.Text
	revealDetails.Text = "The incubator is opening your egg."
	TweenService:Create(overlay, TweenInfo.new(0.22), { GroupTransparency = 0 }):Play()
	TweenService:Create(eggScale, TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	for index = 1, 8 do
		TweenService:Create(egg, TweenInfo.new(0.09), { Rotation = if index % 2 == 0 then -10 else 10 }):Play()
		task.wait(0.09)
	end
	TweenService:Create(egg, TweenInfo.new(0.1), { Rotation = 0 }):Play()
	local deadline = os.clock() + 5
	repeat task.wait() until pendingResult ~= nil or os.clock() >= deadline
	local result = pendingResult
	if typeof(result) ~= "table" or result.Success ~= true or typeof(result.Pet) ~= "table" then
		revealTitle.Text = "HATCH FAILED"
		revealTitle.TextColor3 = Color3.fromRGB(255, 120, 125)
		revealDetails.Text = if typeof(result) == "table" and typeof(result.Message) == "string" then result.Message else "Please try again."
		egg.BackgroundColor3 = Color3.fromRGB(150, 75, 82)
		task.wait(1.35)
	else
		local definition = SharedPetData.Pets[result.Pet.PetID]
		if definition then
			egg.BackgroundColor3 = definition.Color
			revealStroke.Color = definition.RarityColor
			revealTitle.TextColor3 = definition.RarityColor
			revealTitle.Text = string.upper(definition.Rarity) .. " " .. string.upper(definition.Name) .. "!"
			revealDetails.Text = string.format(
				"Cash +%d%%  •  Speed +%d%%\nAdded to your pet inventory.",
				math.round((definition.CashMult - 1) * 100), math.round((definition.SpeedMult - 1) * 100)
			)
			TweenService:Create(eggScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1.35 }):Play()
			if statusLabel then statusLabel.Text = "YOU HATCHED A " .. string.upper(definition.Name) .. "!" end
		end
		task.wait(2)
	end
	local fade = TweenService:Create(overlay, TweenInfo.new(0.25), { GroupTransparency = 1 })
	fade:Play()
	fade.Completed:Wait()
	overlay.Visible = false
	pendingResult = nil
	hatching = false
end

ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt.Name ~= "EggPrompt" or hatching then return end
	hatching = true
	pendingResult = nil
	HatchEggRequest:FireServer()
	task.spawn(animateHatch)
end)
PetHatched.OnClientEvent:Connect(function(result) pendingResult = result end)
PetInventoryChanged.OnClientEvent:Connect(function(inventory)
	if typeof(inventory) ~= "table" then return end
	ownedPets = inventory.OwnedPets or {}
	equippedPetUID = inventory.EquippedPet
	renderInventory()
end)

setPopupVisible(false)
renderInventory()
PetInventoryRequest:FireServer()
