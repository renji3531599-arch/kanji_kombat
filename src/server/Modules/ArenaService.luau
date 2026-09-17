--!nonstrict
-- 対戦アリーナの生成 (豪華版): 各級ごとにテーマ別アリーナ + エフェクト
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("KKShared"):WaitForChild("GameConfig"))

local ArenaService = {}
local arenas = {}

local ARENA_BASE_Y = 620
local ARENA_GAP = 280

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do p[k]=v end
	return p
end

local THEMES = {
	K10 = { mat=Enum.Material.SmoothPlastic, floor=Color3.fromRGB(85,165,90), accent=Color3.fromRGB(90,185,105) },
	K09 = { mat=Enum.Material.SmoothPlastic, floor=Color3.fromRGB(95,150,70), accent=Color3.fromRGB(110,175,70) },
	K08 = { mat=Enum.Material.Slate, floor=Color3.fromRGB(110,130,55), accent=Color3.fromRGB(150,165,50) },
	K07 = { mat=Enum.Material.Slate, floor=Color3.fromRGB(130,115,40), accent=Color3.fromRGB(190,155,40) },
	K06 = { mat=Enum.Material.Concrete, floor=Color3.fromRGB(150,95,30), accent=Color3.fromRGB(215,130,35) },
	K05 = { mat=Enum.Material.Concrete, floor=Color3.fromRGB(170,70,25), accent=Color3.fromRGB(235,100,30) },
	K04 = { mat=Enum.Material.Marble, floor=Color3.fromRGB(180,50,35), accent=Color3.fromRGB(240,70,45) },
	K03 = { mat=Enum.Material.Marble, floor=Color3.fromRGB(170,40,60), accent=Color3.fromRGB(235,50,75) },
	KP2 = { mat=Enum.Material.Metal, floor=Color3.fromRGB(160,35,100), accent=Color3.fromRGB(220,45,130) },
	K02 = { mat=Enum.Material.Metal, floor=Color3.fromRGB(140,35,140), accent=Color3.fromRGB(190,45,190) },
	KP1 = { mat=Enum.Material.Neon, floor=Color3.fromRGB(90,40,180), accent=Color3.fromRGB(140,50,220) },
	K01 = { mat=Enum.Material.Neon, floor=Color3.fromRGB(45,40,180), accent=Color3.fromRGB(70,60,225) },
}

