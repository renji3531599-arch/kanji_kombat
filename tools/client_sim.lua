--!nocheck
-- Roblox API のモック (ヘッドレス環境でクライアントを走らせるスモークテスト用)
--
-- tools/test_luau.py から呼ばれる:
--   * Instance / UDim2 / Color3 / Enum ... を「何でも生える」モックに置き換える
--   * クライアントスクリプトを実行し、サーバー→クライアントのメッセージを流し込む
--   * _G を見て、ロケール判定 → 描画 → 言語切替 → 再度描画 が落ちないか検証する
--
-- 本物の Roblox ではなく「Lua としての妥当性」だけを見るテスト。

local sim = {}

local connections, sent, errors, feed_log = {}, {}, {}, {}

local mock_mt = {}

local function newmock(name)
	return setmetatable({ __name = name }, mock_mt)
end

local function record_error(where, err)
	errors[#errors + 1] = tostring(where) .. ': ' .. tostring(err)
end

mock_mt.__index = function(self, k)
	if k == "Connect" then
		local f = function(sig, cb)
			local info = debug.getinfo(cb, "S")
			connections[#connections + 1] = {
				fn = cb,
				line = (info and info.linedefined) or -1,
				signal = tostring(rawget(sig, "__name")),
			}
			return newmock("Connection")
		end
		rawset(self, k, f)
		return f
	elseif k == "WaitForChild" or k == "FindFirstChild" or k == "FindFirstChildOfClass" then
		local f = function(obj, child)
			local have = rawget(obj, child)
			if have ~= nil then
				return have
			end
			if __mods[child] ~= nil then
				return __mods[child] -- ModuleScript (UiKit / GameConfig / ...)
			end
			local made = newmock(tostring(child))
			rawset(obj, child, made)
			return made
		end
		rawset(self, k, f)
		return f
	elseif k == "Play" or k == "Destroy" or k == "Stop" or k == "Pause" then
		local f = function() end
		rawset(self, k, f)
		return f
	elseif k == "GetChildren" or k == "GetPlayers" or k == "GetDescendants" then
		local f = function() return {} end
		rawset(self, k, f)
		return f
	end
	local v = newmock(tostring(k))
	rawset(self, k, v)
	return v
end
mock_mt.__call = function() return newmock("call") end
mock_mt.__newindex = function(self, k, v) rawset(self, k, v) end
mock_mt.__tostring = function(self) return tostring(rawget(self, "__name") or "mock") end

-- ---------------------------------------------------------------- globals
local function install()
	local Players, ReplicatedStorage, LocalizationService, TweenService, SoundService
	local player

	local profile = {
		ratings = { K10 = 1234, K01 = 1000 },
		wins = 3, losses = 1, streak = 2, bestStreak = 5,
		locale = nil,
	}

	local remotes = newmock("Remotes")
	remotes.ServerToClient = newmock("ServerToClient")
	remotes.ClientToServer = newmock("ClientToServer")
	remotes.ClientToServer.FireServer = function(_, data)
		sent[#sent + 1] = data
	end
	remotes.GetProfile = newmock("GetProfile")
	remotes.GetProfile.InvokeServer = function() return profile end

	ReplicatedStorage = newmock("ReplicatedStorage")
	ReplicatedStorage.Remotes = remotes

	player = newmock("Player")
	player.LocaleId = sim.locale or "en-us"
	player.DisplayName = "Tester"

	Players = newmock("Players")
	Players.LocalPlayer = player

	LocalizationService = newmock("LocalizationService")
	LocalizationService.RobloxLocaleId = sim.locale or "en-us"

	TweenService = newmock("TweenService")
	TweenService.Create = function(_, obj, info, props) return newmock("Tween") end

	SoundService = newmock("SoundService")

	local services = {
		Players = Players,
		ReplicatedStorage = ReplicatedStorage,
		LocalizationService = LocalizationService,
		TweenService = TweenService,
		SoundService = SoundService,
	}
	_G.game = {
		GetService = function(_, name) return services[name] or newmock(name) end,
		BindToClose = function() end,
	}
	_G.workspace = newmock("Workspace")
	_G.workspace.CurrentCamera = newmock("Camera")
	_G.workspace.CurrentCamera.ViewportSize = { X = 1280, Y = 720 }

	_G.Instance = { new = function(cls) return newmock(cls) end }
	_G.UDim = { new = function(x, y) return { Scale = x, Offset = y } end }
	_G.UDim2 = {
		new = function(xs, xo, ys, yo) return { X = { Scale = xs, Offset = xo }, Y = { Scale = ys, Offset = yo } } end,
		fromOffset = function(x, y) return { X = { Offset = x }, Y = { Offset = y } } end,
		fromScale = function(x, y) return { X = { Scale = x }, Y = { Scale = y } } end,
	}
	_G.Vector2 = { new = function(x, y) return { X = x, Y = y } end }
	_G.Color3 = { fromRGB = function(r, g, b) return { R = r, G = g, B = b } end }
	_G.ColorSequence = { new = function() return {} end }
	_G.CFrame = { new = function() return {} end, Angles = function() return {} end }
	_G.Enum = newmock("Enum")
	_G.TweenInfo = { new = function() return {} end }
	_G.task = {
		spawn = function(f, ...)
			local ok, err = pcall(f, ...)
			if not ok then
				record_error("task.spawn", err)
			end
		end,
		delay = function(_, f, ...)
			local ok, err = pcall(f, ...)
			if not ok then
				record_error("task.delay", err)
			end
		end,
		defer = function() end,
		wait = function() end,
	}
	if math.clamp == nil then -- LuaJIT には Luau の math.clamp が無い
		math.clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end
	end

	-- ModuleScript の require スタブ
	_G.script = newmock("script")
	_G.script.Parent = newmock("Parent")
	_G.require = function(mod) return mod end
end

-- ---------------------------------------------------------------- helpers
local function expect(label, got, want)
	if tostring(got) ~= tostring(want) then
		record_error(label, string.format("got %q, want %q", tostring(got), tostring(want)))
	end
end

local function contains(label, got, want)
	if type(got) ~= "string" or got:find(want, 1, true) == nil then
		record_error(label, string.format("got %q, expected it to contain %q", tostring(got), tostring(want)))
	end
end

local function hook()
	return sim.hook
end

local function is_en()
	return hook() and hook().getLocale() == "en"
end

local function call_line(line, ...)
	local found = false
	for _, c in ipairs(connections) do
		if c.line == line then
			found = true
			local ok, err = pcall(c.fn, ...)
			if not ok then
				record_error(string.format("handler@%d(%s)", line, c.signal), err)
			end
		end
	end
	if not found then
		record_error(string.format("handler@%d", line), "not connected")
	end
	return found
end

local function feed(line, payload)
	feed_log[#feed_log + 1] = payload.action or "?"
	return call_line(line, payload)
end

local function drive(lines, tag)
	local H = hook()
	-- 1) レベルを選んで対戦エントリー
	call_line(lines.level)
	expect("level card title (" .. tag .. ")", H.levelCard("K10").title.Text, is_en() and "Level 10" or "10級")
	if is_en() then
		contains("level card desc (" .. tag .. ")", H.levelCard("K10").desc.Text, "JLPT N5")
	end
	contains("status (" .. tag .. ")", H.status(), is_en() and "Selected" or "選択中")
	call_line(lines.battle)
	contains("searching status (" .. tag .. ")", H.status(), is_en() and "Searching" or "マッチング中")
	feed(lines.s2c, { action = "queue", K10 = 3 })
	feed(lines.s2c, { action = "toast", key = "toastSearching", args = { level = "K10" } })
	feed(lines.s2c, { action = "matchIntro", levelKey = "K10", opponent = "Robo", total = 10 })
	-- 2) 対戦 (通常問題 → 誤答、じ/ぢ のローマ字衝突問題 → 正答、サドンデス、結果)
	feed(lines.s2c, {
		action = "question", round = 1, total = 10, sudden = false, prompt = "十目", isKanji = false,
		choices = { "じゅうもく", "じゅっもく", "すいでん", "だいえん" }, timeLimit = 12, hpMe = 100, hpOp = 80,
	})
	expect("round label (" .. tag .. ")", H.round(), "ROUND 1/10")
	local main, sub = H.choiceText(1)
	if is_en() then
		expect("choice is romaji (" .. tag .. ")", main, "juumoku")
		expect("choice shows kana (" .. tag .. ")", sub, "じゅうもく")
	else
		expect("choice is kana (" .. tag .. ")", main, "じゅうもく")
		expect("no kana sub-label (" .. tag .. ")", sub, "")
	end
	call_line(lines.choice)
	feed(lines.s2c, {
		action = "answerResult", round = 1, correct = false, correctIdx = 1, myIdx = 2,
		dealt = 0, taken = 20, hpMe = 80, hpOp = 80,
	})
	contains("wrong-answer hint (" .. tag .. ")", H.hint(), is_en() and "juumoku" or "じゅうもく")
	contains("wrong-answer hint label (" .. tag .. ")", H.hint(), is_en() and "Missed" or "ざんねん")
	feed(lines.s2c, {
		action = "question", round = 2, total = 10, sudden = false, prompt = "痔瘻", isKanji = false,
		choices = { "じろう", "ぢろう", "かかん", "きたん" }, timeLimit = 12, hpMe = 80, hpOp = 60,
	})
	if is_en() then
		-- じ / ぢ が同じ表記にならないこと
		expect("ji/di 1 (" .. tag .. ")", select(1, H.choiceText(1)), "jirou")
		expect("ji/di 2 (" .. tag .. ")", select(1, H.choiceText(2)), "dirou")
	end
	feed(lines.s2c, {
		action = "answerResult", round = 2, correct = true, correctIdx = 1, myIdx = 1,
		dealt = 20, taken = 0, hpMe = 80, hpOp = 40,
	})
	feed(lines.s2c, {
		action = "question", round = 11, total = 10, sudden = true, prompt = "空", isKanji = true,
		choices = { "から", "そら", "あき", "くう" }, timeLimit = 12, hpMe = 20, hpOp = 20,
	})
	feed(lines.s2c, {
		action = "matchEnd", win = true, reason = "KO", opponent = "Robo",
		rating = 1016, delta = 16, wins = 4, losses = 1, streak = 3,
	})
	do
		local title, detail = H.result()
		expect("win title (" .. tag .. ")", title, is_en() and "YOU WIN!" or "WIN！")
		contains("result detail (" .. tag .. ")", detail, "1016")
	end
	feed(lines.s2c, { action = "matchEnd", draw = true })
	feed(lines.s2c, { action = "toLobby" })
	-- 3) 練習モード
	call_line(lines.practice)
	contains("practice title (" .. tag .. ")", select(1, H.practice()), is_en() and "Practice Mode" or "練習モード")
	feed(lines.s2c, {
		action = "practiceQ", prompt = "十目", isKanji = false,
		choices = { "じゅうもく", "じゅっもく", "すいでん", "だいえん" }, timeLimit = 20, streak = 0, levelKey = "K10",
	})
	feed(lines.s2c, { action = "practiceResult", correct = true, correctIdx = 3, streak = 1 })
	feed(lines.s2c, {
		action = "practiceQ", prompt = "痔瘻", isKanji = false,
		choices = { "じろう", "ぢろう", "かかん", "きたん" }, timeLimit = 20, streak = 1, levelKey = "K10",
	})
	feed(lines.s2c, { action = "practiceResult", correct = false, correctIdx = 2, streak = 0 })
	call_line(lines.exit)
	-- 4) キャンセル / ロビー戻り (旧形式の msg トーストも一応)
	call_line(lines.cancel)
	call_line(lines.result)
	feed(lines.s2c, { action = "toast", msg = "legacy message" })
