--!nocheck
-- サーバーをヘッドレスで起動するスモークテスト (tools/test_luau.py から呼ばれる)
--
-- client_sim.lua は「サーバー役」を演じて S2C を手で流し込むため、
-- サーバー側の配線が壊れていても何も検出できない。
-- こちらは Main.server.luau を実際に起動し、クライアント役として C2S を発火して
-- 「サーバーが本当に応答を返すか」を検証する。
--   * 練習モード: practiceStart → practiceQ が届くか / 正答で次の問題が出るか
--   * 対戦: queue x2 → マッチして question → submit → answerResult → matchEnd
-- (「練習で問題が1問も表示されない」ような配線ミスを捕まえるためのもの)

local sim = {}

-- LuaJIT (5.1) と Lua 5.2+ のどちらでも動くように
local unpack = unpack or table.unpack

local function inCoroutine()
	local co, isMain = coroutine.running()
	if co == nil then
		return false -- Lua 5.1: メインスレッドでは nil
	end
	if isMain ~= nil then
		return not isMain -- Lua 5.2+: 2つ目の戻り値が main かどうか
	end
	return true
end

local errors = {}
local prints = {}
local connections = {}
local threads = {}
local delays = {}
local inbox = {}       -- [player] = { data, ... }  サーバー→クライアントの送信ログ
local pending = {}     -- 読み込むモジュール { name = ..., src = ... }
local vtime = 0        -- 仮想クロック (task.wait で進む。os.clock はこれを返す)

sim.players = {}

