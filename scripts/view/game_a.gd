extends GameBase
## Режим A «Комбинация» — матч против соперника.
## Раунд: ваша атака (карты футболистов → клетки, после каждого действия оборона делает шаг),
## затем атака соперника (ставите защитника на его маршрут). Побеждает тот, кто забил больше.

var phase := "attack"  # attack / defense

# --- атака
var state: Dictionary = {}
var selected := -1
var hovered_card := -1
var mull_mode := false
var mull_marks: Array = []
var cards: Array[CardView] = []

var _att_ui: Control
var _def_title: Label
var _def_hint: Label
var _minis: Array[MiniPlan] = []
var _tempo_pips: Control
var _quality_lb: Label
var _holder_lb: Label
var _mull_btn: Button
var _mull_cancel: Button
var _info: RichTextLabel
var _next_lb: RichTextLabel
var _shot_btn: Button
var _shot_sub: Label

# --- защита
var dstate: Dictionary = {}
var dselected := -1
var _dui: Control
var _d_title: Label
var _d_steps: RichTextLabel
var _d_info: RichTextLabel
var _d_next: RichTextLabel
var _d_btn: Button
var _d_sub: Label


func _mode_id() -> String:
	return "a"


func _template_name() -> String:
	if phase == "defense":
		return dstate.get("template_name", "")
	return state.get("plan", {}).get("name", "")


func _opp() -> Dictionary:
	return GameData.opponent()


# ------------------------------------------------------------------ оболочка: раунды и счёт
func _attack_label() -> String:
	var n: int = GameData.series()["attacks"]
	var ph := "атака" if phase == "attack" else "защита"
	if tutorial_active:
		return "Тренировка · " + ph
	return "Раунд %d/%d · %s" % [mini(attack_idx + 1, n), n, ph]


func _draw_pips() -> void:
	var f := ThemeDB.fallback_font
	var us := 0 if tutorial_active else Game.goals()
	var them := 0 if tutorial_active else Game.opp_goals()
	var txt := "ВЫ  %d : %d  %s" % [us, them, _opp()["short"]]
	_pips.draw_rect(Rect2(0, 2, 262, 30), Color(0, 0, 0, 0.35))
	_pips.draw_string(f, Vector2(14, 24), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("f7d27a"))


func _result_style(outcome: String) -> Array:
	if phase == "defense":
		match outcome:
			"tackle":
				return ["Отбор!", Game.C_SAFE]
			"save":
				return ["Сейв: %s" % RulesDefend.keeper()["name"], Game.C_SAFE]
			"goal":
				return ["Гол соперника", Game.C_DANGER]
	return super._result_style(outcome)


func _continue_label() -> String:
	if phase == "attack":
		return "Атака соперника ▶"
	if tutorial_active:
		return "Начать матч ▶"
	var n: int = GameData.series()["attacks"]
	return "Итоги матча ▶" if attack_idx + 1 >= n else "Следующий раунд ▶"


func _offer_retry() -> bool:
	return tutorial_active and phase == "defense"


func _on_continue() -> void:
	if phase == "attack":
		_start_defense()
		return
	super._on_continue()


# ------------------------------------------------------------------ построение интерфейса
func _build_mode_ui() -> void:
	# в верхней панели вместо кружков атак — счёт матча
	_attack_lb.add_theme_font_size_override("font_size", 15)
	_attack_lb.position = Vector2(394, 14)
	_pips.position = Vector2(566, 8)
	_pips.size = Vector2(266, 32)
	_att_ui = _layer_ui()
	_build_attack_ui(_att_ui)
	_dui = _layer_ui()
	_build_defense_ui(_dui)
	_dui.visible = false
	pitch.cell_clicked.connect(_on_cell_clicked)
	pitch.cell_hovered.connect(_on_cell_hovered)


func _layer_ui() -> Control:
	var c := Control.new()
	c.size = right.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(c)
	return c


