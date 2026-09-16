--!nocheck
-- かな → ローマ字 (ヘボン式ベース / 長音は母音を重ねる wāpuro 式)
-- 英語圏プレイヤー向けに読みの選択肢を "きょうしゅう / kyoushuu" のように併記するために使う。
-- utf8 ライブラリに依存しない実装 (LuaJIT / Luau 両対応) — テストは tools/test_luau.py から実行。

local Romaji = {}

local BASE = {
	["あ"] = "a", ["い"] = "i", ["う"] = "u", ["え"] = "e", ["お"] = "o",
	["か"] = "ka", ["き"] = "ki", ["く"] = "ku", ["け"] = "ke", ["こ"] = "ko",
	["が"] = "ga", ["ぎ"] = "gi", ["ぐ"] = "gu", ["げ"] = "ge", ["ご"] = "go",
	["さ"] = "sa", ["し"] = "shi", ["す"] = "su", ["せ"] = "se", ["そ"] = "so",
	["ざ"] = "za", ["じ"] = "ji", ["ず"] = "zu", ["ぜ"] = "ze", ["ぞ"] = "zo",
	["た"] = "ta", ["ち"] = "chi", ["つ"] = "tsu", ["て"] = "te", ["と"] = "to",
	["だ"] = "da", ["ぢ"] = "ji", ["づ"] = "zu", ["で"] = "de", ["ど"] = "do",
	["な"] = "na", ["に"] = "ni", ["ぬ"] = "nu", ["ね"] = "ne", ["の"] = "no",
	["は"] = "ha", ["ひ"] = "hi", ["ふ"] = "fu", ["へ"] = "he", ["ほ"] = "ho",
	["ば"] = "ba", ["び"] = "bi", ["ぶ"] = "bu", ["べ"] = "be", ["ぼ"] = "bo",
	["ぱ"] = "pa", ["ぴ"] = "pi", ["ぷ"] = "pu", ["ぺ"] = "pe", ["ぽ"] = "po",
	["ま"] = "ma", ["み"] = "mi", ["む"] = "mu", ["め"] = "me", ["も"] = "mo",
	["や"] = "ya", ["ゆ"] = "yu", ["よ"] = "yo",
	["ら"] = "ra", ["り"] = "ri", ["る"] = "ru", ["れ"] = "re", ["ろ"] = "ro",
	["わ"] = "wa", ["ゐ"] = "i", ["ゑ"] = "e", ["を"] = "o", ["ん"] = "n",
	["ゔ"] = "vu",
	["ぁ"] = "a", ["ぃ"] = "i", ["ぅ"] = "u", ["ぇ"] = "e", ["ぉ"] = "o",
	["ゃ"] = "ya", ["ゅ"] = "yu", ["ょ"] = "yo", ["ゎ"] = "wa",
	-- カタカナ (データは基本ひらがなだが一応)
	["ア"] = "a", ["イ"] = "i", ["ウ"] = "u", ["エ"] = "e", ["オ"] = "o",
	["カ"] = "ka", ["キ"] = "ki", ["ク"] = "ku", ["ケ"] = "ke", ["コ"] = "ko",
	["サ"] = "sa", ["シ"] = "shi", ["ス"] = "su", ["セ"] = "se", ["ソ"] = "so",
	["タ"] = "ta", ["チ"] = "chi", ["ツ"] = "tsu", ["テ"] = "te", ["ト"] = "to",
	["ナ"] = "na", ["ニ"] = "ni", ["ヌ"] = "nu", ["ネ"] = "ne", ["ノ"] = "no",
	["ハ"] = "ha", ["ヒ"] = "hi", ["フ"] = "fu", ["ヘ"] = "he", ["ホ"] = "ho",
	["マ"] = "ma", ["ミ"] = "mi", ["ム"] = "mu", ["メ"] = "me", ["モ"] = "mo",
	["ヤ"] = "ya", ["ユ"] = "yu", ["ヨ"] = "yo",
	["ラ"] = "ra", ["リ"] = "ri", ["ル"] = "ru", ["レ"] = "re", ["ロ"] = "ro",
	["ワ"] = "wa", ["ヲ"] = "o", ["ン"] = "n",
}

local COMBO = {
	["きゃ"] = "kya", ["きゅ"] = "kyu", ["きょ"] = "kyo",
	["ぎゃ"] = "gya", ["ぎゅ"] = "gyu", ["ぎょ"] = "gyo",
	["しゃ"] = "sha", ["しゅ"] = "shu", ["しょ"] = "sho",
	["じゃ"] = "ja", ["じゅ"] = "ju", ["じょ"] = "jo",
	["ちゃ"] = "cha", ["ちゅ"] = "chu", ["ちょ"] = "cho",
	["ぢゃ"] = "ja", ["ぢゅ"] = "ju", ["ぢょ"] = "jo",
	["にゃ"] = "nya", ["にゅ"] = "nyu", ["にょ"] = "nyo",
	["ひゃ"] = "hya", ["ひゅ"] = "hyu", ["ひょ"] = "hyo",
	["びゃ"] = "bya", ["びゅ"] = "byu", ["びょ"] = "byo",
	["ぴゃ"] = "pya", ["ぴゅ"] = "pyu", ["ぴょ"] = "pyo",
	["みゃ"] = "mya", ["みゅ"] = "myu", ["みょ"] = "myo",
	["りゃ"] = "rya", ["りゅ"] = "ryu", ["りょ"] = "ryo",
	["ふぁ"] = "fa", ["ふぃ"] = "fi", ["ふぇ"] = "fe", ["ふぉ"] = "fo",
	["うぃ"] = "wi", ["うぇ"] = "we", ["うぉ"] = "wo",
	["しぇ"] = "she", ["じぇ"] = "je", ["ちぇ"] = "che",
	["てぃ"] = "ti", ["でぃ"] = "di", ["とぅ"] = "tu", ["どぅ"] = "du",
	["つぁ"] = "tsa", ["つぃ"] = "tsi", ["つぇ"] = "tse", ["つぉ"] = "tso",
	["ゔぁ"] = "va", ["ゔぃ"] = "vi", ["ゔぇ"] = "ve", ["ゔぉ"] = "vo",
}

