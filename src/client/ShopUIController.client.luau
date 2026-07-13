--!strict

-- Local shop presentation. Requests are sent to ShopServer; this controller
-- never changes cash, ownership, equipped items, or tank capacity itself.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local SharedShopData = require(ReplicatedStorage.Shared.SharedShopData)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local PurchaseItemRequest = remotes:WaitForChild("PurchaseItemRequest") :: RemoteEvent
local EquipItemRequest = remotes:WaitForChild("EquipItemRequest") :: RemoteEvent
local PurchaseTankRequest = remotes:WaitForChild("PurchaseTankRequest") :: RemoteEvent

-- Keep these temporary IDs aligned with MonetizationManager until real passes
-- are created and their asset IDs are substituted in both locations.
local INFINITE_WATER_ID = 1111111
local DOUBLE_SPEED_ID = 2222222

local gui = Instance.new("ScreenGui")
gui.Name = "ShopUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "ShopPanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(560, 430)
panel.BackgroundColor3 = Color3.fromRGB(22, 30, 42)
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)

local heading = Instance.new("TextLabel")
heading.Position = UDim2.fromOffset(22, 12)
heading.Size = UDim2.new(1, -80, 0, 42)
heading.BackgroundTransparency = 1
heading.Text = "BASE COMPUTER"
heading.TextColor3 = Color3.fromRGB(213, 239, 255)
heading.TextSize = 25
heading.Font = Enum.Font.GothamBold
heading.TextXAlignment = Enum.TextXAlignment.Left
heading.Parent = panel

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
close.Activated:Connect(function()
	panel.Visible = false
end)

local tabs = Instance.new("Frame")
tabs.Position = UDim2.fromOffset(18, 62)
tabs.Size = UDim2.new(1, -36, 0, 40)
tabs.BackgroundTransparency = 1
tabs.Parent = panel

local content = Instance.new("ScrollingFrame")
content.Position = UDim2.fromOffset(18, 112)
content.Size = UDim2.new(1, -36, 1, -130)
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
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function addRow(titleText: string, detailText: string, actionText: string, callback: () -> (), equipCallback: (() -> ())?)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -4, 0, 62)
	row.BackgroundColor3 = Color3.fromRGB(45, 57, 77)
	row.Parent = content
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)

	local text = Instance.new("TextLabel")
	text.Position = UDim2.fromOffset(14, 6)
	text.Size = UDim2.new(1, -142, 1, -12)
	text.BackgroundTransparency = 1
	text.Text = titleText .. "\n" .. detailText
	text.TextColor3 = Color3.fromRGB(240, 246, 255)
	text.TextSize = 14
	text.Font = Enum.Font.GothamMedium
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Center
	text.Parent = row

	local action = Instance.new("TextButton")
	action.AnchorPoint = Vector2.new(1, 0.5)
	action.Position = UDim2.new(1, -10, 0.5, 0)
	action.Size = UDim2.fromOffset(112, 38)
	action.BackgroundColor3 = Color3.fromRGB(54, 125, 175)
	action.Text = actionText
	action.TextColor3 = Color3.new(1, 1, 1)
	action.TextSize = 13
	action.Font = Enum.Font.GothamBold
	action.Parent = row
	Instance.new("UICorner", action).CornerRadius = UDim.new(0, 8)
	action.Activated:Connect(callback)

	if equipCallback ~= nil then
		local equip = action:Clone()
		equip.Name = "Equip"
		equip.Position = UDim2.new(1, -132, 0.5, 0)
		equip.BackgroundColor3 = Color3.fromRGB(72, 151, 110)
		equip.Text = "EQUIP"
		equip.Parent = row
		equip.Activated:Connect(equipCallback)
	end
end

local renderSection: (string) -> ()
renderSection = function(section: string)
	clearRows()
	if section == "Washers" then
		for itemName, item in pairs(SharedShopData.Washers) do
			addRow(itemName, string.format("Clean speed: %.1f  •  $%d", item.CleanSpeed, item.Cost), "BUY", function()
				PurchaseItemRequest:FireServer("Washers", itemName)
			end, function()
				EquipItemRequest:FireServer("Washers", itemName)
			end)
		end
	elseif section == "Trucks" then
		for itemName, item in pairs(SharedShopData.Trucks) do
			addRow(itemName, string.format("Truck upgrade  •  $%d", item.Cost), "BUY", function()
				PurchaseItemRequest:FireServer("Trucks", itemName)
			end, function()
				EquipItemRequest:FireServer("Trucks", itemName)
			end)
		end
	elseif section == "Tanks" then
		for _, tankID in SharedShopData.TankOrder do
			local tank = SharedShopData.Tanks[tankID]
			addRow(tank.Name, string.format("Water capacity: %d  •  $%d", tank.NewMaxWater, tank.Cost), "UPGRADE", function()
				PurchaseTankRequest:FireServer(tankID)
			end)
		end
	elseif section == "Gamepasses" then
		addRow("Infinite Water", "Never consume water while cleaning  •  500 Robux", "BUY", function()
			MarketplaceService:PromptGamePassPurchase(player, INFINITE_WATER_ID)
		end)
		addRow("2x Walk Speed", "Walk at 32 speed instead of 16  •  250 Robux", "BUY", function()
			MarketplaceService:PromptGamePassPurchase(player, DOUBLE_SPEED_ID)
		end)
	end
end

for index, section in ipairs({ "Washers", "Trucks", "Tanks", "Gamepasses" }) do
	local tab = Instance.new("TextButton")
	tab.Size = UDim2.new(1 / 4, -5, 1, 0)
	tab.Position = UDim2.new((index - 1) / 4, (index - 1) * 2, 0, 0)
	tab.BackgroundColor3 = Color3.fromRGB(43, 83, 119)
	tab.Text = string.upper(section)
	tab.TextColor3 = Color3.new(1, 1, 1)
	tab.TextSize = 14
	tab.Font = Enum.Font.GothamBold
	tab.Parent = tabs
	Instance.new("UICorner", tab).CornerRadius = UDim.new(0, 8)
	tab.Activated:Connect(function()
		renderSection(section)
	end)
end

renderSection("Washers")

ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt.Name == "ShopPrompt" then
		panel.Visible = true
	end
end)
