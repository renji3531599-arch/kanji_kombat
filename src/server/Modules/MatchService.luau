--!nonstrict
-- マッチメイキング、同時回答バトル、スキル、練習モード。
-- クライアントは「選んだ番号」しか送れず、正解・制限時間・ダメージは全てサーバー判定。
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("KKShared"):WaitForChild("GameConfig"))

local MatchService = {}

local QuestionBank, StatsService, ArenaService, LobbyService
local S2C, C2S

local queues = {}       -- [levelKey] = { player, ... }
local queueMeta = {}    -- [player] = { joinedAt, warned }
local inMatch = {}      -- [player] = match
local matches = {}      -- [match] = true
local practice = {}     -- [player] = state

local function send(player, action, data)
	data = data or {}
	data.action = action
	pcall(function()
		S2C:FireClient(player, data)
	end)
end

local function profileRating(player, levelKey)
	local profile = StatsService.get(player)
	return (profile.ratings and profile.ratings[levelKey]) or Config.DEFAULT_RATING
end

local function broadcastQueueCounts()
	local counts = {}
	for key, q in pairs(queues) do
		local n = 0
		for _, p in ipairs(q) do
			if p.Parent and not inMatch[p] then
				n = n + 1
			end
		end
		counts[key] = n
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

-- ================================================================ queue
function MatchService.leaveQueue(player)
	for key, q in pairs(queues) do
		for i = #q, 1, -1 do
			if q[i] == player then
				table.remove(q, i)
			end
		end
		if #q == 0 then
			queues[key] = nil
		end
	end
	queueMeta[player] = nil
	broadcastQueueCounts()
end

