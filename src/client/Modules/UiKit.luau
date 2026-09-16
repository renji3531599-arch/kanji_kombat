--!nonstrict
-- UI構築ヘルパー
local UiKit = {}

function UiKit.mk(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	inst.Parent = props.Parent or parent
	return inst
end

function UiKit.corner(parent, radius)
	UiKit.mk("UICorner", { CornerRadius = UDim.new(0, radius or 10), Parent = parent })
end

function UiKit.stroke(parent, color, thickness, transparency)
	return UiKit.mk("UIStroke", {
		Color = color or Color3.fromRGB(70, 70, 90),
		Thickness = thickness or 1.5,
		Transparency = transparency or 0.2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function UiKit.label(props, parent)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or Color3.fromRGB(235, 235, 245)
	props.TextScaled = props.TextScaled ~= false and true or false
	local l = UiKit.mk("TextLabel", props, parent)
	return l
end

function UiKit.button(props, parent)
	props.BackgroundColor3 = props.BackgroundColor3 or Color3.fromRGB(55, 55, 75)
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or Color3.fromRGB(240, 240, 250)
	props.TextScaled = props.TextScaled ~= false and true or false
	props.AutoButtonColor = true
	local b = UiKit.mk("TextButton", props, parent)
	UiKit.corner(b, props.radius or 10)
	local st = UiKit.stroke(b, Color3.fromRGB(90, 90, 120), 1.5, 0.35)
	b.MouseEnter:Connect(function()
		st.Color = Color3.fromRGB(160, 160, 220)
	end)
	b.MouseLeave:Connect(function()
		st.Color = Color3.fromRGB(90, 90, 120)
	end)
	return b
end

function UiKit.hpBar(parent, size, position, color, anchor)
	local holder = UiKit.mk("Frame", {
		Size = size,
		Position = position,
		AnchorPoint = anchor or Vector2.new(0, 0),
		BackgroundColor3 = Color3.fromRGB(25, 25, 32),
		BorderSizePixel = 0,
		Parent = parent,
	})
	UiKit.corner(holder, 8)
	UiKit.stroke(holder, Color3.fromRGB(80, 80, 100), 1.5, 0.3)
	local fill = UiKit.mk("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = holder,
	})
	UiKit.corner(fill, 8)
	local grad = UiKit.mk("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 190, 190)),
		Parent = fill,
	})
	return holder, fill
end

function UiKit.playSound(id, pitch, volume)
	pcall(function()
		local s = Instance.new("Sound")
		s.SoundId = id
		s.PlaybackSpeed = pitch or 1
		s.Volume = volume or 0.6
		s.Parent = game:GetService("SoundService")
		s:Play()
		s.Ended:Connect(function()
			s:Destroy()
		end)
		task.delay(4, function()
			if s.Parent then
				s:Destroy()
			end
		end)
	end)
end

return UiKit
