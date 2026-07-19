--!strict

-- Global lifetime job-earnings board. Spendable cash is intentionally not
-- ranked because purchases and development grants would make it inaccurate.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local DataManager = require(script.Parent:WaitForChild("DataManager"))

local GlobalLeaderboardManager = {}
local initialized = false
local store = DataStoreService:GetOrderedDataStore("PressureWashing_LifetimeCash_v1")
local boardRows: {TextLabel} = {}
local refreshQueued = false

local function formatCash(value: number): string
	if value >= 1_000_000_000 then return string.format("$%.1fB", value / 1_000_000_000) end
	if value >= 1_000_000 then return string.format("$%.1fM", value / 1_000_000) end
	if value >= 1_000 then return string.format("$%.1fK", value / 1_000) end
	return string.format("$%d", math.floor(value))
end

local function findComputer(): BasePart?
	local base = Workspace:FindFirstChild("Base")
	local computer = base and base:FindFirstChild("Computer", true)
	return if computer and computer:IsA("BasePart") then computer else nil
end

local function createLabel(parent: Instance, name: string, height: number, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.new(1, -28, 0, height)
	label.BackgroundColor3 = Color3.fromRGB(20, 31, 42)
	label.BackgroundTransparency = 0.08
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(235, 245, 255)
	label.TextSize = textSize
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 18)
	padding.PaddingRight = UDim.new(0, 18)
	padding.Parent = label
	return label
end

local function ensureBoard()
	local base = Workspace:FindFirstChild("Base")
	local computer = findComputer()
	if base == nil or computer == nil then
		warn("GlobalLeaderboardManager could not find Workspace.Base.Computer")
		return
	end
	local model = base:FindFirstChild("GlobalCashLeaderboard")
	if model ~= nil and not model:IsA("Model") then model:Destroy(); model = nil end
	if model == nil then
		model = Instance.new("Model")
		model.Name = "GlobalCashLeaderboard"
		model.Parent = base
	end
	local board = model:FindFirstChild("Board")
	if board ~= nil and not board:IsA("Part") then board:Destroy(); board = nil end
	if board == nil then
		board = Instance.new("Part")
		board.Name = "Board"
		board.Parent = model
	end
	local typedBoard = board :: Part
	typedBoard.Size = Vector3.new(11, 7.5, 0.4)
	local position = computer.Position + Vector3.new(-8.5, 4.6, 0)
	typedBoard.CFrame = CFrame.lookAt(position, Vector3.new(-16, position.Y, 164))
	typedBoard.Anchored = true
	typedBoard.CanCollide = false
	typedBoard.Material = Enum.Material.SmoothPlastic
	typedBoard.Color = Color3.fromRGB(8, 20, 30)
	typedBoard:SetAttribute("GlobalLifetimeCashBoard", true)

	local oldGui = typedBoard:FindFirstChild("LeaderboardSurface")
	if oldGui then oldGui:Destroy() end
	local editorPreview = typedBoard:FindFirstChild("EditorPreview")
	if editorPreview then editorPreview:Destroy() end
	local surface = Instance.new("SurfaceGui")
	surface.Name = "LeaderboardSurface"
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(880, 600)
	surface.LightInfluence = 0
	surface.Parent = typedBoard
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(9, 21, 31)
	frame.BorderSizePixel = 0
	frame.Parent = surface
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = frame
	local framePadding = Instance.new("UIPadding")
	framePadding.PaddingTop = UDim.new(0, 14)
	framePadding.PaddingBottom = UDim.new(0, 14)
	framePadding.Parent = frame
	local header = createLabel(frame, "Header", 68, 30)
	header.LayoutOrder = 0
	header.BackgroundColor3 = Color3.fromRGB(18, 91, 137)
	header.Text = "🌎  GLOBAL CASH EARNED"
	boardRows = {}
	for index = 1, 8 do
		local row = createLabel(frame, string.format("Rank%02d", index), 52, 24)
		row.LayoutOrder = index
		row.Text = string.format("#%d   Loading...", index)
		boardRows[index] = row
	end
end

local function submitScore(player: Player, lifetimeCash: number)
	local score = math.max(0, math.floor(lifetimeCash))
	task.spawn(function()
		local success, message = pcall(function()
			store:UpdateAsync(tostring(player.UserId), function(previous)
				return math.max(tonumber(previous) or 0, score)
			end)
		end)
		if not success then
			warn(string.format("Global cash leaderboard could not save %s: %s", player.Name, tostring(message)))
		end
	end)
end

local function refreshBoard()
	local success, pages = pcall(function()
		return store:GetSortedAsync(false, #boardRows)
	end)
	if not success then
		if boardRows[1] then boardRows[1].Text = "Rankings temporarily unavailable" end
		return
	end
	local entries = pages:GetCurrentPage()
	for index, row in boardRows do
		local entry = entries[index]
		if entry == nil then
			row.Text = string.format("#%d   —", index)
		else
			local userID = tonumber(entry.key)
			local playerName = "Unknown Cleaner"
			if userID then
				local nameSuccess, resolvedName = pcall(Players.GetNameFromUserIdAsync, Players, userID)
				if nameSuccess then playerName = resolvedName end
			end
			row.Text = string.format("#%d   %s                                      %s", index, playerName, formatCash(entry.value))
		end
	end
end

local function queueRefresh()
	if refreshQueued then return end
	refreshQueued = true
	task.delay(5, function()
		refreshQueued = false
		refreshBoard()
	end)
end

local function submitLoadedProfile(player: Player)
	task.spawn(function()
		for _ = 1, 100 do
			local data = DataManager:GetData(player)
			if data ~= nil then
				if data.LifetimeCashEarned > 0 then submitScore(player, data.LifetimeCashEarned) end
				return
			end
			task.wait(0.1)
		end
	end)
end

function GlobalLeaderboardManager:Init()
	if initialized then return end
	initialized = true
	ensureBoard()
	DataManager.CashEarned:Connect(function(player: Player, lifetimeCash: number)
		submitScore(player, lifetimeCash)
		queueRefresh()
	end)
	Players.PlayerAdded:Connect(submitLoadedProfile)
	for _, player in Players:GetPlayers() do submitLoadedProfile(player) end
	task.spawn(function()
		while true do
			refreshBoard()
			task.wait(90)
		end
	end)
	print("GlobalLeaderboardManager: lifetime cash board is ready beside the Base computer.")
end

return GlobalLeaderboardManager
