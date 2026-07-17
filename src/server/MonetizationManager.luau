--!strict

-- Session-cached gamepass verification. Replace these placeholders with the
-- published gamepass asset IDs before release.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local INFINITE_WATER_ID = 1111111
local DOUBLE_SPEED_ID = 2222222

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
	if cached == nil or not cached.DoubleSpeed then
		return
	end

	local targetCharacter = character or player.Character
	local humanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		local petMultiplier = player:GetAttribute("PetSpeedMultiplier")
		if typeof(petMultiplier) ~= "number" then
			petMultiplier = 1
		end
		humanoid.WalkSpeed = 16 * 2 * petMultiplier
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
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid")
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
