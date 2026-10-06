extends GameBase
## Режим B «Три касания»: собрать план (2 действия + удар), затем «Разыграть» — без вмешательства.

var state: Dictionary = {}
var selected := -1  # индекс карты в руке
var active_slot := 0
var hovered_slot := -1
var cards: Array[CardView] = []

var _def_title: Label
var _def_hint: Label
var _minis: Array[MiniPlan] = []
var _slot_boxes: Array[Panel] = []
var _slot_title: Array[Label] = []
var _slot_body: Array[RichTextLabel] = []
var _slot_x: Array[Button] = []
var _swap_btn: Button
var _info: RichTextLabel
var _play_btn: Button
var _play_sub: Label

const STEP_CAPS := ["действие 1", "действие 2", "удар"]


func _mode_id() -> String:
	return "b"


func _template_name() -> String:
	return state.get("plan", {}).get("name", "")


func _build_mode_ui() -> void:
	panel(right, Rect2(0, 0, 632, 140))
	_def_title = lbl(right, "", Vector2(14, 8), 20)
	_def_hint = lbl(right, "", Vector2(14, 38), 14, Game.C_MUTED, 320)
	lbl(right, "Все три положения обороны известны заранее →", Vector2(14, 114), 12, Game.C_MUTED)
	for i in 3:
		var m := MiniPlan.new()
		m.position = Vector2(344 + i * 96, 10)
		m.size = Vector2(90, 120)
		right.add_child(m)
		_minis.append(m)
	# слоты
	panel(right, Rect2(0, 148, 632, 156))
	for i in 3:
		var box := Panel.new()
		box.position = Vector2(12 + i * 212, 160)
		box.size = Vector2(184, 132)
		box.mouse_filter = Control.MOUSE_FILTER_STOP
		box.gui_input.connect(_on_slot_input.bind(i))
		box.mouse_entered.connect(_on_slot_hover.bind(i, true))
		box.mouse_exited.connect(_on_slot_hover.bind(i, false))
		right.add_child(box)
		_slot_boxes.append(box)
		var t := lbl(box, "%d · %s" % [i + 1, RulesB.SLOT_NAMES[i]], Vector2(10, 6), 16, Game.C_ACCENT)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_slot_title.append(t)
		var body := rich(box, Rect2(10, 32, 168, 96), 14)
		_slot_body.append(body)
		if i < 2:
			var x := Button.new()
			x.text = "×"
			x.position = Vector2(148, 4)
			x.size = Vector2(30, 26)
			x.focus_mode = Control.FOCUS_NONE
			x.tooltip_text = "Убрать карту из слота"
			x.pressed.connect(_on_remove.bind(i))
			box.add_child(x)
			_slot_x.append(x)
	_swap_btn = button(right, "⇄", Rect2(197, 206, 26, 40), _on_swap, 16)
	_swap_btn.tooltip_text = "Поменять местами слоты 1 и 2"
	# инфо и запуск
	panel(right, Rect2(0, 312, 632, 100))
	_info = rich(right, Rect2(14, 318, 604, 90), 15)
	_play_btn = button(right, "", Rect2(0, 418, 632, 58), _on_play, 24)
	_play_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_play_sub = lbl(_play_btn, "", Vector2(250, 8), 15, Game.C_MUTED, 370)
	_play_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pitch.cell_clicked.connect(_on_cell_clicked)
	pitch.cell_hovered.connect(_on_cell_hovered)


func _start_attack(tutorial: bool) -> void:
	state = RulesB.new_attack(Game.series_seed, attack_idx, tutorial)
	selected = -1
	active_slot = 0
	hovered_slot = -1
	pitch.clear_marks()
	pitch.set_route([])
	pitch.place_all(state["start"], RulesB.danger(state, 0))
	_refresh()


# ------------------------------------------------------------------ интерфейс
func _field_step() -> int:
	if hovered_slot >= 0:
		return hovered_slot
	if busy or state["over"]:
		return -1
	if RulesB.slot_status(state, 0)["ok"] and RulesB.slot_status(state, 1)["ok"] and selected < 0:
		return 2
	return active_slot


