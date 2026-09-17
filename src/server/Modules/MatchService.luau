--!nonstrict
-- マッチメイキングと超拡張対戦進行 + 練習モード
-- 古いテスト互換を維持しつつ、コンボ・必殺・シールド・クリティカル・課金アイテムを統合

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("KKShared"):WaitForChild("GameConfig"))

local MatchService = {}

local QuestionBank, StatsService, ArenaService, LobbyService
local CurrencyService, ProgressionService
local S2C, C2S -- RemoteEvents

local queues = {}     -- [levelKey] = { {player, rating, enqueuedAt}, ... }
local inMatch = {}    -- [player] = match
local matches = {}    -- [match] = true
local practice = {}   -- [player] = state

local B = Config.BATTLE

local function send(player, action, data)
	data = data or {}
	data.action = action
	pcall(function()
		S2C:FireClient(player, data)
	end)
end

local function broadcastQueueCounts()
	local counts = {}
	for key, q in pairs(queues) do
		counts[key] = #q
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		send(pl, "queue", counts)
	end
end

function MatchService.init(deps)
	QuestionBank = deps.QuestionBank
	StatsService = deps.StatsService
	ArenaService = deps.ArenaService
	LobbyService = deps.LobbyService
	CurrencyService = deps.CurrencyService
	ProgressionService = deps.ProgressionService
	S2C = deps.S2C
	C2S = deps.C2S
end

-- ------------------------------------------------------------- queue
function MatchService.joinQueue(player, levelKey)
	if not Config.levelByKey(levelKey) then return end
	if inMatch[player] then return end
	MatchService.leaveQueue(player)
	if not queues[levelKey] then queues[levelKey] = {} end
	local prof = StatsService and StatsService.get(player)
	local rating = prof and prof.ratings[levelKey] or Config.DEFAULT_RATING
	table.insert(queues[levelKey], { player = player, rating = rating, t = os.clock() })
	send(player, "toast", { key = "toastSearching", args = { level = levelKey } })
	broadcastQueueCounts()
end

function MatchService.leaveQueue(player)
	for key, q in pairs(queues) do
		for i, ent in ipairs(q) do
			if ent.player == player then
				table.remove(q, i)
				break
			end
		end
	end
	broadcastQueueCounts()
end

local function popTwo(levelKey)
	local q = queues[levelKey]
	if not q then return nil end
	-- 退場済み掃除
	for i = #q, 1, -1 do
		local ent = q[i]
		if not ent.player.Parent or inMatch[ent.player] then
			table.remove(q, i)
		end
	end
	if #q < 2 then return nil end
	-- レーティング近い順にソートして先頭2人を出す (簡易スキルマッチ)
	table.sort(q, function(a,b) return a.rating < b.rating end)
	-- 初回はなるべくレート差が小さいペアを探す。差が200以上なら少し待つ (最大45秒のQUEUE_TIMEOUTで強制マッチ)
	local now = os.clock()
	for i=1, #q-1 do
		for j=i+1, #q do
			local diff = math.abs(q[i].rating - q[j].rating)
			local wait = math.max(now - q[i].t, now - q[j].t)
			if diff < 250 or wait > Config.QUEUE_TIMEOUT * 0.7 then
				local a = table.remove(q, j)
				local b = table.remove(q, i)
				return a.player, b.player
			end
		end
	end
	-- 見つからなければ先頭2人
	local a = table.remove(q, 1)
	local b = table.remove(q, 1)
	return a.player, b.player
end

function MatchService.tick()
	for _, lv in ipairs(Config.LEVELS) do
		while true do
			local a, b = popTwo(lv.key)
			if not a then break end
			MatchService.startMatch(lv.key, a, b)
		end
	end
end

-- ------------------------------------------------------------- match
local function teleport(player, cf)
	local char = player.Character
	if char and char.PrimaryPart then
		char:PivotTo(cf)
	end
end

local function ensureBattleState(profile, player)
	-- プロファイル側ではなく match 内の一時ステートを初期化
	return {
		combo = 0,
		maxCombo = 0,
		ult = 0,
		shield = B.START_SHIELD,
		missStreak = 0,
		perfects = 0,
		hintUsed = false,
		ultUsed = false,
		totalDealt = 0,
	}
