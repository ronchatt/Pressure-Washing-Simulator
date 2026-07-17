--!strict

-- Temporary development guard for an unapproved audio asset embedded in the
-- Studio place or a Roblox-loaded object. Remove this after replacing the ID.

local BLOCKED_SOUND_ASSET_ID = "188608071"

local function disableBlockedSound(instance: Instance)
	if not instance:IsA("Sound") or not string.find(instance.SoundId, BLOCKED_SOUND_ASSET_ID, 1, true) then
		return
	end

	local success, message = pcall(function()
		instance:Stop()
		instance.SoundId = ""
	end)
	if success then
		warn("DIAGNOSTIC: Cleared blocked sound from " .. instance:GetFullName())
	else
		warn(string.format("Could not disable blocked sound %s: %s", instance:GetFullName(), tostring(message)))
	end
end

for _, descendant in game:GetDescendants() do
	disableBlockedSound(descendant)
end
game.DescendantAdded:Connect(disableBlockedSound)