func _refresh() -> void:
	var plan: Dictionary = state["plan"]
	_def_title.text = "Оборона: " + plan["name"]
	_def_hint.text = plan["hint"]
	var fs := _field_step()
	var sim := RulesB.simulate(state)
	for i in 3:
		var ball_mark := Pitch.NONE
		if i == 0:
			ball_mark = state["start"]
		elif i - 1 < sim["steps"].size() and not sim["steps"][i - 1]["intercepted"]:
			ball_mark = sim["steps"][i - 1]["to"]
		_minis[i].set_data(RulesB.danger(state, i), ball_mark, STEP_CAPS[i], i == fs)
	if fs >= 0 and not busy:
		pitch.set_danger(RulesB.danger(state, fs), [])
		pitch.move_defenders(RulesB.danger(state, fs), dur(0.18))
	_refresh_slots(sim)
	_show_route(sim)
	_build_hand()
	_update_play(sim)
	_default_info(sim)
	_tutorial_hint(sim)


func _refresh_slots(sim: Dictionary) -> void:
	for i in 3:
		var box := _slot_boxes[i]
		var active: bool = i == active_slot and not busy and not state["over"] and i < 2
		var border := Game.C_ACCENT if active else Game.C_BORDER
		var bg := Game.C_PANEL_LIGHT if active else Color(0.11, 0.085, 0.07, 0.95)
		if i == hovered_slot:
			border = border.lightened(0.3)
		box.add_theme_stylebox_override("panel", Game.box(bg, border, 10, 3 if active else 2))
		var step_res := ""
		if i < sim["steps"].size():
			var st: Dictionary = sim["steps"][i]
			step_res = "[color=#e4553f]✕ перехват: %s[/color]" % Pitch.cell_name(st["cell"]) if st["intercepted"] \
				else "[color=#86d46f]✓ проходит, качество +%d[/color]" % st["quality_gain"]
		if i == 2:
			var shot: Dictionary = sim["shot"]
			if sim["broke_at"] >= 0 and sim["broke_at"] < 2:
				_slot_body[i].text = "Удар\n[color=#b9a68d]отменён: план сломается раньше[/color]"
			elif shot.is_empty():
				_slot_body[i].text = "Удар — всегда последний.\n[color=#b9a68d]Сначала заполните слоты 1 и 2.[/color]"
			elif not shot["available"]:
				_slot_body[i].text = "Удар\n[color=#e4553f]с линии %d невозможен[/color]" % (sim["final_ball"].y + 1)
			else:
				_slot_body[i].text = "Удар: %d + %d − %d = [b]%d[/b]\nпорог %d → %s" % [shot["quality"], shot["pos_bonus"], shot["pressure"],
					shot["value"], shot["threshold"], "[color=#86d46f][b]ГОЛ[/b][/color]" if shot["goal"] else "[color=#f0c04a][b]СЕЙВ[/b][/color]"]
			continue
		var stt := RulesB.slot_status(state, i)
		_slot_x[i].visible = stt["filled"] and not busy and not state["over"]
		if not stt["filled"]:
			_slot_body[i].text = "[color=#b9a68d]пусто[/color]\n" + ("[color=#f2a33a]← сюда встанет следующая карта[/color]" if active else "")
		else:
			var d := RulesB.card_def(stt["card"])
			var tgt: String = Pitch.cell_name(stt["target"]) if stt["target"] != Pitch.NONE else "направление не выбрано"
			_slot_body[i].text = "[b]%s[/b]\n→ %s\n%s" % [d["name"], tgt, step_res if stt["ok"] else "[color=#e4553f]" + stt["reason"] + "[/color]"]
	_swap_btn.disabled = busy or state["over"] or (not RulesB.slot_status(state, 0)["filled"] and not RulesB.slot_status(state, 1)["filled"])


