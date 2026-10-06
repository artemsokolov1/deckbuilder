extends GameBase
## Режим C «Ещё один пас»: бить сейчас или рискнуть ещё одной передачей.
## Позиция мяча на поле — наглядность: линия = качество момента (чем ближе к воротам, тем выше шанс),
## защитники вплотную к мячу = накопленное давление.

var state: Dictionary = {}
var selected := -1
var cards: Array[CardView] = []
var ball_cell := Vector2i(1, 0)

var _deck_vis: Control
var _deck_lb: RichTextLabel
var _chance_lb: Label
var _quality_lb: Label
var _pressure_vis: Control
var _played_lb: Label
var _info: RichTextLabel
var _next_lb: RichTextLabel
var _shot_btn: Button
var _shot_sub: Label
var _reveal: Label

const EV_COL := {"safe": Color("86d46f"), "pressure": Color("f0a43a"), "intercept": Color("e4553f")}


func _mode_id() -> String:
	return "c"


func _template_name() -> String:
	return ""


func _build_mode_ui() -> void:
	panel(right, Rect2(0, 0, 632, 150))
	lbl(right, "Колода обороны на эту атаку", Vector2(14, 8), 20)
	lbl(right, "события открываются сверху, без возвращения; порядок скрыт", Vector2(14, 36), 13, Game.C_MUTED)
	_deck_vis = Control.new()
	_deck_vis.position = Vector2(14, 60)
	_deck_vis.size = Vector2(604, 46)
	_deck_vis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deck_vis.draw.connect(_draw_deck)
	right.add_child(_deck_vis)
	_deck_lb = rich(right, Rect2(14, 112, 604, 30), 15)
	panel(right, Rect2(0, 158, 632, 96))
	lbl(right, "Шанс гола", Vector2(14, 166), 15, Game.C_MUTED)
	_chance_lb = lbl(right, "", Vector2(14, 184), 44, Game.C_SAFE)
	_quality_lb = lbl(right, "", Vector2(176, 164), 17)
	lbl(right, "Давление", Vector2(176, 192), 17, Game.C_MUTED)
	_pressure_vis = Control.new()
	_pressure_vis.position = Vector2(262, 188)
	_pressure_vis.size = Vector2(360, 32)
	_pressure_vis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pressure_vis.draw.connect(_draw_pressure)
	right.add_child(_pressure_vis)
	_played_lb = lbl(right, "", Vector2(176, 222), 15, Game.C_MUTED)
	panel(right, Rect2(0, 262, 632, 146))
	_info = rich(right, Rect2(14, 270, 604, 96), 16)
	_next_lb = rich(right, Rect2(14, 366, 604, 40), 15)
	_shot_btn = button(right, "", Rect2(0, 414, 632, 62), _on_shot, 26)
	_shot_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_shot_btn.mouse_entered.connect(_on_shot_hover.bind(true))
	_shot_btn.mouse_exited.connect(_on_shot_hover.bind(false))
	_shot_sub = lbl(_shot_btn, "", Vector2(260, 10), 15, Game.C_TEXT, 360)
	_shot_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reveal = Label.new()
	_reveal.position = Vector2(PITCH_POS.x + 150, PITCH_POS.y + 200)
	_reveal.size = Vector2(300, 70)
	_reveal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reveal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_reveal.add_theme_font_size_override("font_size", 30)
	_reveal.visible = false
	_reveal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_reveal)
	pitch.shot_lines = [0, 1, 2, 3]
	pitch.show_shot_band = false
	pitch.cell_clicked.connect(_on_cell_clicked)


func _start_attack(tutorial: bool) -> void:
	state = RulesC.new_attack(Game.series_seed, attack_idx, tutorial)
	selected = -1
	ball_cell = Vector2i(1, 0)
	pitch.clear_marks()
	pitch.set_danger([], [])
	pitch.place_all(ball_cell, [])
	_place_defense(0.0)
	_refresh()


