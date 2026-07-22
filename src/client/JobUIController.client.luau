--!strict

task.wait(1)
print("DIAGNOSTIC: JobUIController is RUNNING.")

-- Controls the hand-authored StarterGui.JobUI. Job selection remains manually
-- authored; the short-lived completion celebration is generated at runtime.
-- Cash, job acceptance, progress, and completion remain server-authoritative.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
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
local baseProgressPanelSize = progressPanel.Size
-- The persistent XP bar occupies the bottom-center edge. Active contract
-- progress stacks immediately above it instead of obscuring either meter.
progressPanel.AnchorPoint = Vector2.new(0.5, 1)
progressPanel.Position = UDim2.new(0.5, 0, 1, -116)

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
local SharedUITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SharedUITheme"))
local UI_COLORS = SharedUITheme.Colors
local catalogJobs: {[string]: any} = table.clone(SharedJobData.Jobs)
local catalogJobOrder: {string} = table.clone(SharedJobData.JobOrder)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local AcceptJobRequest = remotes:WaitForChild("AcceptJobRequest") :: RemoteEvent
local QuitJobRequest = remotes:WaitForChild("QuitJobRequest") :: RemoteEvent
local JobStateChanged = remotes:WaitForChild("JobStateChanged") :: RemoteEvent
local JobStateRequest = remotes:WaitForChild("JobStateRequest") :: RemoteEvent

local activeJobID: string? = nil
local activeWaterSource = "OWN WATER"
local currentCleaned = 0
local totalSegments = 0
local currentPerJobProgress: {[string]: number} = {}
local currentTargetJobID: string? = nil
local waypointFolder: Folder? = nil
local waypointConnection: RBXScriptConnection? = nil
local unlockedTiers: {[string]: boolean} = { Benches = true }
local currentLevel = 1
local jobAvailability: {[string]: boolean} = {}
local jobButtons: {[string]: GuiButton} = {}
local connectedJobButtons = setmetatable({} :: {[GuiButton]: boolean}, { __mode = "k" })

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
local DEFAULT_JOB_COMPLETION_FRACTION = 0.95
local JOB_COMPLETION_FRACTIONS: {[string]: number} = {
	Driveway_1 = 0.98,
	SingleStoryHouse_1 = 0.98,
}

local function getCompletionFraction(jobID: string?): number
	if jobID then
		local job = catalogJobs[jobID]
		if job and typeof(job.CompletionThreshold) == "number" then
			return math.clamp(job.CompletionThreshold / 100, 0.5, 1)
		end
		return JOB_COMPLETION_FRACTIONS[jobID] or DEFAULT_JOB_COMPLETION_FRACTION
	end
	return DEFAULT_JOB_COMPLETION_FRACTION
end
local targetProgressFraction = 0
local displayedProgressFraction = 0

if progressFill == nil then
	warn("JobUI.JobProgress needs a horizontal progress bar Frame.")
end

local function jobIDForButton(button: GuiButton): string?
	local attribute = button:GetAttribute("JobID")
	if typeof(attribute) == "string" and catalogJobs[attribute] ~= nil then
		return attribute
	end

	if catalogJobs[button.Name] ~= nil then
		return button.Name
	end

	local buttonText = if button:IsA("TextButton") then button.Text else ""
	for _, jobID in ipairs(catalogJobOrder) do
		if string.find(button.Name, jobID, 1, true) or string.find(buttonText, jobID, 1, true) then
			return jobID
		end
	end
	return nil
end

local quitButton: GuiButton? = nil
local closePhoneButton: GuiButton? = nil
for _, descendant in phoneMenu:GetDescendants() do
	if descendant:IsA("GuiButton") then
		local action = descendant:GetAttribute("Action")
		local lowerName = string.lower(descendant.Name)
		local lowerText = if descendant:IsA("TextButton") then string.lower(descendant.Text) else ""
		-- A manually authored button named exactly "Quit" is supported, as is
		-- any GuiButton carrying the string attribute Action = "QuitJob".
		if action == "ClosePhone"
			or string.find(lowerName, "closephone", 1, true)
			or lowerName == "x"
		then
			closePhoneButton = descendant
		elseif descendant.Name == "Quit"
			or action == "QuitJob"
			or string.find(lowerName, "quit", 1, true)
			or string.find(lowerText, "quit", 1, true)
		then
			quitButton = descendant
		else
			local jobID = jobIDForButton(descendant)
			if jobID ~= nil then
				jobButtons[jobID] = descendant
			end
		end
	end