func _build_attack_ui(ui: Control) -> void:
	panel(ui, Rect2(0, 0, 632, 150))
	_def_title = lbl(ui, "", Vector2(14, 8), 20, Game.C_TEXT)
	_def_hint = lbl(ui, "", Vector2(14, 38), 14, Game.C_MUTED, 320)
	lbl(ui, "Оборона шагает после каждого вашего действия →", Vector2(14, 122), 12, Game.C_MUTED)
	for i in 3:
		var m := MiniPlan.new()
		m.position = Vector2(344 + i * 96, 14)
		m.size = Vector2(90, 120)
		ui.add_child(m)
		_minis.append(m)
	panel(ui, Rect2(0, 158, 632, 58))
	lbl(ui, "Темп", Vector2(14, 160), 15, Game.C_MUTED)
	_tempo_pips = Control.new()
	_tempo_pips.position = Vector2(4, 178)
	_tempo_pips.size = Vector2(150, 36)
	_tempo_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tempo_pips.draw.connect(_draw_tempo)
	ui.add_child(_tempo_pips)
	_quality_lb = lbl(ui, "", Vector2(160, 162), 17, Game.C_TEXT)
	_holder_lb = lbl(ui, "", Vector2(160, 188), 14, Game.C_MUTED)
	_mull_btn = button(ui, "Обмен карт", Rect2(424, 166, 196, 42), _on_mulligan, 16)
	_mull_cancel = button(ui, "Отмена", Rect2(398, 166, 82, 42), _cancel_mulligan, 15)
	_mull_cancel.visible = false
	panel(ui, Rect2(0, 224, 632, 162))
	_info = rich(ui, Rect2(14, 230, 604, 122), 15)
	_next_lb = rich(ui, Rect2(14, 344, 604, 40), 14)
	_shot_btn = button(ui, "", Rect2(0, 394, 632, 82), _on_shot, 26)
	_shot_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_shot_btn.mouse_entered.connect(_on_shot_hover.bind(true))
	_shot_btn.mouse_exited.connect(_on_shot_hover.bind(false))
	_shot_sub = lbl(_shot_btn, "", Vector2(250, 8), 15, Game.C_TEXT, 370)
	_shot_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _build_defense_ui(ui: Control) -> void:
	panel(ui, Rect2(0, 0, 632, 196), Game.C_DEF)
	_d_title = lbl(ui, "", Vector2(14, 8), 20, Game.C_TEXT)
	lbl(ui, "Мяч идёт к ВАШИМ воротам (вверху). Маршрут и игроки соперника видны заранее.", Vector2(14, 36), 13, Game.C_MUTED)
	_d_steps = rich(ui, Rect2(14, 60, 604, 132), 15)
	panel(ui, Rect2(0, 204, 632, 182))
	_d_info = rich(ui, Rect2(14, 212, 604, 120), 15)
	_d_next = rich(ui, Rect2(14, 336, 604, 46), 14)
	_d_btn = button(ui, "", Rect2(0, 394, 632, 82), _on_defend, 26)
	_d_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_d_sub = lbl(_d_btn, "", Vector2(290, 10), 15, Game.C_TEXT, 330)
	_d_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _clear_hand() -> void:
	for c in cards:
		c.queue_free()
	cards.clear()


# ==================================================================== АТАКА
func _start_attack(tutorial: bool) -> void:
	phase = "attack"
	_att_ui.visible = true
	_dui.visible = false
	state = RulesA.new_attack(Game.series_seed, attack_idx, tutorial)
	selected = -1
	hovered_card = -1
	mull_mode = false
	mull_marks = []
	pitch.goal_caption = ""
	pitch.show_shot_band = true
	pitch.queue_redraw()
	pitch.set_route([])
	pitch.clear_marks()
	pitch.reset_chips()
	pitch.place_all(state["ball"], RulesA.danger(state))
	_update_top()
	_refresh()


func _refresh() -> void:
	var plan: Dictionary = state["plan"]
	_def_title.text = "Их оборона: " + plan["name"]
	_def_hint.text = plan["hint"]
	var caps := ["сейчас", "через 1 ход", "через 2 хода"]
	for i in 3:
		_minis[i].set_data(RulesA.danger(state, i), state["ball"] if i == 0 else Pitch.NONE, caps[i], i == 0)
	pitch.set_danger(RulesA.danger(state, 0), RulesA.danger(state, 1) if not state["over"] else [])
	_tempo_pips.queue_redraw()
	_quality_lb.text = "Качество момента: %d" % state["quality"]
	var h: String = state["holder"]
	if h == "":
		_holder_lb.text = "Мяч ещё ни у кого из карт"
	else:
		var pl := GameData.player(h)
		_holder_lb.text = "Мяч у №%d %s · удар %d (%+d к удару)" % [pl["num"], pl["name"], pl["shot"], RulesA.shooter_bonus(h)]
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
	_holder_lb.visible = not mull_mode
	_build_hand()
	_update_shot_button()
	_default_info()
	_tutorial_hint()


func _build_hand() -> void:
	_clear_hand()
	var n: int = state["hand"].size()
	var gap := 14.0
	var total := n * CardView.SIZE.x + (n - 1) * gap
	var x0 := (1280.0 - total) / 2.0
	for i in n:
		var cv := CardView.new()
		cv.setup_player(state["hand"][i], RulesA.card_def(state["hand"][i]), i, false)
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
		var c := Vector2(20 + i * 26, 18)
		var full: bool = i < int(state.get("tempo", 0))
		_tempo_pips.draw_circle(c, 10, Game.C_ACCENT if full else Color(1, 1, 1, 0.12))
		_tempo_pips.draw_arc(c, 10, 0, TAU, 20, Color(0, 0, 0, 0.5), 1.5)


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
		var who: String = info.get("shooter_name", "—")
		_shot_sub.text = "Сейчас: %s (бьёт %s)\n%d + %d %+d − %d = %d (порог %d)" % [res, who, info["quality"], info["pos_bonus"],
			info["shooter_bonus"], info["pressure"], info["value"], info["threshold"]]
		_shot_sub.add_theme_color_override("font_color", Game.C_SAFE if info["goal"] else Game.C_WARN)
		var border := Game.C_SAFE if info["goal"] else Game.C_WARN
		_shot_btn.add_theme_stylebox_override("normal", Game.box(Color("3a2c1f"), border, 10, 3))
		_shot_btn.add_theme_stylebox_override("hover", Game.box(Color("4d3a27"), border.lightened(0.3), 10, 3))


