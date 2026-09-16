--!nocheck
-- 漢字コンバット shared configuration (ReplicatedStorage.KKShared.GameConfig)

local GameConfig = {}

GameConfig.GAME_NAME = "漢字コンバット"

-- 漢検10級〜1級 (公式 級別漢字表 2020改正準拠の配当漢字データを使用)
GameConfig.LEVELS = {
	{ key = "K10", label = "10級", desc = "小学校1年生修了程度", kanji = 80,    color = { 90, 185, 105 } },
	{ key = "K09", label = "9級",  desc = "小学校2年生修了程度", kanji = 240,   color = { 110, 175, 70 } },
	{ key = "K08", label = "8級",  desc = "小学校3年生修了程度", kanji = 440,   color = { 150, 165, 50 } },
	{ key = "K07", label = "7級",  desc = "小学校4年生修了程度", kanji = 642,   color = { 190, 155, 40 } },
	{ key = "K06", label = "6級",  desc = "小学校5年生修了程度", kanji = 835,   color = { 215, 130, 35 } },
	{ key = "K05", label = "5級",  desc = "小学校6年生修了程度", kanji = 1026,  color = { 235, 100, 30 } },
	{ key = "K04", label = "4級",  desc = "中学校在学程度",     kanji = 1339,  color = { 240, 70, 45 } },
	{ key = "K03", label = "3級",  desc = "中学校卒業程度",     kanji = 1623,  color = { 235, 50, 75 } },
	{ key = "KP2", label = "準2級", desc = "高校在学程度",      kanji = 1951,  color = { 220, 45, 130 } },
	{ key = "K02", label = "2級",  desc = "高校卒業程度",       kanji = 2136,  color = { 190, 45, 190 } },
	{ key = "KP1", label = "準1級", desc = "大学・一般程度",    kanji = 2997,  color = { 140, 50, 220 } },
	{ key = "K01", label = "1級",  desc = "大学・一般程度",     kanji = 6357,  color = { 70, 60, 225 } },
}

GameConfig.ROUND_COUNT = 10        -- 1マッチの問題数
GameConfig.QUESTION_TIME = 12      -- 制限時間(秒)
GameConfig.INTRO_TIME = 3
GameConfig.REVEAL_TIME = 1.6
GameConfig.MAX_HP = 100
GameConfig.DMG_BASE = 20           -- 正答時の基本ダメージ
GameConfig.DMG_FAST_BONUS = 10     -- 3秒以内の正答ボーナス
GameConfig.DMG_FIRST_BONUS = 5     -- 一番乗りボーナス
GameConfig.QUEUE_TIMEOUT = 45      -- マッチが組まれなければ練習を勧める
GameConfig.ELO_K = 32
GameConfig.DEFAULT_RATING = 1000

function GameConfig.levelByKey(key)
	for _, lv in ipairs(GameConfig.LEVELS) do
		if lv.key == key then
			return lv
		end
	end
	return nil
end

function GameConfig.color3(lv)
	local c = lv.color
	return Color3.fromRGB(c[1], c[2], c[3])
end

return GameConfig