# ------------------------------------------------------------------ отображение
func _defense_points() -> Array:
	# Защитники перед мячом в каждом коридоре + по одному вплотную за каждое давление.
	var pts: Array = []
	var ahead := mini(3, ball_cell.y + 1)
	for x in 3:
		if x != ball_cell.x or ahead != ball_cell.y:
			pts.append(PitchView.def_pos(Vector2i(x, ahead)))
	var p := int(state.get("pressure", 0))
	var ball_p := PitchView.att_pos(ball_cell)
	var close := [Vector2(26, -6), Vector2(-4, -30)]
	for i in mini(p, 2):
		pts.append(ball_p + close[i])
	return pts


func _place_defense(d: float) -> Tween:
	if d <= 0:
		pitch._place_points(_defense_points(), 0.0)
		return null
	return pitch.move_defender_points(_defense_points(), d)


func _target_cell(card_id: String, q_after: int) -> Vector2i:
	var line := clampi(q_after, 0, 3)
	var lane := ball_cell.x
	match card_id:
		"pass", "risky":
			lane = 0 if ball_cell.x == 1 and int(state["played"]) % 2 == 0 else (2 if ball_cell.x == 1 else 1)
		"switch_c":
			lane = 2 - ball_cell.x if ball_cell.x != 1 else (0 if int(state["played"]) % 2 == 0 else 2)
	return Vector2i(lane, line)


func _refresh() -> void:
	var q: int = state["quality"]
	_chance_lb.text = "%d%%" % RulesC.goal_chance(q)
	_quality_lb.text = "Качество момента: %d   (+%d%% за единицу, не выше %d%%)" % [q, RulesC.cfg()["chance_per_quality"], RulesC.cfg()["max_chance"]]
	_played_lb.text = "Сыграно карт: %d из %d" % [state["played"], RulesC.cfg()["max_cards_played"]]
	var cnt := RulesC.counts(state)
	var n: int = cnt["safe"] + cnt["pressure"] + cnt["intercept"]
	_deck_lb.text = "Осталось %d: [color=#86d46f]безопасно %d[/color] · [color=#f0a43a]давление %d[/color] · [color=#e4553f]перехват %d[/color]" % [
		n, cnt["safe"], cnt["pressure"], cnt["intercept"]]
	_deck_vis.queue_redraw()
	_pressure_vis.queue_redraw()
	_build_hand()
	_update_shot()
	_default_info()
	_tutorial_hint()


func _draw_deck() -> void:
	if state.is_empty():
		return
	# Открытые события (затемнены) слева, затем остаток колоды рубашкой вверх, сгруппированный по типу.
	var x := 0.0
	var f := ThemeDB.fallback_font
	for e in state.get("drawn", []):
		_deck_vis.draw_rect(Rect2(x, 4, 34, 40), Color(EV_COL[e], 0.25))
		_deck_vis.draw_rect(Rect2(x, 4, 34, 40), Color(EV_COL[e], 0.6), false, 1.5)
		_deck_vis.draw_line(Vector2(x + 6, 10), Vector2(x + 28, 38), Color(1, 1, 1, 0.3), 2)
		x += 38
	if not state.get("drawn", []).is_empty():
		x += 10
	var cnt := RulesC.counts(state)
	for t in ["safe", "pressure", "intercept"]:
		for i in cnt[t]:
			_deck_vis.draw_rect(Rect2(x, 4, 34, 40), EV_COL[t].darkened(0.1))
			_deck_vis.draw_rect(Rect2(x, 4, 34, 40), Color(0, 0, 0, 0.5), false, 1.5)
			var ch: String = {"safe": "✓", "pressure": "!", "intercept": "✕"}[t]
			_deck_vis.draw_string(f, Vector2(x + 11, 31), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("1a120c"))
			x += 38


