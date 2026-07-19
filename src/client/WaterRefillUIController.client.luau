--!strict

-- Simulator-style confirmation UI for authored refill prompts. The server
-- resolves and validates the real source; this controller only presents the
-- choice and sends its refill type.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local SharedWaterData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SharedWaterData"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local WaterRefillRequest = remotes:WaitForChild("WaterRefillRequest") :: RemoteEvent
local WaterRefillResult = remotes:WaitForChild("WaterRefillResult") :: RemoteEvent
local JobStateChanged = remotes:WaitForChild("JobStateChanged") :: RemoteEvent

local activeJobID: string? = nil
local pendingRefillType: string? = nil

local gui = Instance.new("ScreenGui")
gui.Name = "WaterRefillUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 20
gui.Parent = playerGui

-- Replaces Roblox's world-space customer ProximityPrompt, which covered the
-- exact fence/bench surface the player needed to see while cleaning.
local customerHint = Instance.new("Frame")
customerHint.Name = "CustomerWaterHint"
customerHint.AnchorPoint = Vector2.new(1, 1)
customerHint.Position = UDim2.new(1, -20, 1, -190)
customerHint.Size = UDim2.fromOffset(300, 78)
customerHint.BackgroundColor3 = Color3.fromRGB(20, 31, 43)
customerHint.BackgroundTransparency = 0.08
customerHint.BorderSizePixel = 0
customerHint.Visible = false
customerHint.Parent = gui
Instance.new("UICorner", customerHint).CornerRadius = UDim.new(0, 14)
local hintStroke = Instance.new("UIStroke")
hintStroke.Color = Color3.fromRGB(67, 183, 236)
hintStroke.Thickness = 2
hintStroke.Transparency = 0.15
hintStroke.Parent = customerHint

local hintKey = Instance.new("TextLabel")
hintKey.AnchorPoint = Vector2.new(0, 0.5)
hintKey.Position = UDim2.new(0, 13, 0.5, 0)
hintKey.Size = UDim2.fromOffset(48, 48)
hintKey.BackgroundColor3 = Color3.fromRGB(43, 59, 76)
hintKey.Text = "E"
hintKey.TextColor3 = Color3.fromRGB(242, 248, 255)
hintKey.TextSize = 20
hintKey.Font = Enum.Font.GothamBold
hintKey.Parent = customerHint
Instance.new("UICorner", hintKey).CornerRadius = UDim.new(0, 12)
local keyStroke = Instance.new("UIStroke")
keyStroke.Color = Color3.fromRGB(166, 184, 199)
keyStroke.Thickness = 2
keyStroke.Parent = hintKey

local hintTitle = Instance.new("TextLabel")
hintTitle.Position = UDim2.fromOffset(74, 12)
hintTitle.Size = UDim2.new(1, -88, 0, 25)
hintTitle.BackgroundTransparency = 1
hintTitle.Text = "CUSTOMER WATER"
hintTitle.TextColor3 = Color3.fromRGB(92, 205, 255)
hintTitle.TextSize = 16
hintTitle.Font = Enum.Font.GothamBold
hintTitle.TextXAlignment = Enum.TextXAlignment.Left
hintTitle.Parent = customerHint

local hintMessage = Instance.new("TextLabel")
hintMessage.Position = UDim2.fromOffset(74, 38)
hintMessage.Size = UDim2.new(1, -88, 0, 26)
hintMessage.BackgroundTransparency = 1
hintMessage.Text = "Hold E to refill  •  Job payout -15%"
hintMessage.TextColor3 = Color3.fromRGB(222, 232, 241)
hintMessage.TextSize = 12
hintMessage.Font = Enum.Font.GothamMedium
hintMessage.TextXAlignment = Enum.TextXAlignment.Left
hintMessage.Parent = customerHint

local hintScale = Instance.new("UIScale")
hintScale.Scale = 1
hintScale.Parent = customerHint

local shade = Instance.new("TextButton")
shade.Name = "Shade"
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.new(0, 0, 0)
shade.BackgroundTransparency = 0.55
shade.Text = ""
shade.AutoButtonColor = false
shade.Visible = false
shade.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "Confirmation"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(430, 255)
panel.BackgroundColor3 = Color3.fromRGB(20, 28, 40)
panel.BorderSizePixel = 0
panel.Parent = shade
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(62, 176, 235)
stroke.Thickness = 2
stroke.Transparency = 0.15
stroke.Parent = panel
local scale = Instance.new("UIScale")
scale.Scale = 1
scale.Parent = panel