func _card_text(d: Dictionary) -> String:
	var t: String = d["text"]
	if d.has("player"):
		var pl: Dictionary = d["player"]
		t = "Мяч уходит к №%d %s (%s). %s" % [pl["num"], pl["name"], pl["pos"], t]
		if int(d["mastery"]) > 0:
			t += " [color=#86d46f]Мастерство: +%d к качеству[/color]." % d["mastery"]
	return t


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
		_info.text = "[b]%s[/b] выбрана. %s\n[color=#b9a68d]Наведите на подсвеченную клетку — увидите исход. Зелёная — безопасно, красная — перехват, голубая — проход через защитника.[/color]" % [d["name"], _card_text(d)]
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
		parts.append("выберите футболиста (доступно: %d)" % playable)
	var info := RulesA.shot_info(state)
	if info["available"]:
		parts.append("нажмите «Удар» (%s)" % ("гол" if info["goal"] else "вратарь отобьёт"))
	if RulesA.can_mulligan(state):
		parts.append("или обменяйте карты")
	return ", ".join(parts) + "."


func _on_card_hovered(cv: CardView, on: bool) -> void:
	if phase == "defense":
		_on_dcard_hovered(cv, on)
		return
	if busy or state.is_empty() or state["over"]:
		return
	hovered_card = cv.hand_idx if on else -1
	if selected >= 0 or mull_mode:
		return
	if on:
		var reason := RulesA.card_block_reason(state, cv.hand_idx)
		var d := RulesA.card_def(cv.card_id)
		if reason != "":
			_info.text = "[b]%s[/b] — [color=#e4553f]сейчас нельзя:[/color] %s\n[color=#b9a68d]%s[/color]" % [d["name"], reason, _card_text(d)]
			pitch.set_targets({})
		else:
			_info.text = "[b]%s[/b] (темп %d): %s\n[color=#b9a68d]Нажмите карту, затем клетку на поле.[/color]" % [d["name"], d["cost"], _card_text(d)]
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
	if phase == "defense":
		_on_dcard_pressed(cv)
		return
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
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) or busy:
		return
	if phase == "attack" and selected >= 0:
		selected = -1
		pitch.clear_marks()
		for c in cards:
			c.selected = false
		_default_info()
	elif phase == "defense" and dselected >= 0:
		dselected = -1
		_refresh_defense()


func _on_cell_hovered(cell: Vector2i) -> void:
	if phase == "defense":
		_on_dcell_hovered(cell)
		return
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
		t += "Качество %d → [b]%d[/b], темп %d → %d. Оборона затем шагнёт (пунктир «след.»)." % [state["quality"], after["quality"], state["tempo"], after["tempo"]]
		if p["ends"]:
			t += "\n[color=#e4553f]Внимание: после этого не останется ни одного действия — мяч будет потерян.[/color]"
		else:
			var si := RulesA.shot_info(after)
			if si["available"]:
				t += "\nУдар после хода: [b]%s[/b] (%d против %d, бьёт %s)." % ["ГОЛ" if si["goal"] else "сейв", si["value"], si["threshold"], si.get("shooter_name", "—")]
	_info.text = t


func _on_cell_clicked(cell: Vector2i) -> void:
	if phase == "defense":
		_on_dcell_clicked(cell)
		return
	if busy or state["over"]:
		return
	if selected < 0:
		if not mull_mode:
			_info.text = "Сначала выберите футболиста внизу, затем клетку. [color=#f2a33a]Дальше:[/color] " + _next_text()
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
	var num: int = d["player"]["num"] if d.has("player") else -1
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
	var action: String = d["action"]
	var tw: Tween
	if d["path"] == "none" or action == "dribble":
		tw = pitch.carry_ball(cell, dur(0.32), bad, num)
	else:
		tw = pitch.pass_ball(cell, dur(0.34 if action != "through" else 0.42), bad, action == "through", num)
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


