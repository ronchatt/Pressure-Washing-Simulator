--!strict

-- Local job-selection and navigation presentation. The server remains the
-- only authority for accepting jobs, cleaning progress, cash, and water.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local SharedJobData = require(ReplicatedStorage.Shared.SharedJobData)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local AcceptJobRequest = remotes:WaitForChild("AcceptJobRequest") :: RemoteEvent
local QuitJobRequest = remotes:WaitForChild("QuitJobRequest") :: RemoteEvent
local JobStateChanged = remotes:WaitForChild("JobStateChanged") :: RemoteEvent

local activeJobID: string? = nil
local currentCleaned = 0
local totalSegments = 0
local waypointFolder: Folder? = nil
local waypointConnection: RBXScriptConnection? = nil

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "JobUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local progressSignal = Instance.new("BindableEvent")
progressSignal.Name = "JobProgressPredicted"
progressSignal.Parent = playerGui

local openPhoneButton = Instance.new("TextButton")
openPhoneButton.Name = "OpenPhone"
openPhoneButton.AnchorPoint = Vector2.new(1, 1)
openPhoneButton.Position = UDim2.fromScale(0.97, 0.92)
openPhoneButton.Size = UDim2.fromOffset(128, 46)
openPhoneButton.BackgroundColor3 = Color3.fromRGB(38, 73, 112)
openPhoneButton.Text = "PHONE"
openPhoneButton.TextColor3 = Color3.new(1, 1, 1)
openPhoneButton.TextSize = 18
openPhoneButton.Font = Enum.Font.GothamBold
openPhoneButton.Parent = screenGui
Instance.new("UICorner", openPhoneButton).CornerRadius = UDim.new(0, 10)

local phone = Instance.new("Frame")
phone.Name = "PhoneMenu"
phone.AnchorPoint = Vector2.new(0.5, 0.5)
phone.Position = UDim2.fromScale(0.5, 0.5)
phone.Size = UDim2.fromOffset(380, 460)
phone.BackgroundColor3 = Color3.fromRGB(22, 28, 40)
phone.Parent = screenGui
Instance.new("UICorner", phone).CornerRadius = UDim.new(0, 20)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -32, 0, 58)
title.Position = UDim2.fromOffset(16, 10)
title.BackgroundTransparency = 1
title.Text = "WASHER PHONE"
title.TextColor3 = Color3.fromRGB(220, 240, 255)
title.TextSize = 24
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = phone

local jobsList = Instance.new("ScrollingFrame")
jobsList.Position = UDim2.fromOffset(16, 70)
jobsList.Size = UDim2.new(1, -32, 1, -142)
jobsList.BackgroundTransparency = 1
jobsList.BorderSizePixel = 0
jobsList.CanvasSize = UDim2.new()
jobsList.ScrollBarThickness = 5
jobsList.Parent = phone

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 8)
listLayout.Parent = jobsList
listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	jobsList.CanvasSize = UDim2.fromOffset(0, listLayout.AbsoluteContentSize.Y + 8)
end)

for _, jobID in SharedJobData.JobOrder do
	local job = SharedJobData.Jobs[jobID]
	local row = Instance.new("TextButton")
	row.Name = jobID
	row.Size = UDim2.new(1, -4, 0, 58)
	row.BackgroundColor3 = Color3.fromRGB(43, 54, 75)
	row.Text = string.format("%s  |  %s  |  $%d  |  ACCEPT", job.JobID, job.RequiredTier, job.Reward)
	row.TextColor3 = Color3.fromRGB(240, 245, 255)
	row.TextSize = 14
	row.Font = Enum.Font.GothamMedium
	row.Parent = jobsList
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)
	row.Activated:Connect(function()
		AcceptJobRequest:FireServer(jobID)
	end)
end

local quitButton = Instance.new("TextButton")
quitButton.AnchorPoint = Vector2.new(0.5, 1)
quitButton.Position = UDim2.new(0.5, 0, 1, -16)
quitButton.Size = UDim2.new(1, -32, 0, 44)
quitButton.BackgroundColor3 = Color3.fromRGB(135, 55, 62)
quitButton.Text = "QUIT JOB  (-$50)"
quitButton.TextColor3 = Color3.new(1, 1, 1)
quitButton.TextSize = 15
quitButton.Font = Enum.Font.GothamBold
quitButton.Parent = phone
Instance.new("UICorner", quitButton).CornerRadius = UDim.new(0, 10)
quitButton.Activated:Connect(function()
	QuitJobRequest:FireServer()
end)

local progressPanel = Instance.new("Frame")
progressPanel.Name = "JobProgress"
progressPanel.AnchorPoint = Vector2.new(0, 1)
progressPanel.Position = UDim2.new(0.025, 0, 0.95, 0)
progressPanel.Size = UDim2.fromOffset(300, 76)
progressPanel.BackgroundColor3 = Color3.fromRGB(20, 27, 37)
progressPanel.Visible = false
progressPanel.Parent = screenGui
Instance.new("UICorner", progressPanel).CornerRadius = UDim.new(0, 12)

local progressLabel = Instance.new("TextLabel")
progressLabel.Position = UDim2.fromOffset(14, 8)
progressLabel.Size = UDim2.new(1, -28, 0, 26)
progressLabel.BackgroundTransparency = 1
progressLabel.TextColor3 = Color3.fromRGB(235, 245, 255)
progressLabel.TextSize = 15
progressLabel.Font = Enum.Font.GothamBold
progressLabel.TextXAlignment = Enum.TextXAlignment.Left
progressLabel.Parent = progressPanel