func _draw_pressure() -> void:
	var limit: int = RulesC.cfg()["pressure_limit"]
	var p: int = state.get("pressure", 0)
	for i in limit:
		var c := Vector2(14 + i * 34, 14)
		_pressure_vis.draw_circle(c, 12, EV_COL["pressure"] if i < p else Color(1, 1, 1, 0.12))
		_pressure_vis.draw_arc(c, 12, 0, TAU, 20, Color(0, 0, 0, 0.5), 1.5)
	var f := ThemeDB.fallback_font
	_pressure_vis.draw_string(f, Vector2(14 + limit * 34, 20), "%d из %d — на %d-м мяч потерян" % [p, limit, limit], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Game.C_MUTED)


func _build_hand() -> void:
	for c in cards:
		c.queue_free()
	cards.clear()
	var n: int = state["hand"].size()
	var gap := 14.0
	var total := n * CardView.SIZE.x + (n - 1) * gap
	var x0 := (1280.0 - total) / 2.0
	for i in n:
		var cv := CardView.new()
		cv.setup(state["hand"][i], RulesC.card_def(state["hand"][i]), i)
		cv.position = Vector2(x0 + i * (CardView.SIZE.x + gap), 6)
		cv.base_y = 6
		hand_box.add_child(cv)
		cv.used = state["used"][i]
		if state["used"][i]:
			cv.tag = "сыграна"
		cv.disabled = busy or RulesC.card_block_reason(state, i) != ""
		cv.selected = i == selected
		cv.pressed.connect(_on_card_pressed)
		cv.hovered.connect(_on_card_hovered)
		cards.append(cv)


func _update_shot() -> void:
	var info := RulesC.shot_info(state)
	_shot_btn.text = "  УДАР · %d%%" % info["chance"]
	_shot_btn.disabled = not info["available"] or busy
	_shot_sub.text = "Один бросок 0–99: гол, если меньше %d. Завершает атаку." % info["chance"]
	_shot_btn.add_theme_stylebox_override("normal", Game.box(Color("3a2c1f"), Game.C_SAFE.lerp(Game.C_WARN, 1.0 - info["chance"] / 90.0), 10, 3))


func _default_info() -> void:
	if state["over"] or busy:
		return
	if selected >= 0:
		_show_odds(selected)
		_next_lb.text = "[color=#f2a33a]Дальше:[/color] нажмите подсвеченную клетку (партнёра) или карту ещё раз — сыграть. Правая кнопка — отмена."
		return
	var p := RulesC.shot_info(state)
	_info.text = "Удар сейчас: [b]%d%%[/b]. Каждая карта может улучшить момент, но открывает события обороны.\nНаведите на карту — увидите точный шанс потери и шанс гола после неё." % p["chance"]
	var playable := 0
	for i in state["hand"].size():
		if RulesC.card_block_reason(state, i) == "":
			playable += 1
	_next_lb.text = "[color=#f2a33a]Дальше:[/color] " + ("сыграйте карту (доступно: %d) или ударьте." % playable if playable > 0 else "карты закончились — только удар.")


func _show_odds(idx: int) -> void:
	var o := RulesC.preview_card(state, idx)
	var d := RulesC.card_def(state["hand"][idx])
	if not o["legal"]:
		_info.text = "[b]%s[/b] — [color=#e4553f]нельзя:[/color] %s\n[color=#b9a68d]%s[/color]" % [d["name"], o["reason"], d["text"]]
		return
	var t := "[b]%s[/b]: %s\n" % [d["name"], d["text"]]
	if int(d["draw_count"]) == 0:
		t += "[color=#86d46f]Риска нет[/color]: событие не открывается. Давление %d → %d. Шанс гола не меняется (%d%%)." % [state["pressure"], o["pressure_after_relief"], o["chance_now"]]
	else:
		var parts: PackedStringArray = []
		if o["intercept"] > 0:
			parts.append("перехват %s" % pct(float(o["intercept"]) / o["den"]))
		if o["pressure"] > 0:
			parts.append("второе давление %s" % pct(float(o["pressure"]) / o["den"]))
		t += "Шанс потери: [b][color=#e4553f]%s[/color][/b] (%d из %d%s). " % [pct(o["p_loss"]), o["loss"], o["den"], (": " + ", ".join(parts)) if parts.size() > 1 else ""]
		t += "Если мяч сохранён: шанс гола %d%% → [b][color=#86d46f]%d%%[/color][/b]." % [o["chance_now"], o["chance_after"]]
	_info.text = t