local icon = Instance.new("TextLabel")
icon.Position = UDim2.fromOffset(22, 17)
icon.Size = UDim2.fromOffset(45, 45)
icon.BackgroundColor3 = Color3.fromRGB(37, 163, 224)
icon.Text = "💧"
icon.TextSize = 25
icon.Parent = panel
Instance.new("UICorner", icon).CornerRadius = UDim.new(1, 0)

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(80, 16)
title.Size = UDim2.new(1, -102, 0, 28)
title.BackgroundTransparency = 1
title.TextColor3 = Color3.fromRGB(229, 245, 255)
title.TextSize = 21
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local description = Instance.new("TextLabel")
description.Position = UDim2.fromOffset(80, 43)
description.Size = UDim2.new(1, -102, 0, 22)
description.BackgroundTransparency = 1
description.TextColor3 = Color3.fromRGB(153, 181, 202)
description.TextSize = 13
description.Font = Enum.Font.GothamMedium
description.TextXAlignment = Enum.TextXAlignment.Left
description.Parent = panel

local details = Instance.new("TextLabel")
details.Position = UDim2.fromOffset(22, 82)
details.Size = UDim2.new(1, -44, 0, 82)
details.BackgroundColor3 = Color3.fromRGB(31, 42, 58)
details.TextColor3 = Color3.fromRGB(235, 244, 251)
details.TextSize = 16
details.Font = Enum.Font.GothamMedium
details.TextWrapped = true
details.Parent = panel
Instance.new("UICorner", details).CornerRadius = UDim.new(0, 11)

local cancel = Instance.new("TextButton")
cancel.Name = "Cancel"
cancel.Position = UDim2.new(0, 22, 1, -67)
cancel.Size = UDim2.new(0.5, -28, 0, 45)
cancel.BackgroundColor3 = Color3.fromRGB(64, 74, 89)
cancel.Text = "CANCEL"
cancel.TextColor3 = Color3.fromRGB(231, 237, 244)
cancel.TextSize = 14
cancel.Font = Enum.Font.GothamBold
cancel.Parent = panel
Instance.new("UICorner", cancel).CornerRadius = UDim.new(0, 10)

local confirm = Instance.new("TextButton")
confirm.Name = "Confirm"
confirm.AnchorPoint = Vector2.new(1, 0)
confirm.Position = UDim2.new(1, -22, 1, -67)
confirm.Size = UDim2.new(0.5, -28, 0, 45)
confirm.BackgroundColor3 = Color3.fromRGB(40, 169, 224)
confirm.Text = "REFILL"
confirm.TextColor3 = Color3.new(1, 1, 1)
confirm.TextSize = 14
confirm.Font = Enum.Font.GothamBold
confirm.Parent = panel
Instance.new("UICorner", confirm).CornerRadius = UDim.new(0, 10)

local function closePanel()
	pendingRefillType = nil
	shade.Visible = false
	confirm.Active = true
	confirm.AutoButtonColor = true
end

local function applyLayout(refillType: string)
	if refillType == "Customer" then
		-- Customer water is offered beside the object being cleaned. Keep this
		-- prompt compact and above the play area so it never hides the dirt.
		shade.BackgroundTransparency = 1
		panel.AnchorPoint = Vector2.new(0.5, 0)
		panel.Position = UDim2.new(0.5, 0, 0, 72)
		panel.Size = UDim2.fromOffset(520, 190)
		icon.Position = UDim2.fromOffset(18, 14)
		icon.Size = UDim2.fromOffset(40, 40)
		title.Position = UDim2.fromOffset(70, 11)
		title.Size = UDim2.new(1, -88, 0, 27)
		description.Position = UDim2.fromOffset(70, 37)
		description.Size = UDim2.new(1, -88, 0, 20)
		details.Position = UDim2.fromOffset(18, 68)
		details.Size = UDim2.new(1, -36, 0, 50)
		cancel.Position = UDim2.new(0, 18, 1, -58)
		cancel.Size = UDim2.new(0.5, -24, 0, 40)
		confirm.Position = UDim2.new(1, -18, 1, -58)
		confirm.Size = UDim2.new(0.5, -24, 0, 40)
	else
		shade.BackgroundTransparency = 0.55
		panel.AnchorPoint = Vector2.new(0.5, 0.5)
		panel.Position = UDim2.fromScale(0.5, 0.5)
		panel.Size = UDim2.fromOffset(430, 255)
		icon.Position = UDim2.fromOffset(22, 17)
		icon.Size = UDim2.fromOffset(45, 45)
		title.Position = UDim2.fromOffset(80, 16)
		title.Size = UDim2.new(1, -102, 0, 28)
		description.Position = UDim2.fromOffset(80, 43)
		description.Size = UDim2.new(1, -102, 0, 22)
		details.Position = UDim2.fromOffset(22, 82)
		details.Size = UDim2.new(1, -44, 0, 82)
		cancel.Position = UDim2.new(0, 22, 1, -67)
		cancel.Size = UDim2.new(0.5, -28, 0, 45)
		confirm.Position = UDim2.new(1, -22, 1, -67)
		confirm.Size = UDim2.new(0.5, -28, 0, 45)
	end