func _on_shot_hover(on: bool) -> void:
	if busy or state.is_empty() or state["over"] or phase != "attack":
		return
	var info := RulesA.shot_info(state)
	if on and info["available"]:
		pitch.set_pressure(info["pressure_cells"])
		var t := "[b]Удар[/b] из зоны «%s»: %s.\n" % [Pitch.cell_name(state["ball"]), Moves.shot_breakdown(info)]
		t += "Бьёт тот, у кого мяч: удар %d даёт %+d. Позиция: ближе к воротам и по центру — больше. " % [info.get("shooter_shot", 3), info["shooter_bonus"]]
		if info["pressure"] > 0:
			t += "[color=#c98cff]Давление %d — опасные зоны в коридоре до ворот (фиолетовые).[/color]" % info["pressure"]
		t += "\nИтог: [b]%s[/b]." % ("ГОЛ" if info["goal"] else "вратарь отобьёт")
		_info.text = t
	elif on:
		_info.text = "[b]Удар[/b] недоступен: " + info["reason"]
	else:
		pitch.set_pressure([])
		_default_info()


func _on_shot() -> void:
	if busy or phase != "attack" or state["over"]:
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


# ==================================================================== ЗАЩИТА
func _start_defense() -> void:
	phase = "defense"
	attack_over = false
	busy = false
	_att_ui.visible = false
	_dui.visible = true
	dstate = RulesDefend.new_defense(Game.series_seed, attack_idx, state["deck"], tutorial_active)
	dselected = -1
	pitch.clear_marks()
	pitch.set_danger([], [])
	pitch.set_preview({})
	pitch.show_shot_band = false
	pitch.goal_caption = "ВАШИ ВОРОТА"
	pitch.queue_redraw()
	pitch.reset_chips()
	_place_defense_chips(0.0)
	_hint_lb.visible = tutorial_active
	_update_top()
	Sfx.play("whistle")
	_refresh_defense()


## Фишки фазы защиты: синие — соперник (разыгрывающий на старте и по одному на каждом шаге),
## оранжевая — ваш поставленный защитник, зелёный — ваш вратарь.
func _place_defense_chips(d: float) -> void:
	var opp: Dictionary = _opp()["players"]
	var route: Array = dstate["route"]
	var tw: Tween = create_tween().set_parallel(true) if d > 0 else null
	if tw:
		tw.tween_interval(0.01)
	for i in pitch.defenders.size():
		var ch: Chip = pitch.defenders[i]
		var target: Vector2
		var alpha := 1.0
		if i == 0:
			ch.number = 5
			target = PitchView.def_pos(route[0])
		elif i <= 3:
			ch.number = opp[dstate["attackers"][i - 1]]["num"]
			target = PitchView.def_pos(route[i])
		else:
			target = Vector2(300, -40)
			alpha = 0.0
		ch.queue_redraw()
		if tw:
			tw.tween_property(ch, "position", target, d)
			tw.tween_property(ch, "modulate:a", alpha, d)
		else:
			ch.position = target
			ch.modulate.a = alpha
	# наши: один оранжевый на каждого поставленного
	var used := 0
	for k in RulesDefend.STEPS:
		var hi: int = dstate["placed"][k]
		if hi < 0:
			continue
		var ch2: Chip = pitch.attackers[used]
		ch2.number = GameData.player(dstate["hand"][hi])["num"]
		ch2.queue_redraw()
		var p := PitchView.att_pos(RulesDefend.step_cell(dstate, k))
		if tw:
			tw.tween_property(ch2, "position", p, d)
			tw.tween_property(ch2, "modulate:a", 1.0, d)
		else:
			ch2.position = p
			ch2.modulate.a = 1.0
		used += 1
	for j in range(used, pitch.attackers.size()):
		pitch.attackers[j].modulate.a = 0.0
		pitch.attackers[j].glow = 0.0
	for a in pitch.attackers:
		a.glow = 0.0
		a.queue_redraw()
	pitch.carrier = null
	pitch.ball.position = PitchView.def_pos(route[0]) + Vector2(-10, 8)
	pitch.ball.height = 0
	pitch.keeper.position = Vector2(300, PitchView.FIELD.position.y + 6)
	pitch.keeper.rotation = 0
	pitch.keeper.number = RulesDefend.keeper()["num"]


