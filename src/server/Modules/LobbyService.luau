--!nonstrict
-- ロビーマップ生成: 広場 + 鳥居風ゲート + 大看板
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("KKShared"):WaitForChild("GameConfig"))

local LobbyService = {}

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

function LobbyService.build(folder)
	local lobby = Instance.new("Folder")
	lobby.Name = "Lobby"
	lobby.Parent = folder

	part({
		Name = "LobbyFloor",
		Size = Vector3.new(160, 2, 160),
		Position = Vector3.new(0, 0, 0),
		Color = Color3.fromRGB(52, 48, 60),
		Material = Enum.Material.Slate,
		Parent = lobby,
	})

	-- カーペット
	part({
		Name = "Carpet",
		Size = Vector3.new(10, 0.2, 70),
		Position = Vector3.new(0, 1.05, -20),
		Color = Color3.fromRGB(160, 40, 50),
		Material = Enum.Material.Fabric,
		Parent = lobby,
	})

	-- 鳥居風ゲート
	local red = Color3.fromRGB(190, 40, 50)
	part({ Name = "PillarL", Size = Vector3.new(3, 22, 3), Position = Vector3.new(-11, 12, -55), Color = red, Material = Enum.Material.Wood, Parent = lobby })
	part({ Name = "PillarR", Size = Vector3.new(3, 22, 3), Position = Vector3.new(11, 12, -55), Color = red, Material = Enum.Material.Wood, Parent = lobby })
	part({ Name = "LintelTop", Size = Vector3.new(34, 2, 4), Position = Vector3.new(0, 24, -55), Color = red, Material = Enum.Material.Wood, Parent = lobby })
	part({ Name = "LintelMid", Size = Vector3.new(26, 1.6, 3), Position = Vector3.new(0, 20, -55), Color = red, Material = Enum.Material.Wood, Parent = lobby })

	-- 大看板
	local sign = part({
		Name = "Sign",
		Size = Vector3.new(30, 8, 1),
		Position = Vector3.new(0, 31, -55),
		Color = Color3.fromRGB(20, 18, 26),
		Parent = lobby,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(245, 210, 90)
	label.Text = Config.GAME_NAME
	label.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.fromScale(1, 0.35)
	sub.Position = UDim2.fromScale(0, 0.65)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.Gotham
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(220, 220, 230)
	sub.Text = "読み勝負・漢字バトル 〜 漢検10級〜1級 12,000問"
	sub.Parent = gui

	-- 周囲の灯篭風ポール
	for i = -1, 1, 2 do
		for j = -1, 1, 2 do
			part({
				Name = "Lantern",
				Size = Vector3.new(1.4, 9, 1.4),
				Position = Vector3.new(55 * i, 5.5, 55 * j),
				Color = Color3.fromRGB(30, 28, 36),
				Parent = lobby,
			})
			part({
				Name = "LanternLight",
				Size = Vector3.new(1.8, 1.8, 1.8),
				Position = Vector3.new(55 * i, 10.5, 55 * j),
				Color = Color3.fromRGB(255, 200, 90),
				Material = Enum.Material.Neon,
				Parent = lobby,
			})
		end
	end

	-- スポーン
	local spawnLoc = Instance.new("SpawnLocation")
	spawnLoc.Name = "Spawn"
	spawnLoc.Size = Vector3.new(12, 1, 12)
	spawnLoc.Position = Vector3.new(0, 1.5, 30)
	spawnLoc.Anchored = true
	spawnLoc.Neutral = true
	spawnLoc.Duration = 0
	spawnLoc.Color = Color3.fromRGB(90, 75, 110)
	spawnLoc.Parent = lobby

	LobbyService.spawnCFrame = CFrame.new(0, 8, 30)
	LobbyService.spectateCFrame = CFrame.new(0, 8, 10)
end

function LobbyService.getSpawn()
	return LobbyService.spawnCFrame or CFrame.new(0, 8, 30)
end

return LobbyService
