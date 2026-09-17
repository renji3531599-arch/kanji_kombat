--!nonstrict
-- ロビーマップ生成: 超豪華版 — 広場 + 鳥居 + ショップ屋台 + バトルパスタワー + デイリー神社 + VIPラウンジ
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("KKShared"):WaitForChild("GameConfig"))

local LobbyService = {}

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k]=v end
	return p
end

function LobbyService.build(folder)
	local lobby = Instance.new("Folder")
	lobby.Name = "Lobby"
	lobby.Parent = folder

	-- 大床
	part({
		Name = "LobbyFloor",
		Size = Vector3.new(200, 2, 200),
		Position = Vector3.new(0, 0, 0),
		Color = Color3.fromRGB(38, 36, 50),
		Material = Enum.Material.Slate,
		Parent = lobby,
	})
	-- 外周の石畳
	for i=-4,4 do
		part({
			Name = "Tile",
			Size = Vector3.new(2, 0.3, 200),
			Position = Vector3.new(i*12, 1.1, 0),
			Color = Color3.fromRGB(45,42,60),
			Material = Enum.Material.Concrete,
			Parent = lobby,
		})
	end

	-- メインカーペット (中央通り)
	part({
		Name = "Carpet",
		Size = Vector3.new(12, 0.25, 90),
		Position = Vector3.new(0, 1.15, -10),
		Color = Color3.fromRGB(165, 40, 55),
		Material = Enum.Material.Fabric,
		Parent = lobby,
	})
	-- 金縁
	part({ Name="CarpetGoldL", Size=Vector3.new(0.6,0.3,90), Position=Vector3.new(-6,1.18,-10), Color=Color3.fromRGB(245,210,90), Material=Enum.Material.Neon, Parent=lobby })
	part({ Name="CarpetGoldR", Size=Vector3.new(0.6,0.3,90), Position=Vector3.new(6,1.18,-10), Color=Color3.fromRGB(245,210,90), Material=Enum.Material.Neon, Parent=lobby })

	-- 鳥居
	local red = Color3.fromRGB(185, 35, 45)
	part({ Name = "PillarL", Size = Vector3.new(3.2, 24, 3.2), Position = Vector3.new(-12, 13, -58), Color = red, Material = Enum.Material.Wood, Parent = lobby })
	part({ Name = "PillarR", Size = Vector3.new(3.2, 24, 3.2), Position = Vector3.new(12, 13, -58), Color = red, Material = Enum.Material.Wood, Parent = lobby })
	part({ Name = "LintelTop", Size = Vector3.new(36, 2.4, 4.2), Position = Vector3.new(0, 26, -58), Color = red, Material = Enum.Material.Wood, Parent = lobby })
	part({ Name = "LintelMid", Size = Vector3.new(28, 1.8, 3.2), Position = Vector3.new(0, 21.5, -58), Color = red, Material = Enum.Material.Wood, Parent = lobby })
	-- 鳥居提灯
	for _, x in ipairs({-8,8}) do
		part({ Name="ToriiLantern", Size=Vector3.new(1.6,1.6,1.6), Position=Vector3.new(x,20,-58), Color=Color3.fromRGB(255,230,120), Material=Enum.Material.Neon, Parent=lobby })
	end

	-- 大看板 (両言語)
	local sign = part({
		Name = "Sign",
		Size = Vector3.new(34, 9, 1.2),
		Position = Vector3.new(0, 34, -58),
		Color = Color3.fromRGB(18, 16, 22),
		Parent = lobby,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 42
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 0.62)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(245, 210, 90)
	label.Text = (Config.GAME_NAME_EN or "KANJI KOMBAT") .. " / " .. Config.GAME_NAME
	label.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.fromScale(1, 0.32)
	sub.Position = UDim2.fromScale(0, 0.62)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.Gotham
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(220, 220, 230)
	sub.Text = "READING BATTLES / 12,000問 · RANKED · BATTLE PASS · DAILY"
	sub.Parent = gui

	-- 左右のショップ屋台
	for _, side in ipairs({-1,1}) do
		local x = side * 38
		-- 屋台床
		part({ Name="StallFloor"..side, Size=Vector3.new(16,1,14), Position=Vector3.new(x,0.6,-18), Color=Color3.fromRGB(55,48,42), Material=Enum.Material.Wood, Parent=lobby })
		-- 屋根
		part({ Name="StallRoof"..side, Size=Vector3.new(18,1.2,16), Position=Vector3.new(x,7.5,-18), Color=Color3.fromRGB(185,35,45), Material=Enum.Material.Wood, Parent=lobby })
		-- 柱
		for _, dx in ipairs({-7,7}) do for _, dz in ipairs({-6,6}) do
			part({ Name="StallPillar", Size=Vector3.new(0.7,7,0.7), Position=Vector3.new(x+dx,3.8,-18+dz), Color=Color3.fromRGB(90,70,60), Parent=lobby })
		end end
		-- 看板
		local stallSign = part({ Name="StallSign"..side, Size=Vector3.new(10,3,0.6), Position=Vector3.new(x,9.5,-18), Color=Color3.fromRGB(28,26,36), Parent=lobby })
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 32
		sg.Parent = stallSign
		local tl = Instance.new("TextLabel")
		tl.Size = UDim2.fromScale(1,1)
		tl.BackgroundTransparency=1
		tl.Font=Enum.Font.GothamBold
		tl.TextScaled=true
		tl.TextColor3 = Color3.fromRGB(245,210,90)
		tl.Text = (side==-1) and "SHOP / ショップ" or "PASS / パス"
		tl.Parent=sg
	end

	-- デイリー神社 (賽銭箱)
	part({ Name="ShrineBase", Size=Vector3.new(14,1,10), Position=Vector3.new(-38,0.6,10), Color=Color3.fromRGB(60,52,42), Material=Enum.Material.Wood, Parent=lobby })
	part({ Name="ShrineBox", Size=Vector3.new(6,3,4), Position=Vector3.new(-38,2.5,10), Color=Color3.fromRGB(35,30,28), Material=Enum.Material.Wood, Parent=lobby })
	part({ Name="ShrineRoof", Size=Vector3.new(16,1.5,12), Position=Vector3.new(-38,5.5,10), Color=Color3.fromRGB(185,35,45), Material=Enum.Material.Wood, Parent=lobby })
	part({ Name="ShrineBell", Size=Vector3.new(1.2,2.2,1.2), Position=Vector3.new(-38,7.8,10), Color=Color3.fromRGB(245,210,90), Material=Enum.Material.Metal, Parent=lobby })
	local shrineSign = part({ Name="ShrineSign", Size=Vector3.new(8,2.2,0.5), Position=Vector3.new(-38,8.5,14), Color=Color3.fromRGB(20,18,22), Parent=lobby })
	local ssg = Instance.new("SurfaceGui")
	ssg.Face=Enum.NormalId.Front
	ssg.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud
	ssg.PixelsPerStud=28
	ssg.Parent=shrineSign
	local stl = Instance.new("TextLabel")
	stl.Size=UDim2.fromScale(1,1)
	stl.BackgroundTransparency=1
	stl.Font=Enum.Font.GothamBold
	stl.TextScaled=true
	stl.TextColor3=Color3.fromRGB(255,220,90)
	stl.Text="DAILY / デイリー"
	stl.Parent=ssg

	-- VIPラウンジ (金ピカ)
	part({ Name="VipFloor", Size=Vector3.new(18,1,18), Position=Vector3.new(38,0.6,12), Color=Color3.fromRGB(45,38,20), Material=Enum.Material.Marble, Parent=lobby })
	part({ Name="VipCarpet", Size=Vector3.new(10,0.3,10), Position=Vector3.new(38,1.2,12), Color=Color3.fromRGB(245,210,90), Material=Enum.Material.Fabric, Parent=lobby })
	for _, dx in ipairs({-7,7}) do for _, dz in ipairs({-7,7}) do
		part({ Name="VipPillar", Size=Vector3.new(1,8,1), Position=Vector3.new(38+dx,4.6,12+dz), Color=Color3.fromRGB(245,210,90), Material=Enum.Material.Metal, Parent=lobby })
	end end
	part({ Name="VipRoof", Size=Vector3.new(20,1,20), Position=Vector3.new(38,9.2,12), Color=Color3.fromRGB(40,35,18), Parent=lobby })
	local vipSign = part({ Name="VipSign", Size=Vector3.new(10,2.5,0.5), Position=Vector3.new(38,11,20), Color=Color3.fromRGB(18,16,12), Parent=lobby })
	local vsg = Instance.new("SurfaceGui")
	vsg.Face=Enum.NormalId.Front
	vsg.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud
	vsg.PixelsPerStud=30
	vsg.Parent=vipSign
	local vtl = Instance.new("TextLabel")
	vtl.Size=UDim2.fromScale(1,1)
	vtl.BackgroundTransparency=1
	vtl.Font=Enum.Font.GothamBlack
	vtl.TextScaled=true
	vtl.TextColor3=Color3.fromRGB(245,210,90)
	vtl.Text="VIP LOUNGE"
	vtl.Parent=vsg

	-- ランクボード (中央奥の石碑)
	part({ Name="RankBoard", Size=Vector3.new(18,10,1), Position=Vector3.new(0,5.5,-42), Color=Color3.fromRGB(28,26,34), Parent=lobby })
	local rsg = Instance.new("SurfaceGui")
	rsg.Face=Enum.NormalId.Front
	rsg.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud
	rsg.PixelsPerStud=18
	rsg.Parent=part({ Name="RankBoardBack", Size=Vector3.new(18,10,0.2), Position=Vector3.new(0,5.5,-42.6), Color=Color3.fromRGB(28,26,34), Parent=lobby })
	-- 実際には空だが雰囲気用

	-- 灯篭
	for i=-1,1,2 do for j=-1,1,2 do
		part({ Name="Lantern", Size=Vector3.new(1.6,10,1.6), Position=Vector3.new(65*i,5.5,65*j), Color=Color3.fromRGB(32,30,38), Parent=lobby })
		part({ Name="LanternLight", Size=Vector3.new(2.2,2.2,2.2), Position=Vector3.new(65*i,11.5,65*j), Color=Color3.fromRGB(255,200,90), Material=Enum.Material.Neon, Parent=lobby })
		local lp = Instance.new("PointLight")
		lp.Color = Color3.fromRGB(255,200,90)
		lp.Range=22
		lp.Brightness=2
		lp.Shadows=true
		lp.Parent = lobby:FindFirstChild("LanternLight") or lobby
	end end

	-- スポーン
	local spawnLoc = Instance.new("SpawnLocation")
	spawnLoc.Name = "Spawn"
	spawnLoc.Size = Vector3.new(12, 1, 12)
	spawnLoc.Position = Vector3.new(0, 1.5, 34)
	spawnLoc.Anchored = true
	spawnLoc.Neutral = true
	spawnLoc.Duration = 0
	spawnLoc.Color = Color3.fromRGB(90, 75, 110)
	spawnLoc.Parent = lobby

	LobbyService.spawnCFrame = CFrame.new(0, 8, 34)
	LobbyService.spectateCFrame = CFrame.new(0, 8, 12)
end

function LobbyService.getSpawn()
	return LobbyService.spawnCFrame or CFrame.new(0, 8, 34)
end

return LobbyService