func _refresh_defense() -> void:
	var opp: Dictionary = _opp()["players"]
	_d_title.text = "Атака соперника: " + dstate["template_name"]
	var sim := RulesDefend.simulate(dstate)
	var lines: PackedStringArray = []
	for k in RulesDefend.STEPS:
		var a: Dictionary = opp[dstate["attackers"][k]]
		var cell := RulesDefend.step_cell(dstate, k)
		var mark := ""
		if k < sim["steps"].size():
			var st: Dictionary = sim["steps"][k]
			if st["tackled"]:
				mark = " → [color=#86d46f]отбор: %s (%d)[/color]" % [GameData.player(st["defender"])["name"], st["tackle"]]
			elif st["beaten"]:
				mark = " → [color=#e4553f]обыгрывает %s (%d)[/color]" % [GameData.player(st["defender"])["name"], st["tackle"]]
		else:
			mark = " [color=#b9a68d](не дойдёт)[/color]"
		lines.append("[b]Шаг %d[/b] · %s: №%d %s, дриблинг [b]%d[/b]%s" % [k + 1, Pitch.cell_name(cell), a["num"], a["name"], a["drib"], mark])
	var sh: Dictionary = opp[dstate["attackers"][RulesDefend.STEPS - 1]]
	var kp := RulesDefend.keeper()
	var shot_res := "[color=#b9a68d](не дойдёт)[/color]"
	if not sim["shot"].is_empty():
		shot_res = "[color=#e4553f]гол[/color]" if sim["shot"]["goal"] else "[color=#86d46f]сейв[/color]"
	lines.append("[b]Удар[/b]: %s, удар [b]%d[/b] против вашего вратаря %s, реакция [b]%d[/b] → %s" % [sh["name"], sh["shot"], kp["name"], kp["reaction"], shot_res])
	_d_steps.text = "\n".join(lines)
	# маршрут на поле
	var segs: Array = []
	for k in RulesDefend.STEPS:
		var seg := {"from": PitchView.def_pos(dstate["route"][k]), "to": PitchView.def_pos(dstate["route"][k + 1]), "num": k + 1,
			"col": Color(0.55, 0.75, 1.0)}
		if k < sim["steps"].size() and sim["steps"][k]["tackled"]:
			seg["bad"] = dstate["route"][k + 1]
			seg["col"] = Game.C_SAFE
		elif k >= sim["steps"].size():
			seg["dim"] = true
		segs.append(seg)
	if not sim["shot"].is_empty():
		segs.append({"from": PitchView.def_pos(dstate["route"][3]), "to": PitchView.GOAL_RECT.get_center() + Vector2(0, 12), "num": "У",
			"col": Game.C_DANGER if sim["shot"]["goal"] else Game.C_WARN})
	pitch.set_route(segs)
	# рука защиты
	_clear_hand()
	var n: int = dstate["hand"].size()
	var gap := 18.0
	var x0 := (1280.0 - (n * CardView.SIZE.x + (n - 1) * gap)) / 2.0
	var dl: Dictionary = RulesA.cfg()["defend_lines"]
	for i in n:
		var id: String = dstate["hand"][i]
		var cv := CardView.new()
		cv.setup_player(id, RulesA.card_def(id), i, true, RulesDefend.lines_text(dl[GameData.player(id)["pos"]]))
		cv.position = Vector2(x0 + i * (CardView.SIZE.x + gap), 6)
		cv.base_y = 6
		hand_box.add_child(cv)
		var st_i := RulesDefend.step_of(dstate, i)
		if st_i >= 0:
			cv.tag = "шаг %d" % (st_i + 1)
		cv.disabled = busy or dstate["over"] or (st_i < 0 and _legal_steps(i).is_empty())
		cv.selected = i == dselected
		cv.pressed.connect(_on_card_pressed)
		cv.hovered.connect(_on_card_hovered)
		cards.append(cv)
	if dselected >= 0:
		pitch.set_targets(_dtarget_kinds(dselected))
	else:
		pitch.set_targets({})
	# кнопка и подсказки
	_d_btn.text = "  ЗАЩИЩАТЬСЯ ▶"
	_d_btn.disabled = busy or dstate["over"]
	var outcome_txt := {"tackle": "отбор на шаге %d" % (sim["stopped_at"] + 1), "save": "удар отобьёт вратарь", "goal": "соперник ЗАБЬЁТ"}
	_d_sub.text = "Сейчас: " + outcome_txt[sim["outcome"]]
	_d_sub.add_theme_color_override("font_color", Game.C_DANGER if sim["outcome"] == "goal" else Game.C_SAFE)
	_d_btn.add_theme_stylebox_override("normal", Game.box(Color("3a2c1f"), Game.C_DANGER if sim["outcome"] == "goal" else Game.C_SAFE, 10, 3))
	if not busy and not dstate["over"]:
		_ddefault_info()
	_tutorial_hint()


## Шаги, куда можно поставить карту (с учётом того, что одно место можно освободить заменой).
func _legal_steps(i: int) -> Array:
	var out: Array = []
	for k in RulesDefend.STEPS:
		var probe: Dictionary = dstate.duplicate(true)
		if RulesDefend.step_of(probe, i) < 0 and RulesDefend.placed_count(probe) >= int(RulesA.cfg()["defense_slots"]):
			probe["placed"] = [-1, -1, -1]
		if RulesDefend.place_reason(probe, i, k) == "":
			out.append(k)
	return out


func _place_with_swap(i: int, k: int) -> bool:
	if RulesDefend.step_of(dstate, i) < 0 and RulesDefend.placed_count(dstate) >= int(RulesA.cfg()["defense_slots"]) \
			and RulesDefend.place_reason(dstate, i, k) != "":
		# мест нет — прежний защитник уходит, новый встаёт
		var probe: Dictionary = dstate.duplicate(true)
		probe["placed"] = [-1, -1, -1]
		if RulesDefend.place_reason(probe, i, k) != "":
			return false
		dstate["placed"] = [-1, -1, -1]
	return RulesDefend.place(dstate, i, k)


