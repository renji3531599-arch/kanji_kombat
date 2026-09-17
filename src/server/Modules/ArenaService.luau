--!nonstrict
-- 対戦アリーナの生成 (各級ごとに空中に1面)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("KKShared"):WaitForChild("GameConfig"))

local ArenaService = {}
local arenas = {} -- [levelKey] = { spawnA=CFrame, spawnB=CFrame, center=CFrame, folder=Instance }

local ARENA_BASE_Y = 600
local ARENA_GAP = 260

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

function ArenaService.build(folder)
	for i, lv in ipairs(Config.LEVELS) do
		local y = ARENA_BASE_Y + (i - 1) * ARENA_GAP
		local f = Instance.new("Folder")
		f.Name = "Arena_" .. lv.key
		f.Parent = folder

		local color = Config.color3(lv)
		local floor = part({
			Name = "Floor",
			Size = Vector3.new(30, 2, 60),
			Position = Vector3.new(0, y, 0),
			Color = Color3.fromRGB(35, 35, 45),
			Material = Enum.Material.Slate,
			Parent = f,
		})

		-- 両陣営のスポーン台。対戦開始時に色が見えるので「自分の側」が直感的。
		for side, z in ipairs({ -20, 20 }) do
			local pad = part({
				Name = side == 1 and "SpawnPadA" or "SpawnPadB",
				Size = Vector3.new(12, 0.35, 8),
				Position = Vector3.new(0, y + 1.2, z),
				Color = side == 1 and Color3.fromRGB(70, 125, 170) or Color3.fromRGB(170, 65, 85),
				Material = Enum.Material.Neon,
				Parent = f,
			})
			local light = Instance.new("PointLight")
			light.Color = pad.Color
			light.Brightness = 1.4
			light.Range = 12
			light.Parent = pad
		end

		-- センターライン
		part({
			Name = "CenterLine",
			Size = Vector3.new(30, 0.4, 1),
			Position = Vector3.new(0, y + 1.1, 0),
			Color = color,
			Material = Enum.Material.Neon,
			Parent = f,
		})

		-- 級カラーの縁取り
		part({
			Name = "TrimA",
			Size = Vector3.new(30, 0.6, 1.4),
			Position = Vector3.new(0, y + 1.2, -29.5),
			Color = color,
			Material = Enum.Material.Neon,
			Parent = f,
		})
		part({
			Name = "TrimB",
			Size = Vector3.new(30, 0.6, 1.4),
			Position = Vector3.new(0, y + 1.2, 29.5),
			Color = color,
			Material = Enum.Material.Neon,
			Parent = f,
		})

		-- 観戦者にも級が分かる小さな立体看板。
		local sign = part({
			Name = "LevelSign",
			Size = Vector3.new(18, 4, 0.35),
			Position = Vector3.new(0, y + 8, 0),
			Color = Color3.fromRGB(20, 18, 28),
			Parent = f,
		})
		local signGui = Instance.new("SurfaceGui")
		signGui.Face = Enum.NormalId.Front
		signGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		signGui.PixelsPerStud = 30
		signGui.Parent = sign
		local signText = Instance.new("TextLabel")
		signText.Size = UDim2.fromScale(1, 1)
		signText.BackgroundTransparency = 1
		signText.Font = Enum.Font.GothamBlack
		signText.TextScaled = true
		signText.TextColor3 = color
		signText.Text = lv.label .. "  /  " .. (lv.en and lv.en.label or lv.label)
		signText.Parent = signGui

		-- 透明な壁 (落下防止)
		local wallDefs = {
			{ Vector3.new(32, 30, 1), Vector3.new(0, y + 15, -30.5) },
			{ Vector3.new(32, 30, 1), Vector3.new(0, y + 15, 30.5) },
			{ Vector3.new(1, 30, 62), Vector3.new(-15.5, y + 15, 0) },
			{ Vector3.new(1, 30, 62), Vector3.new(15.5, y + 15, 0) },
		}
		for wi, def in ipairs(wallDefs) do
			local w = part({
				Name = "Wall" .. wi,
				Size = def[1],
				Position = def[2],
				Transparency = 1,
				Parent = f,
			})
			w.CanCollide = true
		end

		-- 天面 (上から飛び込めないように)
		part({
			Name = "Ceiling",
			Size = Vector3.new(32, 1, 62),
			Position = Vector3.new(0, y + 30, 0),
			Transparency = 1,
			Parent = f,
		})

		arenas[lv.key] = {
			spawnA = CFrame.new(0, y + 4, -20) * CFrame.Angles(0, math.pi, 0),
			spawnB = CFrame.new(0, y + 4, 20),
			folder = f,
		}
	end
end

function ArenaService.get(levelKey)
	return arenas[levelKey]
end

return ArenaService
