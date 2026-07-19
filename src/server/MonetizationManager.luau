--!strict

-- Session-cached gamepass verification. Replace these placeholders with the
-- published gamepass asset IDs before release.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local INFINITE_WATER_ID = 1111111
local DOUBLE_SPEED_ID = 2222222
local BASE_WALK_SPEED = 16
local SPRINT_MULTIPLIER = 1.5
local SprintStateRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SprintStateRequest") :: RemoteEvent

local MonetizationManager = {}
local initialized = false
local ownership: {[Player]: {InfiniteWater: boolean, DoubleSpeed: boolean}} = {}

local function ownsPass(userId: number, gamepassId: number): boolean
	-- Placeholder IDs are never treated as owned during development. Replace
	-- them with this experience's real pass IDs to enable Marketplace checks.
	if gamepassId == 1111111 or gamepassId == 2222222 then
		return false
	end

	local success, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(userId, gamepassId)
	end)
	return success and result == true
end

local function applyWalkSpeed(player: Player, character: Model?)
	local cached = ownership[player]
	local targetCharacter = character or player.Character
	local humanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		local gamepassMultiplier = if cached ~= nil and cached.DoubleSpeed then 2 else 1
		local petMultiplier = player:GetAttribute("PetSpeedMultiplier")
		if typeof(petMultiplier) ~= "number" then
			petMultiplier = 1
		end
		local sprintMultiplier = if player:GetAttribute("IsSprinting") == true then SPRINT_MULTIPLIER else 1
		humanoid.WalkSpeed = BASE_WALK_SPEED * gamepassMultiplier * petMultiplier * sprintMultiplier
	end
end

local function refreshOwnership(player: Player)
	local cached = ownership[player]
	if cached == nil then
		cached = { InfiniteWater = false, DoubleSpeed = false }
		ownership[player] = cached
	end

	cached.InfiniteWater = ownsPass(player.UserId, INFINITE_WATER_ID)
	cached.DoubleSpeed = ownsPass(player.UserId, DOUBLE_SPEED_ID)
	player:SetAttribute("OwnsInfiniteWater", cached.InfiniteWater)
	player:SetAttribute("OwnsDoubleSpeed", cached.DoubleSpeed)
	applyWalkSpeed(player)
end

local function watchPlayer(player: Player)
	ownership[player] = { InfiniteWater = false, DoubleSpeed = false }
	player:SetAttribute("IsSprinting", false)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid")
		player:SetAttribute("IsSprinting", false)
		applyWalkSpeed(player, character)
	end)

	task.spawn(function()
		refreshOwnership(player)
	end)
end

function MonetizationManager:OwnsInfiniteWater(player: Player): boolean
	local cached = ownership[player]
	return cached ~= nil and cached.InfiniteWater
end

function MonetizationManager:OwnsDoubleSpeed(player: Player): boolean
	local cached = ownership[player]
	return cached ~= nil and cached.DoubleSpeed
end

function MonetizationManager:ApplyWalkSpeed(player: Player, character: Model?)
	applyWalkSpeed(player, character)
end

function MonetizationManager:Init()
	if initialized then
		return
	end
	initialized = true

	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		ownership[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end

	SprintStateRequest.OnServerEvent:Connect(function(player, wantsToSprint)
		if typeof(wantsToSprint) ~= "boolean" then
			return
		end
		player:SetAttribute("IsSprinting", wantsToSprint)
		applyWalkSpeed(player)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamepassId, wasPurchased)
		if not wasPurchased then
			return
		end

		local cached = ownership[player]
		if cached == nil then
			return
		end

		if gamepassId == INFINITE_WATER_ID then
			cached.InfiniteWater = true
			player:SetAttribute("OwnsInfiniteWater", true)
		elseif gamepassId == DOUBLE_SPEED_ID then
			cached.DoubleSpeed = true
			player:SetAttribute("OwnsDoubleSpeed", true)
			applyWalkSpeed(player)
		end
	end)
end

return MonetizationManager
