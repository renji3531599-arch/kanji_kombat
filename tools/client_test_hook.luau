-- tools/test_luau.py がクライアントのソース末尾に足して読み込む、テスト用の覗き窓
-- (実機では使われない。UIに実際に表示された文字列を検証するためだけのもの)
return {
	getLocale = function() return I18n.getLocale() end,
	levelCard = function(key) return levelCards[key] end,
	choiceText = function(i)
		if not choiceButtons[i] then
			return nil
		end
		return choiceButtons[i].main.Text, choiceButtons[i].sub.Text
	end,
	choiceColor = function(i) return choiceButtons[i].button.BackgroundColor3 end,
	hint = function() return promptHint.Text end,
	round = function() return roundLbl.Text end,
	status = function() return T.status.Text end,
	profile = function() return T.profileChip.Text end,
	battle = function() return battle.Visible, promptText.Text end,
	practice = function() return pracTitle.Text, pracStreak.Text, pracFeedback.Text end,
	result = function() return resultTitle.Text, resultDetail.Text end,
	splash = function() return splashTitle.Text, splashSub.Text end,
}
