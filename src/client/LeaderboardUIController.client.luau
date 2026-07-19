--!strict

-- Replaces Roblox's minimally themeable PlayerList with a simulator-style
-- server leaderboard. Cash still comes exclusively from server leaderstats.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local leaderboardGui = playerGui:WaitForChild("LeaderboardUI") :: ScreenGui
local panel = leaderboardGui:WaitForChild("LeaderboardPanel") :: Frame
local header = panel:WaitForChild("Header") :: Frame
local collapseButton = header:WaitForChild("Collapse") :: TextButton
local playerList = panel:WaitForChild("PlayerList") :: ScrollingFrame
local rowTemplate = playerList:WaitForChild("RowTemplate") :: Frame

local expandedSize = UDim2.fromOffset(242, 101)
local COLLAPSED_SIZE = UDim2.fromOffset(242, 50)
local collapsed = false
local renderQueued = false
local watchedPlayers = setmetatable({} :: {[Player]: boolean}, { __mode = "k" })

local RANK_COLORS = {
	Color3.fromRGB(255, 216, 93),
	Color3.fromRGB(204, 222, 236),
	Color3.fromRGB(220, 146, 88),
}

local function disableNativePlayerList()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)
end

local function getCash(player: Player): number
	local leaderstats = player:FindFirstChild("leaderstats")
	local cash = leaderstats and leaderstats:FindFirstChild("Cash")
	if cash ~= nil and (cash:IsA("NumberValue") or cash:IsA("IntValue")) then
		return cash.Value
	end
	return 0
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

local renderLeaderboard: () -> ()

local function queueRender()
	if renderQueued then
		return
	end
	renderQueued = true
	task.defer(function()
		renderQueued = false
		renderLeaderboard()
	end)
end

local function watchCashContainer(container: Instance)
	local function connectCash(candidate: Instance)
		if candidate.Name == "Cash" and (candidate:IsA("NumberValue") or candidate:IsA("IntValue")) then
			candidate:GetPropertyChangedSignal("Value"):Connect(queueRender)
			queueRender()
		end
	end

	local existingCash = container:FindFirstChild("Cash")
	if existingCash then
		connectCash(existingCash)
	end
	container.ChildAdded:Connect(connectCash)
end

local function watchPlayer(player: Player)
	if watchedPlayers[player] then
		return
	end
	watchedPlayers[player] = true

	local existingLeaderstats = player:FindFirstChild("leaderstats")
	if existingLeaderstats then
		watchCashContainer(existingLeaderstats)
	end
	player.ChildAdded:Connect(function(child)
		if child.Name == "leaderstats" then
			watchCashContainer(child)
		end
	end)
	queueRender()
end

renderLeaderboard = function()
	for _, child in playerList:GetChildren() do
		if child:GetAttribute("LeaderboardGeneratedRow") == true then
			child:Destroy()
		end
	end

	local rankedPlayers = Players:GetPlayers()
	table.sort(rankedPlayers, function(left, right)
		local leftCash = getCash(left)
		local rightCash = getCash(right)
		if leftCash == rightCash then
			return left.UserId < right.UserId
		end
		return leftCash > rightCash
	end)

	for rankIndex, player in rankedPlayers do
		local row = rowTemplate:Clone()
		row.Name = "Player_" .. player.UserId
		row.LayoutOrder = rankIndex
		row.Visible = true
		row:SetAttribute("LeaderboardGeneratedRow", true)

		local rankLabel = row:FindFirstChild("Rank") :: TextLabel
		local avatar = row:FindFirstChild("Avatar") :: ImageLabel
		local nameLabel = row:FindFirstChild("PlayerName") :: TextLabel
		local statusLabel = row:FindFirstChild("Status") :: TextLabel
		local cashLabel = row:FindFirstChild("Cash") :: TextLabel
		local rowStroke = row:FindFirstChild("RowStroke") :: UIStroke

		rankLabel.Text = "#" .. rankIndex
		rankLabel.TextColor3 = RANK_COLORS[rankIndex] or Color3.fromRGB(105, 190, 235)
		nameLabel.Text = player.DisplayName
		statusLabel.Text = if player == localPlayer then "YOU - PRESSURE WASHER" else "PRESSURE WASHER"
		cashLabel.Text = formatCash(getCash(player))

		if player == localPlayer then
			row.BackgroundColor3 = Color3.fromRGB(39, 76, 105)
			rowStroke.Color = Color3.fromRGB(82, 191, 241)
			rowStroke.Transparency = 0.25
			statusLabel.TextColor3 = Color3.fromRGB(119, 215, 255)
		end

		row.Parent = playerList
		task.spawn(function()
			local success, image = pcall(function()
				return Players:GetUserThumbnailAsync(
					player.UserId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size100x100
				)
			end)
			if success and row.Parent ~= nil then
				avatar.Image = image
			end
		end)
	end

	-- Remain compact in solo/small servers and grow only as rows are needed.
	local rowCount = math.max(1, #rankedPlayers)
	local targetHeight = math.clamp(63 + rowCount * 38, 101, 305)
	expandedSize = UDim2.fromOffset(242, targetHeight)
	if not collapsed then
		panel.Size = expandedSize
	end
end

local function setCollapsed(shouldCollapse: boolean)
	collapsed = shouldCollapse
	collapseButton.Text = if collapsed then "+" else "–"
	if not collapsed then
		playerList.Visible = true
	end

	local tween = TweenService:Create(
		panel,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = if collapsed then COLLAPSED_SIZE else expandedSize }
	)
	tween.Completed:Once(function()
		if collapsed then
			playerList.Visible = false
		end
	end)
	tween:Play()
end

disableNativePlayerList()
task.delay(1, disableNativePlayerList)

collapseButton.Activated:Connect(function()
	setCollapsed(not collapsed)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and input.KeyCode == Enum.KeyCode.Tab then
		setCollapsed(not collapsed)
	end
end)

Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(queueRender)
for _, player in Players:GetPlayers() do
	watchPlayer(player)
end
renderLeaderboard()