func _dtarget_kinds(i: int) -> Dictionary:
	var out := {}
	var tk := int(GameData.player(dstate["hand"][i])["tackle"])
	for k in _legal_steps(i):
		var a: Dictionary = _opp()["players"][dstate["attackers"][k]]
		out[RulesDefend.step_cell(dstate, k)] = "safe" if tk >= int(a["drib"]) else "risk"
	return out


func _ddefault_info() -> void:
	var slots: int = RulesA.cfg()["defense_slots"]
	if dselected >= 0:
		var pl := GameData.player(dstate["hand"][dselected])
		_d_info.text = "[b]№%d %s[/b] (%s), отбор [b]%d[/b]. Зелёные клетки — там он отберёт мяч, красные — его обыграют.\n[color=#b9a68d]Наведите на клетку — увидите исход всей атаки.[/color]" % [
			pl["num"], pl["name"], pl["pos"], pl["tackle"]]
		_d_next.text = "[color=#f2a33a]Дальше:[/color] нажмите клетку маршрута. Правая кнопка — отмена."
		return
	var who := "одного защитника" if slots == 1 else "до %d защитников" % slots
	_d_info.text = "Поставьте %s на шаг маршрута. Отбор ≥ дриблинга соперника на этом шаге — мяч ваш. Иначе он проходит дальше и в конце бьёт: гол, если удар больше реакции вашего вратаря.\nПозиция ограничивает линии: защитники — у своих ворот, полузащитники — в середине, нападающие — только на первой линии прессинга." % who
	_d_next.text = "[color=#f2a33a]Дальше:[/color] выберите футболиста внизу и клетку маршрута — или сразу «Защищаться»."


func _on_dcard_hovered(cv: CardView, on: bool) -> void:
	if busy or dstate.is_empty() or dstate["over"] or dselected >= 0:
		return
	if on:
		var pl := GameData.player(cv.card_id)
		var steps := _legal_steps(cv.hand_idx)
		if steps.is_empty():
			_d_info.text = "[b]%s[/b] — [color=#e4553f]некуда встать:[/color] %s защищается на линиях %s, а маршрут там не проходит." % [
				pl["name"], pl["pos"], RulesDefend.lines_text(RulesA.cfg()["defend_lines"][pl["pos"]])]
		else:
			_d_info.text = "[b]№%d %s[/b], отбор [b]%d[/b]. Может встать на шаги: %s." % [pl["num"], pl["name"], pl["tackle"],
				", ".join(PackedStringArray(steps.map(func(k): return str(k + 1))))]
			pitch.set_targets(_dtarget_kinds(cv.hand_idx))
	else:
		pitch.set_targets({})
		_ddefault_info()


func _on_dcard_pressed(cv: CardView) -> void:
	if busy or dstate["over"]:
		return
	var i := cv.hand_idx
	if _legal_steps(i).is_empty() and RulesDefend.step_of(dstate, i) < 0:
		Sfx.play("error")
		_wiggle(cv)
		return
	Sfx.play("click")
	dselected = -1 if dselected == i else i
	_refresh_defense()


func _step_at(cell: Vector2i) -> int:
	for k in RulesDefend.STEPS:
		if RulesDefend.step_cell(dstate, k) == cell:
			return k
	return -1


func _on_dcell_hovered(cell: Vector2i) -> void:
	if busy or dstate.is_empty() or dstate["over"] or dselected < 0:
		return
	var k := _step_at(cell)
	if k < 0 or not pitch.targets.has(cell):
		_ddefault_info()
		return
	var probe: Dictionary = dstate.duplicate(true)
	if RulesDefend.step_of(probe, dselected) < 0 and RulesDefend.placed_count(probe) >= int(RulesA.cfg()["defense_slots"]):
		probe["placed"] = [-1, -1, -1]
	RulesDefend.place(probe, dselected, k)
	var sim := RulesDefend.simulate(probe)
	var res := {"tackle": "[color=#86d46f]ОТБОР на шаге %d — соперник не ударит[/color]" % (sim["stopped_at"] + 1),
		"save": "[color=#86d46f]соперник дойдёт до удара, но вратарь отобьёт[/color]", "goal": "[color=#e4553f]соперник пройдёт и ЗАБЬЁТ[/color]"}
	_d_info.text = "[b]Если поставить сюда:[/b] " + res[sim["outcome"]] + "."


