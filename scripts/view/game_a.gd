extends GameBase
## Режим A «Комбинация»: карта → клетка, после каждого действия оборона делает шаг.

var state: Dictionary = {}
var selected := -1
var hovered_card := -1
var mull_mode := false
var mull_marks: Array = []
var cards: Array[CardView] = []

var _def_title: Label
var _def_hint: Label
var _minis: Array[MiniPlan] = []
var _tempo_pips: Control
var _quality_lb: Label
var _mull_btn: Button
var _mull_cancel: Button
var _info: RichTextLabel
var _next_lb: RichTextLabel
var _shot_btn: Button
var _shot_sub: Label


func _mode_id() -> String:
	return "a"


func _template_name() -> String:
	return state.get("plan", {}).get("name", "")


func _build_mode_ui() -> void:
	# --- оборона
	panel(right, Rect2(0, 0, 632, 150))
	_def_title = lbl(right, "", Vector2(14, 8), 20, Game.C_TEXT)
	_def_hint = lbl(right, "", Vector2(14, 38), 14, Game.C_MUTED, 320)
	lbl(right, "Оборона шагает после каждого вашего действия →", Vector2(14, 122), 12, Game.C_MUTED)
	for i in 3:
		var m := MiniPlan.new()
		m.position = Vector2(344 + i * 96, 14)
		m.size = Vector2(90, 120)
		right.add_child(m)
		_minis.append(m)
	# --- ресурсы
	panel(right, Rect2(0, 158, 632, 58))
	lbl(right, "Темп", Vector2(14, 174), 17, Game.C_MUTED)
	_tempo_pips = Control.new()
	_tempo_pips.position = Vector2(62, 168)
	_tempo_pips.size = Vector2(150, 36)
	_tempo_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tempo_pips.draw.connect(_draw_tempo)
	right.add_child(_tempo_pips)
	_quality_lb = lbl(right, "", Vector2(206, 172), 19, Game.C_TEXT)
	_mull_btn = button(right, "Обмен карт", Rect2(424, 166, 196, 42), _on_mulligan, 16)
	_mull_cancel = button(right, "Отмена", Rect2(398, 166, 82, 42), _cancel_mulligan, 15)
	_mull_cancel.visible = false
	# --- инфо
	panel(right, Rect2(0, 224, 632, 162))
	_info = rich(right, Rect2(14, 232, 604, 100), 16)
	_next_lb = rich(right, Rect2(14, 334, 604, 50), 15)
	# --- удар
	_shot_btn = button(right, "", Rect2(0, 394, 632, 82), _on_shot, 26)
	_shot_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_shot_btn.mouse_entered.connect(_on_shot_hover.bind(true))
	_shot_btn.mouse_exited.connect(_on_shot_hover.bind(false))
	_shot_sub = lbl(_shot_btn, "", Vector2(250, 14), 16, Game.C_TEXT, 370)
	_shot_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pitch.cell_clicked.connect(_on_cell_clicked)
	pitch.cell_hovered.connect(_on_cell_hovered)


func _start_attack(tutorial: bool) -> void:
	state = RulesA.new_attack(Game.series_seed, attack_idx, tutorial)
	selected = -1
	hovered_card = -1
	mull_mode = false
	mull_marks = []
	pitch.clear_marks()
	pitch.place_all(state["ball"], RulesA.danger(state))
	_refresh()


# ------------------------------------------------------------------ обновление интерфейса
func _refresh() -> void:
	var plan: Dictionary = state["plan"]
	_def_title.text = "Оборона: " + plan["name"]
	_def_hint.text = plan["hint"]
	var caps := ["сейчас", "через 1 ход", "через 2 хода"]
	for i in 3:
		_minis[i].set_data(RulesA.danger(state, i), state["ball"] if i == 0 else Pitch.NONE, caps[i], i == 0)
	pitch.set_danger(RulesA.danger(state, 0), RulesA.danger(state, 1) if not state["over"] else [])
	_tempo_pips.queue_redraw()
	_quality_lb.text = "Качество момента: %d" % state["quality"]
	var can_m := RulesA.can_mulligan(state) and not busy
	_mull_btn.visible = can_m or mull_mode
	_mull_cancel.visible = mull_mode
	_mull_btn.position.x = 488.0 if mull_mode else 424.0
	_mull_btn.size.x = 132.0 if mull_mode else 196.0
	if mull_mode:
		_mull_btn.text = "Заменить: %d" % mull_marks.size() if mull_marks.size() > 0 else "Отметьте карты"
		_mull_btn.disabled = mull_marks.is_empty()
	else:
		_mull_btn.text = "Обмен карт (до 2)"
		_mull_btn.disabled = false
	_build_hand()
	_update_shot_button()
	_default_info()
	_tutorial_hint()


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
		cv.setup(state["hand"][i], RulesA.card_def(state["hand"][i]), i)
		cv.position = Vector2(x0 + i * (CardView.SIZE.x + gap), 6)
		cv.base_y = 6
		hand_box.add_child(cv)
		cv.disabled = RulesA.card_block_reason(state, i) != "" and not mull_mode
		cv.marked = mull_marks.has(i)
		cv.selected = i == selected
		cv.pressed.connect(_on_card_pressed)
		cv.hovered.connect(_on_card_hovered)
		cards.append(cv)


