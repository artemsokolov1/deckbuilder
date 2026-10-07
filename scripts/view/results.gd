extends Control
## Экран итогов серии: статистика, разбор атак, необязательные оценки 1–5, сравнение режимов.

var _ratings := {"clarity": 0, "football": 0, "replay": 0}
var _rating_btns := {}
var _save_btn: Button
var _saved_lb: Label


func _ready() -> void:
	theme = Game.theme
	size = Vector2(1280, 720)
	var bg := ColorRect.new()
	bg.color = Game.C_BG
	bg.size = size
	add_child(bg)
	var need: int = GameData.series()["goals_to_win"]
	var n: int = GameData.series()["attacks"]
	var goals := Game.goals()
	var result := Game.series_result()
	var win := result == "win"
	var match_mode := Game.is_match()
	var opp: Dictionary = GameData.opponent()
	var t := Label.new()
	if match_mode:
		var word: String = {"win": "ПОБЕДА", "draw": "НИЧЬЯ", "loss": "ПОРАЖЕНИЕ"}[result]
		t.text = "%s  %d : %d" % [word, goals, Game.opp_goals()]
	else:
		t.text = ("ПОБЕДА — %d из %d" if win else "Не хватило голов — %d из %d") % [goals, n]
	t.position = Vector2(40, 22)
	t.add_theme_font_size_override("font_size", 40)
	t.add_theme_color_override("font_color", Game.C_SAFE if win else (Game.C_WARN if result == "draw" or not match_mode else Game.C_DANGER))
	add_child(t)
	var sub := Label.new()
	if match_mode:
		sub.text = "%s · против «%s» · seed %d" % [Game.mode_title(Game.mode), opp["name"], Game.series_seed]
	else:
		sub.text = "%s · цель: %d гола · seed %d" % [Game.mode_title(Game.mode), need, Game.series_seed]
	sub.position = Vector2(42, 76)
	sub.add_theme_color_override("font_color", Game.C_MUTED)
	add_child(sub)
	if win:
		Sfx.play("goal")
	if match_mode:
		# крупное табло
		var board := Label.new()
		board.text = "ВЫ  %d : %d  %s" % [goals, Game.opp_goals(), opp["short"]]
		board.position = Vector2(680, 30)
		board.size = Vector2(560, 50)
		board.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		board.add_theme_font_size_override("font_size", 30)
		board.add_theme_color_override("font_color", Color("f7d27a"))
		add_child(board)
	# --- статистика
	var left := _panel(Rect2(40, 112, 620, 470))
	var sec := int(Game.duration_sec())
	var stats := [["Голы", Game.count_outcome("goal"), Game.C_SAFE], ["Сейвы вратаря", Game.count_outcome("save"), Game.C_WARN],
		["Перехваты", Game.count_outcome("intercept"), Game.C_DANGER], ["Потери (темп / давление)", Game.count_outcome("lost"), Color(0.8, 0.75, 0.7)]]
	if match_mode:
		var tackles := 0
		var saves := 0
		for dd in Game.defenses:
			tackles += 1 if dd["outcome"] == "tackle" else 0
			saves += 1 if dd["outcome"] == "save" else 0
		stats = [["Забито", goals, Game.C_SAFE], ["Пропущено", Game.opp_goals(), Game.C_DANGER],
			["Отборы / сейвы Петрова", "%d / %d" % [tackles, saves], Game.C_INFO], ["Перехваты / сейвы их вратаря", "%d / %d" % [Game.count_outcome("intercept"), Game.count_outcome("save")], Game.C_WARN]]
	for i in stats.size():
		_label(left, stats[i][0], Vector2(20, 16 + i * 32), 18, Game.C_MUTED)
		_label(left, str(stats[i][1]), Vector2(290, 14 + i * 32), 22, stats[i][2])
	_label(left, "Длительность", Vector2(400, 16), 18, Game.C_MUTED)
	_label(left, "%d:%02d" % [sec / 60, sec % 60], Vector2(400, 42), 30, Game.C_TEXT)
	_label(left, "Раунды:" if match_mode else "Атаки:", Vector2(20, 152), 18, Game.C_ACCENT)
	var names := {"goal": "ГОЛ", "save": "сейв", "intercept": "перехват", "lost": "потеря"}
	var cols := {"goal": Game.C_SAFE, "save": Game.C_WARN, "intercept": Game.C_DANGER, "lost": Color(0.8, 0.75, 0.7)}
	var list := RichTextLabel.new()
	list.bbcode_enabled = true
	list.position = Vector2(20, 180)
	list.size = Vector2(580, 280)
	list.add_theme_font_size_override("normal_font_size", 14)
	list.add_theme_font_size_override("bold_font_size", 14)
	var txt := ""
	var dnames := {"goal": "пропустили", "save": "сейв Петрова", "tackle": "отбор"}
	var dcols := {"goal": Game.C_DANGER, "save": Game.C_SAFE, "tackle": Game.C_SAFE}
	for i in Game.attacks.size():
		var a: Dictionary = Game.attacks[i]
		var reason: String = a["reason"].split("\n")[0]
		if match_mode:
			txt += "[b]%d.[/b] Вы: [color=#%s][b]%s[/b][/color] · %s" % [i + 1, cols[a["outcome"]].to_html(false), names[a["outcome"]], a["template"]]
			if i < Game.defenses.size():
				var dd: Dictionary = Game.defenses[i]
				txt += "   Они: [color=#%s][b]%s[/b][/color] · %s" % [dcols[dd["outcome"]].to_html(false), dnames[dd["outcome"]], dd["template"]]
			txt += "\n"
		else:
			txt += "[b]%d.[/b] [color=#%s][b]%s[/b][/color]%s — %s\n" % [i + 1, cols[a["outcome"]].to_html(false), names[a["outcome"]],
				(" · " + a["template"]) if a["template"] != "" else "", reason]
	list.text = txt
	left.add_child(list)
	# --- оценки
	var right := _panel(Rect2(680, 112, 560, 300))
	_label(right, "Оценка режима (необязательно)", Vector2(20, 14), 20, Game.C_ACCENT)
	var qs := [["clarity", "Понятно ли происходящее?"], ["football", "Чувствуется ли футбол?"], ["replay", "Хочется ли повторить?"]]
	for i in qs.size():
		var key: String = qs[i][0]
		_label(right, qs[i][1], Vector2(20, 58 + i * 62), 17)
		_rating_btns[key] = []
		for v in 5:
			var b := Button.new()
			b.text = str(v + 1)
			b.toggle_mode = true
			b.position = Vector2(20 + v * 50, 84 + i * 62)
			b.size = Vector2(44, 30)
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(_rate.bind(key, v + 1))
			right.add_child(b)
			_rating_btns[key].append(b)
	_label(right, "1 — нет, 5 — да", Vector2(300, 90), 14, Game.C_MUTED)
	_save_btn = Button.new()
	_save_btn.text = "Сохранить оценку"
	_save_btn.position = Vector2(300, 240)
	_save_btn.size = Vector2(240, 42)
	_save_btn.disabled = true
	_save_btn.pressed.connect(_save)
	right.add_child(_save_btn)
	_saved_lb = _label(right, "", Vector2(20, 250), 15, Game.C_SAFE)
	# --- сравнение режимов
	var cmp := _panel(Rect2(680, 422, 560, 160))
	_label(cmp, "Сравнение режимов (на этом компьютере)", Vector2(20, 10), 16, Game.C_ACCENT)
	var y := 40
	for m in Game.MODE_IDS:
		var s := Game.mode_summary(m)
		var line := "%s: серий %d, побед %d" % [Game.mode_title(m), s["series"], s["wins"]]
		if s["ratings"] > 0:
			line += " · оценки %.1f / %.1f / %.1f" % [s["clarity"], s["football"], s["replay"]]
		_label(cmp, line, Vector2(20, y), 14, Game.C_TEXT if m == Game.mode else Game.C_MUTED)
		y += 26
	_label(cmp, "оценки: понятно / футбол / повторить", Vector2(20, y + 2), 12, Game.C_MUTED)
	# --- кнопки
	var specs := [["Повторить те же условия", _again], ["Новая серия", _new], ["Другой режим", Game.go_menu]]
	for i in specs.size():
		var b := Button.new()
		b.text = specs[i][0]
		b.position = Vector2(40 + i * 410, 610)
		b.size = Vector2(380, 64)
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(specs[i][1])
		add_child(b)
		if i == 0:
			b.grab_focus.call_deferred()
	var hint := Label.new()
	hint.text = "«Повторить те же условия» — тот же seed: те же руки, планы обороны и события."
	hint.position = Vector2(40, 684)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Game.C_MUTED)
	add_child(hint)


func _panel(r: Rect2) -> Panel:
	var p := Panel.new()
	p.position = r.position
	p.size = r.size
	add_child(p)
	return p


func _label(parent: Control, text: String, pos: Vector2, fs: int = 17, col: Color = Game.C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l


func _rate(key: String, v: int) -> void:
	Sfx.play("click")
	_ratings[key] = v
	for i in 5:
		_rating_btns[key][i].button_pressed = i + 1 == v
	_save_btn.disabled = false
	_saved_lb.text = ""


func _save() -> void:
	Game.save_rating(_ratings["clarity"], _ratings["football"], _ratings["replay"])
	Sfx.play("click")
	_save_btn.disabled = true
	_saved_lb.text = "Сохранено локально."


func _again() -> void:
	Sfx.play("click")
	Game.tutorial_seen[Game.mode] = true
	Game.start_mode(Game.mode, Game.series_seed, false)


func _new() -> void:
	Sfx.play("click")
	Game.start_mode(Game.mode, -1, false)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Game.go_menu()