end

if quitButton == nil then
	warn("JobUI.PhoneMenu needs a GuiButton named with 'Quit' or Action='QuitJob'")
end

local function shortCash(value: number): string
	return "$" .. tostring(math.floor(value + 0.5))
end

local jobList = phoneMenu:FindFirstChildWhichIsA("ScrollingFrame", true)
local comboButtons: {[string]: GuiButton} = {}
if jobList then
	local cardTemplate = jobButtons["Bench_1"]
	for _, comboID in SharedJobData.ComboJobOrder do
		local existing = jobList:FindFirstChild(comboID)
		local button: GuiButton? = if existing and existing:IsA("GuiButton") then existing else nil
		if button == nil and cardTemplate then
			button = cardTemplate:Clone()
			button.Name = comboID
			button.Parent = jobList
		end
		if button then comboButtons[comboID] = button end
	end
end

local function connectJobButton(jobID: string, button: GuiButton)
	if connectedJobButtons[button] then return end
	connectedJobButtons[button] = true
	button:SetAttribute("JobID", jobID)
	button.Activated:Connect(function()
		AcceptJobRequest:FireServer(jobID)
	end)
end

local function ensureCatalogJobButtons()
	if jobList == nil then return end
	local cardTemplate = jobButtons.Bench_1
	for order, jobID in catalogJobOrder do
		local button = jobButtons[jobID]
		if button == nil then
			local existing = jobList:FindFirstChild(jobID)
			if existing and existing:IsA("GuiButton") then
				button = existing
			elseif cardTemplate then
				button = cardTemplate:Clone()
				button.Name = jobID
				button.Parent = jobList
			end
			if button then jobButtons[jobID] = button end
		end
		if button then
			button.LayoutOrder = order
			connectJobButton(jobID, button)
		end
	end
end

local function renderJobCards()
	for _, jobID in catalogJobOrder do
		local button = jobButtons[jobID]
		local job = catalogJobs[jobID]
		if button and job then
			local unlocked = unlockedTiers[job.RequiredTier] == true
			local available = jobAvailability[jobID] == true
			local isActive = activeJobID == jobID
			local status: string
			if not unlocked then status = string.format("LOCKED  •  LEVEL %d REQUIRED (YOU: %d)", job.UnlockLevel or 1, currentLevel)
			elseif not available then status = "SITE COMING SOON"
			elseif isActive then status = "ACTIVE JOB"
			elseif activeJobID ~= nil then status = "FINISH CURRENT JOB FIRST"
			else status = "ACCEPT JOB" end
			if button:IsA("TextButton") then
				button.Text = string.format(
					"%s  •  %s\nReward %s  •  Recommended: %s\n%s",
					job.DisplayName, string.upper(job.Difficulty), shortCash(job.Reward), job.RecommendedWasher, status
				)
				button.TextWrapped = true
				button.TextSize = 12
				button.TextColor3 = Color3.fromRGB(239, 247, 255)
				button.TextTransparency = 0
				button.Font = Enum.Font.GothamBold
			end
			local legacyGradient = button:FindFirstChildWhichIsA("UIGradient")
			if legacyGradient then
				legacyGradient.Enabled = false
			end
			button.Size = UDim2.new(1, -4, 0, 76)
			button.Active = unlocked and available and activeJobID == nil
			button.AutoButtonColor = button.Active
			button.BackgroundColor3 = if isActive
				then UI_COLORS.Green:Lerp(UI_COLORS.Surface, 0.58)
				elseif not unlocked or not available then UI_COLORS.MutedSurface
				else UI_COLORS.Surface
			local cardStroke = button:FindFirstChildWhichIsA("UIStroke")
			if cardStroke then
				cardStroke.Color = if isActive then UI_COLORS.Green else UI_COLORS.Cyan
				cardStroke.Transparency = if unlocked and available then 0.28 else 0.7
			end
		end
	end
	for _, comboID in SharedJobData.ComboJobOrder do
		local button = comboButtons[comboID]
		local combo = SharedJobData.ComboJobs[comboID]
		if button and combo then
			local unlocked = unlockedTiers[combo.RequiredTier] == true
			local available = jobAvailability[comboID] == true
			local isActive = activeJobID == comboID
			local status: string
			if not unlocked then status = "LOCKED  •  Unlock Fences first"
			elseif not available then status = "A REQUIRED JOB SITE IS UNAVAILABLE"
			elseif isActive then status = "ACTIVE COMBO"
			elseif activeJobID ~= nil then status = "FINISH CURRENT JOB FIRST"
			else status = "ACCEPT COMBO JOB" end
			if button:IsA("TextButton") then
				button.Text = string.format(
					"★ %s  •  %s\nBench + Fence  •  Reward %s\n%s",
					combo.DisplayName, string.upper(combo.Difficulty), shortCash(combo.Reward), status
				)
				button.TextWrapped = true
				button.TextSize = 12
				button.TextColor3 = Color3.fromRGB(249, 242, 255)
				button.Font = Enum.Font.GothamBold
			end
			local gradient = button:FindFirstChildWhichIsA("UIGradient")
			if gradient then
				gradient.Enabled = false
			end
			button.Size = UDim2.new(1, -4, 0, 82)
			button.Active = unlocked and available and activeJobID == nil
			button.AutoButtonColor = button.Active
			button.BackgroundColor3 = if isActive
				then UI_COLORS.Green:Lerp(UI_COLORS.Surface, 0.58)
				elseif not unlocked or not available then UI_COLORS.MutedSurface
				else UI_COLORS.Purple:Lerp(UI_COLORS.Surface, 0.68)
		end
	end
