--!strict

-- Persistent level/XP presentation. The server-owned Player attributes are the
-- source of truth; this controller only animates their latest values.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local shared = ReplicatedStorage:WaitForChild("Shared")
local SharedProgressionData = require(shared:WaitForChild("SharedProgressionData"))
local SharedUITheme = require(shared:WaitForChild("SharedUITheme"))
local AudioManager = require(script.Parent:WaitForChild("AudioManager"))
local colors = SharedUITheme.Colors

local existing = playerGui:FindFirstChild("ProgressionUI")
if existing then existing:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "ProgressionUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 18
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "XPPanel"
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -6)
panel.Size = UDim2.new(0.32, 0, 0, 46)
panel.BackgroundColor3 = colors.Panel
panel.BorderSizePixel = 0
panel.Parent = gui

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MinSize = Vector2.new(280, 46)
sizeConstraint.MaxSize = Vector2.new(390, 46)
sizeConstraint.Parent = panel

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = colors.Cyan
panelStroke.Thickness = 1.5
panelStroke.Transparency = 0.16
panelStroke.Parent = panel

local panelGradient = Instance.new("UIGradient")
panelGradient.Rotation = 90
panelGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(25, 47, 63)),
	ColorSequenceKeypoint.new(1, colors.Background),
})
panelGradient.Parent = panel

local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

local levelBadge = Instance.new("Frame")
levelBadge.Name = "LevelBadge"
levelBadge.AnchorPoint = Vector2.new(0, 0.5)
levelBadge.Position = UDim2.new(0, 7, 0.5, 0)
levelBadge.Size = UDim2.fromOffset(70, 32)
levelBadge.BackgroundColor3 = colors.Cyan:Lerp(colors.Surface, 0.55)
levelBadge.BorderSizePixel = 0
levelBadge.Parent = panel
Instance.new("UICorner", levelBadge).CornerRadius = UDim.new(0, 9)

local badgeStroke = Instance.new("UIStroke")
badgeStroke.Color = colors.CyanBright
badgeStroke.Transparency = 0.18
badgeStroke.Parent = levelBadge

local levelLabel = Instance.new("TextLabel")
levelLabel.Name = "LevelDisplay"
levelLabel.Size = UDim2.fromScale(1, 1)
levelLabel.BackgroundTransparency = 1
levelLabel.Text = "LEVEL 1"
levelLabel.TextColor3 = colors.Text
levelLabel.TextSize = 12
levelLabel.Font = Enum.Font.GothamBold
levelLabel.Parent = levelBadge

local progressHeader = Instance.new("TextLabel")
progressHeader.Name = "XPDisplay"
progressHeader.Position = UDim2.new(0, 87, 0, 4)
progressHeader.Size = UDim2.new(1, -96, 0, 16)
progressHeader.BackgroundTransparency = 1
progressHeader.Text = "0 / 40 XP"
progressHeader.TextColor3 = colors.Text
progressHeader.TextSize = 10
progressHeader.Font = Enum.Font.GothamBold
progressHeader.TextXAlignment = Enum.TextXAlignment.Left
progressHeader.Parent = panel

local track = Instance.new("Frame")
track.Name = "XPTrack"
track.Position = UDim2.new(0, 87, 0, 25)
track.Size = UDim2.new(1, -96, 0, 12)
track.BackgroundColor3 = colors.MutedSurface
track.BorderSizePixel = 0
track.ClipsDescendants = true
track.Parent = panel
Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

local fill = Instance.new("Frame")
fill.Name = "XPFill"
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = colors.Cyan
fill.BorderSizePixel = 0
fill.Parent = track
Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

local fillGradient = Instance.new("UIGradient")
fillGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, colors.Cyan),
	ColorSequenceKeypoint.new(1, colors.Green),
})
fillGradient.Parent = fill

local shine = Instance.new("Frame")
shine.Size = UDim2.new(1, 0, 0.32, 0)
shine.BackgroundColor3 = Color3.new(1, 1, 1)
shine.BackgroundTransparency = 0.72
shine.BorderSizePixel = 0
shine.Parent = fill
Instance.new("UICorner", shine).CornerRadius = UDim.new(1, 0)