end

local function calcDamage(correct, timeTaken, first, ownHp, state, opponentCorrect, opponentShield)
	if not correct then return 0, { isPerfect=false, isCrit=false, combo=state.combo, guard=false, shielded=false } end
	local elapsed = timeTaken
	local dmg = Config.DMG_BASE
	local flags = { isPerfect=false, isCrit=false, combo=state.combo, guard=false, shielded=false, comeback=false }
	-- 速答
	if elapsed <= 3 then dmg = dmg + Config.DMG_FAST_BONUS end
	if first then dmg = dmg + Config.DMG_FIRST_BONUS end
	-- パーフェクト
	if elapsed <= B.PERFECT_WINDOW then
		dmg = dmg + B.PERFECT_BONUS
		flags.isPerfect = true
	end
	-- 逆転
	if ownHp <= B.COMEBACK_HP then
		dmg = dmg + B.COMEBACK_BONUS
		flags.comeback = true
	end
	-- 残り時間ボーナス
	local remain = Config.QUESTION_TIME - elapsed
	if remain > 0 then
		dmg = dmg + math.clamp(math.floor(remain/2), 0, B.TIME_BONUS_MAX)
	end
	-- コンボ
	local combo = state.combo -- この問題を正解する前の combo (呼出側で +1 する前)
	local bonus = B.COMBO_BONUS[math.min(combo+1, #B.COMBO_BONUS)] or 0
	local mult = B.COMBO_MULTIPLIER[math.min(combo+1, #B.COMBO_MULTIPLIER)] or 1
	dmg = dmg + bonus
	dmg = math.floor(dmg * mult + 0.5)
	flags.combo = combo+1
	flags.mult = mult
	-- クリティカル (12%)
	if math.random() < B.CRIT_CHANCE then
		dmg = math.floor(dmg * B.CRIT_MULTIPLIER + 0.5)
		flags.isCrit = true
	end
	-- ガード (両者正解なら被ダメ側が軽減 = 与ダメ側が減る)
	if opponentCorrect then
		dmg = math.floor(dmg * (1 - B.GUARD_REDUCTION) + 0.5)
		flags.guard = true
	end
	-- シールド
	if opponentShield then
		dmg = math.floor(dmg * (1 - B.SHIELD_REDUCTION) + 0.5)
		flags.shielded = true
	end
	return dmg, flags
end

function MatchService.startMatch(levelKey, p1, p2)
	local arena = ArenaService.get(levelKey)
	if not arena then return end
	inMatch[p1] = true
	inMatch[p2] = true
	MatchService.leaveQueue(p1)
	MatchService.leaveQueue(p2)

	local match = {
		levelKey = levelKey,
		players = { p1, p2 },
		hp = { [p1] = Config.MAX_HP, [p2] = Config.MAX_HP },
		exclude = {},
		round = 0,
		answers = {}, -- [player] = {idx, t}
		answerCount = 0,
		dead = false,
		state = {
			[p1] = ensureBattleState(StatsService.get(p1), p1),
			[p2] = ensureBattleState(StatsService.get(p2), p2),
		},
		levelKey = levelKey,
		midActions = {}, -- [player] = {hint, ult}
	}
	matches[match] = true
	-- プロファイルのコスメを反映 (アリーナスキン)
	local prof1 = StatsService.get(p1)
	local prof2 = StatsService.get(p2)

	task.spawn(function()
		teleport(p1, arena.spawnA)
		teleport(p2, arena.spawnB)
		-- イントロでバトル演出を送る
		send(p1, "matchIntro", {
			levelKey = levelKey, opponent = p2.DisplayName, opponentRank = Config.rankOf(prof2.ratings[levelKey] or 1000).key,
			total = Config.ROUND_COUNT, myRank = Config.rankOf(prof1.ratings[levelKey] or 1000).key,
			myHp = Config.MAX_HP, opHp = Config.MAX_HP,
		})
		send(p2, "matchIntro", {
			levelKey = levelKey, opponent = p1.DisplayName, opponentRank = Config.rankOf(prof1.ratings[levelKey] or 1000).key,
			total = Config.ROUND_COUNT, myRank = Config.rankOf(prof2.ratings[levelKey] or 1000).key,
			myHp = Config.MAX_HP, opHp = Config.MAX_HP,
		})
		task.wait(Config.INTRO_TIME)

		local loser = nil
		for round = 1, Config.ROUND_COUNT do
			if match.dead then break end
			local ko = MatchService.playRound(match, round, false)
			if ko then loser = ko break end
			task.wait(0.35)
		end
		if match.dead then MatchService.endMatch(match, nil) return end

		local suddenCount = 0
		while not match.dead and not loser and match.hp[p1] == match.hp[p2] and suddenCount < 10 do
			suddenCount = suddenCount + 1
			loser = MatchService.playRound(match, match.round + 1, true)
			if loser == "none" then loser = nil end
		end

		local winner, reason
		if loser and loser ~= "none" and loser ~= "win1" and loser ~= "win2" then
			winner = (loser == p1) and p2 or p1
			reason = "KO"
		elseif loser == "win1" then
			winner = p1; loser = p2; reason = "KO"
		elseif loser == "win2" then
			winner = p2; loser = p1; reason = "KO"
		elseif match.hp[p1] > match.hp[p2] then
			winner = p1; loser = p2; reason = "HP"
		elseif match.hp[p2] > match.hp[p1] then
			winner = p2; loser = p1; reason = "HP"
		else
			send(p1, "matchEnd", { draw = true, levelKey=levelKey, coins=Config.ECONOMY.REWARD_DRAW })
			send(p2, "matchEnd", { draw = true, levelKey=levelKey, coins=Config.ECONOMY.REWARD_DRAW })
			-- 引き分けでも報酬
			for _, p in ipairs(match.players) do
				if CurrencyService then CurrencyService.grant(p, Config.ECONOMY.REWARD_DRAW, 0, "draw") end
				if ProgressionService then ProgressionService.addXp(p, Config.PROGRESSION.XP_PER_LOSE, "draw") end
			end
			task.wait(2.5)
			MatchService.endMatch(match, nil)
			return
		end

		-- Elo + 報酬計算
		local dw = StatsService.applyResult(levelKey, winner, loser)
		for _, p in ipairs(match.players) do
			local prof = StatsService.get(p)
			local isWin = (p == winner)
			local coins = isWin and Config.ECONOMY.REWARD_WIN or Config.ECONOMY.REWARD_LOSE
			-- コンボやパーフェクトで追加
			local st = match.state[p]
			if st then
				if st.maxCombo >=3 then coins = coins + Config.ECONOMY.REWARD_COMBO3 end
				if st.perfects >=1 then coins = coins + Config.ECONOMY.REWARD_PERFECT * st.perfects end
			end
			if isWin then coins = coins + math.floor((st and st.maxCombo or 0)/2) * 5 end
			if CurrencyService then CurrencyService.grant(p, coins, 0, isWin and "win" or "lose") end
			-- XP
			if ProgressionService then
				local xp = isWin and Config.PROGRESSION.XP_PER_WIN or Config.PROGRESSION.XP_PER_LOSE
				xp = xp + (st and st.maxCombo or 0) * 4
				xp = xp + (st and st.perfects or 0) * Config.PROGRESSION.XP_PERFECT_BONUS
				ProgressionService.addXp(p, xp, isWin and "win" or "lose")
				-- ミッション
				ProgressionService.progressMission(p, isWin and "win1" or "lose1", 1)
				if isWin then ProgressionService.progressMission(p, "win10", 1) end
				ProgressionService.progressMission(p, "correct10", st and st.totalDealt and 5 or 0)
			end

			local rank = Config.rankOf(prof.ratings[levelKey])
			local prog = Config.rankProgress(prof.ratings[levelKey])
			send(p, "matchEnd", {
				win = isWin,
				reason = reason,
				opponent = (p == winner) and loser.DisplayName or winner.DisplayName,
				rating = prof.ratings[levelKey],
				delta = isWin and dw or -dw,
				wins = prof.wins,
				losses = prof.losses,
				streak = prof.streak,
				coins = coins,
				rankKey = rank.key,
				rankIcon = rank.icon,
				rankProgress = prog,
				maxCombo = st and st.maxCombo or 0,
				perfects = st and st.perfects or 0,
			})
		end
		task.wait(4)
		MatchService.endMatch(match, winner)
	end)
end

-- 1ラウンド進行。KO時は敗者playerを返す。サドンデス時は勝者を返す("none"=両方誤答)
function MatchService.playRound(match, round, sudden)
	match.round = round
	match.answers = {}
	match.answerCount = 0
	match.midActions = {}
	local q = QuestionBank.draw(match.levelKey, match.exclude)
	if not q then return nil end
	local choices, correct = QuestionBank.pack(q)
	local deadline = os.clock() + Config.QUESTION_TIME
	local qStart = os.clock()
	match.correct = correct
	match.deadline = deadline
	match.qStart = qStart
	match.choices = choices

	local hp1, hp2 = match.hp[match.players[1]], match.hp[match.players[2]]
	local st1, st2 = match.state[match.players[1]], match.state[match.players[2]]

	send(match.players[1], "question", {
		round = round, total = Config.ROUND_COUNT, sudden = sudden,
		prompt = q.p, isKanji = (#q.p == 1), choices = choices,
		timeLimit = Config.QUESTION_TIME, hpMe = hp1, hpOp = hp2,
		combo = st1.combo, ult = st1.ult, shield = st1.shield, opUlt = st2.ult,
	})
	send(match.players[2], "question", {
		round = round, total = Config.ROUND_COUNT, sudden = sudden,
		prompt = q.p, isKanji = (#q.p == 1), choices = choices,
		timeLimit = Config.QUESTION_TIME, hpMe = hp2, hpOp = hp1,
		combo = st2.combo, ult = st2.ult, shield = st2.shield, opUlt = st1.ult,
	})

	while os.clock() < deadline and match.answerCount < 2 do
		task.wait(0.05)
	end
	task.wait(0.1)

	local function resultOf(p)
		local a = match.answers[p]
		if not a then return { correct = false, t = math.huge, idx = 0, timeTaken = Config.QUESTION_TIME } end
		local timeTaken = a.t - qStart
		return {
			correct = (a.idx == match.correct) and a.t <= deadline + 0.6,
			t = a.t,
			idx = a.idx,
			timeTaken = timeTaken,
		}
	end

	local r1 = resultOf(match.players[1])
	local r2 = resultOf(match.players[2])

	-- 必殺発動チェック (回答より前にUltボタンを押したか)
	local ult1 = match.midActions[match.players[1]] and match.midActions[match.players[1]].ult
	local ult2 = match.midActions[match.players[2]] and match.midActions[match.players[2]].ult
	local ultDmg1, ultDmg2 = 0,0
	if ult1 and st1.ult >= B.ULT_MAX and r1.correct then
		ultDmg1 = B.ULT_DAMAGE
		st1.ult = 0
		st1.ultUsed = true
		-- ヒール
		match.hp[match.players[1]] = math.min(Config.MAX_HP, match.hp[match.players[1]] + B.ULT_HEAL)
		hp1 = match.hp[match.players[1]]
	end
	if ult2 and st2.ult >= B.ULT_MAX and r2.correct then
		ultDmg2 = B.ULT_DAMAGE
		st2.ult = 0
		st2.ultUsed = true
		match.hp[match.players[2]] = math.min(Config.MAX_HP, match.hp[match.players[2]] + B.ULT_HEAL)
		hp2 = match.hp[match.players[2]]
	end

	-- ダメージ計算 (拡張)
	local firstT = math.min(r1.t, r2.t)
	local first1 = r1.correct and r1.t == firstT
	local first2 = r2.correct and r2.t == firstT

	local dmg1, flags1 = calcDamage(r1.correct, r1.timeTaken, first1, hp1, st1, r2.correct, st2.shield)
	local dmg2, flags2 = calcDamage(r2.correct, r2.timeTaken, first2, hp2, st2, r1.correct, st1.shield)
	-- Ult ダメージを加算
	dmg1 = dmg1 + ultDmg1
	dmg2 = dmg2 + ultDmg2

	-- シールド消費
	if flags1.shielded then st2.shield = false end
	if flags2.shielded then st1.shield = false end

	-- コンボ・ゲージ更新
	for _, pair in ipairs({{p=match.players[1], r=r1, st=st1}, {p=match.players[2], r=r2, st=st2}}) do
		if pair.r.correct then
			pair.st.combo = pair.st.combo + 1
			if pair.st.combo > pair.st.maxCombo then pair.st.maxCombo = pair.st.combo end
			pair.st.missStreak = 0
			pair.st.totalDealt = pair.st.totalDealt + (pair.p == match.players[1] and dmg1 or dmg2)
			-- ゲージ
			local gain = B.ULT_GAIN_CORRECT
			if pair.r.timeTaken <= B.PERFECT_WINDOW then
				gain = B.ULT_GAIN_PERFECT
				pair.st.perfects = pair.st.perfects + 1
			end
			pair.st.ult = math.clamp(pair.st.ult + gain, 0, B.ULT_MAX)
			-- 統計
			local prof = StatsService.get(pair.p)
			if prof then
				prof.totalCorrect = (prof.totalCorrect or 0)+1
				if pair.r.timeTaken <= B.PERFECT_WINDOW then prof.totalPerfect = (prof.totalPerfect or 0)+1 end
				if pair.st.combo > (prof.maxCombo or 0) then prof.maxCombo = pair.st.combo end
			end
			if ProgressionService then
				ProgressionService.progressMission(pair.p, "correct10", 1)
				ProgressionService.progressMission(pair.p, "correct100", 1)
				if pair.r.timeTaken <= B.PERFECT_WINDOW then ProgressionService.progressMission(pair.p, "perfect3", 1) end
				if pair.st.combo >=5 then ProgressionService.progressMission(pair.p, "combo5", 1) end
			end
		else
			-- 誤答: コンボリセット、ペナルティ
			pair.st.combo = 0
			pair.st.missStreak = pair.st.missStreak + 1
			pair.st.ult = math.clamp(pair.st.ult + B.ULT_GAIN_WRONG, 0, B.ULT_MAX)
			if pair.st.missStreak >= B.MISS_STREAK_PENALTY then
				-- 相手に回復させてしまう
				local other = (pair.p == match.players[1]) and match.players[2] or match.players[1]
				match.hp[other] = math.min(Config.MAX_HP, match.hp[other] + 5)
				if pair.p == match.players[1] then hp2 = match.hp[other] else hp1 = match.hp[other] end
			end
		end
	end

	-- HP反映
	match.hp[match.players[1]] = math.max(0, hp1 - dmg2)
	match.hp[match.players[2]] = math.max(0, hp2 - dmg1)

	-- セカンドチャンス (Robuxアイテム) で蘇生
	for _, p in ipairs(match.players) do
		if match.hp[p] <= 0 then
			local prof = StatsService.get(p)
			if prof and prof.inventory and (prof.inventory.secondChance or 0) > 0 then
				prof.inventory.secondChance = prof.inventory.secondChance - 1
				match.hp[p] = 30
				send(p, "secondChanceActivated", { hp = 30 })
				send((p==match.players[1] and match.players[2] or match.players[1]), "opponentSecondChance", {})
			end
		end
	end

	local nowHp1, nowHp2 = match.hp[match.players[1]], match.hp[match.players[2]]
	send(match.players[1], "answerResult", {
		round = round, correct = r1.correct, correctIdx = match.correct,
		myIdx = r1.idx, dealt = dmg1, taken = dmg2,
		hpMe = nowHp1, hpOp = nowHp2,
		opCorrect = r2.correct,
		combo = st1.combo, maxCombo = st1.maxCombo, ult = st1.ult, opUlt = st2.ult,
		isPerfect = flags1.isPerfect, isCrit = flags1.isCrit, isGuarded = flags1.guard, wasShielded = flags1.shielded,
		mult = flags1.mult or 1, opCombo = st2.combo,
		ultDamage = ultDmg1,
	})
	send(match.players[2], "answerResult", {
		round = round, correct = r2.correct, correctIdx = match.correct,
		myIdx = r2.idx, dealt = dmg2, taken = dmg1,
		hpMe = nowHp2, hpOp = nowHp1,
		opCorrect = r1.correct,
		combo = st2.combo, maxCombo = st2.maxCombo, ult = st2.ult, opUlt = st1.ult,
		isPerfect = flags2.isPerfect, isCrit = flags2.isCrit, isGuarded = flags2.guard, wasShielded = flags2.shielded,
		mult = flags2.mult or 1, opCombo = st1.combo,
		ultDamage = ultDmg2,
	})

	if sudden then
		if r1.correct and r2.correct then
			return (r1.t <= r2.t) and match.players[2] or match.players[1]
		elseif r1.correct then
			return match.players[2] == nil and "none" or "win1"
		elseif r2.correct then
			return "win2"
		end
		return "none"
	end

	if nowHp1 <= 0 then return match.players[1]
	elseif nowHp2 <= 0 then return match.players[2] end
	return nil
end

function MatchService.endMatch(match, winner)
	match.dead = true
	matches[match] = nil
	for _, p in ipairs(match.players) do
		inMatch[p] = nil
		-- プロファイルの streak / 統計も更新済み
		if CurrencyService then CurrencyService.sendUpdate(p) end
		teleport(p, LobbyService.getSpawn())
		send(p, "toLobby", {})
	end
end

-- ------------------------------------------------------------- practice
function MatchService.practiceStart(player, levelKey)
	if not Config.levelByKey(levelKey) then return end
	practice[player] = { levelKey = levelKey, streak = 0, exclude = {}, active = true, correct = nil }
	MatchService.practiceNext(player)
end

function MatchService.practiceNext(player)
	local st = practice[player]
	if not st or not st.active then return end
	local q = QuestionBank.draw(st.levelKey, st.exclude)
	if not q then return end
	local choices, correct = QuestionBank.pack(q)
	st.correct = correct
	st.choices = choices
	st.prompt = q.p
	send(player, "practiceQ", {
		prompt = q.p, isKanji = (#q.p == 1), choices = choices,
		timeLimit = 20, streak = st.streak,
		levelKey = st.levelKey,
	})
end

function MatchService.practiceSubmit(player, idx)
	local st = practice[player]
	if not st or not st.active then return end
	if not st.correct then return end
	local ok = (idx == st.correct)
	if ok then st.streak = st.streak + 1 else st.streak = 0 end
	-- 報酬
	if ok and CurrencyService then
		CurrencyService.grant(player, Config.ECONOMY.REWARD_PRACTICE_CORRECT, 0, "practice")
		if st.streak % 5 == 0 then
			CurrencyService.grant(player, Config.ECONOMY.REWARD_PRACTICE_STREAK5 - Config.ECONOMY.REWARD_PRACTICE_CORRECT, 0, "streak5")
		end
	end
	if ProgressionService then
		if ok then
			ProgressionService.addXp(player, Config.PROGRESSION.XP_PER_CORRECT, "practice")
		end
		ProgressionService.progressMission(player, ok and "correct10" or "miss", 1)
		ProgressionService.progressMission(player, "practice5", ok and 1 or 0)
	end
	send(player, "practiceResult", { correct = ok, correctIdx = st.correct, streak = st.streak })
	if ok then
		MatchService.practiceNext(player)
	else
		-- 誤答時は2秒後に次へ促すが、クライアントがpracticeNextを送るのでここでは待機
	end
	-- 経験値
end

function MatchService.practiceStop(player)
	local st = practice[player]
	if st then st.active = false end
	practice[player] = nil
end

function MatchService.practiceReroll(player)
	local st = practice[player]
	if not st or not st.active then return end
	-- コイン消費
	if CurrencyService then
		local prof = StatsService.get(player)
		if (prof.inventory.reroll or 0) > 0 then
			prof.inventory.reroll = prof.inventory.reroll - 1
		else
			if not CurrencyService.spend(player, Config.ECONOMY.COST_REROLL_QUESTION, 0, "reroll") then
				send(player, "toast", { key = "toastNotEnoughCoins" })
				return
			end
		end
	end
	MatchService.practiceNext(player)
end

-- ------------------------------------------------------------- router
function MatchService.onRemote(player, data)
	if type(data) ~= "table" or type(data.action) ~= "string" then return end
	local a = data.action
	if a == "queue" and type(data.levelKey) == "string" then
		MatchService.joinQueue(player, data.levelKey)
	elseif a == "cancelQueue" then
		MatchService.leaveQueue(player)
	elseif a == "submit" and inMatch[player] then
		for m in pairs(matches) do
			if m.players[1] == player or m.players[2] == player then
				if m.round == data.round and not m.answers[player] and type(data.idx) == "number" then
					local idx = math.floor(data.idx)
					if idx >= 1 and idx <= 4 then
						m.answers[player] = { idx = idx, t = os.clock() }
						m.answerCount = m.answerCount + 1
					end
				end
				break
			end
		end
	elseif a == "useHint" and inMatch[player] then
		for m in pairs(matches) do
			if m.players[1]==player or m.players[2]==player then
				local st = m.state[player]
				if st and not st.hintUsed and m.choices then
					-- コイン or 所持品消費
					local prof = StatsService.get(player)
					local consumed = false
					if (prof.inventory.hint or 0) > 0 then
						prof.inventory.hint = prof.inventory.hint - 1; consumed=true
					elseif CurrencyService and CurrencyService.spend(player, Config.ECONOMY.COST_HINT, 0, "hint") then
						consumed=true
					end
					if consumed then
						st.hintUsed=true
						-- 誤答の1つをランダムに消す (正解以外)
						local wrong = {}
						for i=1,4 do if i~=m.correct then table.insert(wrong,i) end end
						local elim = wrong[math.random(#wrong)]
						send(player, "hintResult", { eliminate = elim })
						-- 少しだけXP付与?
					else
						send(player, "toast", { key="toastNotEnoughCoins" })
					end
				end
				break
			end
		end
	elseif a == "activateUltimate" and inMatch[player] then
		for m in pairs(matches) do
			if m.players[1]==player or m.players[2]==player then
				local st = m.state[player]
				if st and st.ult >= B.ULT_MAX then
					m.midActions[player] = m.midActions[player] or {}
					m.midActions[player].ult = true
					send(player, "ultimateReady", { activated=true })
				else
					send(player, "toast", { key="toastUltNotReady" })
				end
				break
			end
		end
	elseif a == "useShield" and inMatch[player] then
		for m in pairs(matches) do
			if m.players[1]==player or m.players[2]==player then
				local st = m.state[player]
				local prof = StatsService.get(player)
				if st and not st.shield and (prof.inventory.shield or 0)>0 then
					prof.inventory.shield = prof.inventory.shield - 1
					st.shield = true
					send(player, "shieldActivated", {})
					if CurrencyService then CurrencyService.sendUpdate(player) end
				elseif CurrencyService and CurrencyService.spend(player, Config.ECONOMY.COST_SHIELD_REFILL, 0, "shield") then
					st.shield = true
					send(player, "shieldActivated", {})
				else
					send(player, "toast", { key="toastNotEnoughCoins" })
				end
				break
			end
		end
	elseif a == "practiceStart" and type(data.levelKey) == "string" then
		MatchService.practiceStop(player)
		MatchService.practiceStart(player, data.levelKey)
	elseif a == "practiceSubmit" and type(data.idx) == "number" then
		local idx = math.floor(data.idx)
		if idx >= 1 and idx <= 4 then MatchService.practiceSubmit(player, idx) end
	elseif a == "practiceNext" then
		MatchService.practiceNext(player)
	elseif a == "practiceReroll" then
		MatchService.practiceReroll(player)
	elseif a == "practiceStop" then
		MatchService.practiceStop(player)
	elseif a == "setLocale" and type(data.locale) == "string" then
		StatsService.setLocale(player, data.locale, data.source)
	end
end

Players.PlayerRemoving:Connect(function(player)
	MatchService.leaveQueue(player)
	MatchService.practiceStop(player)
	if inMatch[player] then
		for m in pairs(matches) do
			if m.players[1] == player or m.players[2] == player then
				local other = (m.players[1] == player) and m.players[2] or m.players[1]
				if not m.dead then
					m.dead = true
					local prof = StatsService.get(other)
					send(other, "matchEnd", {
						win = true, reason = "leave",
						opponent = player.DisplayName,
						rating = prof.ratings[m.levelKey],
						delta = 10, wins = prof.wins, losses = prof.losses, streak = prof.streak,
						coins = Config.ECONOMY.REWARD_WIN,
					})
					if CurrencyService then CurrencyService.grant(other, Config.ECONOMY.REWARD_WIN, 0, "leave") end
					task.delay(3, function() MatchService.endMatch(m, other) end)
				end
			end
		end
	end
end)

return MatchService