end

local jobListLayout = jobList and jobList:FindFirstChildWhichIsA("UIListLayout")
if jobList and jobListLayout then
	jobListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	local function updateJobCanvas()
		jobList.CanvasSize = UDim2.fromOffset(0, jobListLayout.AbsoluteContentSize.Y + 12)
	end
	jobListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateJobCanvas)
	task.defer(updateJobCanvas)
end

local noticeVersion = 0
local function showJobNotice(message: string, success: boolean)
	noticeVersion += 1
	local version = noticeVersion
	local old = jobGui:FindFirstChild("JobNotice")
	if old then old:Destroy() end
	local notice = Instance.new("TextLabel")
	notice.Name = "JobNotice"
	notice.AnchorPoint = Vector2.new(0.5, 0)
	notice.Position = UDim2.new(0.5, 0, 0, -70)
	notice.Size = UDim2.fromOffset(460, 58)
	notice.BackgroundColor3 = Color3.fromRGB(20, 30, 42)
	notice.BorderSizePixel = 0
	notice.Text = message
	notice.TextColor3 = if success then Color3.fromRGB(94, 235, 151) else Color3.fromRGB(255, 132, 132)
	notice.TextSize = 15
	notice.TextWrapped = true
	notice.Font = Enum.Font.GothamBold
	notice.ZIndex = 70
	notice.Parent = jobGui
	Instance.new("UICorner", notice).CornerRadius = UDim.new(0, 14)
	local stroke = Instance.new("UIStroke")
	stroke.Color = notice.TextColor3
	stroke.Thickness = 2
	stroke.Transparency = 0.2
	stroke.Parent = notice
	TweenService:Create(notice, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, 20) }):Play()
	task.delay(2.8, function()
		if noticeVersion == version and notice.Parent then notice:Destroy() end
	end)
end