# ------------------------------------------------------------------ карты
func _on_card_hovered(cv: CardView, on: bool) -> void:
	if busy or state.is_empty() or state["over"] or selected >= 0:
		return
	if on:
		_show_odds(cv.hand_idx)
		if RulesC.card_block_reason(state, cv.hand_idx) == "":
			var o := RulesC.preview_card(state, cv.hand_idx)
			pitch.set_targets({_target_cell(cv.card_id, o["quality_after"]): "chance" if o["p_loss"] > 0 else "safe"})
	else:
		pitch.set_targets({})
		_default_info()


func _on_card_pressed(cv: CardView) -> void:
	if busy or state["over"]:
		return
	var i := cv.hand_idx
	var reason := RulesC.card_block_reason(state, i)
	if reason != "":
		Sfx.play("error")
		_info.text = "[b]%s[/b] — [color=#e4553f]нельзя:[/color] %s" % [cv.title, reason]
		return
	if selected == i:
		_play(i)
		return
	Sfx.play("click")
	selected = i
	var o := RulesC.preview_card(state, i)
	pitch.set_targets({_target_cell(cv.card_id, o["quality_after"]): "chance" if o["p_loss"] > 0 else "safe"})
	for c in cards:
		c.selected = c.hand_idx == selected
	_default_info()


func _on_cell_clicked(cell: Vector2i) -> void:
	if busy or state["over"] or selected < 0:
		return
	if pitch.targets.has(cell):
		_play(selected)
	else:
		Sfx.play("error")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and not busy and selected >= 0:
		selected = -1
		pitch.clear_marks()
		_refresh()


func _play(idx: int) -> void:
	busy = true
	selected = -1
	pitch.clear_marks()
	Sfx.play("click")
	var id: String = state["hand"][idx]
	var d := RulesC.card_def(id)
	var q_before: int = state["quality"]
	var r := RulesC.play_card(state, idx)
	if not r["legal"]:
		busy = false
		_refresh()
		return
	_build_hand()
	_shot_btn.disabled = true
	_info.text = "[b]%s[/b]: открываем события обороны…" % d["name"]
	_next_lb.text = ""
	if r["relieved"] > 0:
		pitch.float_text("−%d давление" % r["relieved"], PitchView.att_pos(ball_cell) + Vector2(0, -34), Game.C_INFO)
		_pressure_vis.queue_redraw()
		await _place_defense(dur(0.3)).finished
	# События открываются по одному; давление сразу видно на поле.
	var running_p: int = maxi(0, _pressure_before(r))
	for k in r["draws"].size():
		var ev: Dictionary = r["draws"][k]
		await _reveal_event(ev, k + 1, r["draws"].size(), int(d["draw_count"]))
		if ev["type"] == "pressure" and not ev["ignored"]:
			running_p += 1
			_show_pressure(running_p)
			await _place_defense_with(running_p, dur(0.3)).finished
	_deck_vis.queue_redraw()
	if r["lost"]:
		if r["outcome"] == "intercept":
			Sfx.play("intercept")
			pitch.banner("ПЕРЕХВАТ", Game.C_DANGER, dur(0.8))
		else:
			Sfx.play("lost")
			pitch.banner("ОТОБРАЛИ", Color(0.9, 0.7, 0.5), dur(0.8))
		shake(7)
		await pitch.steal_ball(ball_cell, dur(0.4)).finished
		await wait(0.7)
		var expl: String = state["end_reason"]
		if int(d["draw_count"]) == 2 and r["draws"].size() == 1:
			expl += " Второе событие не открывалось, бонус качества не начислен."
		end_attack(r["outcome"], expl)
		return
	# мяч сохранён — атака продвигается
	if int(d["draw_count"]) > 0 or r["quality_gain"] > 0:
		var to := _target_cell(id, int(state["quality"]))
		var tw: Tween
		if to == ball_cell:
			tw = pitch.carry_ball(to, dur(0.3))
		elif id == "sprint":
			tw = pitch.carry_ball(to, dur(0.36))
		else:
			tw = pitch.pass_ball(to, dur(0.36), Pitch.NONE, id == "risky")
		Sfx.play("pass")
		await tw.finished
		ball_cell = to
		pitch.relayout_attackers(ball_cell, dur(0.3))
		if r["quality_gain"] > 0:
			pitch.float_text("+%d к качеству → %d%%" % [r["quality_gain"], RulesC.goal_chance(state["quality"])], PitchView.cell_center(ball_cell) + Vector2(0, -30), Game.C_SAFE, 18)
		await _place_defense(dur(0.3)).finished
	busy = false
	_refresh()
	if q_before == state["quality"] and int(d["draw_count"]) == 0:
		_info.text = "[b]%s[/b]: давление снято." % d["name"]