func _show_route(sim: Dictionary, extra: Dictionary = {}) -> void:
	var s: Dictionary = extra if not extra.is_empty() else sim
	var segs: Array = []
	for st in s["steps"]:
		var seg := {"from": st["from"], "to": st["to"], "ok": not st["intercepted"], "num": st["slot"] + 1}
		if st["intercepted"]:
			seg["bad"] = st["cell"]
			seg["to"] = st["cell"]
		segs.append(seg)
	if not s["shot"].is_empty() and s["shot"]["available"]:
		segs.append({"from": PitchView.att_pos(s["final_ball"]), "to": PitchView.GOAL_RECT.get_center() + Vector2(0, 12),
			"ok": s["shot"]["goal"], "num": 3})
	pitch.set_route(segs)
	pitch.set_pressure(s["shot"].get("pressure_cells", []) if not s["shot"].is_empty() else [])


func _build_hand() -> void:
	for c in cards:
		c.queue_free()
	cards.clear()
	var n: int = state["hand"].size()
	var gap := 12.0
	var total := n * CardView.SIZE.x + (n - 1) * gap
	var x0 := (1280.0 - total) / 2.0
	for i in n:
		var cv := CardView.new()
		cv.setup(state["hand"][i], RulesB.card_def(state["hand"][i]), i)
		cv.position = Vector2(x0 + i * (CardView.SIZE.x + gap), 6)
		cv.base_y = 6
		hand_box.add_child(cv)
		var in_slot := RulesB.slot_of_card(state, i)
		if in_slot >= 0:
			cv.tag = "слот %d" % (in_slot + 1)
			cv.used = true
		cv.disabled = busy or state["over"] or (in_slot < 0 and RulesB.card_reason(state, i, active_slot) != "")
		cv.selected = i == selected
		cv.pressed.connect(_on_card_pressed)
		cv.hovered.connect(_on_card_hovered)
		cards.append(cv)


func _update_play(sim: Dictionary) -> void:
	var reason := RulesB.ready_reason(state)
	_play_btn.text = "  РАЗЫГРАТЬ ▶"
	_play_btn.disabled = reason != "" or busy
	if busy:
		_play_sub.text = "План исполняется…"
	elif reason != "":
		_play_sub.text = reason
		_play_sub.add_theme_color_override("font_color", Game.C_MUTED)
	else:
		var outcome := {"goal": "план ведёт к ГОЛУ", "save": "вратарь отобьёт удар", "intercept": "план сломается: перехват на шаге %d" % (sim["broke_at"] + 1)}
		_play_sub.text = "Предпросмотр: " + outcome.get(sim["outcome"], "")
		_play_sub.add_theme_color_override("font_color", Game.C_SAFE if sim["outcome"] == "goal" else (Game.C_WARN if sim["outcome"] == "save" else Game.C_DANGER))


func _default_info(sim: Dictionary) -> void:
	if state["over"] or busy:
		return
	if selected >= 0:
		var d := RulesB.card_def(state["hand"][selected])
		_info.text = "[b]%s[/b] → слот %d «%s». %s\n[color=#f2a33a]Дальше:[/color] нажмите подсвеченную клетку на поле. Наведите на клетку — увидите, как изменится весь план." % [
			d["name"], active_slot + 1, RulesB.SLOT_NAMES[active_slot], d["text"]]
		return
	var t := ""
	var r := RulesB.ready_reason(state)
	if r == "":
		t = "План готов. Маршрут на поле: зелёный — проходит, красный — перехват. Можно ещё заменить карты.\n[color=#f2a33a]Дальше:[/color] «Разыграть» или правки (× — убрать, ⇄ — поменять местами)."
	else:
		t = "Соберите план для слота %d «%s». Оборона на поле — та, что будет в момент этого действия.\n[color=#f2a33a]Дальше:[/color] нажмите карту внизу, затем клетку." % [active_slot + 1, RulesB.SLOT_NAMES[active_slot]]
	_info.text = t