func _draw_tempo() -> void:
	var total: int = RulesA.cfg()["tempo"]
	for i in total:
		var c := Vector2(14 + i * 27, 18)
		var full: bool = i < int(state.get("tempo", 0))
		_tempo_pips.draw_circle(c, 11, Game.C_ACCENT if full else Color(1, 1, 1, 0.12))
		_tempo_pips.draw_arc(c, 11, 0, TAU, 20, Color(0, 0, 0, 0.5), 1.5)


func _update_shot_button() -> void:
	var info := RulesA.shot_info(state)
	_shot_btn.text = "  УДАР · %d темп" % info["cost"]
	_shot_btn.disabled = not info["available"] or busy or state["over"]
	if not info["available"]:
		_shot_sub.text = info["reason"]
		_shot_sub.add_theme_color_override("font_color", Game.C_MUTED)
		_shot_btn.add_theme_stylebox_override("normal", Game.box(Color("2a2119"), Game.C_BORDER, 10, 2))
	else:
		var res := "ГОЛ" if info["goal"] else "СЕЙВ вратаря"
		_shot_sub.text = "Сейчас: %s\n%d + %d − %d = %d (порог %d)" % [res, info["quality"], info["pos_bonus"], info["pressure"], info["value"], info["threshold"]]
		_shot_sub.add_theme_color_override("font_color", Game.C_SAFE if info["goal"] else Game.C_WARN)
		var border := Game.C_SAFE if info["goal"] else Game.C_WARN
		_shot_btn.add_theme_stylebox_override("normal", Game.box(Color("3a2c1f"), border, 10, 3))
		_shot_btn.add_theme_stylebox_override("hover", Game.box(Color("4d3a27"), border.lightened(0.3), 10, 3))


func _default_info() -> void:
	if state["over"]:
		_info.text = ""
		_next_lb.text = ""
		return
	if mull_mode:
		_info.text = "[b]Обмен.[/b] Нажмите до двух карт, которые хотите заменить, затем «Заменить». Новые карты придут из колоды. Обмен — один раз за атаку и только до первого действия."
		_next_lb.text = ""
		return
	if selected >= 0:
		var d := RulesA.card_def(state["hand"][selected])
		_info.text = "[b]%s[/b] выбрана. %s\n[color=#b9a68d]Наведите на подсвеченную клетку — увидите исход до подтверждения. Зелёная — безопасно, красная — перехват, голубая — проход через защитника.[/color]" % [d["name"], d["text"]]
		_next_lb.text = "[color=#f2a33a]Дальше:[/color] нажмите клетку-цель. Правая кнопка мыши или повторный клик по карте — отмена."
		return
	_info.text = "Мяч: %s. Темп: %d. Качество момента: %d.\n%s" % [Pitch.cell_name(state["ball"]), state["tempo"], state["quality"], _danger_text()]
	_next_lb.text = "[color=#f2a33a]Дальше:[/color] " + _next_text()


func _danger_text() -> String:
	var now := RulesA.danger(state)
	return "[color=#e4553f]Опасно сейчас:[/color] " + (Pitch.cells_text(now) if not now.is_empty() else "нет")


func _next_text() -> String:
	var playable := 0
	for i in state["hand"].size():
		if RulesA.card_block_reason(state, i) == "":
			playable += 1
	var parts: PackedStringArray = []
	if playable > 0:
		parts.append("выберите карту (доступно: %d)" % playable)
	var info := RulesA.shot_info(state)
	if info["available"]:
		parts.append("нажмите «Удар» (%s)" % ("гол" if info["goal"] else "вратарь отобьёт"))
	if RulesA.can_mulligan(state):
		parts.append("или обменяйте карты")
	return ", ".join(parts) + "."