local progressTrack = Instance.new("Frame")
progressTrack.Position = UDim2.fromOffset(14, 44)
progressTrack.Size = UDim2.new(1, -28, 0, 18)
progressTrack.BackgroundColor3 = Color3.fromRGB(56, 65, 79)
progressTrack.Parent = progressPanel
Instance.new("UICorner", progressTrack).CornerRadius = UDim.new(1, 0)

local progressFill = Instance.new("Frame")
progressFill.Size = UDim2.fromScale(0, 1)
progressFill.BackgroundColor3 = Color3.fromRGB(91, 190, 255)
progressFill.Parent = progressTrack
Instance.new("UICorner", progressFill).CornerRadius = UDim.new(1, 0)

local function updateProgress()
	if activeJobID == nil or totalSegments <= 0 then
		return
	end

	local fraction = math.clamp(currentCleaned / totalSegments, 0, 1)
	progressLabel.Text = string.format("%s  •  %d / %d", activeJobID, currentCleaned, totalSegments)
	progressFill.Size = UDim2.fromScale(fraction, 1)
end

local function clearWaypoint()
	if waypointConnection ~= nil then
		waypointConnection:Disconnect()
		waypointConnection = nil
	end
	if waypointFolder ~= nil then
		waypointFolder:Destroy()
		waypointFolder = nil
	end
end

local function createWaypoint(jobID: string)
	clearWaypoint()

	local jobSites = workspace:FindFirstChild("JobSites")
	local site = jobSites and jobSites:FindFirstChild(jobID)
	if site == nil then
		return
	end

	local sitePart: BasePart? = nil
	if site:IsA("Model") then
		sitePart = site.PrimaryPart or site:FindFirstChildWhichIsA("BasePart", true)
	elseif site:IsA("BasePart") then
		sitePart = site
	end
	if sitePart == nil then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "LocalJobWaypoint"
	folder.Parent = workspace
	waypointFolder = folder

	local startPart = Instance.new("Part")
	startPart.Anchored = true
	startPart.CanCollide = false
	startPart.CanQuery = false
	startPart.Transparency = 1
	startPart.Size = Vector3.new(0.2, 0.2, 0.2)
	startPart.Parent = folder

	local endPart = startPart:Clone()
	endPart.Parent = folder

	local startAttachment = Instance.new("Attachment")
	startAttachment.Parent = startPart
	local endAttachment = Instance.new("Attachment")
	endAttachment.Parent = endPart

	local beam = Instance.new("Beam")
	beam.Attachment0 = startAttachment
	beam.Attachment1 = endAttachment
	beam.FaceCamera = true
	beam.Width0 = 0.6
	beam.Width1 = 0.35
	beam.Color = ColorSequence.new(Color3.fromRGB(104, 203, 255))
	beam.Transparency = NumberSequence.new(0.38)
	beam.LightEmission = 0.5
	beam.Segments = 8
	beam.Parent = folder

	local marker = Instance.new("BillboardGui")
	marker.Name = "LocalJobSiteMarker"
	marker.Adornee = sitePart
	marker.AlwaysOnTop = true
	marker.Size = UDim2.fromOffset(130, 44)
	marker.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	marker.Parent = folder

	local markerLabel = Instance.new("TextLabel")
	markerLabel.Size = UDim2.fromScale(1, 1)
	markerLabel.BackgroundColor3 = Color3.fromRGB(35, 90, 130)
	markerLabel.BackgroundTransparency = 0.2
	markerLabel.TextColor3 = Color3.new(1, 1, 1)
	markerLabel.TextSize = 14
	markerLabel.Font = Enum.Font.GothamBold
	markerLabel.Parent = marker
	Instance.new("UICorner", markerLabel).CornerRadius = UDim.new(0, 8)

	waypointConnection = RunService.RenderStepped:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root == nil or not root:IsA("BasePart") or sitePart == nil then
			return
		end

		local startPosition = Vector3.new(root.Position.X, 0.25, root.Position.Z)
		local endPosition = Vector3.new(sitePart.Position.X, 0.25, sitePart.Position.Z)
		startPart.Position = startPosition
		endPart.Position = endPosition
		beam.Transparency = NumberSequence.new(0.32 + math.sin(os.clock() * 2) * 0.1)
		markerLabel.Text = string.format("JOB SITE\n%d studs", math.floor((root.Position - sitePart.Position).Magnitude))
	end)
end

openPhoneButton.Activated:Connect(function()
	phone.Visible = not phone.Visible
end)

progressSignal.Event:Connect(function()
	if activeJobID == nil then
		return
	end
	currentCleaned = math.min(totalSegments, currentCleaned + 1)
	updateProgress()
end)

JobStateChanged.OnClientEvent:Connect(function(state)
	if typeof(state) ~= "table" then
		return
	end

	if state.State == "Active" then
		activeJobID = state.JobID
		currentCleaned = state.SegmentsCleaned or 0
		totalSegments = state.TotalSegments or 0
		progressPanel.Visible = true
		phone.Visible = false
		updateProgress()
		createWaypoint(activeJobID)
	elseif state.State == "Progress" and state.JobID == activeJobID then
		currentCleaned = state.SegmentsCleaned or currentCleaned
		totalSegments = state.TotalSegments or totalSegments
		updateProgress()
	elseif state.State == "Completed" or state.State == "Quit" then
		activeJobID = nil
		currentCleaned = 0
		totalSegments = 0
		progressPanel.Visible = false
		clearWaypoint()
	end
end)
