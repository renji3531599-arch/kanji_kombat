--!nonstrict
-- 対戦アリーナ生成: 究極豪華版 — 級ごとに全く異なる世界観 (神社 / 竹林 / 城 / 宇宙 など)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("KKShared"):WaitForChild("GameConfig"))

local ArenaService = {}
local arenas = {}

local ARENA_BASE_Y = 620
local ARENA_GAP = 300

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do p[k]=v end
	return p
end

local function addLight(parent, color, range, bright)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = bright
	l.Shadows = true
	l.Parent = parent
	return l
end

local THEMES = {
	K10 = { mat=Enum.Material.SmoothPlastic, floor=Color3.fromRGB(85,165,90), accent=Color3.fromRGB(110,205,120), name="わかばの庭 / Sprout Garden", deco="sprout" },
	K09 = { mat=Enum.Material.SmoothPlastic, floor=Color3.fromRGB(95,155,75), accent=Color3.fromRGB(125,190,85), name="さくらの小径", deco="sakura" },
	K08 = { mat=Enum.Material.Slate, floor=Color3.fromRGB(115,135,60), accent=Color3.fromRGB(165,180,65), name="たけの里", deco="bamboo" },
	K07 = { mat=Enum.Material.Slate, floor=Color3.fromRGB(132,118,42), accent=Color3.fromRGB(200,165,45), name="まつりの広場", deco="festival" },
	K06 = { mat=Enum.Material.Concrete, floor=Color3.fromRGB(150,98,34), accent=Color3.fromRGB(225,135,38), name="あきの山道", deco="autumn" },
	K05 = { mat=Enum.Material.Concrete, floor=Color3.fromRGB(170,72,28), accent=Color3.fromRGB(240,105,35), name="ゆうやけの浜", deco="sunset" },
	K04 = { mat=Enum.Material.Marble, floor=Color3.fromRGB(182,52,38), accent=Color3.fromRGB(250,72,50), name="せんじょうの城", deco="castle" },
	K03 = { mat=Enum.Material.Marble, floor=Color3.fromRGB(172,42,62), accent=Color3.fromRGB(245,55,82), name="べにの神殿", deco="shrine" },
	KP2 = { mat=Enum.Material.Metal, floor=Color3.fromRGB(162,38,110), accent=Color3.fromRGB(230,50,145), name="あやかしの森", deco="mystic" },
	K02 = { mat=Enum.Material.Metal, floor=Color3.fromRGB(142,38,152), accent=Color3.fromRGB(200,50,210), name="ほしの天守", deco="star" },
	KP1 = { mat=Enum.Material.Neon, floor=Color3.fromRGB(92,42,188), accent=Color3.fromRGB(145,60,230), name="らいめいの間", deco="thunder" },
	K01 = { mat=Enum.Material.Neon, floor=Color3.fromRGB(45,42,182), accent=Color3.fromRGB(72,64,235), name="てんくうの祭壇 / Celestial Altar", deco="celestial" },
}

