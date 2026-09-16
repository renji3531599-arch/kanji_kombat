--!nonstrict
-- マッチメイキングと対戦進行、練習モード
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("KKShared"):WaitForChild("GameConfig"))

local MatchService = {}

local QuestionBank, StatsService, ArenaService, LobbyService
local S2C, C2S -- RemoteEvents

local queues = {}     -- [levelKey] = {player, ...}
local inMatch = {}    -- [player] = match
local matches = {}    -- [match] = true
local practice = {}   -- [player] = state

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
	S2C = deps.S2C
	C2S = deps.C2S
end

-- ------------------------------------------------------------- queue
function MatchService.joinQueue(player, levelKey)
	if not Config.levelByKey(levelKey) then
		return
	end
	if inMatch[player] then
		return
	end
	MatchService.leaveQueue(player)
	if not queues[levelKey] then
		queues[levelKey] = {}
	end
	table.insert(queues[levelKey], player)
	send(player, "toast", { msg = Config.levelByKey(levelKey).label .. " の対戦相手を探しています…" })
	broadcastQueueCounts()
end

function MatchService.leaveQueue(player)
	for key, q in pairs(queues) do
		for i, p in ipairs(q) do
			if p == player then
				table.remove(q, i)
				break
			end
		end
	end
	broadcastQueueCounts()
end

local function popTwo(levelKey)
	local q = queues[levelKey]
	if not q then
		return nil
	end
	-- 退場済みプレイヤーを掃除
	for i = #q, 1, -1 do
		local p = q[i]
		if not p.Parent or inMatch[p] then
			table.remove(q, i)
		end
	end
	if #q < 2 then
		return nil
	end
	local a = table.remove(q, 1)
	local b = table.remove(q, 1)
	return a, b
end

function MatchService.tick()
	for _, lv in ipairs(Config.LEVELS) do
		while true do
			local a, b = popTwo(lv.key)
			if not a then
				break
			end
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