# ------------------------------------------------------------------ карты и слоты
func _on_card_hovered(cv: CardView, on: bool) -> void:
	if busy or state.is_empty() or state["over"] or selected >= 0:
		return
	if on:
		var d := RulesB.card_def(cv.card_id)
		var in_slot := RulesB.slot_of_card(state, cv.hand_idx)
		var reason := RulesB.card_reason(state, cv.hand_idx, active_slot)
		if in_slot >= 0:
			_info.text = "[b]%s[/b] уже в слоте %d. Нажмите, чтобы выбрать новое направление.\n[color=#b9a68d]%s[/color]" % [d["name"], in_slot + 1, d["text"]]
		elif reason != "":
			_info.text = "[b]%s[/b] — [color=#e4553f]в слот %d сейчас нельзя:[/color] %s\n[color=#b9a68d]%s[/color]" % [d["name"], active_slot + 1, reason, d["text"]]
		else:
			_info.text = "[b]%s[/b]: %s\n[color=#b9a68d]Нажмите карту, затем клетку — она встанет в слот %d.[/color]" % [d["name"], d["text"], active_slot + 1]
			pitch.set_targets(_target_kinds(cv.hand_idx, active_slot))
	else:
		pitch.set_targets({})
		_default_info(RulesB.simulate(state))


func _target_kinds(hidx: int, slot_i: int) -> Dictionary:
	var out := {}
	for t in RulesB.card_targets(state, hidx, slot_i):
		var from: Vector2i = RulesB.slot_context(state, slot_i)["from"]
		var res := Moves.resolve(RulesB.card_def(state["hand"][hidx]), from, t, RulesB.danger(state, slot_i))
		out[t] = "risk" if res["intercepted"] else ("protected" if not res["beaten"].is_empty() else "safe")
	return out


func _on_card_pressed(cv: CardView) -> void:
	if busy or state["over"]:
		return
	var i := cv.hand_idx
	var in_slot := RulesB.slot_of_card(state, i)
	if in_slot >= 0:
		active_slot = in_slot
	var reason := RulesB.card_reason(state, i, active_slot)
	if reason != "":
		Sfx.play("error")
		_info.text = "[b]%s[/b] — [color=#e4553f]нельзя:[/color] %s" % [cv.title, reason]
		return
	Sfx.play("click")
	if selected == i:
		selected = -1
		pitch.clear_marks()
	else:
		selected = i
		pitch.set_targets(_target_kinds(i, active_slot))
	_refresh()


func _on_slot_input(event: InputEvent, i: int) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if busy or state["over"] or i >= 2:
		return
	Sfx.play("click")
	active_slot = i
	var sl: Dictionary = state["slots"][i]
	selected = sl["hand_idx"] if sl["hand_idx"] >= 0 and RulesB.card_reason(state, sl["hand_idx"], i) == "" else -1
	if selected >= 0:
		pitch.set_targets(_target_kinds(selected, i))
	else:
		pitch.set_targets({})
	_refresh()


func _on_slot_hover(i: int, on: bool) -> void:
	if busy or state.is_empty() or state["over"]:
		return
	hovered_slot = i if on else -1
	_refresh()
	if on:
		_info.text = "Оборона в момент шага %d («%s») показана на поле и на мини-карте «%s»." % [i + 1, RulesB.SLOT_NAMES[i], STEP_CAPS[i]]


func _on_remove(i: int) -> void:
	if busy or state["over"]:
		return
	Sfx.play("card")
	RulesB.remove(state, i)
	active_slot = i
	selected = -1
	pitch.clear_marks()
	_refresh()


func _on_swap() -> void:
	if busy or state["over"]:
		return
	Sfx.play("card")
	RulesB.swap(state)
	selected = -1
	pitch.clear_marks()
	_auto_active()
	_refresh()


func _auto_active() -> void:
	for i in 2:
		var st := RulesB.slot_status(state, i)
		if not st["ok"]:
			active_slot = i
			return
	active_slot = 1


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and not busy and selected >= 0:
		selected = -1
		pitch.clear_marks()
		_refresh()


