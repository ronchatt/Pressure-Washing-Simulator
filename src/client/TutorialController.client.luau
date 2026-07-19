--!strict

-- Lightweight, skippable first-session guidance. Milestones are event-driven
-- and remembered locally even if the player completes one slightly early.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local TutorialStateRequest = remotes:WaitForChild("TutorialStateRequest") :: RemoteEvent
local TutorialStateChanged = remotes:WaitForChild("TutorialStateChanged") :: RemoteEvent
local TutorialCompleteRequest = remotes:WaitForChild("TutorialCompleteRequest") :: RemoteEvent
local JobStateChanged = remotes:WaitForChild("JobStateChanged") :: RemoteEvent

local milestones: {[string]: boolean} = {
	PhoneOpened = false,
	BenchAccepted = false,
	BenchReached = false,
	DirtSprayed = false,
	BenchCompleted = false,
	ShopOpened = false,
}
local steps = {
	{ Key = "PhoneOpened", Title = "OPEN YOUR PHONE", Detail = "Use the PHONE button to view available jobs." },
	{ Key = "BenchAccepted", Title = "ACCEPT THE BENCH JOB", Detail = "Choose Neighborhood Bench from the Phone." },
	{ Key = "BenchReached", Title = "FOLLOW THE WAYPOINT", Detail = "Travel to the marked Neighborhood Bench." },
	{ Key = "DirtSprayed", Title = "START CLEANING", Detail = "Equip your washer and spray some dirt." },
	{ Key = "BenchCompleted", Title = "FINISH THE JOB", Detail = "Clean the Bench to 95% completion." },
	{ Key = "ShopOpened", Title = "VISIT THE SHOP", Detail = "Open the Base Computer shop to view upgrades." },
}

local gui = Instance.new("ScreenGui")
gui.Name = "TutorialUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 15
gui.Enabled = false
gui.Parent = playerGui

local card = Instance.new("Frame")
card.Name = "ObjectiveCard"
card.Position = UDim2.fromOffset(20, 90)
card.Size = UDim2.fromOffset(365, 126)
card.BackgroundColor3 = Color3.fromRGB(19, 29, 41)
card.BackgroundTransparency = 0.06
card.BorderSizePixel = 0
card.Parent = gui
Instance.new("UICorner", card).CornerRadius = UDim.new(0, 16)
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(61, 180, 235)
stroke.Thickness = 2
stroke.Transparency = 0.16
stroke.Parent = card

local eyebrow = Instance.new("TextLabel")
eyebrow.Position = UDim2.fromOffset(16, 10)
eyebrow.Size = UDim2.new(1, -90, 0, 20)
eyebrow.BackgroundTransparency = 1
eyebrow.Text = "GETTING STARTED  •  1 / 6"
eyebrow.TextColor3 = Color3.fromRGB(79, 197, 250)
eyebrow.TextSize = 12
eyebrow.Font = Enum.Font.GothamBold
eyebrow.TextXAlignment = Enum.TextXAlignment.Left
eyebrow.Parent = card

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(16, 34)
title.Size = UDim2.new(1, -32, 0, 28)
title.BackgroundTransparency = 1
title.TextColor3 = Color3.fromRGB(239, 247, 255)
title.TextSize = 19
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = card

local detail = Instance.new("TextLabel")
detail.Position = UDim2.fromOffset(16, 64)
detail.Size = UDim2.new(1, -32, 0, 24)
detail.BackgroundTransparency = 1
detail.TextColor3 = Color3.fromRGB(181, 199, 215)
detail.TextSize = 13
detail.Font = Enum.Font.GothamMedium
detail.TextXAlignment = Enum.TextXAlignment.Left
detail.TextWrapped = true
detail.Parent = card

local track = Instance.new("Frame")
track.Position = UDim2.fromOffset(16, 101)
track.Size = UDim2.new(1, -102, 0, 9)
track.BackgroundColor3 = Color3.fromRGB(55, 68, 84)
track.BorderSizePixel = 0
track.ClipsDescendants = true
track.Parent = card
Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = Color3.fromRGB(57, 190, 239)
fill.BorderSizePixel = 0
fill.Parent = track
Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

local skip = Instance.new("TextButton")
skip.AnchorPoint = Vector2.new(1, 0)
skip.Position = UDim2.new(1, -14, 0, 9)
skip.Size = UDim2.fromOffset(62, 24)
skip.BackgroundTransparency = 1
skip.Text = "SKIP"
skip.TextColor3 = Color3.fromRGB(151, 168, 183)
skip.TextSize = 11
skip.Font = Enum.Font.GothamBold
skip.Parent = card

local tutorialActive = false
local completionRequested = false
local currentStepIndex = 1
local skipConfirmationExpires = 0

