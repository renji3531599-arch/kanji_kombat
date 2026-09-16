--!nonstrict
-- 問題バンク: ServerScriptService.KanjiKombat.Data の12レベル分の問題を読み込む
local QuestionBank = {}

local dataFolder = script.Parent.Parent:WaitForChild("Data")

local banks = {}
local order = { "K10", "K09", "K08", "K07", "K06", "K05", "K04", "K03", "KP2", "K02", "KP1", "K01" }

for _, key in ipairs(order) do
	local mod = dataFolder:WaitForChild("Questions_" .. key)
	local ok, result = pcall(require, mod)
	if ok and type(result) == "table" then
		banks[key] = result
	else
		warn("[QuestionBank] failed to load " .. key)
		banks[key] = {}
	end
end

-- levelKey の問題を1問引く (exclude 内のプロンプトは避ける)
function QuestionBank.draw(levelKey, exclude)
	local bank = banks[levelKey]
	if not bank or #bank == 0 then
		return nil
	end
	exclude = exclude or {}
	for _ = 1, 12 do
		local q = bank[math.random(#bank)]
		if not exclude[q.p] then
			exclude[q.p] = true
			return q
		end
	end
	-- 見つからなければ重複を許容
	local q = bank[math.random(#bank)]
	exclude[q.p] = true
	return q
end

-- 選択肢をシャッフルして正解インデックスを返す (1-4)
function QuestionBank.pack(q)
	local choices = { q.a, q.d[1], q.d[2], q.d[3] }
	for i = #choices, 2, -1 do
		local j = math.random(i)
		choices[i], choices[j] = choices[j], choices[i]
	end
	local correct = 1
	for i, c in ipairs(choices) do
		if c == q.a then
			correct = i
			break
		end
	end
	return choices, correct
end

function QuestionBank.count(levelKey)
	return banks[levelKey] and #banks[levelKey] or 0
end

return QuestionBank
