--!strict

-- Controls the hand-authored StarterGui.WaterUI. Server-authored attributes
-- correct the responsive local water prediction after every accepted report.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local waterGui = playerGui:WaitForChild("WaterUI") :: ScreenGui
local waterPanel = waterGui:WaitForChild("WaterPanel") :: Frame
local existingWaterLabel = waterPanel:FindFirstChild("WaterDisplay") or waterPanel:FindFirstChildWhichIsA("TextLabel")
local waterLabel: TextLabel
if existingWaterLabel and existingWaterLabel:IsA("TextLabel") then
	waterLabel = existingWaterLabel
else
	waterLabel = Instance.new("TextLabel")
	waterLabel.Name = "WaterDisplay"
	waterLabel.Size = UDim2.fromScale(1, 1)
	waterLabel.BackgroundTransparency = 1
	waterLabel.TextColor3 = Color3.new(1, 1, 1)
	waterLabel.TextScaled = true
	waterLabel.Parent = waterPanel
end

local function isBarObject(instance: Instance?): boolean
	return instance ~= nil and (instance:IsA("Frame") or instance:IsA("ImageLabel"))
end

local function findWaterFill(): GuiObject?
	-- These names are supported directly for hand-authored interfaces.
	for _, name in { "WaterFill", "BarFill", "BlueBar", "Fill" } do
		local candidate = waterPanel:FindFirstChild(name, true)
		if isBarObject(candidate) then
			return candidate :: GuiObject
		end
	end

	-- Also support an Action attribute so artists can freely rename the bar.
	for _, descendant in waterPanel:GetDescendants() do
		if isBarObject(descendant) and descendant:GetAttribute("Action") == "WaterFill" then
			return descendant :: GuiObject
		end
	end

	-- Last-resort compatibility with the existing unnamed blue Frame.
	local bestCandidate: GuiObject? = nil
	local bestBlueScore = 0
	for _, descendant in waterPanel:GetDescendants() do
		if descendant:IsA("Frame") then
			local color = descendant.BackgroundColor3
			local blueScore = color.B - math.max(color.R, color.G) * 0.55
			if color.B > color.R and blueScore > bestBlueScore then
				bestBlueScore = blueScore
				bestCandidate = descendant
			end
		elseif descendant:IsA("ImageLabel") then
			local color = descendant.ImageColor3
			local blueScore = color.B - math.max(color.R, color.G) * 0.55
			if color.B > color.R and blueScore > bestBlueScore then
				bestBlueScore = blueScore
				bestCandidate = descendant
			end
		end
	end
	return bestCandidate
end

local waterFill = findWaterFill()
local fullWaterFillSize = if waterFill then waterFill.Size else nil
if waterFill == nil then
	warn("WaterUI.WaterPanel has no blue fill bar. Name it WaterFill, BarFill, BlueBar, or Fill.")
end

local emptyAlert = waterGui:FindFirstChild("WaterEmptyAlert")
if emptyAlert ~= nil and not emptyAlert:IsA("Frame") then
	emptyAlert:Destroy()
	emptyAlert = nil
end
if emptyAlert == nil then
	local alert = Instance.new("Frame")
	alert.Name = "WaterEmptyAlert"
	alert.AnchorPoint = waterPanel.AnchorPoint
	alert.Size = UDim2.new(waterPanel.Size.X.Scale, waterPanel.Size.X.Offset, 0, 68)
	alert.BackgroundColor3 = waterPanel.BackgroundColor3
	alert.BackgroundTransparency = waterPanel.BackgroundTransparency
	alert.BorderSizePixel = 0
	alert.Visible = false
	alert.Parent = waterGui

	local corner = waterPanel:FindFirstChildWhichIsA("UICorner")
	if corner then
		corner:Clone().Parent = alert
	else
		local newCorner = Instance.new("UICorner")
		newCorner.CornerRadius = UDim.new(0, 12)
		newCorner.Parent = alert
	end
	local stroke = waterPanel:FindFirstChildWhichIsA("UIStroke")
	if stroke then
		stroke:Clone().Parent = alert
	end

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(14, 7)
	title.Size = UDim2.new(1, -28, 0, 28)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Text = "OUT OF WATER!"
	title.TextColor3 = Color3.fromRGB(79, 196, 255)
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = alert

	local message = Instance.new("TextLabel")
	message.Name = "Message"
	message.Position = UDim2.fromOffset(14, 34)
	message.Size = UDim2.new(1, -28, 0, 22)
	message.BackgroundTransparency = 1
	message.Font = Enum.Font.GothamMedium
	message.Text = "Refill at the nearby fire hydrant"
	message.TextColor3 = Color3.fromRGB(235, 242, 248)
	message.TextSize = 13
	message.TextXAlignment = Enum.TextXAlignment.Left
	message.Parent = alert

	local scale = Instance.new("UIScale")
	scale.Name = "PopScale"
	scale.Scale = 1
	scale.Parent = alert
	emptyAlert = alert