-- 同じ発音になるかな (じ/ぢ など) の衝突回避用の代替表記
local ALT = { ["ぢ"] = "di", ["づ"] = "du" }
local ALT_COMBO = { ["ぢゃ"] = "dya", ["ぢゅ"] = "dyu", ["ぢょ"] = "dyo" }

local SMALL = {
	["ぁ"] = true, ["ぃ"] = true, ["ぅ"] = true, ["ぇ"] = true, ["ぉ"] = true,
	["ゃ"] = true, ["ゅ"] = true, ["ょ"] = true, ["ゎ"] = true,
}
local VOWELS = { a = true, i = true, u = true, e = true, o = true }
local N_APOSTROPHE = {
	["あ"] = true, ["い"] = true, ["う"] = true, ["え"] = true, ["お"] = true,
	["や"] = true, ["ゆ"] = true, ["よ"] = true,
	["ぁ"] = true, ["ぃ"] = true, ["ぅ"] = true, ["ぇ"] = true, ["ぉ"] = true,
	["ゃ"] = true, ["ゅ"] = true, ["ょ"] = true,
}

-- UTF-8 文字列を1文字ずつのテーブルに分解 (utf8 ライブラリ非依存)
local function chars(s)
	local out, i, n = {}, 1, #s
	while i <= n do
		local b = string.byte(s, i)
		local len = 1
		if b >= 0xF0 then
			len = 4
		elseif b >= 0xE0 then
			len = 3
		elseif b >= 0xC0 then
			len = 2
		end
		out[#out + 1] = string.sub(s, i, i + len - 1)
		i = i + len
	end
	return out
end

-- i 番目 (1始まり) の音節を返す: romaji, 消費した文字数
local function syllable(cs, i, alt)
	local two = cs[i + 1] and (cs[i] .. cs[i + 1]) or nil
	if two then
		local c = (alt and ALT_COMBO[two]) or COMBO[two]
		if c then
			return c, 2
		end
	end
	local ch = cs[i]
	if ch == "ん" then
		local nxt = cs[i + 1]
		if nxt and N_APOSTROPHE[nxt] then
			return "n'", 1
		end
		return "n", 1
	end
	if alt and ALT[ch] then
		return ALT[ch], 1
	end
	return BASE[ch] or ch, 1
end

-- かな文字列 → ローマ字
function Romaji.convert(kana, alt)
	if type(kana) ~= "string" or kana == "" then
		return kana or ""
	end
	local cs = chars(kana)
	local out = {}
	local i, n = 1, #cs
	while i <= n do
		local c = cs[i]
		if c == "っ" or c == "ッ" then
			local nxt = cs[i + 1]
			if nxt and not SMALL[nxt] and nxt ~= "ー" and nxt ~= "っ" and nxt ~= "ッ" then
				local r = syllable(cs, i + 1, alt)
				if r and r ~= "" then
					if string.sub(r, 1, 2) == "ch" then
						out[#out + 1] = "t" -- 抹茶 = matcha
					else
						local k = string.sub(r, 1, 1)
						if not VOWELS[k] then
							if k == "n" and alt then
								-- なんにゅう (nannyuu) と なっにゅう (nannyuu) の区別
								out[#out + 1] = "n'"
							else
								out[#out + 1] = k -- じゅっもく = jummoku (促音の重ね)
							end
						end
					end
				end
			end
			i = i + 1
		elseif c == "ー" then
			local prev = table.concat(out)
			local v = ""
			for j = #prev, 1, -1 do
				local ch = string.sub(prev, j, j)
				if VOWELS[ch] then
					v = ch
					break
				end
			end
			out[#out + 1] = v -- らーめん = raamen
			i = i + 1
		else
			local r, used = syllable(cs, i, alt)
			out[#out + 1] = r
			i = i + used
		end
	end
	return table.concat(out)
end

-- 選択肢4つのように「並べたときに重複しない」ローマ字を返す (例: じ / ぢ → ji / di)
function Romaji.convertMany(list)
	local out, used = {}, {}
	for i = 1, #list do
		local r = Romaji.convert(list[i])
		if used[r] then
			-- 1) 先に出た同表記のものを代替表記へ移せないか (なっにゅう = nan'nyuu)
			for j = 1, i - 1 do
				if out[j] == r then
					local alt = Romaji.convert(list[j], true)
					if alt ~= r and not used[alt] then
						out[j] = alt
						used[alt] = true
						used[r] = nil
						break
					end
				end
			end
		end
		if used[r] then
			-- 2) 自分を代替表記にする (ぢ = di / づ = du)
			local alt = Romaji.convert(list[i], true)
			if alt ~= r and not used[alt] then
				r = alt
			end
		end
		out[i] = r
		used[r] = true
	end
	return out
end

return Romaji