local levelUp = Instance.new("TextLabel")
levelUp.Name = "LevelUpNotice"
levelUp.AnchorPoint = Vector2.new(0.5, 1)
levelUp.Position = UDim2.new(0.5, 0, 0, -8)
levelUp.Size = UDim2.fromOffset(260, 38)
levelUp.BackgroundTransparency = 1
levelUp.Text = "LEVEL UP!"
levelUp.TextColor3 = colors.Green
levelUp.TextSize = 25
levelUp.Font = Enum.Font.GothamBlack
levelUp.TextTransparency = 1
levelUp.TextStrokeTransparency = 1
levelUp.Parent = panel

local displayedLevel: number? = nil
local renderQueued = false

local function formatNumber(value: number): string
	local digits = tostring(math.max(0, math.floor(value)))
	local formatted = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(formatted, 1, 1) == "," then formatted = string.sub(formatted, 2) end
	return formatted
end

local function render()
	renderQueued = false
	local xpAttribute = player:GetAttribute("XP")
	local levelAttribute = player:GetAttribute("Level")
	local xp = if typeof(xpAttribute) == "number" then math.max(0, math.floor(xpAttribute)) else 0
	local level = if typeof(levelAttribute) == "number"
		then math.clamp(math.floor(levelAttribute), 1, SharedProgressionData.MaxLevel)
		else SharedProgressionData.GetLevelFromXP(xp)
	local previousDisplayedLevel = displayedLevel
	displayedLevel = level
	levelLabel.Text = "LEVEL " .. level

	local fraction: number
	if level >= SharedProgressionData.MaxLevel then
		fraction = 1
		progressHeader.Text = "MAX LEVEL  •  REBIRTH READY"
	else
		local levelStart = SharedProgressionData.GetXPForLevel(level)
		local nextLevelXP = SharedProgressionData.GetXPForLevel(level + 1)
		local earnedThisLevel = math.max(0, xp - levelStart)
		local neededThisLevel = math.max(1, nextLevelXP - levelStart)
		fraction = math.clamp(earnedThisLevel / neededThisLevel, 0, 1)
		progressHeader.Text = string.format(
			"%s / %s XP  •  NEXT: LEVEL %d",
			formatNumber(earnedThisLevel), formatNumber(neededThisLevel), level + 1
		)
	end

	TweenService:Create(fill, TweenInfo.new(0.42, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(fraction, 1),
	}):Play()

	if previousDisplayedLevel ~= nil and level > previousDisplayedLevel then
		levelUp.Text = "LEVEL " .. level .. " UNLOCKED!"
		levelUp.Position = UDim2.new(0.5, 0, 0, -4)
		levelUp.TextTransparency = 1
		levelUp.TextStrokeTransparency = 1
		panelScale.Scale = 1
		AudioManager:Play("JobComplete", 0.3, 1.16)
		TweenService:Create(panelScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.07 }):Play()
		TweenService:Create(levelUp, TweenInfo.new(0.2), { TextTransparency = 0, TextStrokeTransparency = 0.62 }):Play()
		task.delay(0.22, function()
			if panel.Parent then TweenService:Create(panelScale, TweenInfo.new(0.22), { Scale = 1 }):Play() end
		end)
		task.delay(1.25, function()
			if levelUp.Parent then
				TweenService:Create(levelUp, TweenInfo.new(0.35), {
					Position = UDim2.new(0.5, 0, 0, -28),
					TextTransparency = 1,
					TextStrokeTransparency = 1,
				}):Play()
			end
		end)
	end
end

local function queueRender()
	if renderQueued then return end
	renderQueued = true
	task.defer(render)
end

player:GetAttributeChangedSignal("XP"):Connect(queueRender)
player:GetAttributeChangedSignal("Level"):Connect(queueRender)
player:GetAttributeChangedSignal("XPToNextLevel"):Connect(queueRender)
render()
