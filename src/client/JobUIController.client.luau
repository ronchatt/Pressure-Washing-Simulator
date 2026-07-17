--!strict

task.wait(1)
print("DIAGNOSTIC: JobUIController is RUNNING.")

-- Controls the hand-authored StarterGui.JobUI. This script never creates UI;
-- cash, job acceptance, progress, and completion remain server-authoritative.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local function waitForDescendant(root: Instance, name: string, timeout: number): Instance?
	local deadline = os.clock() + timeout
	repeat
		local candidate = root:FindFirstChild(name, true)
		if candidate then
			return candidate
		end
		task.wait(0.1)
	until os.clock() >= deadline
	return nil
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local phone = playerGui:FindFirstChild("JobUI")
if phone == nil then
	phone = playerGui:WaitForChild("JobUI", 10)
end
if phone then
	print("DIAGNOSTIC: JobUI found in PlayerGui.")
else
	warn("DIAGNOSTIC: JobUI NOT FOUND in PlayerGui!")
	return
end
local jobGuiInstance = phone
if jobGuiInstance == nil or not jobGuiInstance:IsA("ScreenGui") then
	warn(string.format(
		"Type mismatch: PlayerGui.JobUI found %s; expected ScreenGui.",
		jobGuiInstance and jobGuiInstance.ClassName or "nil (not found)"
	))
	return
end
local jobGui = jobGuiInstance
local jobFrameInstance = waitForDescendant(jobGui, "Frame", 1)
local jobFrame: Instance = jobGui
if jobFrameInstance and (jobFrameInstance:IsA("Frame") or jobFrameInstance:IsA("ScrollingFrame")) then
	jobFrame = jobFrameInstance
elseif jobFrameInstance then
	warn(string.format(
		"Type mismatch: PlayerGui.JobUI.Frame found %s; expected Frame or ScrollingFrame. Searching all of JobUI instead.",
		jobFrameInstance.ClassName
	))
end

local phoneMenuInstance = waitForDescendant(jobGui, "PhoneMenu", 10)
if phoneMenuInstance == nil or (not phoneMenuInstance:IsA("Frame") and not phoneMenuInstance:IsA("ScrollingFrame")) then
	warn(string.format(
		"Type mismatch: PlayerGui.JobUI.PhoneMenu found %s; expected Frame or ScrollingFrame.",
		phoneMenuInstance and phoneMenuInstance.ClassName or "nil (not found)"
	))
	return
end
local phoneMenu = phoneMenuInstance :: GuiObject

local progressPanelInstance = waitForDescendant(jobGui, "JobProgress", 10)
if progressPanelInstance == nil or (not progressPanelInstance:IsA("Frame") and not progressPanelInstance:IsA("ScrollingFrame")) then
	warn(string.format(
		"Type mismatch: PlayerGui.JobUI.JobProgress found %s; expected Frame or ScrollingFrame.",
		progressPanelInstance and progressPanelInstance.ClassName or "nil (not found)"
	))
	return
end
local progressPanel = progressPanelInstance :: GuiObject

local openPhoneInstance = waitForDescendant(jobFrame, "OpenPhone", 3) or waitForDescendant(jobGui, "OpenPhone", 7)
if openPhoneInstance == nil or (not openPhoneInstance:IsA("TextButton") and not openPhoneInstance:IsA("ImageButton")) then
	warn(string.format(
		"Type mismatch: PlayerGui.JobUI.Frame.OpenPhone found %s; expected TextButton or ImageButton.",
		openPhoneInstance and openPhoneInstance.ClassName or "nil (not found)"
	))
	return
end
local openPhoneButton = openPhoneInstance :: GuiButton

local SharedJobData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SharedJobData"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local AcceptJobRequest = remotes:WaitForChild("AcceptJobRequest") :: RemoteEvent
local QuitJobRequest = remotes:WaitForChild("QuitJobRequest") :: RemoteEvent
local JobStateChanged = remotes:WaitForChild("JobStateChanged") :: RemoteEvent

local activeJobID: string? = nil
local currentCleaned = 0
local totalSegments = 0
local waypointFolder: Folder? = nil
local waypointConnection: RBXScriptConnection? = nil

