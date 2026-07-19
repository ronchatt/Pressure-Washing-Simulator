--!strict

-- Shop presentation only. Ownership, prices, prerequisites, and equipped state
-- are returned by the authoritative ShopServer after every request.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local SharedShopData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SharedShopData"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local PurchaseItemRequest = remotes:WaitForChild("PurchaseItemRequest") :: RemoteEvent
local EquipItemRequest = remotes:WaitForChild("EquipItemRequest") :: RemoteEvent
local PurchaseTankRequest = remotes:WaitForChild("PurchaseTankRequest") :: RemoteEvent
local ShopStateRequest = remotes:WaitForChild("ShopStateRequest") :: RemoteEvent
local ShopStateChanged = remotes:WaitForChild("ShopStateChanged") :: RemoteEvent

local INFINITE_WATER_ID = 1111111
local DOUBLE_SPEED_ID = 2222222

local existingGui = playerGui:FindFirstChild("ShopUI")
local gui: ScreenGui
if existingGui and existingGui:IsA("ScreenGui") then
	gui = existingGui
else
	gui = Instance.new("ScreenGui")
	gui.Name = "ShopUI"
	gui.Parent = playerGui
end
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
local oldPanel = gui:FindFirstChild("ShopPanel")
if oldPanel then oldPanel:Destroy() end

local ownedWashers: {[string]: boolean} = { ["Basic Backpack"] = true }
local equippedWasher = "Basic Backpack"
local ownedTrucks: {[string]: boolean} = { ["Basic Pickup"] = true }
local equippedTruck = "Basic Pickup"
local maxWater = 100
local currentSection = "Washers"

local panel = Instance.new("Frame")
panel.Name = "ShopPanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(670, 520)
panel.BackgroundColor3 = Color3.fromRGB(20, 27, 39)
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)

local heading = Instance.new("TextLabel")
heading.Position = UDim2.fromOffset(22, 10)
heading.Size = UDim2.new(1, -90, 0, 35)
heading.BackgroundTransparency = 1
heading.Text = "PRESSURE WASHER SHOP"
heading.TextColor3 = Color3.fromRGB(218, 241, 255)
heading.TextSize = 24
heading.Font = Enum.Font.GothamBold
heading.TextXAlignment = Enum.TextXAlignment.Left
heading.Parent = panel

local notice = Instance.new("TextLabel")
notice.Position = UDim2.fromOffset(22, 43)
notice.Size = UDim2.new(1, -90, 0, 22)
notice.BackgroundTransparency = 1
notice.Text = "Choose an upgrade to compare it with your equipped washer."
notice.TextColor3 = Color3.fromRGB(139, 171, 194)
notice.TextSize = 13
notice.Font = Enum.Font.GothamMedium
notice.TextXAlignment = Enum.TextXAlignment.Left
notice.Parent = panel

local close = Instance.new("TextButton")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -16, 0, 14)
close.Size = UDim2.fromOffset(42, 36)
close.BackgroundColor3 = Color3.fromRGB(129, 57, 65)
close.Text = "X"
close.TextColor3 = Color3.new(1, 1, 1)
close.TextSize = 18
close.Font = Enum.Font.GothamBold
close.Parent = panel
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 9)
close.Activated:Connect(function() panel.Visible = false end)

local tabs = Instance.new("Frame")
tabs.Position = UDim2.fromOffset(18, 72)
tabs.Size = UDim2.new(1, -36, 0, 40)
tabs.BackgroundTransparency = 1
tabs.Parent = panel

local content = Instance.new("ScrollingFrame")
content.Position = UDim2.fromOffset(18, 122)
content.Size = UDim2.new(1, -36, 1, -140)
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.ScrollBarThickness = 5
content.Parent = panel
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 9)
list.Parent = content
list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	content.CanvasSize = UDim2.fromOffset(0, list.AbsoluteContentSize.Y + 8)
end)

local function clearRows()
	for _, child in content:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
end

local function makeButton(row: Frame, text: string, color: Color3, enabled: boolean, callback: () -> ())
	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -12, 0.5, 0)
	button.Size = UDim2.fromOffset(125, 42)
	button.BackgroundColor3 = color
	button.AutoButtonColor = enabled
	button.Active = enabled
	button.Text = text
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextSize = 13
	button.Font = Enum.Font.GothamBold
	button.Parent = row
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 9)
	if enabled then button.Activated:Connect(callback) end
end

local function addSimpleRow(title: string, detail: string, action: string, callback: () -> ())
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -4, 0, 68)
	row.BackgroundColor3 = Color3.fromRGB(42, 54, 73)
	row.BorderSizePixel = 0
	row.Parent = content
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 11)
	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(14, 7)
	label.Size = UDim2.new(1, -165, 1, -14)
	label.BackgroundTransparency = 1
	label.Text = title .. "\n" .. detail
	label.TextColor3 = Color3.fromRGB(239, 246, 255)
	label.TextSize = 14
	label.Font = Enum.Font.GothamMedium
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = row
	makeButton(row, action, Color3.fromRGB(54, 125, 175), true, callback)
end