func _pressure_before(r: Dictionary) -> int:
	# давление после снятия, но до событий
	var p: int = state["pressure"]
	for ev in r["draws"]:
		if ev["type"] == "pressure" and not ev["ignored"]:
			p -= 1
	return p


func _show_pressure(p: int) -> void:
	var saved: int = state["pressure"]
	state["pressure"] = p
	_pressure_vis.queue_redraw()
	state["pressure"] = saved


func _place_defense_with(p: int, d: float) -> Tween:
	var saved: int = state["pressure"]
	state["pressure"] = p
	var tw := _place_defense(d)
	state["pressure"] = saved
	return tw


func _reveal_event(ev: Dictionary, k: int, total: int, planned: int) -> Signal:
	var names := {"safe": "Безопасно", "pressure": "Давление", "intercept": "Перехват"}
	var txt: String = names[ev["type"]]
	if ev.get("ignored", false):
		txt += "\n(игнорируется)"
	if planned == 2:
		txt = "%d/2: %s" % [k, txt]
	_reveal.text = txt
	_reveal.add_theme_color_override("font_color", EV_COL[ev["type"]])
	_reveal.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02))
	_reveal.add_theme_constant_override("outline_size", 12)
	_reveal.add_theme_stylebox_override("normal", Game.box(Color(0.08, 0.06, 0.05, 0.85), EV_COL[ev["type"]], 12, 3))
	_reveal.visible = true
	_reveal.pivot_offset = _reveal.size / 2
	_reveal.scale = Vector2(0.6, 0.6)
	Sfx.play({"safe": "safe", "pressure": "pressure", "intercept": "intercept"}[ev["type"]] if ev["type"] != "intercept" else "error")
	var tw := create_tween()
	tw.tween_property(_reveal, "scale", Vector2.ONE, dur(0.15)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(dur(0.45))
	tw.tween_callback(func(): _reveal.visible = false)
	return tw.finished


# ------------------------------------------------------------------ удар
func _on_shot_hover(on: bool) -> void:
	if busy or state.is_empty() or state["over"]:
		return
	if on:
		var info := RulesC.shot_info(state)
		_info.text = "[b]Удар[/b]: шанс [b]%d%%[/b] = 35%% + %d × качество %d (не выше %d%%).\nПроверяется одним броском по показанному шансу — без подкруток. Удар завершает атаку." % [
			info["chance"], RulesC.cfg()["chance_per_quality"], state["quality"], RulesC.cfg()["max_chance"]]
	else:
		_default_info()


func _on_shot() -> void:
	if busy or state["over"]:
		return
	busy = true
	selected = -1
	pitch.clear_marks()
	var info := RulesC.shoot(state)
	_build_hand()
	_shot_btn.disabled = true
	_info.text = "[b]Удар![/b] Шанс %d%%…" % info["chance"]
	var tw := create_tween()
	tw.tween_property(pitch.carrier, "scale", Vector2(1.2, 1.2), dur(0.25))
	tw.tween_property(pitch.carrier, "scale", Vector2.ONE, dur(0.12))
	await tw.finished
	Sfx.play("shot")
	await pitch.shoot_ball(info["goal"], dur(0.45)).finished
	if info["goal"]:
		Sfx.play("goal")
		pitch.celebrate(dur(1.4))
		pitch.banner("ГОЛ!", Game.C_SAFE, dur(1.0))
		shake(9)
	else:
		Sfx.play("save")
		pitch.crowd_sigh(dur(0.8))
		pitch.banner("СЕЙВ", Game.C_WARN, dur(0.8))
	await wait(1.1)
	end_attack(state["outcome"], state["end_reason"])


# ------------------------------------------------------------------ обучение
func _tutorial_pages() -> Array:
	return [
		{"title": "Режим C · «Ещё один пас»", "text": "Можно [b]ударить сразу[/b] — шанс 35%. А можно рискнуть [b]ещё одной передачей[/b]: шанс гола растёт, но растёт и риск потерять мяч.\n\nСерия из 5 атак, нужно [b]3 гола[/b]."},
		{"title": "Колода обороны", "text": "У обороны своя колода на каждую атаку: [color=#86d46f]6 «Безопасно»[/color], [color=#f0a43a]3 «Давление»[/color], [color=#e4553f]1 «Перехват»[/color].\n\nСобытия открываются сверху и [b]не возвращаются[/b] — остаток виден справа. [color=#e4553f]Перехват[/color] — сразу потеря мяча. [b]Второе[/b] накопленное давление — тоже потеря."},
		{"title": "Ваши карты", "text": "5 карт, каждая — один раз, всего [b]не больше 4[/b] за атаку, потом только удар.\n\nКарта открывает 0–2 события и, если мяч сохранён, добавляет [b]качество[/b]: +12% к шансу гола за единицу, максимум 90%. Если потеря случилась на первом из двух событий, второе не открывается и бонуса нет."},
		{"title": "Честные проценты", "text": "Наведите на карту — увидите [b]точный шанс потери[/b], посчитанный по оставшемуся составу колоды (без возвращения), и каким станет шанс гола.\n\nУдар — [b]один бросок[/b] по показанному шансу. Результат не подкручивается ради драмы."},
		{"title": "Тренировка", "text": "Сейчас будет [b]тренировочная атака[/b] (не идёт в счёт). Над полем — [color=#7cc3e8]подсказки[/color].\n\nEsc — выход в меню в любой момент."},
	]


func _tutorial_hint() -> void:
	if not tutorial_active or state["over"]:
		set_hint("")
		return
	var played: int = state["played"]
	if played == 0:
		set_hint("наведите на [b]«Пас»[/b] — справа шанс потери (10%) и шанс гола после него. Нажмите карту, затем подсвеченную клетку.")
	elif int(state["pressure"]) > 0 and not state["used"][2]:
		set_hint("есть давление: [b]«Пауза»[/b] снимет его без риска. Ещё одно давление — потеря мяча.")
	elif RulesC.goal_chance(state["quality"]) >= 59:
		set_hint("шанс уже [b]%d%%[/b]. Решайте: бить сейчас или рискнуть ещё раз." % RulesC.goal_chance(state["quality"]))
	else:
		set_hint("сравните: шанс потери у карты против прироста шанса гола. [b]«Прикрыть мяч»[/b] не боится давления.")