local function showQuitConfirmation()
	if activeJobID == nil then showJobNotice("You do not have an active job to quit.", false); return end
	local old = jobGui:FindFirstChild("QuitConfirmation")
	if old then old:Destroy() end
	local popup = Instance.new("Frame")
	popup.Name = "QuitConfirmation"
	popup.AnchorPoint = Vector2.new(0.5, 0)
	popup.Position = UDim2.new(0.5, 0, 0, 78)
	popup.Size = UDim2.fromOffset(420, 138)
	popup.BackgroundColor3 = Color3.fromRGB(22, 30, 42)
	popup.BorderSizePixel = 0
	popup.ZIndex = 75
	popup.Parent = jobGui
	Instance.new("UICorner", popup).CornerRadius = UDim.new(0, 16)
	local text = Instance.new("TextLabel")
	text.Size = UDim2.new(1, -28, 0, 72)
	text.Position = UDim2.fromOffset(14, 6)
	text.BackgroundTransparency = 1
	text.Text = "QUIT " .. activeJobID .. "?\nProgress will reset and you may be charged $50."
	text.TextColor3 = Color3.fromRGB(239, 245, 251)
	text.TextSize = 15
	text.TextWrapped = true
	text.Font = Enum.Font.GothamBold
	text.ZIndex = 76
	text.Parent = popup
	local cancel = Instance.new("TextButton")
	cancel.Size = UDim2.new(0.5, -20, 0, 42)
	cancel.Position = UDim2.new(0, 14, 1, -52)
	cancel.BackgroundColor3 = Color3.fromRGB(69, 78, 92)
	cancel.Text = "KEEP CLEANING"
	cancel.TextColor3 = Color3.new(1, 1, 1)
	cancel.Font = Enum.Font.GothamBold
	cancel.ZIndex = 76
	cancel.Parent = popup
	Instance.new("UICorner", cancel).CornerRadius = UDim.new(0, 9)
	local confirm = cancel:Clone()
	confirm.AnchorPoint = Vector2.new(1, 0)
	confirm.Position = UDim2.new(1, -14, 1, -52)
	confirm.BackgroundColor3 = Color3.fromRGB(176, 62, 72)
	confirm.Text = "QUIT JOB  (-$50)"
	confirm.Parent = popup
	cancel.Activated:Connect(function() popup:Destroy() end)
	confirm.Activated:Connect(function() popup:Destroy(); QuitJobRequest:FireServer() end)
end

for jobID, button in jobButtons do connectJobButton(jobID, button) end
for comboID, button in comboButtons do
	button.Activated:Connect(function() AcceptJobRequest:FireServer(comboID) end)
end
if quitButton then quitButton.Activated:Connect(showQuitConfirmation) end
if closePhoneButton then
	closePhoneButton.Activated:Connect(function()
		phoneMenu.Visible = false
	end)
end
ensureCatalogJobButtons()
renderJobCards()

SharedUITheme.StylePanel(phoneMenu, UI_COLORS.Cyan)
local phoneOutline = phoneMenu:FindFirstChildWhichIsA("UIStroke")
if phoneOutline then
	phoneOutline.Enabled = false
end
SharedUITheme.StyleLauncher(openPhoneButton, UI_COLORS.Cyan, "PHONE   >")
SharedUITheme.BindButtonMotion(openPhoneButton, UI_COLORS.Cyan)
if closePhoneButton then
	if closePhoneButton:IsA("TextButton") then
		closePhoneButton.TextColor3 = UI_COLORS.Text
	end
	local closeGradient = closePhoneButton:FindFirstChildWhichIsA("UIGradient")
	if closeGradient then closeGradient.Enabled = false end
	SharedUITheme.BindButtonMotion(closePhoneButton, UI_COLORS.Cyan)
end

local function updateProgress()
	if activeJobID == nil or totalSegments <= 0 then
		return
	end

	local fraction = math.clamp(currentCleaned / totalSegments, 0, 1)
	targetProgressFraction = fraction
	if progressLabel then
		local perObject = ""
		if SharedJobData.ComboJobs[activeJobID] then
			perObject = string.format(
				"\nBench %.0f%%  •  Fence %.0f%%  •  Next: %s",
				currentPerJobProgress.Bench_1 or 0,
				currentPerJobProgress.Fence_1 or 0,
				currentTargetJobID or "Complete"
			)
		end
		progressLabel.Text = string.format("%s  -  %.1f%% CLEAN  •  %s%s", activeJobID, fraction * 100, activeWaterSource, perObject)
		progressLabel.TextWrapped = true
	end
end

local function formatCash(value: number): string
	local rounded = math.floor(value + 0.5)
	local digits = tostring(rounded)
	local formatted = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return "$" .. formatted
end

local function findBankTarget(): GuiObject?
	local leaderboard = playerGui:FindFirstChild("LeaderboardUI")
	if leaderboard == nil then
		return nil
	end
	local playerRow = leaderboard:FindFirstChild("Player_" .. player.UserId, true)
	if playerRow then
		local cash = playerRow:FindFirstChild("Cash", true)
		if cash and cash:IsA("GuiObject") then
			return cash
		end
	end
	local panel = leaderboard:FindFirstChild("LeaderboardPanel", true)
	return if panel and panel:IsA("GuiObject") then panel else nil
