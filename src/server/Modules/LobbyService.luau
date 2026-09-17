--!nonstrict
-- ロビーワールド生成: 究極豪華版 — 和風城下町 × ネオン × 祭り
-- 中央広場・噴水・回遊市場・桜並木・神社・道場・VIP御殿・ガチャコーナー・ランキング殿堂・転送門
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("KKShared"):WaitForChild("GameConfig"))

local LobbyService = {}

local function part(props)
	local p = Instance.new("Part")
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k]=v end
	p.Anchored = true
	p.CanCollide = true
	return p
end

local function addLight(parent, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range or 18
	l.Brightness = brightness or 2
	l.Shadows = true
	l.Parent = parent
	return l
end

local function addSurfaceText(parentPart, text, subText, color)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 28
	sg.Parent = parentPart
	local a = Instance.new("TextLabel")
	a.Size = UDim2.fromScale(1, 0.6)
	a.BackgroundTransparency = 1
	a.Font = Enum.Font.GothamBlack
	a.TextScaled = true
	a.TextColor3 = color or Color3.fromRGB(245,210,90)
	a.Text = text
	a.Parent = sg
	if subText then
		local b = Instance.new("TextLabel")
		b.Size = UDim2.fromScale(1, 0.35)
		b.Position = UDim2.fromScale(0, 0.62)
		b.BackgroundTransparency = 1
		b.Font = Enum.Font.Gotham
		b.TextScaled = true
		b.TextColor3 = Color3.fromRGB(220,220,230)
		b.Text = subText
		b.Parent = sg
	end
	return sg
end

function LobbyService.build(folder)
	local lobby = Instance.new("Folder")
	lobby.Name = "Lobby"
	lobby.Parent = folder

	-- ── 大地 ───────────────────────────────────────────────
	part({ Name="LobbyFloor", Size=Vector3.new(340,4,340), Position=Vector3.new(0,-1,0), Color=Color3.fromRGB(28,28,38), Material=Enum.Material.Slate, Parent=lobby })
	-- 石畳パターン
	for i=-8,8 do
		local c = (i%2==0) and Color3.fromRGB(42,40,55) or Color3.fromRGB(36,34,48)
		part({ Name="Pavement", Size=Vector3.new(3,0.25,340), Position=Vector3.new(i*9,1.05,0), Color=c, Material=Enum.Material.Concrete, Parent=lobby })
		part({ Name="PavementH", Size=Vector3.new(340,0.25,3), Position=Vector3.new(0,1.06,i*9), Color=c, Material=Enum.Material.Concrete, Parent=lobby })
	end
	-- 外周の石塀
	for _, side in ipairs({-1,1}) do
		part({ Name="OuterWallNS", Size=Vector3.new(340,10,2), Position=Vector3.new(0,5,side*168), Color=Color3.fromRGB(45,42,55), Material=Enum.Material.Slate, Parent=lobby })
		part({ Name="OuterWallEW", Size=Vector3.new(2,10,340), Position=Vector3.new(side*168,5,0), Color=Color3.fromRGB(45,42,55), Material=Enum.Material.Slate, Parent=lobby })
	end

	-- ── セントラルカーペット (参道) ───────────────────────
	part({ Name="Carpet", Size=Vector3.new(14,0.3,150), Position=Vector3.new(0,1.2,-10), Color=Color3.fromRGB(165,32,52), Material=Enum.Material.Fabric, Parent=lobby })
	part({ Name="CarpetGoldL", Size=Vector3.new(0.7,0.32,150), Position=Vector3.new(-7,1.22,-10), Color=Color3.fromRGB(245,210,90), Material=Enum.Material.Neon, Parent=lobby })
	part({ Name="CarpetGoldR", Size=Vector3.new(0.7,0.32,150), Position=Vector3.new(7,1.22,-10), Color=Color3.fromRGB(245,210,90), Material=Enum.Material.Neon, Parent=lobby })
	-- カーペットに家紋 (中央)
	for _, z in ipairs({-45,-20,5}) do
		part({ Name="CarpetEmblem", Size=Vector3.new(4,0.35,4), Position=Vector3.new(0,1.25,z), Color=Color3.fromRGB(245,210,90), Material=Enum.Material.Neon, Parent=lobby })
	end

	-- ── 大鳥居 ───────────────────────────────────────────
	local red = Color3.fromRGB(188,30,42)
	local verm = Color3.fromRGB(200,42,52)
	part({ Name="PillarL", Size=Vector3.new(3.8,28,3.8), Position=Vector3.new(-14,14.5,-88), Color=red, Material=Enum.Material.Wood, Parent=lobby })
	part({ Name="PillarR", Size=Vector3.new(3.8,28,3.8), Position=Vector3.new(14,14.5,-88), Color=red, Material=Enum.Material.Wood, Parent=lobby })
	part({ Name="LintelTop", Size=Vector3.new(42,2.8,5), Position=Vector3.new(0,29.5,-88), Color=verm, Material=Enum.Material.Wood, Parent=lobby })
	part({ Name="LintelMid", Size=Vector3.new(34,2,4), Position=Vector3.new(0,24.5,-88), Color=verm, Material=Enum.Material.Wood, Parent=lobby })
	-- 鳥居の額束
	part({ Name="Gakuzuka", Size=Vector3.new(3,6,1.2), Position=Vector3.new(0,27,-88), Color=Color3.fromRGB(22,20,28), Parent=lobby })
	local gz = part({ Name="GakuSign", Size=Vector3.new(7,3,0.4), Position=Vector3.new(0,27,-87.2), Color=Color3.fromRGB(18,16,22), Parent=lobby })
	addSurfaceText(gz, "KANJI KOMBAT", "漢字コンバット", Color3.fromRGB(245,210,90))
	-- 提灯
	for _, x in ipairs({-9,9}) do
		local lan = part({ Name="ToriiLantern", Size=Vector3.new(2,2.6,2), Position=Vector3.new(x,20.5,-88), Color=Color3.fromRGB(255,230,120), Material=Enum.Material.Neon, Parent=lobby })
		addLight(lan, Color3.fromRGB(255,210,90), 16, 2)
		part({ Name="ToriiTassel", Size=Vector3.new(0.4,2,0.4), Position=Vector3.new(x,18.6,-88), Color=Color3.fromRGB(188,30,42), Parent=lobby })
	end

	-- ── 大看板 (頂上に浮遊) ─────────────────────────────
	local sign = part({ Name="Sign", Size=Vector3.new(42,10,1.4), Position=Vector3.new(0,38,-88), Color=Color3.fromRGB(18,16,22), Parent=lobby })
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 38
	sg.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1,0.58)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(245,210,90)
	label.Text = (Config.GAME_NAME_EN or "KANJI KOMBAT") .. " / " .. Config.GAME_NAME
	label.Parent = sg
	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.fromScale(1,0.32)
	sub.Position = UDim2.fromScale(0,0.60)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.Gotham
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(220,220,230)
	sub.Text = "12 LEVELS · 12,000問 · RANKED · BATTLE PASS · DAILY QUESTS"
	sub.Parent = sg
	local sgBack = sg:Clone()
	sgBack.Face = Enum.NormalId.Back
	sgBack.Parent = sign

	-- ── 中央噴水広場 ───────────────────────────────────
	part({ Name="FountainBase", Size=Vector3.new(22,1,22), Position=Vector3.new(0,1.1,0), Color=Color3.fromRGB(50,50,65), Material=Enum.Material.Marble, Parent=lobby })
	part({ Name="FountainRim", Size=Vector3.new(16,1.2,16), Position=Vector3.new(0,1.8,0), Color=Color3.fromRGB(180,180,195), Material=Enum.Material.Marble, Parent=lobby })
	part({ Name="FountainWater", Size=Vector3.new(12,0.4,12), Position=Vector3.new(0,1.6,0), Color=Color3.fromRGB(80,180,220), Material=Enum.Material.Neon, Transparency=0.35, Parent=lobby })
	local pillar = part({ Name="FountainPillar", Size=Vector3.new(2,6,2), Position=Vector3.new(0,4.5,0), Color=Color3.fromRGB(245,210,90), Material=Enum.Material.Metal, Parent=lobby })
	addLight(pillar, Color3.fromRGB(120,200,255), 22, 1.5)
	part({ Name="FountainKanji", Size=Vector3.new(3,3,0.6), Position=Vector3.new(0,7.5,1.2), Color=Color3.fromRGB(18,16,22), Parent=lobby })
	local fk = part({ Name="FountainKanjiSign", Size=Vector3.new(3,3,0.2), Position=Vector3.new(0,7.5,1.6), Color=Color3.fromRGB(18,16,22), Parent=lobby })
	local fsg = Instance.new("SurfaceGui")
	fsg.Face = Enum.NormalId.Front
	fsg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	fsg.PixelsPerStud = 22
	fsg.Parent = fk
	local ftl = Instance.new("TextLabel")
	ftl.Size = UDim2.fromScale(1,1)
	ftl.BackgroundTransparency=1
	ftl.Font = Enum.Font.GothamBlack
	ftl.TextScaled=true
	ftl.TextColor3=Color3.fromRGB(245,210,90)
	ftl.Text="漢"
	ftl.Parent=fsg

	-- ── 桜並木 (12本) ─────────────────────────────────
	local sakuraPositions = {
		Vector3.new(-32,0,-42), Vector3.new(32,0,-42),
		Vector3.new(-46,0,-20), Vector3.new(46,0,-20),
		Vector3.new(-52,0,8), Vector3.new(52,0,8),
		Vector3.new(-48,0,34), Vector3.new(48,0,34),
		Vector3.new(-30,0,56), Vector3.new(30,0,56),
		Vector3.new(-14,0,68), Vector3.new(14,0,68),
	}
	for idx, pos in ipairs(sakuraPositions) do
		part({ Name="SakuraTrunk"..idx, Size=Vector3.new(1.2,10,1.2), Position=Vector3.new(pos.X,5,pos.Z), Color=Color3.fromRGB(74,56,48), Material=Enum.Material.Wood, Parent=lobby })
		local crown = part({ Name="SakuraCrown"..idx, Size=Vector3.new(7,5,7), Position=Vector3.new(pos.X,11.5,pos.Z), Color=Color3.fromRGB(255,175,190), Material=Enum.Material.Leaf, Parent=lobby })
		local bloom = part({ Name="SakuraBloom"..idx, Size=Vector3.new(4,1.5,4), Position=Vector3.new(pos.X,14,pos.Z), Color=Color3.fromRGB(255,205,215), Material=Enum.Material.Neon, Transparency=0.18, Parent=lobby })
		addLight(crown, Color3.fromRGB(255,180,195), 12, 1)
		-- 花びらパーティクル用の小パーツ
		for b=1,2 do
			part({ Name="SakuraPetal"..idx.."_"..b, Size=Vector3.new(0.6,0.06,0.6), Position=Vector3.new(pos.X+(b*2-3),9,pos.Z+(b%2)*2), Color=Color3.fromRGB(255,200,210), Material=Enum.Material.Neon, Transparency=0.4, Parent=lobby })
		end
	end

	-- ── 市場屋台 (6件 + 2大屋台) ────────────────────────
	local stalls = {
		{x=-70, z=-18, label="SHOP / ショップ", color=Color3.fromRGB(245,210,90)},
		{x=70,  z=-18, label="PASS / バトルパス", color=Color3.fromRGB(120,220,255)},
		{x=-70, z=12, label="GACHA / ガチャ", color=Color3.fromRGB(255,140,200)},
		{x=70,  z=12, label="GEMS / ジェム", color=Color3.fromRGB(90,255,160)},
		{x=-52, z=-52, label="BOOST / ブースト", color=Color3.fromRGB(255,210,90)},
		{x=52,  z=-52, label="COSME / アバター", color=Color3.fromRGB(180,140,255)},
	}
	for i, s in ipairs(stalls) do
		part({ Name="StallFloor"..i, Size=Vector3.new(16,1,14), Position=Vector3.new(s.x,0.6,s.z), Color=Color3.fromRGB(60,52,42), Material=Enum.Material.Wood, Parent=lobby })
		part({ Name="StallRoof"..i, Size=Vector3.new(18,1.4,16), Position=Vector3.new(s.x,7.8,s.z), Color=Color3.fromRGB(188,30,42), Material=Enum.Material.Wood, Parent=lobby })
		for _, dx in ipairs({-7,7}) do for _, dz in ipairs({-6,6}) do
			part({ Name="StallPillar"..i, Size=Vector3.new(0.7,7.2,0.7), Position=Vector3.new(s.x+dx,3.9,s.z+dz), Color=Color3.fromRGB(92,72,60), Material=Enum.Material.Wood, Parent=lobby })
		end end
		-- のれん
		part({ Name="StallNoren"..i, Size=Vector3.new(14,2.2,0.3), Position=Vector3.new(s.x,6.2,s.z+7.2), Color=Color3.fromRGB(235,235,242), Material=Enum.Material.Fabric, Parent=lobby })
		-- カウンター
		part({ Name="StallCounter"..i, Size=Vector3.new(12,2.2,3), Position=Vector3.new(s.x,2,s.z+4.5), Color=Color3.fromRGB(38,34,28), Material=Enum.Material.Wood, Parent=lobby })
		-- 看板
		local signPart = part({ Name="StallSign"..i, Size=Vector3.new(11,3.2,0.6), Position=Vector3.new(s.x,10.2,s.z), Color=Color3.fromRGB(22,20,28), Parent=lobby })
		addSurfaceText(signPart, s.label, nil, s.color)
		addLight(signPart, s.color, 14, 1.2)
	end

	-- ── デイリー神社 (拡張: 鳥居 + 狛犬 + 賽銭箱 + 絵馬掛け) ─
	part({ Name="ShrinePlatform", Size=Vector3.new(28,1.6,22), Position=Vector3.new(-88,0.8,18), Color=Color3.fromRGB(62,54,42), Material=Enum.Material.Wood, Parent=lobby })
	-- 小鳥居
	part({ Name="ShrineToriiL", Size=Vector3.new(1.2,8,1.2), Position=Vector3.new(-88-5,4.5,18), Color=red, Material=Enum.Material.Wood, Parent=lobby })
	part({ Name="ShrineToriiR", Size=Vector3.new(1.2,8,1.2), Position=Vector3.new(-88+5,4.5,18), Color=red, Material=Enum.Material.Wood, Parent=lobby })
	part({ Name="ShrineToriiTop", Size=Vector3.new(14,1,2), Position=Vector3.new(-88,8.5,18), Color=red, Material=Enum.Material.Wood, Parent=lobby })
	part({ Name="ShrineBox", Size=Vector3.new(8,3.6,5), Position=Vector3.new(-88,2.8,18), Color=Color3.fromRGB(38,32,28), Material=Enum.Material.Wood, Parent=lobby })
	part({ Name="ShrineRoof", Size=Vector3.new(20,1.8,14), Position=Vector3.new(-88,6.2,18), Color=Color3.fromRGB(188,30,42), Material=Enum.Material.Wood, Parent=lobby })
	part({ Name="ShrineBell", Size=Vector3.new(1.4,2.6,1.4), Position=Vector3.new(-88,8.6,18), Color=Color3.fromRGB(245,210,90), Material=Enum.Material.Metal, Parent=lobby })
	addLight(part({ Name="ShrineBellLight", Size=Vector3.new(1.4,0.4,1.4), Position=Vector3.new(-88,7.2,18), Color=Color3.fromRGB(245,210,90), Material=Enum.Material.Neon, Parent=lobby }), Color3.fromRGB(245,210,90), 10, 1)
	-- 狛犬
	for _, sx in ipairs({-4,4}) do
		part({ Name="Komainu", Size=Vector3.new(1.6,2.2,2), Position=Vector3.new(-88+sx,2,22), Color=Color3.fromRGB(160,160,170), Material=Enum.Material.Slate, Parent=lobby })
	end
	-- 絵馬掛け
	part({ Name="EmaRack", Size=Vector3.new(12,3,0.4), Position=Vector3.new(-88,4.5,10), Color=Color3.fromRGB(72,60,48), Material=Enum.Material.Wood, Parent=lobby })
	for e=1,5 do
		part({ Name="Ema"..e, Size=Vector3.new(1.2,1.4,0.15), Position=Vector3.new(-88-4+e*2,4.5,10.3), Color=Color3.fromRGB(245,210,90), Material=Enum.Material.Wood, Parent=lobby })
	end
	local shrineSign = part({ Name="ShrineSign", Size=Vector3.new(10,2.6,0.5), Position=Vector3.new(-88,10.8,26), Color=Color3.fromRGB(20,18,26), Parent=lobby })
	addSurfaceText(shrineSign, "DAILY / デイリー神社", "おみくじ・賽銭", Color3.fromRGB(255,220,90))
	addLight(shrineSign, Color3.fromRGB(255,220,90), 12, 1)

	-- ── 道場 (Training Dojo) ─────────────────────────────
	part({ Name="DojoFloor", Size=Vector3.new(24,1,20), Position=Vector3.new(88,0.6,-10), Color=Color3.fromRGB(62,56,48), Material=Enum.Material.WoodPlanks, Parent=lobby })
	part({ Name="DojoTatami", Size=Vector3.new(18,0.28,14), Position=Vector3.new(88,1.2,-10), Color=Color3.fromRGB(142,166,92), Material=Enum.Material.Fabric, Parent=lobby })
	for _, x in ipairs({-10,10}) do for _, z in ipairs({-8,8}) do
		part({ Name="DojoPillar", Size=Vector3.new(0.9,7,0.9), Position=Vector3.new(88+x,4.2,-10+z), Color=Color3.fromRGB(58,48,42), Material=Enum.Material.Wood, Parent=lobby })
	end end
	part({ Name="DojoRoof", Size=Vector3.new(26,1.6,22), Position=Vector3.new(88,8.2,-10), Color=Color3.fromRGB(42,42,52), Material=Enum.Material.Slate, Parent=lobby })
	local dojoScroll = part({ Name="DojoScroll", Size=Vector3.new(8,4,0.4), Position=Vector3.new(88,5,-19.2), Color=Color3.fromRGB(242,238,230), Parent=lobby })
	addSurfaceText(dojoScroll, "稽古", "PRACTICE / 練習", Color3.fromRGB(40,40,50))
	-- 木人
	part({ Name="DojoDummy", Size=Vector3.new(1,5,1), Position=Vector3.new(88,3.5,-6), Color=Color3.fromRGB(120,90,70), Material=Enum.Material.Wood, Parent=lobby })
	local dojoSign = part({ Name="DojoSign", Size=Vector3.new(10,2.6,0.5), Position=Vector3.new(88,10.6,0), Color=Color3.fromRGB(18,16,22), Parent=lobby })
	addSurfaceText(dojoSign, "DOJO / 道場", "練習バトル", Color3.fromRGB(180,220,255))

	-- ── VIP御殿 (金閣) ─────────────────────────────────
	part({ Name="VipBase", Size=Vector3.new(26,2,26), Position=Vector3.new(88,1,32), Color=Color3.fromRGB(44,38,20), Material=Enum.Material.Marble, Parent=lobby })
	part({ Name="VipFloor", Size=Vector3.new(22,1,22), Position=Vector3.new(88,2,32), Color=Color3.fromRGB(32,30,22), Material=Enum.Material.Marble, Parent=lobby })
	part({ Name="VipCarpet", Size=Vector3.new(12,0.35,12), Position=Vector3.new(88,2.55,32), Color=Color3.fromRGB(245,210,90), Material=Enum.Material.Fabric, Parent=lobby })
	for _, dx in ipairs({-9,9}) do for _, dz in ipairs({-9,9}) do
		part({ Name="VipPillar", Size=Vector3.new(1.1,9,1.1), Position=Vector3.new(88+dx,6.6,32+dz), Color=Color3.fromRGB(245,210,90), Material=Enum.Material.Metal, Parent=lobby })
	end end
	part({ Name="VipRoof1", Size=Vector3.new(28,1.4,28), Position=Vector3.new(88,11.4,32), Color=Color3.fromRGB(42,36,18), Material=Enum.Material.Metal, Parent=lobby })
	part({ Name="VipRoof2", Size=Vector3.new(22,1,22), Position=Vector3.new(88,13.6,32), Color=Color3.fromRGB(245,210,90), Material=Enum.Material.Metal, Parent=lobby })
	part({ Name="VipThrone", Size=Vector3.new(3,4,2), Position=Vector3.new(88,4.6,32-4), Color=Color3.fromRGB(245,210,90), Material=Enum.Material.Metal, Parent=lobby })
	local vipSign = part({ Name="VipSign", Size=Vector3.new(11,3,0.5), Position=Vector3.new(88,15.8,44), Color=Color3.fromRGB(18,16,12), Parent=lobby })
	addSurfaceText(vipSign, "VIP LOUNGE / 御殿", "特典・優先マッチ", Color3.fromRGB(245,210,90))
	addLight(vipSign, Color3.fromRGB(245,210,90), 16, 1.5)

	-- ── ランキング殿堂 (石碑 + トロフィー) ───────────────
	part({ Name="RankHallFloor", Size=Vector3.new(30,1,16), Position=Vector3.new(0,0.6,-62), Color=Color3.fromRGB(42,40,52), Material=Enum.Material.Marble, Parent=lobby })
	part({ Name="RankBoard", Size=Vector3.new(20,11,1.2), Position=Vector3.new(0,6.2,-68), Color=Color3.fromRGB(26,24,32), Material=Enum.Material.Slate, Parent=lobby })
	local rankBoardFake = part({ Name="RankBoardBack", Size=Vector3.new(20,11,0.3), Position=Vector3.new(0,6.2,-68.8), Color=Color3.fromRGB(26,24,32), Parent=lobby })
	local rsg = Instance.new("SurfaceGui")
	rsg.Face = Enum.NormalId.Front
	rsg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	rsg.PixelsPerStud = 16
	rsg.Parent = rankBoardFake
	local rTitle = Instance.new("TextLabel")
	rTitle.Size = UDim2.fromScale(1,0.22)
	rTitle.BackgroundTransparency=1
	rTitle.Font=Enum.Font.GothamBlack
	rTitle.TextScaled=true
	rTitle.TextColor3=Color3.fromRGB(245,210,90)
	rTitle.Text="RANKING / ランキング"
	rTitle.Parent=rsg
	local rList = Instance.new("TextLabel")
	rList.Size=UDim2.fromScale(1,0.75)
	rList.Position=UDim2.fromScale(0,0.24)
	rList.BackgroundTransparency=1
	rList.Font=Enum.Font.Gotham
	rList.TextScaled=false
	rList.TextSize=14
	rList.TextColor3=Color3.fromRGB(220,220,230)
	rList.Text="1.  漢字王  —  12,840\n2.  KANJI ACE — 11,920\n3.  桜の武者 — 10,450\n· · ·\nYOUR RANK — 挑戦せよ!"
	rList.Parent=rsg
	-- トロフィー台
	for tIdx=1,3 do
		local tx = (tIdx-2)*5
		part({ Name="TrophyPedestal"..tIdx, Size=Vector3.new(2,3,2), Position=Vector3.new(tx,2.8,-58), Color=Color3.fromRGB(55,50,40), Material=Enum.Material.Marble, Parent=lobby })
		local trophyColor = (tIdx==1) and Color3.fromRGB(245,210,90) or (tIdx==2) and Color3.fromRGB(200,200,210) or Color3.fromRGB(200,140,90)
		local trophy = part({ Name="Trophy"..tIdx, Size=Vector3.new(1,2,1), Position=Vector3.new(tx,5,-58), Color=trophyColor, Material=Enum.Material.Metal, Parent=lobby })
		addLight(trophy, trophyColor, 10, 1)
	end

	-- ── 転送門 (Portal Gates to Arena) ─────────────────
	for _, side in ipairs({-1,1}) do
		local px = side*18
		part({ Name="PortalBase"..side, Size=Vector3.new(6,0.6,6), Position=Vector3.new(px,1.3,-70), Color=Color3.fromRGB(30,28,42), Parent=lobby })
		part({ Name="PortalArchL"..side, Size=Vector3.new(0.9,7,0.9), Position=Vector3.new(px-2.2,4.8,-70), Color=Color3.fromRGB(60,58,78), Parent=lobby })
		part({ Name="PortalArchR"..side, Size=Vector3.new(0.9,7,0.9), Position=Vector3.new(px+2.2,4.8,-70), Color=Color3.fromRGB(60,58,78), Parent=lobby })
		part({ Name="PortalArchTop"..side, Size=Vector3.new(5.6,0.9,0.9), Position=Vector3.new(px,8,-70), Color=Color3.fromRGB(60,58,78), Parent=lobby })
		local portal = part({ Name="Portal"..side, Size=Vector3.new(3.4,5,0.4), Position=Vector3.new(px,4.8,-70), Color=Color3.fromRGB(120,90,255), Material=Enum.Material.Neon, Transparency=0.26, Parent=lobby })
		addLight(portal, Color3.fromRGB(140,110,255), 18, 2)
		local pSign = part({ Name="PortalSign"..side, Size=Vector3.new(5,1.6,0.3), Position=Vector3.new(px,9.2,-70), Color=Color3.fromRGB(18,16,22), Parent=lobby })
		local txt = (side==-1) and "RANKED / ランク" or "CASUAL / カジュアル"
		addSurfaceText(pSign, txt, nil, Color3.fromRGB(180,160,255))
	end

	-- ── 街灯 & のぼり旗 ─────────────────────────────────
	for i=1,16 do
		local angle = (i/16)*math.pi*2
		local r = 78
		local x = math.cos(angle)*r
		local z = math.sin(angle)*r
		part({ Name="StreetPole"..i, Size=Vector3.new(0.6,8,0.6), Position=Vector3.new(x,4, z), Color=Color3.fromRGB(52,48,42), Parent=lobby })
		local lamp = part({ Name="StreetLamp"..i, Size=Vector3.new(1.4,1.4,1.4), Position=Vector3.new(x,8.4,z), Color=Color3.fromRGB(255,210,90), Material=Enum.Material.Neon, Parent=lobby })
		addLight(lamp, Color3.fromRGB(255,210,90), 18, 1.6)
		-- のぼり
		if i%2==0 then
			part({ Name="Nobori"..i, Size=Vector3.new(0.15,4,1.6), Position=Vector3.new(x,5, z), Color=Color3.fromRGB(188,30,42), Material=Enum.Material.Fabric, Parent=lobby })
		end
	end

	-- ── 大提灯群 (夜祭り感) ─────────────────────────────
	for i=1,8 do
		local x = -56 + (i-1)*16
		local z = -72
		local lan = part({ Name="FestLantern"..i, Size=Vector3.new(1.6,2,1.6), Position=Vector3.new(x,9,z), Color=Color3.fromRGB(255,120,90), Material=Enum.Material.Neon, Parent=lobby })
		addLight(lan, Color3.fromRGB(255,140,90), 14, 1.3)
		part({ Name="FestLanternLine"..i, Size=Vector3.new(0.12,6,0.12), Position=Vector3.new(x,12,z), Color=Color3.fromRGB(80,70,60), Parent=lobby })
	end

	-- ── スポーン ───────────────────────────────────────
	-- placeファイル側に既にSpawnLocationがある場合 (スクリプト起動前の湧き用) は二重に作らない
	if not workspace:FindFirstChildWhichIsA("SpawnLocation", true) then
		local spawnLoc = Instance.new("SpawnLocation")
		spawnLoc.Name = "Spawn"
		spawnLoc.Size = Vector3.new(12,1,12)
		spawnLoc.Position = Vector3.new(0,1.5,54)
		spawnLoc.Anchored = true
		spawnLoc.CanCollide = true
		spawnLoc.Neutral = true
		spawnLoc.Duration = 0
		spawnLoc.Color = Color3.fromRGB(90,75,110)
		spawnLoc.Parent = lobby
	end

	LobbyService.spawnCFrame = CFrame.new(0, 8, 54)
	LobbyService.spectateCFrame = CFrame.new(0, 14, 12) * CFrame.Angles(math.rad(-12), 0, 0)
end

function LobbyService.getSpawn()
	return LobbyService.spawnCFrame or CFrame.new(0, 8, 54)
end

return LobbyService