-- WasherController uses this non-visual signal for immediate local prediction.
local progressSignal = playerGui:FindFirstChild("JobProgressPredicted")
if progressSignal == nil then
	progressSignal = Instance.new("BindableEvent")
	progressSignal.Name = "JobProgressPredicted"
	progressSignal.Parent = playerGui
end
if not progressSignal:IsA("BindableEvent") then
	warn(string.format(
		"Type mismatch: PlayerGui.JobProgressPredicted found %s; expected BindableEvent.",
		progressSignal.ClassName
	))
	return
end
local predictedProgressEvent = progressSignal :: BindableEvent

local function findTextLabel(root: Instance, preferredNames: {string}): TextLabel?
	for _, name in preferredNames do
		local candidate = root:FindFirstChild(name, true)
		if candidate and candidate:IsA("TextLabel") then
			return candidate
		end
	end
	return root:FindFirstChildWhichIsA("TextLabel", true)
end

local function findProgressFill(): Frame?
	for _, name in { "ProgressFill", "Fill", "BarFill", "GreenFill" } do
		local candidate = progressPanel:FindFirstChild(name, true)
		if candidate and candidate:IsA("Frame") then
			return candidate
		end
	end

	local track: Frame? = nil
	for _, name in { "ProgressBar", "ProgressTrack", "Bar", "BarBackground" } do
		local candidate = progressPanel:FindFirstChild(name, true)
		if candidate and candidate:IsA("Frame") then
			track = candidate
			break
		end
	end

	-- Support unnamed manually-authored bars by choosing the widest, thinnest
	-- Frame inside JobProgress. The root progress panel itself is excluded.
	if track == nil then
		local bestScore = 0
		for _, descendant in progressPanel:GetDescendants() do
			if descendant:IsA("Frame") and descendant.AbsoluteSize.Y > 0 then
				local score = descendant.AbsoluteSize.X / descendant.AbsoluteSize.Y
				if score > bestScore and score >= 4 then
					bestScore = score
					track = descendant
				end
			end
		end
	end

	if track == nil then
		return nil
	end

	-- Keep the existing gray bar as a track and insert only the missing fill.
	track.ClipsDescendants = true
	local fill = Instance.new("Frame")
	fill.Name = "ProgressFill"
	fill.AnchorPoint = Vector2.zero
	fill.Position = UDim2.fromScale(0, 0)
	fill.Size = UDim2.fromScale(1, 1)
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = Color3.fromRGB(35, 112, 65)
	fill.ZIndex = track.ZIndex + 1
	fill.Parent = track
	local trackCorner = track:FindFirstChildWhichIsA("UICorner")
	if trackCorner then
		trackCorner:Clone().Parent = fill
	end
	return fill
end

local progressLabel = findTextLabel(progressPanel, { "ProgressText", "ProgressLabel", "TextLabel" })
local progressFill = findProgressFill()
local progressFillFullSize = if progressFill then progressFill.Size else nil
local LOW_PROGRESS_GREEN = Color3.fromRGB(35, 112, 65)
local HIGH_PROGRESS_GREEN = Color3.fromRGB(67, 238, 119)
local JOB_COMPLETION_FRACTION = 0.9
local targetProgressFraction = 0
local displayedProgressFraction = 0

if progressFill == nil then
	warn("JobUI.JobProgress needs a horizontal progress bar Frame.")
end

local function jobIDForButton(button: GuiButton): string?
	local attribute = button:GetAttribute("JobID")
	if typeof(attribute) == "string" and SharedJobData.Jobs[attribute] ~= nil then
		return attribute
	end

	if SharedJobData.Jobs[button.Name] ~= nil then
		return button.Name
	end

	local buttonText = if button:IsA("TextButton") then button.Text else ""
	for _, jobID in SharedJobData.JobOrder do
		if string.find(button.Name, jobID, 1, true) or string.find(buttonText, jobID, 1, true) then
			return jobID
		end
	end
	return nil
end