# ------------------------------------------------------------------ карты
func _on_card_hovered(cv: CardView, on: bool) -> void:
	if busy or state.is_empty() or state["over"]:
		return
	hovered_card = cv.hand_idx if on else -1
	if selected >= 0 or mull_mode:
		return
	if on:
		var reason := RulesA.card_block_reason(state, cv.hand_idx)
		var d := RulesA.card_def(cv.card_id)
		if reason != "":
			_info.text = "[b]%s[/b] — [color=#e4553f]сейчас нельзя:[/color] %s\n[color=#b9a68d]%s[/color]" % [d["name"], reason, d["text"]]
			pitch.set_targets({})
		else:
			_info.text = "[b]%s[/b] (темп %d): %s\n[color=#b9a68d]Нажмите карту, чтобы выбрать её, затем клетку на поле.[/color]" % [d["name"], d["cost"], d["text"]]
			pitch.set_targets(_target_kinds(cv.hand_idx))
	else:
		pitch.set_targets({})
		_default_info()


func _target_kinds(idx: int) -> Dictionary:
	var out := {}
	for t in RulesA.card_targets(state, idx):
		var p := RulesA.preview_card(state, idx, t)
		out[t] = "risk" if p["intercepted"] else ("protected" if not p["beaten"].is_empty() else "safe")
	return out


func _on_card_pressed(cv: CardView) -> void:
	if busy or state["over"]:
		return
	var i := cv.hand_idx
	if mull_mode:
		if mull_marks.has(i):
			mull_marks.erase(i)
		elif mull_marks.size() < int(RulesA.cfg()["mulligan_max"]):
			mull_marks.append(i)
		else:
			Sfx.play("error")
			return
		Sfx.play("click")
		_refresh()
		return
	var reason := RulesA.card_block_reason(state, i)
	if reason != "":
		Sfx.play("error")
		var d := RulesA.card_def(cv.card_id)
		_info.text = "[b]%s[/b] — [color=#e4553f]нельзя:[/color] %s" % [d["name"], reason]
		_wiggle(cv)
		return
	Sfx.play("click")
	if selected == i:
		selected = -1
		pitch.clear_marks()
	else:
		selected = i
		pitch.set_targets(_target_kinds(i))
		pitch.set_preview({})
	for c in cards:
		c.selected = c.hand_idx == selected
	_default_info()


func _wiggle(cv: CardView) -> void:
	var x := cv.position.x
	var tw := cv.create_tween()
	for k in 4:
		tw.tween_property(cv, "position:x", x + (6 if k % 2 == 0 else -6), 0.04)
	tw.tween_property(cv, "position:x", x, 0.04)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if selected >= 0 and not busy:
			selected = -1
			pitch.clear_marks()
			for c in cards:
				c.selected = false
			_default_info()


# ------------------------------------------------------------------ поле
func _on_cell_hovered(cell: Vector2i) -> void:
	if busy or state.is_empty() or state["over"] or selected < 0:
		return
	if not pitch.targets.has(cell):
		pitch.set_preview({})
		_default_info()
		return
	var p := RulesA.preview_card(state, selected, cell)
	pitch.set_preview({"from": p["from"], "cells": p["path"] if not p["path"].is_empty() else [cell], "to": cell,
		"ok": not p["intercepted"], "bad": p["cell"], "beaten": p["beaten"]})
	var after: Dictionary = p["after"]
	var t := "[b]%s → %s[/b]\n" % [p["name"], Pitch.cell_name(cell)]
	if p["intercepted"]:
		t += "[color=#e4553f]ПЕРЕХВАТ в зоне «%s» — атака закончится.[/color]" % Pitch.cell_name(p["cell"])
	else:
		if not p["beaten"].is_empty():
			t += "[color=#7cc3e8]Проход через защитника (%s).[/color] " % Pitch.cells_text(p["beaten"])
		else:
			t += "[color=#86d46f]Безопасно.[/color] "
		t += "Качество %d → [b]%d[/b], темп %d → %d. " % [state["quality"], after["quality"], state["tempo"], after["tempo"]]
		t += "Затем оборона сделает шаг (пунктир «след.»)."
		if p["ends"]:
			t += "\n[color=#e4553f]Внимание: после этого не останется ни одного действия — мяч будет потерян.[/color]"
		else:
			var si := RulesA.shot_info(after)
			if si["available"]:
				t += "\nПосле хода удар даст: [b]%s[/b] (%d против %d)." % ["ГОЛ" if si["goal"] else "сейв", si["value"], si["threshold"]]
	_info.text = t