local function record(where, err)
	errors[#errors + 1] = tostring(where) .. ': ' .. tostring(err)
end

local function expect(label, got, want)
	if tostring(got) ~= tostring(want) then
		record(label, string.format('got %s, want %s', tostring(got), tostring(want)))
	end
end

-- ---------------------------------------------------------------- mock instance
local mock_mt = {}

local function newmock(name)
	return setmetatable({ __name = name }, mock_mt)
end

local function onFireClient(player, data)
	inbox[player] = inbox[player] or {}
	local list = inbox[player]
	list[#list + 1] = data
	if sim.onSend then
		local ok, err = pcall(sim.onSend, player, data)
		if not ok then
			record('onSend', err)
		end
	end
end

mock_mt.__index = function(self, k)
	if k == 'Connect' then
		local f = function(sig, cb)
			connections[#connections + 1] = {
				fn = cb,
				signal = tostring(rawget(sig, '__name')),
				line = (debug.getinfo(cb, 'S') or {}).linedefined or -1,
			}
			return newmock('Connection')
		end
		rawset(self, k, f)
		return f
	elseif k == 'WaitForChild' or k == 'FindFirstChild' or k == 'FindFirstChildOfClass' then
		local f = function(obj, child)
			local have = rawget(obj, child)
			if have ~= nil then
				return have
			end
			if __mods[child] ~= nil then
				return __mods[child] -- ModuleScript (GameConfig / Questions_K10 / ...)
			end
			local made = newmock(tostring(child))
			rawset(obj, child, made)
			return made
		end
		rawset(self, k, f)
		return f
	elseif k == 'FireClient' then
		local f = function(_, player, data)
			onFireClient(player, data)
		end
		rawset(self, k, f)
		return f
	elseif k == 'GetPlayers' then
		local f = function()
			return sim.players
		end
		rawset(self, k, f)
		return f
	elseif k == 'GetChildren' or k == 'GetDescendants' then
		local f = function() return {} end
		rawset(self, k, f)
		return f
	end
	local v = newmock(tostring(k))
	rawset(self, k, v)
	return v
end
mock_mt.__call = function() return newmock('call') end
mock_mt.__newindex = function(self, k, v) rawset(self, k, v) end
mock_mt.__tostring = function(self) return tostring(rawget(self, '__name') or 'mock') end

-- ---------------------------------------------------------------- scheduler
local function spawn(f, ...)
	local th = { co = coroutine.create(f), args = { ... } }
	threads[#threads + 1] = th
	return th
end

local function pump(maxSteps)
	for _ = 1, (maxSteps or 400) do
		local any = false
		for i = 1, #threads do
			local th = threads[i]
			if not th.done then
				any = true
				local ok, err
				if th.started then
					ok, err = coroutine.resume(th.co)
				else
					th.started = true
					ok, err = coroutine.resume(th.co, unpack(th.args))
				end
				if not ok then
					th.done = true
					record('server coroutine', err)
				elseif coroutine.status(th.co) == 'dead' then
					th.done = true
				end
			end
		end
		for i = #delays, 1, -1 do
			if delays[i].at <= vtime then
				local d = table.remove(delays, i)
				spawn(d.f, unpack(d.args))
				any = true
			end
		end
		if not any then
			break
		end
	end
end

-- ---------------------------------------------------------------- globals
function sim.install()
	errors, prints, connections, threads, delays, inbox = {}, {}, {}, {}, {}, {}
	sim.players = {}
	vtime = 0

	local services = {}
	local Players = newmock('Players')
	Players.LocalPlayer = nil
	services.Players = Players
	services.ReplicatedStorage = newmock('ReplicatedStorage')
	services.ServerScriptService = newmock('ServerScriptService')
	services.ServerStorage = newmock('ServerStorage')
	services.DataStoreService = newmock('DataStoreService')
	services.RunService = newmock('RunService')
	services.Lighting = newmock('Lighting')

	_G.game = {
		GetService = function(_, name)
			if services[name] == nil then
				services[name] = newmock(name)
			end
			return services[name]
		end,
		BindToClose = function() end,
	}
	_G.workspace = newmock('Workspace')
	_G.Instance = { new = function(cls) return newmock(cls) end }
	_G.Vector3 = { new = function(x, y, z) return { X = x, Y = y, Z = z } end }
	_G.UDim2 = { fromScale = function() return {} end, fromOffset = function() return {} end, new = function() return {} end }
	_G.Color3 = { fromRGB = function() return {} end }
	local cframeMt = { __mul = function(a) return a end }
	_G.CFrame = {
		new = function() return setmetatable({}, cframeMt) end,
		Angles = function() return setmetatable({}, cframeMt) end,
	}
	_G.Enum = newmock('Enum')
	_G.task = {
		spawn = function(f, ...) return spawn(f, ...) end,
		defer = function(f, ...) return spawn(f, ...) end,
		delay = function(n, f, ...)
			delays[#delays + 1] = { at = vtime + (tonumber(n) or 0), f = f, args = { ... } }
		end,
		wait = function(n)
			vtime = vtime + (tonumber(n) or 0)
			if inCoroutine() then
				coroutine.yield()
			end
		end,
	}
	_G.print = function(...)
		local parts = {}
		for i = 1, select('#', ...) do
			parts[i] = tostring((select(i, ...)))
		end
		prints[#prints + 1] = table.concat(parts, ' ')
	end
	_G.warn = function(...)
		local parts = {}
		for i = 1, select('#', ...) do
			parts[i] = tostring((select(i, ...)))
		end
		record('warn', table.concat(parts, ' '))
	end
	-- os.clock を仮想クロックに (対戦の制限時間ループをヘッドレスで回すため)
	local realOs = os
	_G.os = setmetatable({
		clock = function() return vtime end,
		time = function() return 0 end,
	}, { __index = realOs })
	if math.clamp == nil then -- LuaJIT には Luau の math.clamp が無い
		math.clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end
	end
end

-- ---------------------------------------------------------------- module loader
function sim.add(name, src)
	pending[#pending + 1] = { name = name, src = src }
end

local function loadModule(name, src)
	_G.script = newmock(name)
	local fn, err = load(src, '@' .. name)
	if not fn then
		record('load ' .. name, err)
		return nil
	end
	local ok, mod = pcall(fn)
	if not ok then
		record('run ' .. name, mod)
		return nil
	end
	__mods[name] = mod
	return mod
end

-- ---------------------------------------------------------------- helpers
local function findConnection(signal)
	for i = #connections, 1, -1 do
		if connections[i].signal == signal then
			return connections[i]
		end
	end
	return nil
end

local c2sReported = false
local function fireC2S(player, data)
	local conn = findConnection('OnServerEvent')
	if not conn then
		if not c2sReported then
			c2sReported = true
			record('C2S.OnServerEvent',
				'not connected in Main.server.luau - the server ignores every client action '
				.. '(practice never starts, matching never happens)')
		end
		return false
	end
	local ok, err = pcall(conn.fn, player, data)
	if not ok then
		record('C2S handler (' .. tostring(data.action) .. ')', err)
	end
	return true
end

local function findMsg(player, action, after)
	local list = inbox[player] or {}
	for i = (after or 0) + 1, #list do
		if type(list[i]) == 'table' and list[i].action == action then
			return i, list[i]
		end
	end
	return nil
end

local function countMsg(player, action)
	local list = inbox[player] or {}
	local n = 0
	for i = 1, #list do
		if type(list[i]) == 'table' and list[i].action == action then
			n = n + 1
		end
	end
	return n
end

local userIdSeq = 100
local function newPlayer(name)
	local p = newmock('Player')
	p.Name = name
	p.DisplayName = name
	p.UserId = userIdSeq
	userIdSeq = userIdSeq + 1
	p.Parent = newmock('Players')
	sim.players[#sim.players + 1] = p
	local conn = findConnection('PlayerAdded')
	if conn then
		local ok, err = pcall(conn.fn, p)
		if not ok then
			record('PlayerAdded', err)
		end
	end
	return p
end

-- 問題バンクから正解を引き当て、選択肢の中のインデックスを返す
local function correctIndexOf(levelKey, prompt, choices)
	local bank = __mods['Questions_' .. tostring(levelKey)]
	if type(bank) ~= 'table' then
		return nil, 'no bank for ' .. tostring(levelKey)
	end
	local entry
	for _, e in ipairs(bank) do
		if e.p == prompt then
			entry = e
			break
		end
	end
	if not entry then
		return nil, 'prompt not found in bank: ' .. tostring(prompt)
	end
	for j = 1, #choices do
		if choices[j] == entry.a then
			return j
		end
	end
	return nil, 'correct reading not among the 4 choices: ' .. tostring(prompt)
end

local function wrongIndexOf(correctIdx)
	return (correctIdx == 1) and 2 or 1
end

local function checkQuestion(label, q)
	if type(q) ~= 'table' then
		record(label, 'no question payload')
		return false
	end
	expect(label .. '.prompt', type(q.prompt), 'string')
	expect(label .. '.isKanji', type(q.isKanji), 'boolean')
	if type(q.choices) ~= 'table' then
		record(label .. '.choices', 'not a table')
		return false
	end
	expect(label .. '.choices count', #q.choices, 4)
	expect(label .. '.timeLimit', type(q.timeLimit), 'number')
	for i = 1, 4 do
		if type(q.choices[i]) ~= 'string' or q.choices[i] == '' then
			record(label .. '.choices[' .. i .. ']', 'empty choice')
		end
	end
	return true
end

-- ---------------------------------------------------------------- practice
local function practiceFlow()
	local p = newPlayer('Practicer')
	if not fireC2S(p, { action = 'practiceStart', levelKey = 'K10' }) then
		return
	end

	local i, q = findMsg(p, 'practiceQ')
	if not checkQuestion('practiceQ', q) then
		record('practiceStart -> practiceQ', 'server sent no question at all')
		return
	end
	expect('practiceQ.levelKey', q.levelKey, 'K10')

	local correctIdx, why = correctIndexOf(q.levelKey, q.prompt, q.choices)
	if not correctIdx then
		record('practiceQ answer', why)
		return
	end

	-- 正答 → practiceResult(correct) と、次の問題が続けて届く
	fireC2S(p, { action = 'practiceSubmit', idx = correctIdx })
	local _, r = findMsg(p, 'practiceResult', i)
	if not r then
		record('practiceSubmit -> practiceResult', 'server sent no result')
		return
	end
	expect('practiceResult.correct', tostring(r.correct), 'true')
	expect('practiceResult.correctIdx', r.correctIdx, correctIdx)
	expect('practiceResult.streak', r.streak, 1)
	local j, q2 = findMsg(p, 'practiceQ', i)
	if not checkQuestion('2nd practiceQ', q2) then
		record('practice correct -> next question', 'server sent no next question')
		return
	end
	if q2.prompt == q.prompt then
		record('practice repeat', 'same question served twice in a row: ' .. tostring(q.prompt))
	end

	-- 誤答 → streak がリセットされ、すぐには次の問題を出さない (クライアントが practiceNext を送る)
	local wrongIdx = wrongIndexOf(select(1, correctIndexOf(q2.levelKey, q2.prompt, q2.choices)) or 1)
	fireC2S(p, { action = 'practiceSubmit', idx = wrongIdx })
	local k, r2 = findMsg(p, 'practiceResult', j)
	if not r2 then
		record('wrong practiceSubmit -> practiceResult', 'server sent no result')
		return
	end
	expect('practiceResult.correct (wrong)', tostring(r2.correct), 'false')
	expect('practiceResult.correctIdx (wrong)', r2.correctIdx,
		select(1, correctIndexOf(q2.levelKey, q2.prompt, q2.choices)))
	expect('streak reset', r2.streak, 0)
	if findMsg(p, 'practiceQ', j) then
		record('practice wrong answer', 'next question was pushed without a practiceNext request')
	end

	fireC2S(p, { action = 'practiceNext' })
	if not checkQuestion('3rd practiceQ', select(2, findMsg(p, 'practiceQ', k))) then
		record('practiceNext', 'server sent no question')
	end

	-- practiceStop 後は何も返さない
	fireC2S(p, { action = 'practiceStop' })
	local before = #(inbox[p] or {})
	fireC2S(p, { action = 'practiceSubmit', idx = 1 })
	fireC2S(p, { action = 'practiceNext' })
	expect('silent after practiceStop', #(inbox[p] or {}) - before, 0)
end

-- ---------------------------------------------------------------- battle
local function battleFlow()
	local p1 = newPlayer('Alpha')
	local p2 = newPlayer('Bravo')

	-- question が届いたら p1 は正答 / p2 は誤答を返す (実クライアントと同じ手順)
	sim.onSend = function(player, data)
		if data.action ~= 'question' then
			return
		end
		local idx, why = correctIndexOf('K10', data.prompt, data.choices)
		if not idx then
			record('question answer', why)
			return
		end
		local answer = (player == p1) and idx or wrongIndexOf(idx)
		fireC2S(player, { action = 'submit', round = data.round, idx = answer })
	end

	fireC2S(p1, { action = 'queue', levelKey = 'K10' })
	fireC2S(p2, { action = 'queue', levelKey = 'K10' })
	pump(1200) -- マッチメイキングのループ (1秒間隔) を回す
	sim.onSend = nil

	local intro1 = select(2, findMsg(p1, 'matchIntro'))
	local intro2 = select(2, findMsg(p2, 'matchIntro'))
	if not intro1 or not intro2 then
		record('queue x2 -> matchIntro', 'players were never matched')
		return
	end
	expect('matchIntro.opponent (p1)', intro1.opponent, 'Bravo')
	expect('matchIntro.opponent (p2)', intro2.opponent, 'Alpha')

	local q1 = select(2, findMsg(p1, 'question'))
	local q2 = select(2, findMsg(p2, 'question'))
	checkQuestion('battle question p1', q1)
	checkQuestion('battle question p2', q2)
	if q1 and q2 then
		expect('both players see the same prompt', q1.prompt, q2.prompt)
	end

	local a1 = select(2, findMsg(p1, 'answerResult'))
	local a2 = select(2, findMsg(p2, 'answerResult'))
	if not a1 or not a2 then
		record('submit -> answerResult', 'server sent no answer result')
		return
	end
	expect('answerResult.correct (p1 answered right)', tostring(a1.correct), 'true')
	expect('answerResult.correct (p2 answered wrong)', tostring(a2.correct), 'false')
	-- dealt/taken は「そのプレイヤーから見た」値 (p1: dealt=dmg1, taken=dmg2)
	expect('p1 dealt damage to p2', (a1.dealt or 0) > 0 and 'yes' or 'no', 'yes')
	expect('p2 took that damage', (a2.taken or 0), a1.dealt)
	expect('p1 took no damage (p2 answered wrong)', a1.taken, 0)
	expect('hp dropped for p2', a2.hpMe, a1.hpOp)
	expect('hpMe/hpOp are numbers', type(a1.hpMe) .. '/' .. type(a1.hpOp), 'number/number')

	local end1 = select(2, findMsg(p1, 'matchEnd'))
	local end2 = select(2, findMsg(p2, 'matchEnd'))
	if not end1 or not end2 then
		record('matchEnd', 'match never ended')
		return
	end
	if end1.draw or end2.draw then
		record('matchEnd', 'unexpected draw: p1 always answers correctly')
	else
		expect('matchEnd.win (p1)', tostring(end1.win), 'true')
		expect('matchEnd.win (p2)', tostring(end2.win), 'false')
		expect('matchEnd.reason', end1.reason, 'KO')
	end
	if countMsg(p1, 'question') < 2 then
		record('rounds', 'only ' .. countMsg(p1, 'question') .. ' question(s) served')
	end
	expect('toLobby (p1)', countMsg(p1, 'toLobby') > 0 and 'yes' or 'no', 'yes')
	expect('toLobby (p2)', countMsg(p2, 'toLobby') > 0 and 'yes' or 'no', 'yes')
end

-- ---------------------------------------------------------------- entry point
function sim.run()
	sim.install()
	__mods.Data = __mods.Data or newmock('Data')

	for _, m in ipairs(pending) do
		loadModule(m.name, m.src)
	end
	pump(5) -- Main の起動直後 (マッチメイキングループの1周目)

	local boot = table.concat(prints, '\n')
	if boot:find('server ready', 1, true) == nil then
		record('Main.server.luau', 'server never printed its ready line')
	end
	if boot:find('K10=1000', 1, true) == nil or boot:find('K01=1000', 1, true) == nil then
		record('Main.server.luau', 'question bank not loaded: ' .. boot)
	end

	practiceFlow()
	battleFlow()

	local practiceQuestions = 0
	for _, p in ipairs(sim.players) do
		practiceQuestions = practiceQuestions + countMsg(p, 'practiceQ')
	end

	local summary = string.format(
		'booted %d modules, %d C2S connections, %d questions served in practice, %d errors',
		#pending, #connections, practiceQuestions, #errors)
	return summary, table.concat(errors, '\n')
end

return sim
