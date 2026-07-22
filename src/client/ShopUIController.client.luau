--!strict

-- Shop presentation only. Ownership, prices, prerequisites, and equipped state
-- are returned by the authoritative ShopServer after every request.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local SharedShopData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SharedShopData"))
local SharedUITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SharedUITheme"))
local UI_COLORS = SharedUITheme.Colors
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
local cash = 0
local currentLevel = 1
local currentSection = "Washers"
local tabButtons: {[string]: TextButton} = {}

local function formatCash(value: number): string
	local digits = tostring(math.floor(value + 0.5))
	local formatted = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(formatted, 1, 1) == "," then formatted = string.sub(formatted, 2) end
	return "$" .. formatted
end

local panel = Instance.new("Frame")
panel.Name = "ShopPanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(670, 520)
panel.BackgroundColor3 = UI_COLORS.Panel
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = UI_COLORS.Cyan
panelStroke.Thickness = 1.5
panelStroke.Transparency = 0.18
panelStroke.Parent = panel
local panelGradient = Instance.new("UIGradient")
panelGradient.Rotation = 90
panelGradient.Color = ColorSequence.new(Color3.fromRGB(24, 43, 58), UI_COLORS.Background)
panelGradient.Parent = panel
local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

local targetPanelScale = 1
local function updatePanelScale()
	local camera = Workspace.CurrentCamera
	if camera == nil then return end
	local viewport = camera.ViewportSize
	targetPanelScale = math.clamp(math.min((viewport.X - 32) / 670, (viewport.Y - 32) / 520), 0.58, 1)
	if not panel.Visible then panelScale.Scale = targetPanelScale end
end
updatePanelScale()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updatePanelScale)
end

local heading = Instance.new("TextLabel")
heading.Name = "Title"
heading.Position = UDim2.fromOffset(22, 10)
heading.Size = UDim2.new(1, -245, 0, 35)
heading.BackgroundTransparency = 1
heading.Text = "PRESSURE WASHER SHOP"
heading.TextColor3 = Color3.fromRGB(218, 241, 255)
heading.TextSize = 24
heading.Font = Enum.Font.GothamBold
heading.TextXAlignment = Enum.TextXAlignment.Left
heading.Parent = panel

local notice = Instance.new("TextLabel")
notice.Name = "Notice"
notice.Position = UDim2.fromOffset(22, 43)
notice.Size = UDim2.new(1, -90, 0, 22)
notice.BackgroundTransparency = 1
notice.Text = "Choose an upgrade to compare it with your equipped washer."
notice.TextColor3 = Color3.fromRGB(139, 171, 194)
notice.TextSize = 13
notice.Font = Enum.Font.GothamMedium
notice.TextXAlignment = Enum.TextXAlignment.Left
notice.Parent = panel

local cashDisplay = Instance.new("TextLabel")
cashDisplay.Name = "CashDisplay"
cashDisplay.AnchorPoint = Vector2.new(1, 0)
cashDisplay.Position = UDim2.new(1, -72, 0, 15)
cashDisplay.Size = UDim2.fromOffset(142, 34)
cashDisplay.BackgroundColor3 = UI_COLORS.Surface
cashDisplay.BorderSizePixel = 0
cashDisplay.Text = "$0"
cashDisplay.TextColor3 = UI_COLORS.Green
cashDisplay.TextSize = 15
cashDisplay.Font = Enum.Font.GothamBold
cashDisplay.Parent = panel
Instance.new("UICorner", cashDisplay).CornerRadius = UDim.new(0, 10)
local cashStroke = Instance.new("UIStroke")
cashStroke.Color = UI_COLORS.Green
cashStroke.Transparency = 0.55
cashStroke.Parent = cashDisplay

local close = Instance.new("TextButton")
close.Name = "Close"
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
tabs.Name = "Tabs"
tabs.Position = UDim2.fromOffset(18, 72)
tabs.Size = UDim2.new(1, -36, 0, 40)
tabs.BackgroundTransparency = 1
tabs.Parent = panel

local content = Instance.new("ScrollingFrame")
content.Name = "Content"
content.Position = UDim2.fromOffset(18, 122)
content.Size = UDim2.new(1, -36, 1, -140)
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.ScrollBarThickness = 5
content.Parent = panel
local list = Instance.new("UIListLayout")
list.Name = "List"
list.Padding = UDim.new(0, 9)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = content
list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	content.CanvasSize = UDim2.fromOffset(0, list.AbsoluteContentSize.Y + 8)
end)