function MatchService.startMatch(levelKey, p1, p2)
	local arena = ArenaService.get(levelKey)
	if not arena then
		return
	end
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
		answers = {},
		answerCount = 0,
		dead = false,
	}
	matches[match] = true

	task.spawn(function()
		teleport(p1, arena.spawnA)
		teleport(p2, arena.spawnB)
		send(p1, "matchIntro", { levelKey = levelKey, opponent = p2.DisplayName, total = Config.ROUND_COUNT })
		send(p2, "matchIntro", { levelKey = levelKey, opponent = p1.DisplayName, total = Config.ROUND_COUNT })
		task.wait(Config.INTRO_TIME)

		local loser = nil
		for round = 1, Config.ROUND_COUNT do
			if match.dead then
				break
			end
			local ko = MatchService.playRound(match, round, false)
			if ko then
				loser = ko
				break
			end
			task.wait(0.35)
		end
		if match.dead then
			MatchService.endMatch(match, nil)
			return
		end

		-- 決着してなければサドンデス (最大10問)
		local suddenCount = 0
		while not match.dead and not loser and match.hp[p1] == match.hp[p2] and suddenCount < 10 do
			suddenCount = suddenCount + 1
			loser = MatchService.playRound(match, match.round + 1, true)
			if loser == "none" then
				loser = nil -- 両方不正解なら次のサドンデス問へ
			end
		end

		local winner, reason
		if loser then
			winner = (loser == p1) and p2 or p1
			reason = "KO"
		elseif match.hp[p1] > match.hp[p2] then
			winner = p1
			loser = p2
			reason = "HP"
		elseif match.hp[p2] > match.hp[p1] then
			winner = p2
			loser = p1
			reason = "HP"
		else
			-- 完全引き分け: 勝数に影響させず終了
			send(p1, "matchEnd", { draw = true })
			send(p2, "matchEnd", { draw = true })
			task.wait(2.5)
			MatchService.endMatch(match, nil)
			return
		end

		local dw = StatsService.applyResult(levelKey, winner, loser)
		for _, p in ipairs(match.players) do
			local prof = StatsService.get(p)
			local isWin = (p == winner)
			send(p, "matchEnd", {
				win = isWin,
				reason = reason,
				opponent = (p == winner) and loser.DisplayName or winner.DisplayName,
				rating = prof.ratings[levelKey],
				delta = isWin and dw or -dw,
				wins = prof.wins,
				losses = prof.losses,
				streak = prof.streak,
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
	local q = QuestionBank.draw(match.levelKey, match.exclude)
	if not q then
		return nil
	end
	local choices, correct = QuestionBank.pack(q)
	local deadline = os.clock() + Config.QUESTION_TIME
	match.correct = correct
	match.deadline = deadline

	local hp1, hp2 = match.hp[match.players[1]], match.hp[match.players[2]]
	send(match.players[1], "question", {
		round = round, total = Config.ROUND_COUNT, sudden = sudden,
		prompt = q.p, isKanji = (#q.p == 1), choices = choices,
		timeLimit = Config.QUESTION_TIME, hpMe = hp1, hpOp = hp2,
	})
	send(match.players[2], "question", {
		round = round, total = Config.ROUND_COUNT, sudden = sudden,
		prompt = q.p, isKanji = (#q.p == 1), choices = choices,
		timeLimit = Config.QUESTION_TIME, hpMe = hp2, hpOp = hp1,
	})

	while os.clock() < deadline and match.answerCount < 2 do
		task.wait(0.05)
	end
	task.wait(0.1) -- 正答直前の提出を受け取る猶予

	local function resultOf(p)
		local a = match.answers[p]
		if not a or os.clock() - 0 > deadline + 0.6 then
			-- 期内のみ有効 (下で判定し直す)
		end
		if not a then
			return { correct = false, t = math.huge, idx = 0 }
		end
		return {
			correct = (a.idx == match.correct) and a.t <= deadline + 0.6,
			t = a.t,
			idx = a.idx,
		}
	end

	local r1 = resultOf(match.players[1])
	local r2 = resultOf(match.players[2])

	-- ダメージ計算
	local dmg1, dmg2 = 0, 0
	local firstT = math.min(r1.t, r2.t)
	if r1.correct then
		dmg1 = Config.DMG_BASE
		if r1.t - (deadline - Config.QUESTION_TIME) <= 3 then
			dmg1 = dmg1 + Config.DMG_FAST_BONUS
		end
		if r1.t == firstT then
			dmg1 = dmg1 + Config.DMG_FIRST_BONUS
		end
	end
	if r2.correct then
		dmg2 = Config.DMG_BASE
		if r2.t - (deadline - Config.QUESTION_TIME) <= 3 then
			dmg2 = dmg2 + Config.DMG_FAST_BONUS
		end
		if r2.t == firstT then
			dmg2 = dmg2 + Config.DMG_FIRST_BONUS
		end
	end
	match.hp[match.players[1]] = math.max(0, hp1 - dmg2)
	match.hp[match.players[2]] = math.max(0, hp2 - dmg1)

	local nowHp1, nowHp2 = match.hp[match.players[1]], match.hp[match.players[2]]
	send(match.players[1], "answerResult", {
		round = round, correct = r1.correct, correctIdx = match.correct,
		myIdx = r1.idx, dealt = dmg1, taken = dmg2,
		hpMe = nowHp1, hpOp = nowHp2,
		opCorrect = r2.correct,
	})
	send(match.players[2], "answerResult", {
		round = round, correct = r2.correct, correctIdx = match.correct,
		myIdx = r2.idx, dealt = dmg2, taken = dmg1,
		hpMe = nowHp2, hpOp = nowHp1,
	})

	if sudden then
		if r1.correct and r2.correct then
			return (r1.t <= r2.t) and match.players[2] or match.players[1] -- 速い方の相手が敗者…いや勝者判定は呼び出し側
		elseif r1.correct then
			return match.players[2] == nil and "none" or "win1"
		elseif r2.correct then
			return "win2"
		end
		return "none"
	end

	if nowHp1 <= 0 then
		return match.players[1]
	elseif nowHp2 <= 0 then
		return match.players[2]
	end
	return nil
end

function MatchService.endMatch(match, winner)
	match.dead = true
	matches[match] = nil
	for _, p in ipairs(match.players) do
		inMatch[p] = nil
		teleport(p, LobbyService.getSpawn())
		send(p, "toLobby", {})
	end
end

-- ------------------------------------------------------------- practice
function MatchService.practiceStart(player, levelKey)
	if not Config.levelByKey(levelKey) then
		return
	end
	practice[player] = { levelKey = levelKey, streak = 0, exclude = {}, active = true }
	MatchService.practiceNext(player)
end

function MatchService.practiceNext(player)
	local st = practice[player]
	if not st or not st.active then
		return
	end
	local q = QuestionBank.draw(st.levelKey, st.exclude)
	if not q then
		return
	end
	local choices, correct = QuestionBank.pack(q)
	st.correct = correct
	send(player, "practiceQ", {
		prompt = q.p, isKanji = (#q.p == 1), choices = choices,
		timeLimit = 20, streak = st.streak,
		levelKey = st.levelKey,
	})
end

function MatchService.practiceSubmit(player, idx)
	local st = practice[player]
	if not st or not st.active then
		return
	end
	local ok = (idx == st.correct)
	if ok then
		st.streak = st.streak + 1
	else
		st.streak = 0
	end
	send(player, "practiceResult", { correct = ok, correctIdx = st.correct, streak = st.streak })
	if ok then
		MatchService.practiceNext(player)
	end
end

function MatchService.practiceStop(player)
	local st = practice[player]
	if st then
		st.active = false
	end
	practice[player] = nil
end

-- ------------------------------------------------------------- router
function MatchService.onRemote(player, data)
	if type(data) ~= "table" or type(data.action) ~= "string" then
		return
	end
	local a = data.action
	if a == "queue" and type(data.levelKey) == "string" then
		MatchService.joinQueue(player, data.levelKey)
	elseif a == "cancelQueue" then
		MatchService.leaveQueue(player)
	elseif a == "submit" and inMatch[player] then
		-- find the match
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
	elseif a == "practiceStart" and type(data.levelKey) == "string" then
		MatchService.practiceStop(player)
		MatchService.practiceStart(player, data.levelKey)
	elseif a == "practiceSubmit" and type(data.idx) == "number" then
		local idx = math.floor(data.idx)
		if idx >= 1 and idx <= 4 then
			MatchService.practiceSubmit(player, idx)
		end
	elseif a == "practiceNext" then
		MatchService.practiceNext(player)
	elseif a == "practiceStop" then
		MatchService.practiceStop(player)
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
					-- 残った側を勝ちに
					local prof = StatsService.get(other)
					send(other, "matchEnd", {
						win = true, reason = "leave",
						opponent = player.DisplayName,
						rating = prof.ratings[m.levelKey],
						delta = 10, wins = prof.wins, losses = prof.losses, streak = prof.streak,
					})
					task.delay(3, function()
						MatchService.endMatch(m, other)
					end)
				end
			end
		end
	end
end)

return MatchService
