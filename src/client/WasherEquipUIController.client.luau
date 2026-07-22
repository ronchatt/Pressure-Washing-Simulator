--!strict

-- Replaces Roblox's default tool slot with a compact themed washer control.
-- Equipping still uses Humanoid:EquipTool, so normal Roblox replication and
-- the existing WasherController behavior remain intact.

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local backpack = player:WaitForChild("Backpack") :: Backpack
local shared = ReplicatedStorage:WaitForChild("Shared")
local SharedShopData = require(shared:WaitForChild("SharedShopData"))
local SharedUITheme = require(shared:WaitForChild("SharedUITheme"))
local AudioManager = require(script.Parent:WaitForChild("AudioManager"))
local colors = SharedUITheme.Colors

-- SetCoreGuiEnabled can briefly be unavailable while CoreGui initializes.
task.spawn(function()
	for _ = 1, 20 do
		local success = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if success then return end
		task.wait(0.2)
	end
	warn("WasherEquipUIController could not hide the default Backpack UI.")
end)

local existing = playerGui:FindFirstChild("WasherEquipUI")
if existing then existing:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "WasherEquipUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 19
gui.Parent = playerGui

local button = Instance.new("TextButton")
button.Name = "WasherSlot"
button.AnchorPoint = Vector2.new(0.5, 1)
button.Position = UDim2.new(0.5, 0, 1, -58)
button.Size = UDim2.fromOffset(210, 48)
button.AutoButtonColor = false
button.BackgroundColor3 = colors.Panel
button.BorderSizePixel = 0
button.Text = ""
button.Parent = gui
Instance.new("UICorner", button).CornerRadius = UDim.new(0, 12)

local stroke = Instance.new("UIStroke")
stroke.Color = colors.Cyan
stroke.Thickness = 1.5
stroke.Transparency = 0.16
stroke.Parent = button

local panelGradient = Instance.new("UIGradient")
panelGradient.Rotation = 90
panelGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(25, 47, 63)),
	ColorSequenceKeypoint.new(1, colors.Background),
})
panelGradient.Parent = button

local buttonScale = Instance.new("UIScale")
buttonScale.Parent = button

local keycap = Instance.new("TextLabel")
keycap.Name = "Keycap"
keycap.AnchorPoint = Vector2.new(0, 0.5)
keycap.Position = UDim2.new(0, 8, 0.5, 0)
keycap.Size = UDim2.fromOffset(32, 32)
keycap.BackgroundColor3 = colors.Surface
keycap.BorderSizePixel = 0
keycap.Text = "1"
keycap.TextColor3 = colors.Text
keycap.TextSize = 14
keycap.Font = Enum.Font.GothamBold
keycap.Parent = button
Instance.new("UICorner", keycap).CornerRadius = UDim.new(0, 8)

local keyStroke = Instance.new("UIStroke")
keyStroke.Color = colors.Cyan
keyStroke.Transparency = 0.38
keyStroke.Parent = keycap

local nameLabel = Instance.new("TextLabel")
nameLabel.Name = "WasherName"
nameLabel.Position = UDim2.new(0, 49, 0, 6)
nameLabel.Size = UDim2.new(1, -58, 0, 19)
nameLabel.BackgroundTransparency = 1
nameLabel.Text = "LOADING WASHER..."
nameLabel.TextColor3 = colors.Text
nameLabel.TextSize = 12
nameLabel.Font = Enum.Font.GothamBold
nameLabel.TextXAlignment = Enum.TextXAlignment.Left
nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
nameLabel.Parent = button

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "EquipStatus"
statusLabel.Position = UDim2.new(0, 49, 0, 25)
statusLabel.Size = UDim2.new(1, -58, 0, 16)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "WAITING FOR EQUIPMENT"
statusLabel.TextColor3 = colors.MutedText
statusLabel.TextSize = 9
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Parent = button

local function isWasher(instance: Instance): boolean
	return instance:IsA("Tool") and (
		instance:GetAttribute("IsPressureWasher") == true
		or SharedShopData.Washers[instance.Name] ~= nil
	)
end