# ------------------------------------------------------------------ поле
func _on_cell_hovered(cell: Vector2i) -> void:
	if busy or state.is_empty() or state["over"] or selected < 0:
		return
	if not pitch.targets.has(cell):
		_show_route(RulesB.simulate(state))
		return
	var sim := RulesB.preview_place(state, active_slot, selected, cell)
	if sim.is_empty():
		return
	_show_route(sim, sim)
	var t := "[b]Если поставить сюда:[/b] "
	var parts: PackedStringArray = []
	for st in sim["steps"]:
		parts.append("шаг %d %s" % [st["slot"] + 1, "[color=#e4553f]перехват[/color]" if st["intercepted"] else "[color=#86d46f]проходит[/color]"])
	if not sim["shot"].is_empty() and sim["shot"]["available"]:
		parts.append("удар %d против %d → %s" % [sim["shot"]["value"], sim["shot"]["threshold"], "[color=#86d46f]ГОЛ[/color]" if sim["shot"]["goal"] else "[color=#f0c04a]сейв[/color]"])
	elif sim["complete"] and sim["outcome"] == "no_shot":
		parts.append("[color=#e4553f]до линии удара не дойти[/color]")
	_info.text = t + ", ".join(parts) + "."


func _on_cell_clicked(cell: Vector2i) -> void:
	if busy or state["over"]:
		return
	if selected < 0:
		_info.text = "Сначала выберите карту внизу (она встанет в слот %d), затем клетку." % (active_slot + 1)
		return
	if not pitch.targets.has(cell):
		Sfx.play("error")
		_info.text = "[color=#e4553f]Сюда нельзя.[/color] Подходящие клетки подсвечены."
		return
	if RulesB.place(state, active_slot, selected, cell):
		Sfx.play("card")
		selected = -1
		pitch.clear_marks()
		_auto_active()
		_refresh()


# ------------------------------------------------------------------ исполнение
func _on_play() -> void:
	if busy or state["over"] or RulesB.ready_reason(state) != "":
		return
	busy = true  # сразу: повторные нажатия игнорируются
	_play_btn.disabled = true
	selected = -1
	hovered_slot = -1
	pitch.clear_marks()
	Sfx.play("click")
	var sim := RulesB.execute(state)
	_build_hand()
	_refresh_slots(sim)
	_update_play(sim)
	set_hint("")
	var log := "[b]Исполнение плана[/b]"
	_info.text = log
	await wait(0.25)
	for st in sim["steps"]:
		var i: int = st["slot"]
		_highlight_step(i)
		pitch.set_danger(RulesB.danger(state, i), [])
		var d := RulesB.card_def(st["card"])
		var bad: Vector2i = st["cell"] if st["intercepted"] else Pitch.NONE
		var tw: Tween
		if d["path"] == "none" or st["card"] == "dribble":
			tw = pitch.carry_ball(st["to"], dur(0.34), bad)
		else:
			tw = pitch.pass_ball(st["to"], dur(0.36 if st["card"] != "through" else 0.44), bad, st["card"] == "through")
		Sfx.play("pass")
		await tw.finished
		log += "\nШаг %d · %s → %s: %s" % [i + 1, d["name"], Pitch.cell_name(st["to"]),
			"[color=#e4553f]перехват (%s)[/color]" % Pitch.cell_name(st["cell"]) if st["intercepted"] else "[color=#86d46f]прошёл[/color]"]
		_info.text = log
		if st["intercepted"]:
			Sfx.play("intercept")
			shake(7)
			pitch.banner("ПЕРЕХВАТ", Game.C_DANGER, dur(0.8))
			await pitch.steal_ball(st["cell"], dur(0.4)).finished
			await wait(0.7)
			end_attack("intercept", state["end_reason"] + "\nВ момент шага %d оборона стояла так, как на мини-карте «%s». Дальнейшие шаги отменены." % [i + 1, STEP_CAPS[i]])
			return
		if st["quality_gain"] > 0:
			pitch.float_text("+%d к качеству" % st["quality_gain"], PitchView.cell_center(st["to"]) + Vector2(0, -30), Game.C_SAFE)
		if not st["beaten"].is_empty():
			pitch.float_text("обыграл!", PitchView.def_pos(st["beaten"][0]) + Vector2(0, -26), Game.C_INFO)
		pitch.relayout_attackers(st["to"], dur(0.3))
		pitch.set_danger(RulesB.danger(state, i + 1), [])
		await pitch.move_defenders(RulesB.danger(state, i + 1), dur(0.34)).finished
	_highlight_step(2)
	var shot: Dictionary = sim["shot"]
	_info.text = log + "\nУдар: " + Moves.shot_breakdown(shot)
	pitch.set_pressure(shot["pressure_cells"])
	var tw2 := create_tween()
	tw2.tween_property(pitch.carrier, "scale", Vector2(1.2, 1.2), dur(0.22))
	tw2.tween_property(pitch.carrier, "scale", Vector2.ONE, dur(0.12))
	await tw2.finished
	Sfx.play("shot")
	await pitch.shoot_ball(shot["goal"], dur(0.45)).finished
	if shot["goal"]:
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