func _on_cell_clicked(cell: Vector2i) -> void:
	if busy or state["over"]:
		return
	if selected < 0:
		if not mull_mode:
			_info.text = "Сначала выберите карту внизу, затем клетку. " + "[color=#f2a33a]Дальше:[/color] " + _next_text()
		return
	if not pitch.targets.has(cell):
		Sfx.play("error")
		_info.text = "[color=#e4553f]Сюда «%s» не дотянется.[/color] Подходящие клетки подсвечены." % RulesA.card_def(state["hand"][selected])["name"]
		return
	_play(selected, cell)


func _play(idx: int, cell: Vector2i) -> void:
	busy = true
	var id: String = state["hand"][idx]
	var d := RulesA.card_def(id)
	selected = -1
	pitch.clear_marks()
	Sfx.play("click")
	var r := RulesA.play_card(state, idx, cell)
	if not r["legal"]:
		busy = false
		_refresh()
		return
	_build_hand()
	_shot_btn.disabled = true
	_mull_btn.visible = false
	_info.text = "[b]%s[/b] → %s" % [d["name"], Pitch.cell_name(cell)]
	_next_lb.text = ""
	var bad: Vector2i = r["cell"] if r["intercepted"] else Pitch.NONE
	var tw: Tween
	if d["path"] == "none" or (id == "dribble"):
		tw = pitch.carry_ball(cell, dur(0.32), bad)
	else:
		tw = pitch.pass_ball(cell, dur(0.34 if id != "through" else 0.42), bad, id == "through")
	Sfx.play("pass")
	await tw.finished
	if r["intercepted"]:
		Sfx.play("intercept")
		shake(7)
		pitch.banner("ПЕРЕХВАТ", Game.C_DANGER, dur(0.8))
		await pitch.steal_ball(r["cell"], dur(0.4)).finished
		await wait(0.7)
		end_attack("intercept", state["end_reason"] + "\nОбычная передача в красную зону всегда перехватывается. Смотрите на пунктир «след.» — так оборона встанет после вашего хода.")
		return
	if r["quality_gain"] > 0:
		pitch.float_text("+%d к качеству" % r["quality_gain"], PitchView.cell_center(cell) + Vector2(0, -30), Game.C_SAFE)
	if not r["beaten"].is_empty():
		pitch.float_text("обыграл!", PitchView.def_pos(r["beaten"][0]) + Vector2(0, -26), Game.C_INFO)
	pitch.relayout_attackers(cell, dur(0.3))
	await pitch.move_defenders(RulesA.danger(state), dur(0.32)).finished
	if state["over"]:
		Sfx.play("lost")
		pitch.banner("ПОТЕРЯ", Color(0.85, 0.8, 0.75), dur(0.7))
		await wait(0.9)
		end_attack("lost", state["end_reason"] + "\nОставляйте 1 темп на удар и выходите на линии 3–4.")
		return
	busy = false
	_refresh()


# ------------------------------------------------------------------ удар
func _on_shot_hover(on: bool) -> void:
	if busy or state.is_empty() or state["over"]:
		return
	var info := RulesA.shot_info(state)
	if on and info["available"]:
		pitch.set_pressure(info["pressure_cells"])
		var t := "[b]Удар[/b] из зоны «%s»: %s.\n" % [Pitch.cell_name(state["ball"]), Moves.shot_breakdown(info)]
		t += "Бонус позиции: ближе к воротам и по центру — больше. "
		if info["pressure"] > 0:
			t += "[color=#c98cff]Давление %d: опасные зоны в вашем коридоре до ворот (фиолетовые).[/color]" % info["pressure"]
		else:
			t += "Давления нет: коридор до ворот свободен."
		t += "\nИтог: [b]%s[/b]. Удар завершает атаку." % ("ГОЛ" if info["goal"] else "вратарь отобьёт")
		_info.text = t
	elif on:
		_info.text = "[b]Удар[/b] недоступен: " + info["reason"]
	else:
		pitch.set_pressure([])
		_default_info()


func _on_shot() -> void:
	if busy or state["over"]:
		return
	var info := RulesA.shot_info(state)
	if not info["available"]:
		Sfx.play("error")
		return
	busy = true
	selected = -1
	pitch.clear_marks()
	RulesA.shoot(state)
	_build_hand()
	_update_shot_button()
	_mull_btn.visible = false
	_info.text = "[b]Удар![/b] " + Moves.shot_breakdown(info)
	_next_lb.text = ""
	# пауза-замах перед ударом
	var tw := create_tween()
	tw.tween_property(pitch.carrier, "scale", Vector2(1.2, 1.2), dur(0.2))
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