end

local function tweenTextTransparency(root: Instance, transparency: number, duration: number)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
			TweenService:Create(descendant, TweenInfo.new(duration), {
				TextTransparency = transparency,
				TextStrokeTransparency = transparency,
			}):Play()
		elseif descendant:IsA("UIStroke") then
			TweenService:Create(descendant, TweenInfo.new(duration), { Transparency = transparency }):Play()
		end
	end
end

local function showCompletionCelebration(jobID: string, reward: number, newTier: string?)
	local oldCelebration = jobGui:FindFirstChild("JobCompletionCelebration")
	if oldCelebration then
		oldCelebration:Destroy()
	end

	local overlay = Instance.new("Frame")
	overlay.Name = "JobCompletionCelebration"
	overlay.BackgroundTransparency = 1
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = 80
	overlay.Parent = jobGui

	local popup = Instance.new("Frame")
	popup.Name = "CompletionPopup"
	popup.AnchorPoint = Vector2.new(0.5, 0)
	popup.Position = UDim2.new(0.5, 0, 0, -125)
	popup.Size = UDim2.fromOffset(430, if newTier then 128 else 104)
	popup.BackgroundColor3 = Color3.fromRGB(17, 28, 39)
	popup.BorderSizePixel = 0
	popup.ZIndex = 84
	popup.Parent = overlay

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = popup
	local stroke = Instance.new("UIStroke")
	stroke.Name = "GlowStroke"
	stroke.Color = Color3.fromRGB(67, 215, 255)
	stroke.Thickness = 2
	stroke.Transparency = 0.08
	stroke.Parent = popup
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(19, 40, 58)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 30, 42)),
	})
	gradient.Rotation = 12
	gradient.Parent = popup

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(18, 10)
	title.Size = UDim2.new(1, -36, 0, 42)
	title.Font = Enum.Font.GothamBlack
	title.Text = "JOB COMPLETE!"
	title.TextColor3 = Color3.fromRGB(91, 235, 146)
	title.TextSize = 27
	title.TextStrokeColor3 = Color3.fromRGB(9, 19, 27)
	title.TextStrokeTransparency = 0.4
	title.ZIndex = 85
	title.Parent = popup

	local details = Instance.new("TextLabel")
	details.BackgroundTransparency = 1
	details.Position = UDim2.fromOffset(18, 51)
	details.Size = UDim2.new(1, -36, 0, if newTier then 61 else 37)
	details.Font = Enum.Font.GothamBold
	details.Text = string.format(
		"%s   •   +%s CASH%s",
		jobID,
		formatCash(reward),
		if newTier then "\nNEW JOB TIER UNLOCKED: " .. string.upper(newTier) else ""
	)
	details.TextWrapped = true
	details.TextColor3 = Color3.fromRGB(225, 240, 250)
	details.TextSize = 17
	details.ZIndex = 85
	details.Parent = popup

	local colors = {
		Color3.fromRGB(67, 215, 255),
		Color3.fromRGB(91, 235, 146),
		Color3.fromRGB(255, 211, 81),
		Color3.fromRGB(175, 101, 238),
		Color3.fromRGB(255, 104, 121),
	}
	local random = Random.new(math.floor(os.clock() * 1000) % 2_147_483_647)
	for index = 1, 30 do
		local confetti = Instance.new("Frame")
		confetti.Name = "Confetti_" .. index
		confetti.AnchorPoint = Vector2.new(0.5, 0.5)
		confetti.Position = UDim2.new(0.5, random:NextInteger(-190, 190), 0, random:NextInteger(20, 72))
		confetti.Size = UDim2.fromOffset(random:NextInteger(6, 11), random:NextInteger(11, 19))
		confetti.BackgroundColor3 = colors[random:NextInteger(1, #colors)]
		confetti.BorderSizePixel = 0
		confetti.Rotation = random:NextInteger(-80, 80)
		confetti.ZIndex = 82
		confetti.Parent = overlay
		Instance.new("UICorner", confetti).CornerRadius = UDim.new(0, 2)
		local fallTime = random:NextNumber(1.25, 2.1)
		TweenService:Create(confetti, TweenInfo.new(fallTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, random:NextInteger(-360, 360), 0, random:NextInteger(330, 540)),
			Rotation = confetti.Rotation + random:NextInteger(180, 620),
			BackgroundTransparency = 1,
		}):Play()
	end

	local popupTween = TweenService:Create(
		popup,
		TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0, 20) }
	)
	popupTween:Play()

	task.delay(0.65, function()
		if overlay.Parent == nil or reward <= 0 then
			return
		end
		local cashToken = Instance.new("TextLabel")
		cashToken.Name = "CashDeposit"
		cashToken.AnchorPoint = Vector2.new(0.5, 0.5)
		cashToken.Position = UDim2.new(0.5, 0, 0, 111)
		cashToken.Size = UDim2.fromOffset(150, 48)
		cashToken.BackgroundColor3 = Color3.fromRGB(35, 172, 91)
		cashToken.BorderSizePixel = 0
		cashToken.Font = Enum.Font.GothamBlack
		cashToken.Text = "+" .. formatCash(reward)
		cashToken.TextColor3 = Color3.new(1, 1, 1)
		cashToken.TextSize = 22
		cashToken.ZIndex = 90
		cashToken.Parent = overlay
		Instance.new("UICorner", cashToken).CornerRadius = UDim.new(1, 0)
		local tokenStroke = Instance.new("UIStroke")
		tokenStroke.Color = Color3.fromRGB(132, 255, 177)
		tokenStroke.Thickness = 2
		tokenStroke.Parent = cashToken

		local bankTarget = findBankTarget()
		local viewportSize = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
		local targetPosition = if bankTarget
			then bankTarget.AbsolutePosition + bankTarget.AbsoluteSize * 0.5
			else Vector2.new(viewportSize.X - 120, 70)
		local depositTween = TweenService:Create(
			cashToken,
			TweenInfo.new(0.85, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
			{
				Position = UDim2.fromOffset(targetPosition.X, targetPosition.Y),
				Size = UDim2.fromOffset(40, 20),
				TextTransparency = 1,
				BackgroundTransparency = 0.35,
			}
		)
		depositTween.Completed:Once(function()
			cashToken:Destroy()
			local refreshedTarget = findBankTarget()
			if refreshedTarget then
				local originalSize = refreshedTarget.Size
				TweenService:Create(refreshedTarget, TweenInfo.new(0.12, Enum.EasingStyle.Back), {
					Size = UDim2.new(originalSize.X.Scale, originalSize.X.Offset + 8, originalSize.Y.Scale, originalSize.Y.Offset + 4),
				}):Play()
				task.delay(0.13, function()
					if refreshedTarget.Parent then
						TweenService:Create(refreshedTarget, TweenInfo.new(0.18), { Size = originalSize }):Play()
					end
				end)
			end
		end)
		depositTween:Play()
	end)

	task.delay(2.45, function()
		if overlay.Parent == nil then
			return
		end
		tweenTextTransparency(popup, 1, 0.3)
		local exitTween = TweenService:Create(popup, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, 0, 0, -125),
			BackgroundTransparency = 1,
		})
		exitTween.Completed:Once(function()
			overlay:Destroy()
		end)
		exitTween:Play()
	end)
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
		local brightnessProgress = math.clamp(
			displayedProgressFraction / getCompletionFraction(currentTargetJobID or activeJobID),
			0,
			1
		)
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
	if phoneMenu.Visible then JobStateRequest:FireServer() end