func _highlight_step(i: int) -> void:
	for k in 3:
		var on := k == i
		_slot_boxes[k].add_theme_stylebox_override("panel", Game.box(Game.C_PANEL_LIGHT if on else Color(0.11, 0.085, 0.07, 0.95), Game.C_INFO if on else Game.C_BORDER, 10, 3 if on else 2))
		_minis[k].highlight = on
		_minis[k].queue_redraw()


# ------------------------------------------------------------------ обучение
func _tutorial_pages() -> Array:
	return [
		{"title": "Режим B · «Три касания»", "text": "Здесь вы [b]не ходите по одному действию[/b]. Вы заранее собираете план — два действия и удар — и запускаете его целиком.\n\nСерия из 5 атак, нужно [b]3 гола[/b]. Атака начинается в центре на [b]линии 2[/b]."},
		{"title": "План", "text": "Справа три слота: [b]1 «Подготовка»[/b], [b]2 «Развитие»[/b], [b]3 «Удар»[/b] (всегда удар).\n\n[b]Нажмите карту внизу, затем клетку на поле[/b] — карта встанет в подсвеченный слот. До запуска можно заменять карты, убирать их (×) и переставлять слоты (⇄). Темпа нет — используются ровно две карты из шести."},
		{"title": "Оборона", "text": "После каждого действия оборона делает шаг. [b]Все три её положения видны заранее[/b] — мини-карты «действие 1», «действие 2», «удар».\n\nКаждое действие проверяется против [b]своего[/b] положения обороны. На поле показано положение для слота, который вы заполняете. Наведите на слот — покажется оборона для этого шага."},
		{"title": "Запуск", "text": "Маршрут на поле показывает план и его исход: [color=#86d46f]зелёный[/color] — проходит, [color=#e4553f]красный[/color] — перехват. В слоте «Удар» — итог: [b]качество + позиция − давление[/b] против порога вратаря.\n\nНажмите [b]«Разыграть»[/b] — после этого план не изменить. При перехвате дальнейшие шаги отменяются, и вы увидите, на каком шаге план сломался."},
		{"title": "Тренировка", "text": "Сейчас будет [b]тренировочная атака[/b] (не идёт в счёт). Над полем — [color=#7cc3e8]подсказки[/color].\n\nEsc — выход в меню в любой момент."},
	]


func _tutorial_hint(sim: Dictionary) -> void:
	if not tutorial_active or state["over"] or busy:
		set_hint("")
		return
	var s0 := RulesB.slot_status(state, 0)
	var s1 := RulesB.slot_status(state, 1)
	if not s0["filled"]:
		set_hint("нажмите [b]«Короткий пас»[/b], затем клетку [b]левый коридор, линия 3[/b] — карта встанет в слот 1.")
	elif not s1["filled"]:
		set_hint("теперь второй [b]«Короткий пас»[/b]: [b]левый коридор, линия 4[/b]. Смотрите на маршрут и слот «Удар».")
	elif sim["outcome"] == "goal":
		set_hint("слот «Удар» показывает [b]ГОЛ[/b]. Нажмите [b]«Разыграть»[/b] и смотрите.")
	else:
		set_hint("этот план не забивает. Уберите карту (×) или поменяйте слоты (⇄) и попробуйте другое направление.")