local function findWasher(): Tool?
	local character = player.Character
	if character then
		for _, child in character:GetChildren() do
			if isWasher(child) then return child :: Tool end
		end
	end
	-- Roblox can replace the Backpack instance while the character is being
	-- created. Always resolve the player's current container before searching.
	local currentBackpack = player:FindFirstChildOfClass("Backpack")
	if currentBackpack then backpack = currentBackpack end
	for _, child in backpack:GetChildren() do
		if isWasher(child) then return child :: Tool end
	end
	return nil
end

local function refresh()
	local tool = findWasher()
	if tool == nil then
		nameLabel.Text = "LOADING WASHER..."
		statusLabel.Text = "WAITING FOR EQUIPMENT"
		statusLabel.TextColor3 = colors.MutedText
		button.Active = false
		stroke.Color = colors.MutedSurface
		keyStroke.Color = colors.MutedSurface
		return
	end
	local equipped = player.Character ~= nil and tool.Parent == player.Character
	local definition = SharedShopData.Washers[tool.Name]
	local accent = definition and definition.AccentColor or colors.Cyan
	nameLabel.Text = string.upper(tool.Name)
	statusLabel.Text = if equipped then "EQUIPPED  •  CLICK OR 1 TO UNEQUIP" else "CLICK OR PRESS 1 TO EQUIP"
	statusLabel.TextColor3 = if equipped then colors.Green else colors.MutedText
	button.BackgroundColor3 = if equipped then colors.Green:Lerp(colors.Panel, 0.82) else colors.Panel
	stroke.Color = if equipped then colors.Green else accent
	keyStroke.Color = accent
	button.Active = true
end

local function toggleWasher()
	local tool = findWasher()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if tool == nil or humanoid == nil then return end
	AudioManager:Play("UIClick", 0.18, 1.05)
	if tool.Parent == character then
		humanoid:UnequipTools()
	else
		humanoid:EquipTool(tool)
	end
	task.defer(refresh)
end

button.Activated:Connect(toggleWasher)
button.MouseEnter:Connect(function()
	TweenService:Create(buttonScale, TweenInfo.new(0.12), { Scale = 1.035 }):Play()
end)
button.MouseLeave:Connect(function()
	TweenService:Create(buttonScale, TweenInfo.new(0.14), { Scale = 1 }):Play()
end)
button.MouseButton1Down:Connect(function()
	TweenService:Create(buttonScale, TweenInfo.new(0.07), { Scale = 0.96 }):Play()
end)
button.MouseButton1Up:Connect(function()
	TweenService:Create(buttonScale, TweenInfo.new(0.1), { Scale = 1.035 }):Play()
end)

ContextActionService:BindActionAtPriority(
	"TogglePressureWasher",
	function(_, inputState)
		if inputState == Enum.UserInputState.Begin then toggleWasher() end
		return Enum.ContextActionResult.Sink
	end,
	false,
	Enum.ContextActionPriority.High.Value + 1,
	Enum.KeyCode.One,
	Enum.KeyCode.ButtonX
)

local containerConnections: {RBXScriptConnection} = {}
local function bindContainers(character: Model?)
	for _, connection in containerConnections do connection:Disconnect() end
	table.clear(containerConnections)
	local currentBackpack = player:FindFirstChildOfClass("Backpack")
	if currentBackpack then backpack = currentBackpack end
	table.insert(containerConnections, backpack.ChildAdded:Connect(function() task.defer(refresh) end))
	table.insert(containerConnections, backpack.ChildRemoved:Connect(function() task.defer(refresh) end))
	if character then
		table.insert(containerConnections, character.ChildAdded:Connect(function() task.defer(refresh) end))
		table.insert(containerConnections, character.ChildRemoved:Connect(function() task.defer(refresh) end))
	end
	task.defer(refresh)
end

player.CharacterAdded:Connect(bindContainers)
player:GetAttributeChangedSignal("EquippedWasher"):Connect(function() task.defer(refresh) end)
bindContainers(player.Character)

-- Equipment can be cloned during the same replication frame as CharacterAdded.
-- A very light fallback refresh closes that race and also self-heals if another
-- system reparents the tool without exposing the expected event ordering.
task.spawn(function()
	while gui.Parent ~= nil do
		refresh()
		task.wait(0.5)
	end
end)