function ArenaService.build(folder)
	for i, lv in ipairs(Config.LEVELS) do
		local y = ARENA_BASE_Y + (i - 1) * ARENA_GAP
		local f = Instance.new("Folder")
		f.Name = "Arena_" .. lv.key
		f.Parent = folder

		local th = THEMES[lv.key] or THEMES.K10
		local color = Config.color3(lv)

		-- ── 床 (テーマ別) ─────────────────────────────────
		local floor = part({ Name="Floor", Size=Vector3.new(42,2.2,78), Position=Vector3.new(0,y,0), Color=th.floor, Material=th.mat, Parent=f })
		-- 畳/石/金属の質感を演出: 中央に紋
		part({ Name="FloorEmblemOuter", Size=Vector3.new(14,0.35,14), Position=Vector3.new(0,y+1.15,0), Color=Color3.fromRGB(255,255,255), Transparency=0.82, Parent=f })
		part({ Name="FloorEmblem", Size=Vector3.new(9,0.4,9), Position=Vector3.new(0,y+1.18,0), Color=color, Material=Enum.Material.Neon, Parent=f })
		part({ Name="FloorKanjiCore", Size=Vector3.new(4,0.45,4), Position=Vector3.new(0,y+1.22,0), Color=Color3.fromRGB(18,16,22), Parent=f })
		do
			local k = part({ Name="FloorKanjiLabel", Size=Vector3.new(4,0.2,0.2), Position=Vector3.new(0,y+1.45,0.05), Color=Color3.fromRGB(18,16,22), Parent=f })
			local sg = Instance.new("SurfaceGui")
			sg.Face = Enum.NormalId.Top
			sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			sg.PixelsPerStud = 20
			sg.Parent = k
			local tl = Instance.new("TextLabel")
			tl.Size = UDim2.fromScale(1,1)
			tl.BackgroundTransparency=1
			tl.Font=Enum.Font.GothamBlack
			tl.TextScaled=true
			tl.TextColor3=color
			tl.Text="漢"
			tl.Parent=sg
		end
		-- 格子ライン
		for _, z in ipairs({-24,-12,0,12,24}) do
			part({ Name="Grid", Size=Vector3.new(42,0.22,0.35), Position=Vector3.new(0,y+1.12,z), Color=color, Material=Enum.Material.Neon, Transparency=0.14, Parent=f })
		end
		for _, x in ipairs({-14,0,14}) do
			part({ Name="GridV", Size=Vector3.new(0.35,0.22,78), Position=Vector3.new(x,y+1.12,0), Color=Color3.fromRGB(255,255,255), Transparency=0.78, Parent=f })
		end
		-- センターライン
		part({ Name="CenterLine", Size=Vector3.new(42,0.55,1.4), Position=Vector3.new(0,y+1.3,0), Color=color, Material=Enum.Material.Neon, Parent=f })
		-- 外縁ネオン
		part({ Name="TrimA", Size=Vector3.new(42,0.9,1.6), Position=Vector3.new(0,y+1.35,-38), Color=color, Material=Enum.Material.Neon, Parent=f })
		part({ Name="TrimB", Size=Vector3.new(42,0.9,1.6), Position=Vector3.new(0,y+1.35,38), Color=color, Material=Enum.Material.Neon, Parent=f })
		part({ Name="TrimL", Size=Vector3.new(1.6,0.9,78), Position=Vector3.new(-20.2,y+1.35,0), Color=color, Material=Enum.Material.Neon, Parent=f })
		part({ Name="TrimR", Size=Vector3.new(1.6,0.9,78), Position=Vector3.new(20.2,y+1.35,0), Color=color, Material=Enum.Material.Neon, Parent=f })

		-- ── 四隅の柱 + テーマ装飾 ────────────────────────
		local pillarH = (i>=9) and 20 or (i>=6) and 15 or 12
		for _, sx in ipairs({-19,19}) do for _, sz in ipairs({-36,36}) do
			part({ Name="Pillar", Size=Vector3.new(1.6,pillarH,1.6), Position=Vector3.new(sx, y+pillarH/2, sz), Color=Color3.fromRGB(30,28,38), Material=Enum.Material.Slate, Parent=f })
			-- 柱頭の炎/水晶/提灯
			if th.deco=="celestial" or th.deco=="thunder" then
				local crystal = part({ Name="Crystal", Size=Vector3.new(2,3.2,2), Position=Vector3.new(sx, y+pillarH+1.6, sz), Color=color, Material=Enum.Material.Neon, Parent=f })
				addLight(crystal, color, 20, 2.2)
			elseif th.deco=="sakura" or th.deco=="sprout" then
				local bloom = part({ Name="Bloom", Size=Vector3.new(2.6,2,2.6), Position=Vector3.new(sx, y+pillarH+1, sz), Color=Color3.fromRGB(255,175,190), Material=Enum.Material.Neon, Transparency=0.2, Parent=f })
				addLight(bloom, Color3.fromRGB(255,180,200), 14, 1.2)
			elseif th.deco=="bamboo" then
				part({ Name="BambooTop", Size=Vector3.new(0.7,4,0.7), Position=Vector3.new(sx, y+pillarH+2, sz), Color=Color3.fromRGB(90,165,70), Material=Enum.Material.Wood, Parent=f })
			else
				local flame = part({ Name="Flame", Size=Vector3.new(1.8,1.8,1.8), Position=Vector3.new(sx, y+pillarH+1, sz), Color=color, Material=Enum.Material.Neon, Parent=f })
				addLight(flame, color, 18, 2)
			end
		end end

		-- テーマ別デコレーション
		if th.deco=="bamboo" then
			for bx=1,6 do
				local x = -16 + bx*5.2
				part({ Name="Bamboo"..bx, Size=Vector3.new(0.5,9,0.5), Position=Vector3.new(x, y+4.6, -39.5), Color=Color3.fromRGB(95,170,75), Material=Enum.Material.Wood, Parent=f })
				part({ Name="BambooLeaf"..bx, Size=Vector3.new(1.4,0.4,1.4), Position=Vector3.new(x, y+9.2, -39.5), Color=Color3.fromRGB(110,195,85), Material=Enum.Material.Leaf, Parent=f })
			end
		elseif th.deco=="sakura" then
			for sx=1,4 do
				local x = -12 + sx*8
				part({ Name="SakuraTree"..sx, Size=Vector3.new(0.9,7,0.9), Position=Vector3.new(x, y+3.5, -39), Color=Color3.fromRGB(74,56,48), Material=Enum.Material.Wood, Parent=f })
				part({ Name="SakuraCrown"..sx, Size=Vector3.new(4.5,3,4.5), Position=Vector3.new(x, y+8, -39), Color=Color3.fromRGB(255,175,190), Material=Enum.Material.Leaf, Parent=f })
			end
		elseif th.deco=="castle" then
			part({ Name="CastleWall", Size=Vector3.new(42,8,1.2), Position=Vector3.new(0, y+5, -39.5), Color=Color3.fromRGB(68,64,58), Material=Enum.Material.Slate, Parent=f })
			for cx=1,3 do
				local x = (cx-2)*10
				part({ Name="CastleTurret"..cx, Size=Vector3.new(3,10,3), Position=Vector3.new(x, y+6, -39.5), Color=Color3.fromRGB(72,68,62), Material=Enum.Material.Slate, Parent=f })
				part({ Name="CastleRoof"..cx, Size=Vector3.new(4.2,1.2,4.2), Position=Vector3.new(x, y+11.6, -39.5), Color=Color3.fromRGB(188,30,42), Material=Enum.Material.Wood, Parent=f })
			end
		elseif th.deco=="celestial" then
			-- 浮遊する鳥居と星
			part({ Name="CelestialRing", Size=Vector3.new(18,0.6,18), Position=Vector3.new(0, y+18, 0), Color=color, Material=Enum.Material.Neon, Transparency=0.2, Parent=f })
			for s=1,8 do
				local ang = (s/8)*math.pi*2
				local rx = math.cos(ang)*14
				local rz = math.sin(ang)*14
				local star = part({ Name="Star"..s, Size=Vector3.new(0.8,0.8,0.8), Position=Vector3.new(rx, y+16, rz), Color=Color3.fromRGB(255,240,180), Material=Enum.Material.Neon, Parent=f })
				addLight(star, Color3.fromRGB(255,240,150), 12, 1.5)
			end
		elseif th.deco=="thunder" then
			part({ Name="ThunderCloud", Size=Vector3.new(30,4,12), Position=Vector3.new(0, y+20, 0), Color=Color3.fromRGB(42,38,62), Material=Enum.Material.Slate, Transparency=0.35, Parent=f })
			for b=1,3 do
				part({ Name="Lightning"..b, Size=Vector3.new(0.35,8,0.35), Position=Vector3.new(-8+b*8, y+15, 0), Color=Color3.fromRGB(180,160,255), Material=Enum.Material.Neon, Parent=f })
			end
		elseif th.deco=="festival" then
			for fx=1,5 do
				local x = -16 + fx*8
				local lan = part({ Name="FestLantern"..fx, Size=Vector3.new(1.4,1.8,1.4), Position=Vector3.new(x, y+9, -39), Color=Color3.fromRGB(255,130,90), Material=Enum.Material.Neon, Parent=f })
				addLight(lan, Color3.fromRGB(255,140,90), 12, 1.2)
				part({ Name="FestRope"..fx, Size=Vector3.new(8,0.12,0.12), Position=Vector3.new(x+4, y+10.2, -39), Color=Color3.fromRGB(90,70,60), Parent=f })
			end
		end

		-- ── 観客席 (両サイド) ───────────────────────────────
		for _, sx in ipairs({-1,1}) do
			local xBase = sx*26
			for row=1,3 do
				local zLen = 60 - row*6
				local yOff = y + 3 + row*2.4
				local xOff = xBase + sx*row*1.4
				part({ Name="Stand"..sx.."_"..row, Size=Vector3.new(5,1.2,zLen), Position=Vector3.new(xOff, yOff, 0), Color=Color3.fromRGB(42,40,52), Material=Enum.Material.Concrete, Parent=f })
				-- 席
				part({ Name="StandSeat"..sx.."_"..row, Size=Vector3.new(1.2,0.6,zLen-2), Position=Vector3.new(xOff, yOff+0.9, 0), Color=Color3.fromRGB(62,58,72), Parent=f })
			end
			-- 観客の提灯
			for r=1,3 do
				local lamp = part({ Name="StandLamp"..sx.."_"..r, Size=Vector3.new(1,1,1), Position=Vector3.new(xBase+sx*2, y+10, -20+r*20), Color=Color3.fromRGB(255,210,90), Material=Enum.Material.Neon, Parent=f })
				addLight(lamp, Color3.fromRGB(255,210,90), 10, 1)
			end
		end

		-- ── スコアボード (天井吊り) ───────────────────────
		local board = part({ Name="Board", Size=Vector3.new(16,5,0.8), Position=Vector3.new(0,y+18,0), Color=Color3.fromRGB(16,14,22), Material=Enum.Material.SmoothPlastic, Parent=f })
		do
			local sg = Instance.new("SurfaceGui")
			sg.Face = Enum.NormalId.Front
			sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			sg.PixelsPerStud = 22
			sg.Parent = board
			local tl = Instance.new("TextLabel")
			tl.Size = UDim2.fromScale(1,0.5)
			tl.BackgroundTransparency=1
			tl.Font=Enum.Font.GothamBlack
			tl.TextScaled=true
			tl.TextColor3=color
			tl.Text=lv.label .. " ARENA"
			tl.Parent=sg
			local tl2 = Instance.new("TextLabel")
			tl2.Size=UDim2.fromScale(1,0.3)
			tl2.Position=UDim2.fromScale(0,0.52)
			tl2.BackgroundTransparency=1
			tl2.Font=Enum.Font.Gotham
			tl2.TextScaled=true
			tl2.TextColor3=Color3.fromRGB(220,220,230)
			tl2.Text=th.name
			tl2.Parent=sg
			local tl3 = Instance.new("TextLabel")
			tl3.Size=UDim2.fromScale(1,0.18)
			tl3.Position=UDim2.fromScale(0,0.82)
			tl3.BackgroundTransparency=1
			tl3.Font=Enum.Font.Gotham
			tl3.TextScaled=true
			tl3.TextColor3=Color3.fromRGB(245,210,90)
			tl3.Text="FIRST TO WIN · コンボで大ダメージ!"
			tl3.Parent=sg
			local sg2 = sg:Clone()
			sg2.Face = Enum.NormalId.Back
			sg2.Parent = board
		end
		-- ボードを吊るワイヤー
		part({ Name="BoardWireL", Size=Vector3.new(0.12,6,0.12), Position=Vector3.new(-6,y+21,0), Color=Color3.fromRGB(90,90,100), Parent=f })
		part({ Name="BoardWireR", Size=Vector3.new(0.12,6,0.12), Position=Vector3.new(6,y+21,0), Color=Color3.fromRGB(90,90,100), Parent=f })

		-- ── HPバー台座 (両陣営) ──────────────────────────
		for _, z in ipairs({-24,24}) do
			local off = (z > 0) and -3.6 or 3.6
			part({ Name="HpPedestal"..z, Size=Vector3.new(10,0.6,3), Position=Vector3.new(0,y+1.35,z+off), Color=Color3.fromRGB(28,26,34), Parent=f })
		end

		-- ── スポーンリング (発光) + 魔法陣 ───────────────
		for _, z in ipairs({-22,22}) do
			part({ Name="SpawnRingOuter"..z, Size=Vector3.new(7,0.28,7), Position=Vector3.new(0,y+1.15,z), Color=color, Material=Enum.Material.Neon, Parent=f })
			part({ Name="SpawnRingInner"..z, Size=Vector3.new(3.5,0.32,3.5), Position=Vector3.new(0,y+1.18,z), Color=Color3.fromRGB(255,255,255), Material=Enum.Material.Neon, Transparency=0.35, Parent=f })
			-- 魔法陣の線
			part({ Name="MagicLineA"..z, Size=Vector3.new(6,0.18,0.18), Position=Vector3.new(0,y+1.16,z), Color=color, Material=Enum.Material.Neon, Transparency=0.3, Parent=f })
			part({ Name="MagicLineB"..z, Size=Vector3.new(0.18,0.18,6), Position=Vector3.new(0,y+1.16,z), Color=color, Material=Enum.Material.Neon, Transparency=0.3, Parent=f })
		end

		-- ── 透明壁 + 天井 + スポットライト ───────────────
		local wallDefs = {
			{ Vector3.new(46,32,1), Vector3.new(0,y+16,-39) },
			{ Vector3.new(46,32,1), Vector3.new(0,y+16,39) },
			{ Vector3.new(1,32,80), Vector3.new(-22.5,y+16,0) },
			{ Vector3.new(1,32,80), Vector3.new(22.5,y+16,0) },
		}
		for wi, def in ipairs(wallDefs) do
			local w = part({ Name="Wall"..wi, Size=def[1], Position=def[2], Transparency=1, Parent=f })
			w.CanCollide = true
		end
		part({ Name="Ceiling", Size=Vector3.new(46,1,80), Position=Vector3.new(0,y+32,0), Transparency=1, Parent=f })
		-- スポットライト梁
		for _, sx in ipairs({-10,10}) do for _, sz in ipairs({-18,18}) do
			local spot = part({ Name="Spot"..sx..sz, Size=Vector3.new(0.9,0.9,0.9), Position=Vector3.new(sx,y+28,sz), Color=Color3.fromRGB(255,255,240), Material=Enum.Material.Metal, Parent=f })
			local sl = Instance.new("SpotLight")
			sl.Color = Color3.fromRGB(255,255,240)
			sl.Range = 44
			sl.Angle = 46
			sl.Brightness = 2
			sl.Shadows = true
			sl.Face = Enum.NormalId.Bottom
			sl.Parent = spot
		end end

		arenas[lv.key] = {
			spawnA = CFrame.new(0, y + 4.5, -22) * CFrame.Angles(0, math.pi, 0),
			spawnB = CFrame.new(0, y + 4.5, 22),
			folder = f,
		}
	end
end

function ArenaService.get(levelKey)
	return arenas[levelKey]
end

return ArenaService