local function updateCard()
	if not tutorialActive then return end
	local nextIndex: number? = nil
	for index, step in ipairs(steps) do
		if milestones[step.Key] ~= true then nextIndex = index; break end
	end
	if nextIndex == nil then
		if completionRequested then return end
		completionRequested = true
		eyebrow.Text = "GETTING STARTED  •  COMPLETE"
		title.Text = "YOU'RE READY TO CLEAN!"
		detail.Text = "Jobs, water, and equipment upgrades are now yours to explore."
		TweenService:Create(fill, TweenInfo.new(0.3), { Size = UDim2.fromScale(1, 1) }):Play()
		skip.Visible = false
		task.delay(1.8, function() TutorialCompleteRequest:FireServer() end)
		return
	end
	currentStepIndex = nextIndex
	local step = steps[nextIndex]
	eyebrow.Text = string.format("GETTING STARTED  •  %d / %d", nextIndex, #steps)
	title.Text = step.Title
	detail.Text = step.Detail
	TweenService:Create(fill, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
		Size = UDim2.fromScale((nextIndex - 1) / #steps, 1),
	}):Play()
end

local function mark(key: string)
	if not tutorialActive or milestones[key] == true then return end
	milestones[key] = true
	updateCard()
end

skip.Activated:Connect(function()
	if os.clock() > skipConfirmationExpires then
		skip.Text = "SURE?"
		skip.TextColor3 = Color3.fromRGB(255, 155, 155)
		skipConfirmationExpires = os.clock() + 3
		task.delay(3, function()
			if os.clock() >= skipConfirmationExpires and skip.Parent then
				skip.Text = "SKIP"
				skip.TextColor3 = Color3.fromRGB(151, 168, 183)
			end
		end)
	else
		completionRequested = true
		TutorialCompleteRequest:FireServer()
	end
end)

local jobGui = playerGui:WaitForChild("JobUI", 15)
local phoneMenu = jobGui and jobGui:FindFirstChild("PhoneMenu", true)
if phoneMenu and phoneMenu:IsA("GuiObject") then
	phoneMenu:GetPropertyChangedSignal("Visible"):Connect(function()
		if phoneMenu.Visible then mark("PhoneOpened") end
	end)
end

JobStateChanged.OnClientEvent:Connect(function(state)
	if typeof(state) ~= "table" then return end
	if state.State == "Active" and state.JobID == "Bench_1" then
		milestones.PhoneOpened = true
		mark("BenchAccepted")
	elseif state.State == "Progress" and state.JobID == "Bench_1" then
		milestones.BenchReached = true
		mark("DirtSprayed")
	elseif state.State == "Completed" and state.JobID == "Bench_1" then
		milestones.PhoneOpened = true
		milestones.BenchAccepted = true
		milestones.BenchReached = true
		milestones.DirtSprayed = true
		mark("BenchCompleted")
	end
end)

local attachedProgressSignal: BindableEvent? = nil
local function attachProgressSignal()
	if attachedProgressSignal then return end
	local signal = playerGui:FindFirstChild("JobProgressPredicted")
	if signal and signal:IsA("BindableEvent") then
		attachedProgressSignal = signal
		signal.Event:Connect(function() mark("DirtSprayed") end)
	end
end
attachProgressSignal()
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "JobProgressPredicted" then task.defer(attachProgressSignal) end
end)

local attachedShopPanel: GuiObject? = nil
local function attachShopPanel()
	if attachedShopPanel then return end
	local shopGui = playerGui:FindFirstChild("ShopUI")
	local panel = shopGui and shopGui:FindFirstChild("ShopPanel", true)
	if panel and panel:IsA("GuiObject") then
		attachedShopPanel = panel
		panel:GetPropertyChangedSignal("Visible"):Connect(function()
			if panel.Visible then mark("ShopOpened") end
		end)
	end
end
attachShopPanel()
playerGui.DescendantAdded:Connect(function(descendant)
	if descendant.Name == "ShopPanel" then task.defer(attachShopPanel) end
end)

local distanceAccumulator = 0
RunService.Heartbeat:Connect(function(deltaTime)
	if not tutorialActive or milestones.BenchAccepted ~= true or milestones.BenchReached == true then return end
	distanceAccumulator += deltaTime
	if distanceAccumulator < 0.25 then return end
	distanceAccumulator = 0
	local environment = workspace:FindFirstChild("EnvironmentFixtures")
	local sites = environment and environment:FindFirstChild("JobSites")
	local bench = sites and sites:FindFirstChild("Bench_1")
	local benchPart = bench and bench:FindFirstChildWhichIsA("BasePart", true)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if benchPart and root and root:IsA("BasePart") and (root.Position - benchPart.Position).Magnitude <= 18 then
		mark("BenchReached")
	end
end)

TutorialStateChanged.OnClientEvent:Connect(function(state)
	if typeof(state) ~= "table" then return end
	if state.Completed == true then
		tutorialActive = false
		gui.Enabled = false
	else
		tutorialActive = true
		gui.Enabled = true
		card.Position = UDim2.fromOffset(-390, 90)
		TweenService:Create(card, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(20, 90),
		}):Play()
		updateCard()
	end
end)

TutorialStateRequest:FireServer()
