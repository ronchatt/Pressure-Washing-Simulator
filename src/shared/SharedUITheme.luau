--!strict

-- Shared visual language for the simulator's hand-authored interfaces.
-- Controllers style existing instances; the StarterGui hierarchy remains the
-- source of truth for layout and UI composition.

local TweenService = game:GetService("TweenService")

local Theme = {}

Theme.Colors = {
	Background = Color3.fromRGB(13, 24, 34),
	Panel = Color3.fromRGB(18, 33, 46),
	Surface = Color3.fromRGB(27, 47, 63),
	SurfaceHover = Color3.fromRGB(35, 63, 82),
	MutedSurface = Color3.fromRGB(55, 67, 78),
	Cyan = Color3.fromRGB(57, 190, 239),
	CyanBright = Color3.fromRGB(91, 218, 255),
	Purple = Color3.fromRGB(170, 103, 235),
	PurpleBright = Color3.fromRGB(203, 139, 255),
	Green = Color3.fromRGB(57, 224, 127),
	Danger = Color3.fromRGB(210, 73, 87),
	Text = Color3.fromRGB(244, 249, 252),
	MutedText = Color3.fromRGB(164, 188, 202),
}

local boundButtons = setmetatable({} :: {[GuiButton]: boolean}, { __mode = "k" })

local function tween(instance: Instance, goals: {[string]: any}, duration: number)
	TweenService:Create(
		instance,
		TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		goals
	):Play()
end

function Theme.StylePanel(panel: GuiObject, accent: Color3)
	panel.BackgroundColor3 = Theme.Colors.Panel
	panel.BorderSizePixel = 0

	local stroke = panel:FindFirstChildWhichIsA("UIStroke")
	if stroke then
		stroke.Color = accent
		stroke.Thickness = 1.5
		stroke.Transparency = 0.18
	end

	local gradient = panel:FindFirstChildWhichIsA("UIGradient")
	if gradient then
		gradient.Enabled = true
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 43, 58)),
			ColorSequenceKeypoint.new(1, Theme.Colors.Background),
		})
	end

	for _, descendant in panel:GetDescendants() do
		if descendant:IsA("ScrollingFrame") then
			descendant.BackgroundTransparency = 1
			descendant.BorderSizePixel = 0
			descendant.ScrollBarThickness = 4
			descendant.ScrollBarImageColor3 = accent
		elseif descendant:IsA("TextLabel") then
			descendant.Font = if descendant.Name == "Title" then Enum.Font.GothamBold else Enum.Font.Gotham
			descendant.TextColor3 = Theme.Colors.Text
			descendant.BackgroundTransparency = 1
		end
	end
end

function Theme.StyleLauncher(button: GuiButton, accent: Color3, label: string)
	button.AutoButtonColor = false
	button.BackgroundColor3 = Theme.Colors.Surface
	button.BorderSizePixel = 0
	if button:IsA("TextButton") then
		button.Text = label
		button.TextColor3 = Theme.Colors.Text
		button.TextSize = 15
		button.Font = Enum.Font.GothamBold
	end

	local stroke = button:FindFirstChildWhichIsA("UIStroke")
	if stroke then
		stroke.Color = accent
		stroke.Thickness = 1.5
		stroke.Transparency = 0.12
	end

	local gradient = button:FindFirstChildWhichIsA("UIGradient")
	if gradient then
		gradient.Enabled = true
		gradient.Rotation = 12
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.72, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, accent:Lerp(Color3.new(1, 1, 1), 0.82)),
		})
	end
end

function Theme.BindButtonMotion(button: GuiButton, accent: Color3)
	if boundButtons[button] then
		return
	end
	boundButtons[button] = true

	local scale = button:FindFirstChildWhichIsA("UIScale")
	button.MouseEnter:Connect(function()
		tween(button, { BackgroundColor3 = Theme.Colors.SurfaceHover }, 0.12)
		if scale then tween(scale, { Scale = 1.035 }, 0.12) end
	end)
	button.MouseLeave:Connect(function()
		tween(button, { BackgroundColor3 = Theme.Colors.Surface }, 0.14)
		if scale then tween(scale, { Scale = 1 }, 0.14) end
	end)
	button.MouseButton1Down:Connect(function()
		if scale then tween(scale, { Scale = 0.955 }, 0.07) end
	end)
	button.MouseButton1Up:Connect(function()
		tween(button, { BackgroundColor3 = accent:Lerp(Theme.Colors.SurfaceHover, 0.78) }, 0.08)
		if scale then tween(scale, { Scale = 1.035 }, 0.09) end
	end)
end

return Theme