end

local typedEmptyAlert = emptyAlert :: Frame
local alertScale = typedEmptyAlert:FindFirstChild("PopScale") :: UIScale?
local alertVisible = false
local alertTweenVersion = 0

local function getAlertPosition(extraYOffset: number): UDim2
	local panelHeight = math.max(waterPanel.AbsoluteSize.Y, 68)
	return UDim2.new(
		waterPanel.Position.X.Scale,
		waterPanel.Position.X.Offset,
		waterPanel.Position.Y.Scale,
		waterPanel.Position.Y.Offset - panelHeight - 12 + extraYOffset
	)
end

local function setEmptyAlertVisible(visible: boolean)
	if alertVisible == visible then
		return
	end
	alertVisible = visible
	alertTweenVersion += 1
	local version = alertTweenVersion

	if visible then
		typedEmptyAlert.Position = getAlertPosition(14)
		typedEmptyAlert.Visible = true
		if alertScale then
			alertScale.Scale = 0.88
			TweenService:Create(alertScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		TweenService:Create(typedEmptyAlert, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = getAlertPosition(0),
		}):Play()
	else
		local tween = TweenService:Create(typedEmptyAlert, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = getAlertPosition(10),
		})
		tween.Completed:Once(function()
			if alertTweenVersion == version then
				typedEmptyAlert.Visible = false
			end
		end)
		tween:Play()
	end
end

local EMPTY_TANK_SECONDS = 30
local predictedWater = 0
local maxWater = 100
local isSpraying = false
local hasAuthoritativeWater = false

local function render()
	local ratio = if maxWater > 0 then math.clamp(predictedWater / maxWater, 0, 1) else 0
	if player:GetAttribute("OwnsInfiniteWater") == true then
		waterLabel.Text = "Water: INFINITE"
		ratio = 1
	else
		waterLabel.Text = string.format(
			"Water: %d / %d",
			math.floor(predictedWater + 0.5),
			math.floor(maxWater + 0.5)
		)
	end

	if waterFill ~= nil and fullWaterFillSize ~= nil then
		waterFill.Size = UDim2.new(
			fullWaterFillSize.X.Scale * ratio,
			math.round(fullWaterFillSize.X.Offset * ratio),
			fullWaterFillSize.Y.Scale,
			fullWaterFillSize.Y.Offset
		)
	end
	setEmptyAlertVisible(
		hasAuthoritativeWater
			and player:GetAttribute("OwnsInfiniteWater") ~= true
			and predictedWater <= 0.001
	)
end

local function syncFromServer()
	local serverWater = player:GetAttribute("Water")
	local serverMaxWater = player:GetAttribute("MaxWater")
	if typeof(serverWater) == "number" then
		hasAuthoritativeWater = true
		predictedWater = serverWater
	end
	if typeof(serverMaxWater) == "number" then
		maxWater = serverMaxWater
	end
	render()
end

player:GetAttributeChangedSignal("Water"):Connect(syncFromServer)
player:GetAttributeChangedSignal("MaxWater"):Connect(syncFromServer)
player:GetAttributeChangedSignal("OwnsInfiniteWater"):Connect(render)

local sprayStateInstance = playerGui:FindFirstChild("WasherSprayStateChanged")
if sprayStateInstance == nil then
	sprayStateInstance = Instance.new("BindableEvent")
	sprayStateInstance.Name = "WasherSprayStateChanged"
	sprayStateInstance.Parent = playerGui
end
assert(sprayStateInstance:IsA("BindableEvent"), "WasherSprayStateChanged must be a BindableEvent")
local sprayStateSignal = sprayStateInstance :: BindableEvent
sprayStateSignal.Event:Connect(function(spraying)
	isSpraying = spraying == true
end)

RunService.RenderStepped:Connect(function(deltaTime)
	if isSpraying and player:GetAttribute("OwnsInfiniteWater") ~= true then
		predictedWater = math.max(0, predictedWater - (maxWater / EMPTY_TANK_SECONDS) * deltaTime)
		render()
	end
end)

syncFromServer()