end

local function showConfirmation(refillType: string)
	local config = SharedWaterData.RefillTypes[refillType]
	if config == nil then return end
	pendingRefillType = refillType
	applyLayout(refillType)
	title.Text = config.Name
	description.Text = config.Description
	details.TextColor3 = Color3.fromRGB(235, 244, 251)
	local currentWater = player:GetAttribute("Water") or 0
	local maxWater = player:GetAttribute("MaxWater") or 100
	if refillType == "Customer" then
		details.Text = string.format(
			"CURRENT TANK: %d / %d\nCOST: FREE  •  JOB PAYOUT: -%d%%",
			math.floor(currentWater), math.floor(maxWater), math.round(config.CustomerPayCut * 100)
		)
		confirm.Text = "ACCEPT PAY CUT"
	else
		details.Text = string.format(
			"CURRENT TANK: %d / %d\nFULL REFILL COST: $%d",
			math.floor(currentWater), math.floor(maxWater), config.CashCost
		)
		confirm.Text = string.format("REFILL  $%d", config.CashCost)
	end
	shade.Visible = true
	scale.Scale = 0.88
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

shade.Activated:Connect(closePanel)
cancel.Activated:Connect(closePanel)
confirm.Activated:Connect(function()
	if pendingRefillType == nil then return end
	confirm.Active = false
	confirm.AutoButtonColor = false
	confirm.Text = "REFILLING..."
	WaterRefillRequest:FireServer(pendingRefillType)
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt)
	local refillType = prompt:GetAttribute("RefillType")
	if typeof(refillType) == "string" then
		customerHint.Visible = false
		showConfirmation(refillType)
	end
end)

local function updateCustomerPrompts()
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("ProximityPrompt") and descendant:GetAttribute("RefillType") == "Customer" then
			descendant.Enabled = activeJobID ~= nil and descendant:GetAttribute("JobID") == activeJobID
		end
	end
end

workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("ProximityPrompt") then
		task.defer(updateCustomerPrompts)
	end
end)

ProximityPromptService.PromptShown:Connect(function(prompt)
	if prompt:GetAttribute("RefillType") == "Customer"
		and (activeJobID == nil or prompt:GetAttribute("JobID") ~= activeJobID)
	then
		prompt.Enabled = false
	elseif prompt:GetAttribute("RefillType") == "Customer" then
		customerHint.Visible = true
		hintScale.Scale = 0.88
		TweenService:Create(hintScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end)

ProximityPromptService.PromptHidden:Connect(function(prompt)
	if prompt:GetAttribute("RefillType") == "Customer" then
		customerHint.Visible = false
	end
end)

JobStateChanged.OnClientEvent:Connect(function(state)
	if typeof(state) ~= "table" then return end
	if state.State == "Active" and typeof(state.JobID) == "string" then
		activeJobID = if typeof(state.CurrentTargetJobID) == "string" then state.CurrentTargetJobID else state.JobID
	elseif state.State == "Progress" and typeof(state.CurrentTargetJobID) == "string" then
		activeJobID = state.CurrentTargetJobID
	elseif state.State == "Completed" or state.State == "Quit" then activeJobID = nil end
	updateCustomerPrompts()
end)

WaterRefillResult.OnClientEvent:Connect(function(result)
	if typeof(result) ~= "table" then return end
	confirm.Active = true
	confirm.AutoButtonColor = true
	details.Text = if typeof(result.Message) == "string" then result.Message else "Refill request finished."
	details.TextColor3 = if result.Success == true then Color3.fromRGB(105, 235, 164) else Color3.fromRGB(255, 128, 128)
	confirm.Text = if result.Success == true then "DONE" else "TRY AGAIN"
	if result.Success == true then
		task.delay(1.15, function()
			if shade.Visible then closePanel() end
		end)
	end
end)

updateCustomerPrompts()
task.delay(1, updateCustomerPrompts)