local function clearRows()
	for _, child in content:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
end

local function makeButton(row: Frame, text: string, color: Color3, enabled: boolean, callback: () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.Name = "ActionButton"
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
	local scale = Instance.new("UIScale")
	scale.Parent = button
	if enabled then
		button.Activated:Connect(function()
			TweenService:Create(scale, TweenInfo.new(0.08, Enum.EasingStyle.Back), { Scale = 0.94 }):Play()
			task.delay(0.08, function()
				if scale.Parent then TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Scale = 1 }):Play() end
			end)
			callback()
		end)
	end
	return button
end

local function addSimpleRow(title: string, detail: string, action: string, enabled: boolean, accent: Color3, callback: () -> ())
	local row = Instance.new("Frame")
	row.Name = title
	row.Size = UDim2.new(1, -4, 0, 68)
	row.BackgroundColor3 = UI_COLORS.Surface
	row.BorderSizePixel = 0
	row.Parent = content
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 11)
	local rowStroke = Instance.new("UIStroke")
	rowStroke.Color = accent
	rowStroke.Transparency = 0.55
	rowStroke.Parent = row
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
	makeButton(row, action, if enabled then accent else UI_COLORS.MutedSurface, enabled, callback)
end

local renderSection: (string) -> ()
local function renderWasher(itemName: string)
	local item = SharedShopData.Washers[itemName]
	local equipped = SharedShopData.Washers[equippedWasher] or SharedShopData.Washers["Basic Backpack"]
	local isOwned = ownedWashers[itemName] == true
	local isEquipped = itemName == equippedWasher
	local prerequisiteMet = item.RequiredWasher == nil or ownedWashers[item.RequiredWasher] == true
	local levelMet = currentLevel >= item.UnlockLevel
	local row = Instance.new("Frame")
	row.Name = itemName
	-- UIListLayout falls back to alphabetical ordering when rows share the
	-- default LayoutOrder. Pin washer cards to their progression tier so the
	-- Professional washer always appears before Industrial.
	row.LayoutOrder = item.Tier
	row.Size = UDim2.new(1, -4, 0, 104)
	row.BackgroundColor3 = if isEquipped then UI_COLORS.Green:Lerp(UI_COLORS.Surface, 0.72) else UI_COLORS.Surface
	row.BorderSizePixel = 0
	row.Parent = content
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 12)
	local rowStroke = Instance.new("UIStroke")
	rowStroke.Color = if isEquipped then UI_COLORS.Green else item.AccentColor
	rowStroke.Transparency = if isEquipped then 0.28 else 0.58
	rowStroke.Parent = row
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
	local comparison = if isEquipped
		then "CURRENT LOADOUT"
		elseif powerDelta > 0 then string.format("UPGRADE: +%.1fx pressure versus equipped", powerDelta)
		elseif powerDelta < 0 then string.format("DOWNGRADE: %.1fx less pressure", math.abs(powerDelta))
		else "Same pressure as equipped"
	label.Text = string.format(
		"TIER %d  |  %s  |  LEVEL %d\n%s\nPower %.1fx  |  Width %.2fx  |  Water %.2fx  |  Range %.2fx\n%s",
		item.Tier, itemName, item.UnlockLevel, item.Description, power, item.SprayWidth, item.WaterEfficiency, item.EffectiveRange, comparison
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
	elseif not levelMet then
		makeButton(row, "LEVEL " .. item.UnlockLevel, Color3.fromRGB(83, 88, 99), false, function() end)
	elseif not prerequisiteMet then
		makeButton(row, "PREVIOUS TIER", Color3.fromRGB(83, 88, 99), false, function() end)
	else
		makeButton(row, string.format("BUY  $%d", item.Cost), item.AccentColor, true, function()
			PurchaseItemRequest:FireServer("Washers", itemName)
		end)
	end
end

renderSection = function(section: string)
	currentSection = section
	clearRows()
	for tabSection, tab in tabButtons do
		local selected = tabSection == section
		tab.BackgroundColor3 = if selected then UI_COLORS.Cyan else UI_COLORS.Surface
		tab.TextColor3 = if selected then UI_COLORS.Background else UI_COLORS.Text
	end
	if section == "Washers" then
		for _, itemName in SharedShopData.WasherOrder do renderWasher(itemName) end
	elseif section == "Trucks" then
		for itemName, item in SharedShopData.Trucks do
			local isEquipped = itemName == equippedTruck
			local action = if isEquipped then "EQUIPPED" elseif ownedTrucks[itemName] then "EQUIP" else string.format("BUY  $%d", item.Cost)
			addSimpleRow(itemName, "Server-visible vehicle • Spawns at the communal base", action, not isEquipped, UI_COLORS.Cyan, function()
				if ownedTrucks[itemName] then EquipItemRequest:FireServer("Trucks", itemName) else PurchaseItemRequest:FireServer("Trucks", itemName) end
			end)
		end
	elseif section == "Tanks" then
		for _, tankID in SharedShopData.TankOrder do
			local tank = SharedShopData.Tanks[tankID]
			local owned = maxWater >= tank.NewMaxWater
			local isNext = maxWater == tank.RequiredMaxWater
			local status = if owned then "OWNED" elseif isNext then string.format("UPGRADE  $%d", tank.Cost) else "LOCKED"
			local detail = if owned
				then string.format("%d water capacity permanently unlocked", tank.NewMaxWater)
				elseif isNext then string.format("Current %d  →  New capacity %d water", maxWater, tank.NewMaxWater)
				else string.format("Requires the previous tank tier • Unlocks %d capacity", tank.NewMaxWater)
			addSimpleRow(tank.Name, detail, status, isNext, if isNext then UI_COLORS.Cyan else UI_COLORS.MutedSurface, function()
				PurchaseTankRequest:FireServer(tankID)
			end)
		end
	elseif section == "Gamepasses" then
		addSimpleRow("Infinite Water", "Never consume water while cleaning", "BUY PASS", true, UI_COLORS.Purple, function() MarketplaceService:PromptGamePassPurchase(player, INFINITE_WATER_ID) end)
		addSimpleRow("2x Walk Speed", "Doubles your normal walking speed", "BUY PASS", true, UI_COLORS.Purple, function() MarketplaceService:PromptGamePassPurchase(player, DOUBLE_SPEED_ID) end)
	end
end

for index, section in { "Washers", "Trucks", "Tanks", "Gamepasses" } do
	local tab = Instance.new("TextButton")
	tab.Name = section .. "Tab"
	tab.Size = UDim2.new(0.25, -5, 1, 0)
	tab.Position = UDim2.new((index - 1) * 0.25, (index - 1) * 2, 0, 0)
	tab.BackgroundColor3 = UI_COLORS.Surface
	tab.Text = string.upper(section)
	tab.TextColor3 = Color3.new(1, 1, 1)
	tab.TextSize = 13
	tab.Font = Enum.Font.GothamBold
	tab.Parent = tabs
	Instance.new("UICorner", tab).CornerRadius = UDim.new(0, 8)
	tabButtons[section] = tab
	tab.Activated:Connect(function()
		renderSection(section)
	end)
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
	cash = if typeof(state.Cash) == "number" then state.Cash else cash
	currentLevel = if typeof(state.Level) == "number" then state.Level else currentLevel
	cashDisplay.Text = formatCash(cash)
	if typeof(state.Notice) == "string" then
		notice.Text = state.Notice
		notice.TextColor3 = if state.Success == true then Color3.fromRGB(84, 231, 149) else Color3.fromRGB(255, 124, 124)
		notice.TextTransparency = 1
		TweenService:Create(notice, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { TextTransparency = 0 }):Play()
		if state.Success == true then
			TweenService:Create(cashDisplay, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Rotation = -2 }):Play()
			task.delay(0.12, function()
				if cashDisplay.Parent then TweenService:Create(cashDisplay, TweenInfo.new(0.16, Enum.EasingStyle.Back), { Rotation = 0 }):Play() end
			end)
		end
	end
	renderSection(currentSection)
end)

renderSection("Washers")
ShopStateRequest:FireServer()
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt.Name == "ShopPrompt" then
		panel.Visible = true
		panelScale.Scale = targetPanelScale * 0.9
		TweenService:Create(panelScale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = targetPanelScale }):Play()
		ShopStateRequest:FireServer()
	end
end)