local quitButton: GuiButton? = nil
for _, descendant in phoneMenu:GetDescendants() do
	if descendant:IsA("GuiButton") then
		local action = descendant:GetAttribute("Action")
		local lowerName = string.lower(descendant.Name)
		local lowerText = if descendant:IsA("TextButton") then string.lower(descendant.Text) else ""
		-- A manually authored button named exactly "Quit" is supported, as is
		-- any GuiButton carrying the string attribute Action = "QuitJob".
		if descendant.Name == "Quit"
			or action == "QuitJob"
			or string.find(lowerName, "quit", 1, true)
			or string.find(lowerText, "quit", 1, true)
		then
			quitButton = descendant
		else
			local jobID = jobIDForButton(descendant)
			if jobID ~= nil then
				descendant.Activated:Connect(function()
					AcceptJobRequest:FireServer(jobID)
				end)
			end
		end
	end
end

if quitButton then
	quitButton.Activated:Connect(function()
		QuitJobRequest:FireServer()
	end)
else
	warn("JobUI.PhoneMenu needs a GuiButton named with 'Quit' or Action='QuitJob'")
end

local function updateProgress()
	if activeJobID == nil or totalSegments <= 0 then
		return
	end

	local fraction = math.clamp(currentCleaned / totalSegments, 0, 1)
	targetProgressFraction = fraction
	if progressLabel then
		progressLabel.Text = string.format("%s  -  %.1f%% CLEAN", activeJobID, fraction * 100)
	end
end

RunService.RenderStepped:Connect(function(deltaTime)
	if progressFill and progressFillFullSize then
		-- Exponential smoothing continues toward the newest target even when
		-- dozens of cleaning updates arrive in the same frame.
		local smoothing = 1 - math.exp(-12 * deltaTime)
		displayedProgressFraction += (targetProgressFraction - displayedProgressFraction) * smoothing
		if math.abs(targetProgressFraction - displayedProgressFraction) < 0.0005 then
			displayedProgressFraction = targetProgressFraction
		end
		local brightnessProgress = math.clamp(displayedProgressFraction / JOB_COMPLETION_FRACTION, 0, 1)
		local targetSize = UDim2.new(
			progressFillFullSize.X.Scale * displayedProgressFraction,
			math.round(progressFillFullSize.X.Offset * displayedProgressFraction),
			progressFillFullSize.Y.Scale,
			progressFillFullSize.Y.Offset
		)
		progressFill.Size = targetSize
		progressFill.BackgroundColor3 = LOW_PROGRESS_GREEN:Lerp(HIGH_PROGRESS_GREEN, brightnessProgress)
	end
end)

local function clearWaypoint()
	if waypointConnection then
		waypointConnection:Disconnect()
		waypointConnection = nil
	end
	if waypointFolder then
		waypointFolder:Destroy()
		waypointFolder = nil
	end
end

local function createWaypoint(jobID: string)
	clearWaypoint()

	local environment = Workspace:FindFirstChild("EnvironmentFixtures")
	local jobSites = environment and environment:FindFirstChild("JobSites")
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
	folder.Parent = Workspace
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

	waypointConnection = RunService.RenderStepped:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root == nil or not root:IsA("BasePart") or sitePart == nil then
			return
		end

		startPart.Position = Vector3.new(root.Position.X, 0.25, root.Position.Z)
		endPart.Position = Vector3.new(sitePart.Position.X, 0.25, sitePart.Position.Z)
		beam.Transparency = NumberSequence.new(0.32 + math.sin(os.clock() * 2) * 0.1)
	end)
end

openPhoneButton.Activated:Connect(function()
	phoneMenu.Visible = not phoneMenu.Visible
end)

predictedProgressEvent.Event:Connect(function()
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
		targetProgressFraction = 0
		displayedProgressFraction = 0
		progressPanel.Visible = true
		phoneMenu.Visible = false
		updateProgress()
		createWaypoint(activeJobID :: string)
	elseif state.State == "Progress" and state.JobID == activeJobID then
		currentCleaned = state.SegmentsCleaned or currentCleaned
		totalSegments = state.TotalSegments or totalSegments
		updateProgress()
	elseif state.State == "Completed" or state.State == "Quit" then
		activeJobID = nil
		currentCleaned = 0
		totalSegments = 0
		targetProgressFraction = 0
		displayedProgressFraction = 0
		progressPanel.Visible = false
		clearWaypoint()
	end
end)