end)

predictedProgressEvent.Event:Connect(function(segment)
	if activeJobID == nil then
		return
	end
	local weight = 1
	if typeof(segment) == "Instance" then
		local configuredWeight = segment:GetAttribute("DirtWeight")
		if typeof(configuredWeight) == "number" and configuredWeight > 0 then
			weight = math.clamp(configuredWeight, 0.05, 25)
		end
	end
	-- Prediction stays responsive but cannot announce completion. Only a
	-- Server-confirmed Progress/Completed state owns the final threshold.
	local predictedCeiling = totalSegments * (getCompletionFraction(currentTargetJobID or activeJobID) - 0.001)
	currentCleaned = math.min(predictedCeiling, currentCleaned + weight)
	updateProgress()
end)

JobStateChanged.OnClientEvent:Connect(function(state)
	if typeof(state) ~= "table" then
		return
	end

	if state.State == "Catalog" then
		if typeof(state.JobDefinitions) == "table" then
			catalogJobs = state.JobDefinitions
		end
		if typeof(state.JobOrder) == "table" then
			catalogJobOrder = {}
			for _, jobID in state.JobOrder do
				if typeof(jobID) == "string" and catalogJobs[jobID] ~= nil then
					table.insert(catalogJobOrder, jobID)
				end
			end
		end
		unlockedTiers = {}
		for _, tier in state.UnlockedJobTiers or {} do
			if typeof(tier) == "string" then unlockedTiers[tier] = true end
		end
		jobAvailability = if typeof(state.Availability) == "table" then state.Availability else {}
		currentLevel = if typeof(state.Level) == "number" then state.Level else currentLevel
		if typeof(state.ActiveJobID) == "string" then activeJobID = state.ActiveJobID end
		ensureCatalogJobButtons()
		renderJobCards()
	elseif state.State == "Rejected" then
		showJobNotice(if typeof(state.Message) == "string" then state.Message else "Job request rejected.", false)
	elseif state.State == "Active" then
		activeJobID = state.JobID
		currentPerJobProgress = if typeof(state.PerJobProgress) == "table" then state.PerJobProgress else {}
		currentTargetJobID = if typeof(state.CurrentTargetJobID) == "string" then state.CurrentTargetJobID else state.JobID
		activeWaterSource = "OWN WATER"
		currentCleaned = state.CleanedCoverage or state.SegmentsCleaned or 0
		totalSegments = state.TotalCoverage or state.TotalSegments or 0
		targetProgressFraction = 0
		displayedProgressFraction = 0
		progressPanel.Visible = true
		progressPanel.Size = if state.IsCombo == true
			then UDim2.new(baseProgressPanelSize.X.Scale, baseProgressPanelSize.X.Offset, baseProgressPanelSize.Y.Scale, baseProgressPanelSize.Y.Offset + 30)
			else baseProgressPanelSize
		phoneMenu.Visible = false
		updateProgress()
		createWaypoint(currentTargetJobID :: string)
		renderJobCards()
		showJobNotice("Job accepted: " .. tostring(state.JobID), true)
	elseif state.State == "Progress" and state.JobID == activeJobID then
		currentCleaned = state.CleanedCoverage or state.SegmentsCleaned or currentCleaned
		totalSegments = state.TotalCoverage or state.TotalSegments or totalSegments
		currentPerJobProgress = if typeof(state.PerJobProgress) == "table" then state.PerJobProgress else currentPerJobProgress
		local newTarget = if typeof(state.CurrentTargetJobID) == "string" then state.CurrentTargetJobID else currentTargetJobID
		if newTarget ~= currentTargetJobID and newTarget ~= nil then
			currentTargetJobID = newTarget
			createWaypoint(newTarget)
		end
		updateProgress()
	elseif state.State == "WaterSourceChanged" and state.JobID == activeJobID then
		local multiplier = if typeof(state.RewardMultiplier) == "number" then state.RewardMultiplier else 1
		activeWaterSource = string.format("CUSTOMER WATER (-%d%%)", math.round((1 - multiplier) * 100))
		updateProgress()
	elseif state.State == "Completed" or state.State == "Quit" then
		if state.State == "Completed" then
			showCompletionCelebration(
				if typeof(state.JobID) == "string" then state.JobID else activeJobID or "Job",
				if typeof(state.Reward) == "number" then state.Reward else 0,
				if typeof(state.NewTierUnlocked) == "string" then state.NewTierUnlocked else nil
			)
		elseif typeof(state.Message) == "string" then
			showJobNotice(state.Message, false)
		end
		activeJobID = nil
		currentPerJobProgress = {}
		currentTargetJobID = nil
		activeWaterSource = "OWN WATER"
		currentCleaned = 0
		totalSegments = 0
		targetProgressFraction = 0
		displayedProgressFraction = 0
		progressPanel.Visible = false
		progressPanel.Size = baseProgressPanelSize
		clearWaypoint()
		renderJobCards()
	end
end)

JobStateRequest:FireServer()