local renderSection: (string) -> ()
local function renderWasher(itemName: string)
	local item = SharedShopData.Washers[itemName]
	local equipped = SharedShopData.Washers[equippedWasher] or SharedShopData.Washers["Basic Backpack"]
	local isOwned = ownedWashers[itemName] == true
	local isEquipped = itemName == equippedWasher
	local prerequisiteMet = item.RequiredWasher == nil or ownedWashers[item.RequiredWasher] == true
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -4, 0, 104)
	row.BackgroundColor3 = if isEquipped then Color3.fromRGB(35, 72, 65) else Color3.fromRGB(42, 54, 73)
	row.BorderSizePixel = 0
	row.Parent = content
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 12)
	local accent = Instance.new("Frame")
	accent.Size = UDim2.fromOffset(7, 104)
	accent.BackgroundColor3 = item.AccentColor
	accent.BorderSizePixel = 0
	accent.Parent = row
	Instance.new("UICorner", accent).CornerRadius = UDim.new(0, 12)
	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(18, 8)
	label.Size = UDim2.new(1, -175, 1, -16)
	label.BackgroundTransparency = 1
	local power = item.CleanSpeed / SharedShopData.Washers["Basic Backpack"].CleanSpeed
	local powerDelta = power - equipped.CleanSpeed / SharedShopData.Washers["Basic Backpack"].CleanSpeed
	local comparison = if isEquipped then "CURRENT LOADOUT" elseif powerDelta > 0 then string.format("+%.1fx power vs equipped", powerDelta) else "Starter equipment"
	label.Text = string.format(
		"TIER %d  |  %s\n%s\nPower %.1fx  |  Width %.2fx  |  Water %.2fx  |  Range %.2fx\n%s",
		item.Tier, itemName, item.Description, power, item.SprayWidth, item.WaterEfficiency, item.EffectiveRange, comparison
	)
	label.TextColor3 = Color3.fromRGB(239, 246, 255)
	label.TextSize = 13
	label.Font = Enum.Font.GothamMedium
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = row
	if isEquipped then
		makeButton(row, "EQUIPPED", Color3.fromRGB(64, 145, 103), false, function() end)
	elseif isOwned then
		makeButton(row, "EQUIP", Color3.fromRGB(54, 139, 108), true, function()
			EquipItemRequest:FireServer("Washers", itemName)
		end)
	elseif not prerequisiteMet then
		makeButton(row, "LOCKED", Color3.fromRGB(83, 88, 99), false, function() end)
	else
		makeButton(row, string.format("BUY  $%d", item.Cost), item.AccentColor, true, function()
			PurchaseItemRequest:FireServer("Washers", itemName)
		end)
	end
end

renderSection = function(section: string)
	currentSection = section
	clearRows()
	if section == "Washers" then
		for _, itemName in SharedShopData.WasherOrder do renderWasher(itemName) end
	elseif section == "Trucks" then
		for itemName, item in SharedShopData.Trucks do
			local action = if itemName == equippedTruck then "EQUIPPED" elseif ownedTrucks[itemName] then "EQUIP" else string.format("BUY  $%d", item.Cost)
			addSimpleRow(itemName, "Vehicle upgrade", action, function()
				if ownedTrucks[itemName] then EquipItemRequest:FireServer("Trucks", itemName) else PurchaseItemRequest:FireServer("Trucks", itemName) end
			end)
		end
	elseif section == "Tanks" then
		for _, tankID in SharedShopData.TankOrder do
			local tank = SharedShopData.Tanks[tankID]
			local status = if maxWater >= tank.NewMaxWater then "OWNED" else string.format("UPGRADE  $%d", tank.Cost)
			addSimpleRow(tank.Name, string.format("Capacity: %d water", tank.NewMaxWater), status, function()
				PurchaseTankRequest:FireServer(tankID)
			end)
		end
	elseif section == "Gamepasses" then
		addSimpleRow("Infinite Water", "Never consume water while cleaning", "BUY", function() MarketplaceService:PromptGamePassPurchase(player, INFINITE_WATER_ID) end)
		addSimpleRow("2x Walk Speed", "Doubles your normal walking speed", "BUY", function() MarketplaceService:PromptGamePassPurchase(player, DOUBLE_SPEED_ID) end)
	end
end

for index, section in { "Washers", "Trucks", "Tanks", "Gamepasses" } do
	local tab = Instance.new("TextButton")
	tab.Size = UDim2.new(0.25, -5, 1, 0)
	tab.Position = UDim2.new((index - 1) * 0.25, (index - 1) * 2, 0, 0)
	tab.BackgroundColor3 = Color3.fromRGB(43, 83, 119)
	tab.Text = string.upper(section)
	tab.TextColor3 = Color3.new(1, 1, 1)
	tab.TextSize = 13
	tab.Font = Enum.Font.GothamBold
	tab.Parent = tabs
	Instance.new("UICorner", tab).CornerRadius = UDim.new(0, 8)
	tab.Activated:Connect(function() renderSection(section) end)
end

ShopStateChanged.OnClientEvent:Connect(function(state)
	if typeof(state) ~= "table" then return end
	ownedWashers = {}
	for _, itemName in state.OwnedWashers or {} do if typeof(itemName) == "string" then ownedWashers[itemName] = true end end
	equippedWasher = if typeof(state.EquippedWasher) == "string" then state.EquippedWasher else equippedWasher
	ownedTrucks = {}
	for _, itemName in state.OwnedTrucks or {} do if typeof(itemName) == "string" then ownedTrucks[itemName] = true end end
	equippedTruck = if typeof(state.EquippedTruck) == "string" then state.EquippedTruck else equippedTruck
	maxWater = if typeof(state.MaxWater) == "number" then state.MaxWater else maxWater
	if typeof(state.Notice) == "string" then
		notice.Text = state.Notice
		notice.TextColor3 = if state.Success == true then Color3.fromRGB(84, 231, 149) else Color3.fromRGB(255, 124, 124)
	end
	renderSection(currentSection)
end)

renderSection("Washers")
ShopStateRequest:FireServer()
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt.Name == "ShopPrompt" then
		panel.Visible = true
		ShopStateRequest:FireServer()
	end
end)