function ArenaService.build(folder)
	for i, lv in ipairs(Config.LEVELS) do
		local y = ARENA_BASE_Y + (i - 1) * ARENA_GAP
		local f = Instance.new("Folder")
		f.Name = "Arena_" .. lv.key
		f.Parent = folder

		local th = THEMES[lv.key] or THEMES.K10
		local color = Config.color3(lv)

		-- 床 (テーマ材質 + 少し光る)
		local floor = part({
			Name = "Floor",
			Size = Vector3.new(36, 2, 70),
			Position = Vector3.new(0, y, 0),
			Color = th.floor,
			Material = th.mat,
			Parent = f,
		})
		-- 床の発光ライン (格子)
		for _, z in ipairs({-22,-11,0,11,22}) do
			part({ Name="Grid", Size=Vector3.new(36,0.2,0.4), Position=Vector3.new(0,y+1.05,z), Color=color, Material=Enum.Material.Neon, Parent=f })
		end
		for _, x in ipairs({-12,0,12}) do
			part({ Name="Grid", Size=Vector3.new(0.4,0.2,70), Position=Vector3.new(x,y+1.05,0), Color=Color3.fromRGB(255,255,255), Transparency=0.7, Parent=f })
		end

		-- センターライン (太く光る)
		part({
			Name = "CenterLine",
			Size = Vector3.new(36, 0.5, 1.2),
			Position = Vector3.new(0, y + 1.2, 0),
			Color = color,
			Material = Enum.Material.Neon,
			Parent = f,
		})
		-- 中央の家紋っぽい円
		part({ Name="Emblem", Size=Vector3.new(8,0.4,8), Position=Vector3.new(0,y+1.25,0), Color=color, Material=Enum.Material.Neon, Parent=f })

		-- 縁取り (ネオン)
		part({ Name="TrimA", Size=Vector3.new(36,0.8,1.6), Position=Vector3.new(0,y+1.3,-34), Color=color, Material=Enum.Material.Neon, Parent=f })
		part({ Name="TrimB", Size=Vector3.new(36,0.8,1.6), Position=Vector3.new(0,y+1.3,34), Color=color, Material=Enum.Material.Neon, Parent=f })
		part({ Name="TrimL", Size=Vector3.new(1.6,0.8,70), Position=Vector3.new(-17.2,y+1.3,0), Color=color, Material=Enum.Material.Neon, Parent=f })
		part({ Name="TrimR", Size=Vector3.new(1.6,0.8,70), Position=Vector3.new(17.2,y+1.3,0), Color=color, Material=Enum.Material.Neon, Parent=f })

		-- 四隅の柱 + 炎エフェクト (高位ほど派手)
		local pillarH = (i>=9) and 18 or 12
		for _, sx in ipairs({-16,16}) do for _, sz in ipairs({-32,32}) do
			part({ Name="Pillar", Size=Vector3.new(1.4,pillarH,1.4), Position=Vector3.new(sx, y+pillarH/2, sz), Color=Color3.fromRGB(30,28,36), Parent=f })
			if i>=7 then
				local flame = part({ Name="Flame", Size=Vector3.new(1.8,1.8,1.8), Position=Vector3.new(sx, y+pillarH+1, sz), Color=color, Material=Enum.Material.Neon, Parent=f })
				local light = Instance.new("PointLight")
				light.Color = color
				light.Range = 18
				light.Brightness = 2
				light.Shadows = true
				light.Parent = flame
			end
		end end

		-- 頭上に級名の浮遊看板
		local board = part({ Name="Board", Size=Vector3.new(14,4,0.6), Position=Vector3.new(0,y+14,0), Color=Color3.fromRGB(18,16,22), Parent=f })
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 24
		sg.Parent = board
		local tl = Instance.new("TextLabel")
		tl.Size = UDim2.fromScale(1,0.55)
		tl.BackgroundTransparency=1
		tl.Font=Enum.Font.GothamBlack
		tl.TextScaled=true
		tl.TextColor3=color
		tl.Text=lv.label .. " ARENA"
		tl.Parent=sg
		local tl2 = Instance.new("TextLabel")
		tl2.Size=UDim2.fromScale(1,0.35)
		tl2.Position=UDim2.fromScale(0,0.6)
		tl2.BackgroundTransparency=1
		tl2.Font=Enum.Font.Gotham
		tl2.TextScaled=true
		tl2.TextColor3=Color3.fromRGB(220,220,230)
		tl2.Text=lv.desc
		tl2.Parent=sg
		-- 反対側にも同じ
		local sg2 = sg:Clone()
		sg2.Face = Enum.NormalId.Back
		sg2.Parent = board

		-- 透明壁 + 天井
		local wallDefs = {
			{ Vector3.new(40, 30, 1), Vector3.new(0, y + 15, -35) },
			{ Vector3.new(40, 30, 1), Vector3.new(0, y + 15, 35) },
			{ Vector3.new(1, 30, 72), Vector3.new(-18.5, y + 15, 0) },
			{ Vector3.new(1, 30, 72), Vector3.new(18.5, y + 15, 0) },
		}
		for wi, def in ipairs(wallDefs) do
			local w = part({ Name="Wall"..wi, Size=def[1], Position=def[2], Transparency=1, Parent=f })
			w.CanCollide = true
		end
		part({ Name="Ceiling", Size=Vector3.new(40,1,72), Position=Vector3.new(0,y+30,0), Transparency=1, Parent=f })

		-- スポーンにエフェクトリング
		for _, z in ipairs({-22,22}) do
			part({ Name="SpawnRing", Size=Vector3.new(6,0.3,6), Position=Vector3.new(0,y+1.1,z), Color=color, Material=Enum.Material.Neon, Parent=f })
		end

		arenas[lv.key] = {
			spawnA = CFrame.new(0, y + 4, -22) * CFrame.Angles(0, math.pi, 0),
			spawnB = CFrame.new(0, y + 4, 22),
			folder = f,
		}
	end
end

function ArenaService.get(levelKey)
	return arenas[levelKey]
end

return ArenaService