end

-- ---------------------------------------------------------------- entry point
-- sim.run_all(client_src, s2c, toggle, level, battle, practice, cancel, exit, result, choice)
function sim.run_all(client_src, l_s2c, l_toggle, l_level, l_battle, l_practice, l_cancel, l_exit, l_result, l_choice)
	local lines = {
		s2c = l_s2c, toggle = l_toggle, level = l_level, battle = l_battle,
		practice = l_practice, cancel = l_cancel, exit = l_exit,
		result = l_result, choice = l_choice,
	}
	local locale_text = {}

	for _, locale in ipairs({ "en-us", "ja-jp" }) do
		-- 実行環境を作り直す (ロケール自動判定の両パターンを確認)
		connections, sent = {}, {}
		local before = #errors
		sim.locale = locale
		install()

		sim.hook = nil
		local fn, err = load(client_src, "@client")
		if not fn then
			record_error("load", err)
		else
			local ok, res = pcall(fn)
			if not ok then
				record_error("client init (" .. locale .. ")", res)
			else
				sim.hook = res
				-- 起動直後は端末ロケールで自動判定されているはず
				expect("auto locale (" .. locale .. ")", sim.hook.getLocale(), locale:sub(1, 2))
				expect("splash title (" .. locale .. ")", select(1, sim.hook.splash()),
					__mods.I18n.raw("title", locale:sub(1, 2)))
				-- 🌐 ボタンで切り替えてから、もう一度ひと通り操作する
				drive(lines, "auto")
				call_line(l_toggle)
				expect("toggled locale (" .. locale .. ")", sim.hook.getLocale(),
					locale:sub(1, 2) == "en" and "ja" or "en")
				drive(lines, "toggled")
			end
		end

		local I18n = __mods and __mods.I18n
		local locale_now = I18n and I18n.getLocale() or "?"
		locale_text[#locale_text + 1] = string.format(
			"device locale %s -> auto UI %s -> after toggle %s (%d connections, %d messages sent, %d errors)",
			locale, locale:sub(1, 2), locale_now, #connections, #sent, #errors - before)
	end

	return table.concat(locale_text, "\n"), table.concat(errors, "\n")
end

return sim