function MatchService.joinQueue(player, levelKey)
	if not Config.levelByKey(levelKey) or inMatch[player] or practice[player] then
		return
	end
	MatchService.leaveQueue(player)
	queues[levelKey] = queues[levelKey] or {}
	queues[levelKey][#queues[levelKey] + 1] = player
	queueMeta[player] = { joinedAt = os.clock(), warned = false, levelKey = levelKey }
	send(player, "toast", { key = "toastSearching", args = { level = levelKey } })
	broadcastQueueCounts()
end

local function popTwo(levelKey)
	local q = queues[levelKey]
	if not q then
		return nil
	end
	for i = #q, 1, -1 do
		local p = q[i]
		if not p.Parent or inMatch[p] then
			table.remove(q, i)
			queueMeta[p] = nil
		end
	end
	if #q < 2 then
		return nil
	end

	-- 最古参を軸に、同じ級の中でレートが最も近い相手を選ぶ。
	-- 待ち時間は tick で広がるため、過疎級でも置き去りにしない。
	local a = table.remove(q, 1)
	local aRating = profileRating(a, levelKey)
	local bestIndex, bestScore = 1, math.huge
	for i, p in ipairs(q) do
		local ratingGap = math.abs(profileRating(p, levelKey) - aRating)
		local waited = os.clock() - ((queueMeta[p] and queueMeta[p].joinedAt) or os.clock())
		local score = ratingGap - math.min(waited * 8, 240)
		if score < bestScore then
			bestScore, bestIndex = score, i
		end
	end
	local b = table.remove(q, bestIndex)
	queueMeta[a], queueMeta[b] = nil, nil
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
	-- 45秒以上待っている人には練習モードを案内するが、キューからは消さない。
	for player, meta in pairs(queueMeta) do
		if not meta.warned and os.clock() - meta.joinedAt >= Config.QUEUE_TIMEOUT then
			meta.warned = true
			send(player, "toast", { key = "searching", args = {} })
		end
	end
end

-- ================================================================ match helpers
local function teleport(player, cf)
	local char = player.Character
	if char and char.PrimaryPart then
		char:PivotTo(cf)
	end
end

local function clamp(value, low, high)
	return math.max(low, math.min(high, value))
end

local function playerState(match, player)
	return match.state[player]
end

local function publicState(state)
	return {
		combo = state.combo,
		bestCombo = state.bestCombo,
		energy = state.energy,
		shield = state.shield,
		focus = state.focus,
		correct = state.correct,
		answered = state.answered,
	}
end

local function sendState(match, player, action, extra)
	local data = extra or {}
	data.state = publicState(playerState(match, player))
	send(player, action, data)
end

function MatchService.startMatch(levelKey, p1, p2)
	local arena = ArenaService.get(levelKey)
	if not arena or not p1.Parent or not p2.Parent then
		return
	end
	MatchService.leaveQueue(p1)
	MatchService.leaveQueue(p2)

	local match = {
		levelKey = levelKey,
		players = { p1, p2 },
		hp = { [p1] = Config.MAX_HP, [p2] = Config.MAX_HP },
		state = {
			[p1] = { combo = 0, bestCombo = 0, energy = 0, shield = 0, focus = 0, correct = 0, answered = 0 },
			[p2] = { combo = 0, bestCombo = 0, energy = 0, shield = 0, focus = 0, correct = 0, answered = 0 },
		},
		exclude = {},
		round = 0,
		answers = {},
		answerCount = 0,
		questionId = 0,
		activeQuestion = nil,
		dead = false,
	}
	matches[match] = true
	inMatch[p1], inMatch[p2] = match, match

	task.spawn(function()
		teleport(p1, arena.spawnA)
		teleport(p2, arena.spawnB)
		send(p1, "matchIntro", { levelKey = levelKey, opponent = p2.DisplayName, total = Config.ROUND_COUNT })
		send(p2, "matchIntro", { levelKey = levelKey, opponent = p1.DisplayName, total = Config.ROUND_COUNT })
		task.wait(Config.INTRO_TIME)

		local winner, reason
		for round = 1, Config.ROUND_COUNT do
			if match.dead then
				return
			end
			local outcome = MatchService.playRound(match, round, false)
			if outcome and outcome.winner then
				winner, reason = outcome.winner, outcome.reason
				break
			end
			task.wait(0.35)
		end

		-- 通常ラウンドで決着しなかった場合、HP差を優先する。
		if not winner and match.hp[p1] ~= match.hp[p2] then
			winner = match.hp[p1] > match.hp[p2] and p1 or p2
			reason = "HP"
		end

		-- HPが同じなら、先に正答した側だけが勝つサドンデスへ。
		local suddenCount = 0
		while not match.dead and not winner and match.hp[p1] == match.hp[p2] and suddenCount < 10 do
			suddenCount = suddenCount + 1
			local outcome = MatchService.playRound(match, Config.ROUND_COUNT + suddenCount, true)
			if outcome and outcome.winner then
				winner, reason = outcome.winner, outcome.reason
				break
			end
		end

		if not winner and match.hp[p1] ~= match.hp[p2] then
			winner = match.hp[p1] > match.hp[p2] and p1 or p2
			reason = "HP"
		end

		if not winner then
			match.finished = true
			StatsService.applyDraw(p1, p2)
			send(p1, "matchEnd", { draw = true, summary = MatchService.summaryFor(match, p1) })
			send(p2, "matchEnd", { draw = true, summary = MatchService.summaryFor(match, p2) })
			task.wait(2.5)
			MatchService.endMatch(match, nil)
			return
		end

		MatchService.finishMatch(match, winner, reason or "KO")
		task.wait(4)
		MatchService.endMatch(match, winner)
	end)
end

function MatchService.summaryFor(match, player)
	local state = playerState(match, player)
	return {
		correct = state.correct,
		total = state.answered,
		bestCombo = state.bestCombo,
		accuracy = state.answered > 0 and math.floor(state.correct / state.answered * 100 + 0.5) or 0,
	}
end

function MatchService.finishMatch(match, winner, reason)
	if match.dead or match.finished then
		return
	end
	match.finished = true
	local loser = (match.players[1] == winner) and match.players[2] or match.players[1]
	local delta = StatsService.applyResult(match.levelKey, winner, loser)
	for _, p in ipairs(match.players) do
		local isWin = p == winner
		local summary = MatchService.summaryFor(match, p)
		local reward = StatsService.awardMatch(p, isWin, summary.bestCombo, summary.correct, summary.total)
		local profile = StatsService.get(p)
		send(p, "matchEnd", {
			win = isWin,
			reason = reason,
			opponent = (isWin and loser or winner).DisplayName,
			rating = profile.ratings[match.levelKey],
			delta = isWin and delta or -delta,
			wins = profile.wins,
			losses = profile.losses,
			streak = profile.streak,
			summary = summary,
			reward = reward,
		})
	end
end

-- 1ラウンド進行。return = { winner = Player?, reason = string? }
function MatchService.playRound(match, round, sudden)
	match.round = round
	match.answers = {}
	match.answerCount = 0
	local q = QuestionBank.draw(match.levelKey, match.exclude)
	if not q then
		return nil
	end
	local choices, correct = QuestionBank.pack(q)
	local started = os.clock()
	local deadline = started + Config.QUESTION_TIME
	match.questionId = match.questionId + 1
	match.activeQuestion = { id = match.questionId, round = round, correct = correct, deadline = deadline, started = started }

	local p1, p2 = match.players[1], match.players[2]
	sendState(match, p1, "question", {
		questionId = match.questionId, round = round, total = Config.ROUND_COUNT,
		sudden = sudden, prompt = q.p, isKanji = (#q.p == 1), choices = choices,
		timeLimit = Config.QUESTION_TIME, hpMe = match.hp[p1], hpOp = match.hp[p2],
		opState = publicState(playerState(match, p2)),
	})
	sendState(match, p2, "question", {
		questionId = match.questionId, round = round, total = Config.ROUND_COUNT,
		sudden = sudden, prompt = q.p, isKanji = (#q.p == 1), choices = choices,
		timeLimit = Config.QUESTION_TIME, hpMe = match.hp[p2], hpOp = match.hp[p1],
		opState = publicState(playerState(match, p1)),
	})

	while os.clock() < deadline and match.answerCount < 2 do
		task.wait(0.05)
	end
	task.wait(0.05)

	local function resultOf(player)
		local a = match.answers[player]
		if not a or a.t > deadline + Config.QUESTION_GRACE then
			return { correct = false, t = math.huge, idx = 0, elapsed = Config.QUESTION_TIME }
		end
		return {
			correct = a.idx == correct,
			t = a.t,
			idx = a.idx,
			elapsed = math.max(0, a.t - started),
		}
	end

	local r1, r2 = resultOf(p1), resultOf(p2)
	local firstT = math.min(r1.correct and r1.t or math.huge, r2.correct and r2.t or math.huge)
	local first1 = r1.correct and r1.t == firstT
	local first2 = r2.correct and r2.t == firstT

	local function rawDamage(player, result, isFirst)
		local state = playerState(match, player)
		state.answered = state.answered + 1
		if not result.correct then
			state.combo = 0
			StatsService.recordAnswer(player, false, result.elapsed)
			return 0, { fast = false, first = false, focus = false, combo = 0 }
		end
		state.correct = state.correct + 1
		state.combo = math.min(Config.DMG_COMBO_CAP, state.combo + 1)
		state.bestCombo = math.max(state.bestCombo, state.combo)
		local damage = Config.DMG_BASE + math.max(0, state.combo - 1) * Config.DMG_COMBO_STEP
		local fast = result.elapsed <= 3
		if fast then damage = damage + Config.DMG_FAST_BONUS end
		if isFirst then damage = damage + Config.DMG_FIRST_BONUS end
		local focused = state.focus > 0
		if focused then
			damage = math.floor(damage * Config.DMG_FOCUS_MULTIPLIER + 0.5)
			state.focus = 0
		end
		local gained = Config.ENERGY_CORRECT + (fast and Config.ENERGY_FAST or 0)
		state.energy = clamp(state.energy + gained, 0, Config.ENERGY_MAX)
		StatsService.recordAnswer(player, true, result.elapsed)
		return damage, { fast = fast, first = isFirst, focus = focused, combo = state.combo, energy = gained }
	end

	local raw1, parts1 = rawDamage(p1, r1, first1)
	local raw2, parts2 = rawDamage(p2, r2, first2)
	local function takeDamage(target, amount)
		local state = playerState(match, target)
		local blocked = 0
		if amount > 0 and state.shield > 0 then
			blocked = math.floor(amount * Config.SHIELD_REDUCTION + 0.5)
			amount = math.max(0, amount - blocked)
			state.shield = 0
		end
		return amount, blocked
	end
	local taken1, blocked1 = takeDamage(p1, raw2)
	local taken2, blocked2 = takeDamage(p2, raw1)
	match.hp[p1] = math.max(0, match.hp[p1] - taken1)
	match.hp[p2] = math.max(0, match.hp[p2] - taken2)

	local function resultPayload(me, other, result, parts, dealt, taken, blocked)
		return {
			round = round, questionId = match.questionId, correct = result.correct,
			correctIdx = correct, myIdx = result.idx, dealt = dealt, taken = taken,
			blocked = blocked, opCorrect = result == r1 and r2.correct or r1.correct,
			state = publicState(playerState(match, me)),
			opState = publicState(playerState(match, other)),
			damageParts = parts,
			hpMe = match.hp[me], hpOp = match.hp[other],
		}
	end
	send(p1, "answerResult", resultPayload(p1, p2, r1, parts1, raw1, taken1, blocked1))
	send(p2, "answerResult", resultPayload(p2, p1, r2, parts2, raw2, taken2, blocked2))
	match.activeQuestion = nil

	-- KO は「片方だけ0」なら即時、両方なら先に正答した方を勝者にする。
	if match.hp[p1] <= 0 or match.hp[p2] <= 0 then
		if match.hp[p1] <= 0 and match.hp[p2] <= 0 then
			if first1 and not first2 then return { winner = p1, reason = "KO" } end
			if first2 and not first1 then return { winner = p2, reason = "KO" } end
			return nil
		end
		return { winner = match.hp[p1] <= 0 and p2 or p1, reason = "KO" }
	end

	if sudden then
		if r1.correct and not r2.correct then
			return { winner = p1, reason = "SUDDEN" }
		elseif r2.correct and not r1.correct then
			return { winner = p2, reason = "SUDDEN" }
		elseif r1.correct and r2.correct and first1 ~= first2 then
			return { winner = first1 and p1 or p2, reason = "SUDDEN" }
		end
	end
	return nil
end

function MatchService.useSkill(player, skill)
	local match = inMatch[player]
	if not match or match.dead or not match.activeQuestion then
		return
	end
	local state = playerState(match, player)
	if skill == "guard" then
		if state.energy < Config.ENERGY_GUARD_COST then
			send(player, "skillResult", { ok = false, key = "skillNotReady" })
			return
		end
		state.energy = state.energy - Config.ENERGY_GUARD_COST
		state.shield = Config.GUARD_SHIELD
		sendState(match, player, "skillResult", { ok = true, key = "skillUsed", args = { skill = "Guard" } })
	elseif skill == "focus" then
		if state.energy < Config.ENERGY_FOCUS_COST then
			send(player, "skillResult", { ok = false, key = "skillNotReady" })
			return
		end
		state.energy = state.energy - Config.ENERGY_FOCUS_COST
		state.focus = 1
		sendState(match, player, "skillResult", { ok = true, key = "skillUsed", args = { skill = "Focus" } })
	end
end

function MatchService.endMatch(match, winner)
	if not matches[match] then
		return
	end
	match.dead = true
	match.activeQuestion = nil
	matches[match] = nil
	for _, p in ipairs(match.players) do
		if inMatch[p] == match then
			inMatch[p] = nil
		end
		teleport(p, LobbyService.getSpawn())
		send(p, "toLobby", {})
	end
	broadcastQueueCounts()
end

-- ================================================================ practice
function MatchService.practiceStart(player, levelKey)
	if not Config.levelByKey(levelKey) or inMatch[player] then
		return
	end
	MatchService.leaveQueue(player)
	practice[player] = {
		levelKey = levelKey,
		streak = 0,
		exclude = {},
		active = true,
		questionId = 0,
	}
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
	st.questionId = st.questionId + 1
	st.started = os.clock()
	st.deadline = st.started + 20
	send(player, "practiceQ", {
		questionId = st.questionId, prompt = q.p, isKanji = (#q.p == 1), choices = choices,
		timeLimit = 20, streak = st.streak, levelKey = st.levelKey,
	})
end

function MatchService.practiceSubmit(player, idx)
	local st = practice[player]
	if not st or not st.active or not st.correct or os.clock() > st.deadline + Config.QUESTION_GRACE then
		return
	end
	local ok = idx == st.correct
	local correctIdx = st.correct
	if ok then
		st.streak = st.streak + 1
	else
		st.streak = 0
	end
	StatsService.recordAnswer(player, ok, math.max(0, os.clock() - st.started))
	StatsService.awardPractice(player, ok)
	st.correct = nil
	send(player, "practiceResult", { correct = ok, correctIdx = correctIdx, streak = st.streak })
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

-- ================================================================ router
function MatchService.onRemote(player, data)
	if type(data) ~= "table" or type(data.action) ~= "string" then
		return
	end
	local a = data.action
	if a == "queue" and type(data.levelKey) == "string" then
		MatchService.joinQueue(player, data.levelKey)
	elseif a == "cancelQueue" then
		MatchService.leaveQueue(player)
	elseif a == "submit" then
		local match = inMatch[player]
		local q = match and match.activeQuestion
		if q and q.round == data.round and (data.questionId == nil or q.id == data.questionId) and not match.answers[player]
			and type(data.idx) == "number" and os.clock() <= q.deadline + Config.QUESTION_GRACE then
			local idx = math.floor(data.idx)
			if idx >= 1 and idx <= 4 then
				match.answers[player] = { idx = idx, t = os.clock() }
				match.answerCount = match.answerCount + 1
			end
		end
	elseif a == "useSkill" and type(data.skill) == "string" then
		MatchService.useSkill(player, data.skill)
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
	elseif a == "setLocale" and type(data.locale) == "string" then
		StatsService.setLocale(player, data.locale, data.source)
	end
end

Players.PlayerRemoving:Connect(function(player)
	MatchService.leaveQueue(player)
	MatchService.practiceStop(player)
	local match = inMatch[player]
	if match and not match.dead and not match.finished then
		local other = match.players[1] == player and match.players[2] or match.players[1]
		if other and other.Parent then
			match.dead = true
			local delta = StatsService.applyResult(match.levelKey, other, player)
			local reward = StatsService.awardMatch(other, true, playerState(match, other).bestCombo,
				playerState(match, other).correct, playerState(match, other).answered)
			local profile = StatsService.get(other)
			send(other, "matchEnd", {
				win = true, reason = "leave", opponent = player.DisplayName,
				rating = profile.ratings[match.levelKey], delta = delta,
				wins = profile.wins, losses = profile.losses, streak = profile.streak,
				summary = MatchService.summaryFor(match, other), reward = reward,
			})
			task.delay(3, function()
				MatchService.endMatch(match, other)
			end)
		end
	end
end)

return MatchService