func _on_dcell_clicked(cell: Vector2i) -> void:
	if busy or dstate["over"]:
		return
	var k := _step_at(cell)
	if dselected < 0:
		if k >= 0 and dstate["placed"][k] >= 0:
			Sfx.play("card")
			RulesDefend.remove(dstate, k)
			_place_defense_chips(dur(0.2))
			_refresh_defense()
		return
	if k < 0 or not _place_with_swap(dselected, k):
		Sfx.play("error")
		_d_info.text = "[color=#e4553f]Сюда нельзя.[/color] Подходящие клетки маршрута подсвечены."
		return
	Sfx.play("card")
	dselected = -1
	_place_defense_chips(dur(0.25))
	_refresh_defense()


func _on_defend() -> void:
	if busy or phase != "defense" or dstate["over"]:
		return
	busy = true
	dselected = -1
	pitch.set_targets({})
	Sfx.play("click")
	var sim := RulesDefend.execute(dstate)
	_refresh_defense()
	set_hint("")
	_d_info.text = "[b]Атака соперника…[/b]"
	_d_next.text = ""
	var opp: Dictionary = _opp()["players"]
	var log := "[b]Атака соперника[/b]"
	await wait(0.2)
	for st in sim["steps"]:
		var k: int = st["k"]
		var receiver: Chip = pitch.defenders[k + 1]
		var dest := receiver.position + Vector2(-10, 8)
		Sfx.play("pass")
		await _ball_to(dest, dur(0.34)).finished
		var a: Dictionary = opp[st["attacker"]]
		if st["tackled"]:
			var mine := _my_chip_at(k)
			var tw := create_tween().set_parallel(true)
			if mine:
				tw.tween_property(mine, "position", receiver.position + Vector2(-6, 10), dur(0.18))
			tw.tween_property(pitch.ball, "position", (mine.position if mine else dest) + Vector2(-14, 16), dur(0.25))
			await tw.finished
			Sfx.play("safe")
			pitch.banner("ОТБОР!", Game.C_SAFE, dur(0.8))
			pitch.celebrate(dur(0.9))
			log += "\nШаг %d: отбор! %s — %d, %s — %d." % [k + 1, GameData.player(st["defender"])["name"], st["tackle"], a["name"], st["drib"]]
			_d_info.text = log
			await wait(1.0)
			end_defense("tackle", dstate["end_reason"])
			return
		if st["beaten"]:
			var mine2 := _my_chip_at(k)
			if mine2:
				var tw2 := create_tween()
				tw2.tween_property(mine2, "rotation", 0.8, dur(0.15))
				tw2.tween_property(mine2, "modulate:a", 0.5, dur(0.15))
			pitch.float_text("обыграл!", receiver.position + Vector2(0, -26), Game.C_DANGER)
			log += "\nШаг %d: %s проходит защитника %s (дриблинг %d > отбор %d)." % [k + 1, a["name"], GameData.player(st["defender"])["name"], st["drib"], st["tackle"]]
		else:
			log += "\nШаг %d: %s принимает мяч, никто не мешает." % [k + 1, a["name"]]
		_d_info.text = log
		await wait(0.15)
	var shot: Dictionary = sim["shot"]
	log += "\nУдар: %s (%d) против %s (%d)." % [opp[shot["shooter"]]["name"], shot["shot"], RulesDefend.keeper()["name"], shot["reaction"]]
	_d_info.text = log
	var shooter: Chip = pitch.defenders[RulesDefend.STEPS]
	var tw3 := create_tween()
	tw3.tween_property(shooter, "scale", Vector2(1.2, 1.2), dur(0.2))
	tw3.tween_property(shooter, "scale", Vector2.ONE, dur(0.12))
	await tw3.finished
	Sfx.play("shot")
	await pitch.shoot_ball(shot["goal"], dur(0.45)).finished
	if shot["goal"]:
		Sfx.play("lost")
		pitch.crowd_sigh(dur(0.9))
		pitch.banner("ГОЛ СОПЕРНИКА", Game.C_DANGER, dur(0.9))
		shake(6)
	else:
		Sfx.play("save")
		pitch.celebrate(dur(1.0))
		pitch.banner("СЕЙВ!", Game.C_SAFE, dur(0.9))
	await wait(1.1)
	end_defense(dstate["outcome"], dstate["end_reason"])


func _my_chip_at(k: int) -> Chip:
	var p := PitchView.att_pos(RulesDefend.step_cell(dstate, k))
	for a in pitch.attackers:
		if a.modulate.a > 0.5 and a.position.distance_to(p) < 4:
			return a
	return null


func _ball_to(dest: Vector2, d: float) -> Tween:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(pitch.ball, "position", dest, d).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(func(t: float): pitch.ball.height = sin(t * PI) * 10.0, 0.0, 1.0, d)
	return tw


func end_defense(outcome: String, reason: String) -> void:
	attack_over = true
	busy = false
	if not tutorial_active:
		Game.record_defense(outcome, reason, dstate.get("template_name", ""))
	_update_top()
	_hint_lb.visible = false
	_show_result(outcome, reason)
	if _overlay and is_instance_valid(_overlay):
		_overlay.move_to_front()