# ------------------------------------------------------------------ обмен
func _on_mulligan() -> void:
	if busy or state["over"]:
		return
	Sfx.play("click")
	if not mull_mode:
		mull_mode = true
		mull_marks = []
		selected = -1
		pitch.clear_marks()
		_refresh()
		return
	if mull_marks.is_empty():
		return
	RulesA.mulligan(state, mull_marks)
	mull_mode = false
	mull_marks = []
	Sfx.play("card")
	_refresh()
	for c in cards:
		c.modulate.a = 0.0
		var tw := c.create_tween()
		tw.tween_property(c, "modulate:a", 1.0, 0.25)


func _cancel_mulligan() -> void:
	Sfx.play("click")
	mull_mode = false
	mull_marks = []
	_refresh()


# ------------------------------------------------------------------ обучение
func _tutorial_pages() -> Array:
	return [
		{"title": "Режим A · «Комбинация»", "text": "Серия из [b]5 атак[/b]. Чтобы выиграть, забейте [b]минимум 3 гола[/b].\n\nАтака идёт [b]снизу вверх[/b], к воротам. Поле разбито на [b]3 коридора[/b] (левый, центр, правый) и [b]4 линии[/b] — номера слева от поля. Мяч начинает в центре на линии 1."},
		{"title": "Карты и темп", "text": "Внизу — 5 карт. [b]Нажмите карту, затем подсвеченную клетку[/b] — мяч переместится.\n\nЧисло в жёлтом круге — [b]стоимость в темпе[/b]. На атаку даётся 5 темпа. Карты не добираются, но [b]до первого действия[/b] можно один раз обменять до двух карт.\n\nНедоступная карта затемнена — наведите на неё, и справа будет написано почему."},
		{"title": "Оборона", "text": "[color=#e4553f]Красные клетки[/color] — опасные зоны. Обычный пас туда [b]перехватят[/b], атака закончится.\n\nПосле [b]каждого[/b] вашего действия оборона делает [b]один шаг[/b] своего плана. Где она встанет дальше — показывает [color=#f0c04a]жёлтый пунктир «след.»[/color] на поле и мини-карты справа.\n\nНаведите на клетку при выбранной карте — справа будет точный исход."},
		{"title": "Удар", "text": "Удар — [b]отдельная кнопка справа[/b], стоит 1 темп и возможен только с линий [b]3–4[/b] (жёлтые номера).\n\nРезультат известен заранее:\n[b]качество + бонус позиции − давление ≥ порог вратаря[/b]\n\nКачество растёт от передач и финтов. Давление — опасные зоны в вашем коридоре между мячом и воротами. Не тратьте весь темп: без удара атака потеряна."},
		{"title": "Тренировка", "text": "Сейчас будет [b]тренировочная атака[/b] с заранее подобранной рукой. Она не идёт в счёт.\n\nНад полем появятся [color=#7cc3e8]подсказки[/color]. Можно делать по-своему — правила те же.\n\nВыйти в меню можно в любой момент клавишей [b]Esc[/b]."},
	]


func _tutorial_hint() -> void:
	if not tutorial_active or state["over"]:
		set_hint("")
		return
	var a: int = state["actions"]
	var hist: Array = state["history"]
	var on_script := true
	var script := [["short_pass", Vector2i(0, 1)], ["one_two", Vector2i(0, 2)], ["short_pass", Vector2i(0, 3)]]
	for k in mini(a, script.size()):
		if hist[k]["card"] != script[k][0] or hist[k]["to"] != script[k][1]:
			on_script = false
	if not on_script:
		var si := RulesA.shot_info(state)
		if si["available"] and si["goal"]:
			set_hint("удар сейчас даёт гол — нажмите «Удар».")
		else:
			set_hint("выберите карту, затем зелёную клетку. Помните: 1 темп нужен на удар.")
		return
	match a:
		0:
			set_hint("центр впереди закрыт. Нажмите [b]«Короткий пас»[/b], затем клетку [b]левый коридор, линия 2[/b].")
		1:
			set_hint("[b]«Стеночка»[/b] работает сразу после паса и не перехватывается. Цель — [b]левый, линия 3[/b].")
		2:
			set_hint("ещё один [b]«Короткий пас»[/b] вперёд: [b]левый, линия 4[/b].")
		3:
			set_hint("кнопка «Удар» уже показывает [b]ГОЛ[/b]. Можно бить, а можно сыграть [b]«Финт»[/b] (+1 качества) — темпа хватит.")
		_:
			set_hint("нажмите [b]«Удар»[/b].")