# ==================================================================== ОБУЧЕНИЕ
func _tutorial_pages() -> Array:
	return [
		{"title": "Матч во дворе", "text": "Вы играете против команды [b]«%s»[/b]. Матч — [b]5 раундов[/b]: в каждом сначала атакуете вы, потом соперник. Побеждает тот, кто забьёт больше.\n\nПоле: [b]3 коридора[/b] (левый, центр, правый) и [b]4 линии[/b] — номера слева. В вашей атаке ворота соперника вверху." % _opp()["name"]},
		{"title": "Карты — ваши футболисты", "text": "Каждая карта — игрок вашей команды: номер, позиция, характеристики [b]Пас, Дриблинг, Удар, Отбор[/b] и одно умение (короткий пас, обводка, финт…).\n\n[b]Нажмите карту, затем подсвеченную клетку[/b] — мяч уходит этому игроку. Жёлтый круг — цена в темпе (на атаку 5). Пас или дриблинг 4+ даёт [b]+1 к качеству[/b]. До первого хода можно один раз обменять до двух карт."},
		{"title": "Оборона соперника", "text": "[color=#e4553f]Красные клетки[/color] — опасные зоны. Обычный пас туда [b]перехватят[/b].\n\nПосле [b]каждого[/b] вашего действия оборона делает [b]один шаг[/b] своего плана. Где она встанет дальше — [color=#f0c04a]жёлтый пунктир «след.»[/color] и мини-карты справа. Наведите на клетку — справа будет точный исход."},
		{"title": "Удар", "text": "Удар — [b]кнопка справа[/b], 1 темп, только с линий [b]3–4[/b].\n\n[b]качество + позиция + удар игрока − давление ≥ порог вратаря[/b]\n\nБьёт тот, у кого мяч: удар 5 даёт +2, удар 1 — −2. Поэтому завершайте комбинацию нападающим. Результат виден на кнопке заранее. Не тратьте весь темп: без удара атака потеряна."},
		{"title": "Защита", "text": "Потом атакует соперник. Его [b]маршрут виден целиком[/b]: три шага к вашим воротам, на каждом — его игрок с дриблингом, в конце удар.\n\nПоставьте [b]одного[/b] из трёх футболистов на шаг маршрута. [b]Отбор ≥ дриблинга[/b] — мяч ваш. Не отобрали — бьют: гол, если удар больше реакции вашего вратаря. Защитники стоят у своих ворот, полузащитники — в середине, нападающие — только на первой линии."},
		{"title": "Тренировка", "text": "Сейчас будет [b]тренировочный раунд[/b] — атака и защита с заранее подобранными картами. Он не идёт в счёт.\n\nНад полем появятся [color=#7cc3e8]подсказки[/color]. Esc — выход в меню в любой момент."},
	]


func _tutorial_hint() -> void:
	if not tutorial_active:
		set_hint("")
		return
	if phase == "defense":
		if dstate.is_empty() or dstate["over"] or busy:
			set_hint("")
		elif RulesDefend.simulate(dstate)["outcome"] == "goal":
			set_hint("Рябов (дриблинг 4) забьёт, если его не остановить. Нажмите [b]Миронова[/b] (отбор 5), затем клетку [b]шага 3[/b] — левый коридор, линия 4.")
		else:
			set_hint("кнопка показывает, что соперник не забьёт. Нажмите [b]«Защищаться»[/b].")
		return
	if state["over"]:
		set_hint("")
		return
	var a: int = state["actions"]
	var hist: Array = state["history"]
	var on_script := true
	var script := [["sokolov", Vector2i(0, 1)], ["zaitsev", Vector2i(0, 2)], ["titov", Vector2i(0, 3)]]
	for k in mini(a, script.size()):
		if hist[k]["card"] != script[k][0] or hist[k]["to"] != script[k][1]:
			on_script = false
	if not on_script:
		var si := RulesA.shot_info(state)
		if si["available"] and si["goal"]:
			set_hint("удар сейчас даёт гол — нажмите «Удар».")
		else:
			set_hint("выберите футболиста, затем зелёную клетку. Помните: 1 темп нужен на удар.")
		return
	match a:
		0:
			set_hint("центр впереди закрыт. Нажмите [b]Соколова[/b] (короткий пас), затем клетку [b]левый коридор, линия 2[/b].")
		1:
			set_hint("[b]Зайцев[/b] — «Стеночка»: сразу после паса, без риска перехвата. Цель — [b]левый, линия 3[/b].")
		2:
			set_hint("пас на [b]Титова[/b] вперёд: [b]левый, линия 4[/b]. У него удар 4 — он хорошо бьёт.")
		3:
			set_hint("кнопка «Удар» уже показывает [b]ГОЛ[/b]. Можно бить — или сыграть [b]Козлова[/b] (финт): +2 качества и бить будет он (удар 5).")
		_:
			set_hint("нажмите [b]«Удар»[/b].")
