class_name RulesB
extends RefCounted
## Режим B «Три касания». Атака программируется целиком:
##   слот 1 «Подготовка» → шаг обороны → слот 2 «Развитие» → шаг обороны → слот 3 «Удар».
## Действие слота i проверяется против состояния обороны i (0, 1), удар — против состояния 2.
## Перехват на любом шаге отменяет всё, что дальше. Темпа нет.

const MODE := "b"
const SLOT_NAMES := ["Подготовка", "Развитие", "Удар"]


static func cfg() -> Dictionary:
	return GameData.mode(MODE)


static func card_def(id: String) -> Dictionary:
	return GameData.card(MODE, id)


static func new_attack(series_seed: int, attack_idx: int, tutorial: bool = false) -> Dictionary:
	var c := cfg()
	var rng := Seeds.rng_for(series_seed, "b_deck", attack_idx)
	var deck := Seeds.deck_from_counts(c["deck"])
	Seeds.shuffle(deck, rng)
	var plan: Dictionary
	var hand: Array
	if tutorial:
		plan = Defense.build(MODE, c["tutorial"]["template"], false)
		hand = c["tutorial"]["hand"].duplicate()
	else:
		plan = Defense.pick_for_attack(MODE, series_seed, attack_idx)
		hand = deck.slice(0, int(c["hand_size"]))
	return {
		"mode": MODE,
		"seed": series_seed,
		"attack": attack_idx,
		"tutorial": tutorial,
		"start": c["start"],
		"hand": hand,
		"slots": [_empty_slot(), _empty_slot()],
		"plan": plan,
		"over": false,
		"outcome": "",
		"end_reason": "",
		"end_cell": Pitch.NONE,
	}


static func _empty_slot() -> Dictionary:
	return {"hand_idx": -1, "target": Pitch.NONE}


static func danger(state: Dictionary, step: int) -> Array:
	return Defense.state_at(state["plan"], step)


## Откуда стартует действие слота и какое действие было перед ним (по плану, без учёта перехвата).
static func slot_context(state: Dictionary, slot_i: int) -> Dictionary:
	if slot_i == 0:
		return {"from": state["start"], "prev": "", "ok": true}
	var s0: Dictionary = state["slots"][0]
	if s0["hand_idx"] < 0 or s0["target"] == Pitch.NONE:
		return {"from": state["start"], "prev": "", "ok": false}
	return {"from": s0["target"], "prev": state["hand"][s0["hand_idx"]], "ok": true}


## Почему карту нельзя поставить в слот (пустая строка — можно).
## Завершённость атаки проверяют place/ready_reason, чтобы итог плана оставался виден.
static func card_reason(state: Dictionary, hand_idx: int, slot_i: int) -> String:
	var id: String = state["hand"][hand_idx]
	var d := card_def(id)
	var ctx := slot_context(state, slot_i)
	if not ctx["ok"]:
		return "Сначала заполните слот «%s»." % SLOT_NAMES[0]
	if d.has("slot") and int(d["slot"]) != slot_i:
		return "Эту карту можно поставить только в слот «%s»." % SLOT_NAMES[int(d["slot"])]
	var req := String(d.get("requires_prev", ""))
	if req != "" and ctx["prev"] != req:
		return "Нужен «%s» в слоте «%s»." % [card_def(req)["name"], SLOT_NAMES[0]]
	var from: Vector2i = ctx["from"]
	if d.has("from_max_line") and from.y > int(d["from_max_line"]):
		return "Только когда мяч на линии %d или ниже (сейчас линия %d)." % [int(d["from_max_line"]) + 1, from.y + 1]
	if Moves.targets(d, from).is_empty():
		return "Некуда продвигаться: мяч уже на последней линии."
	return ""


static func card_targets(state: Dictionary, hand_idx: int, slot_i: int) -> Array:
	if card_reason(state, hand_idx, slot_i) != "":
		return []
	var from: Vector2i = slot_context(state, slot_i)["from"]
	return Moves.targets(card_def(state["hand"][hand_idx]), from)


## Какую карту уже занимает слот: индекс руки или -1.
static func slot_of_card(state: Dictionary, hand_idx: int) -> int:
	for i in 2:
		if state["slots"][i]["hand_idx"] == hand_idx:
			return i
	return -1


static func place(state: Dictionary, slot_i: int, hand_idx: int, target: Vector2i) -> bool:
	if state["over"] or slot_i < 0 or slot_i > 1 or not card_targets(state, hand_idx, slot_i).has(target):
		return false
	var other := slot_of_card(state, hand_idx)
	if other >= 0 and other != slot_i:
		state["slots"][other] = _empty_slot()
	state["slots"][slot_i] = {"hand_idx": hand_idx, "target": target}
	_revalidate(state)
	return true


static func remove(state: Dictionary, slot_i: int) -> void:
	if state["over"]:
		return
	state["slots"][slot_i] = _empty_slot()
	_revalidate(state)


## Поменять слоты местами. Цели остаются абсолютными клетками;
## если они перестали быть допустимыми — цель сбрасывается, карта остаётся.
static func swap(state: Dictionary) -> void:
	if state["over"]:
		return
	var a: Dictionary = state["slots"][0]
	state["slots"][0] = state["slots"][1]
	state["slots"][1] = a
	_revalidate(state)


static func _revalidate(state: Dictionary) -> void:
	for i in 2:
		var sl: Dictionary = state["slots"][i]
		if sl["hand_idx"] < 0:
			continue
		if sl["target"] != Pitch.NONE and not card_targets(state, sl["hand_idx"], i).has(sl["target"]):
			sl["target"] = Pitch.NONE


static func slot_status(state: Dictionary, slot_i: int) -> Dictionary:
	var sl: Dictionary = state["slots"][slot_i]
	if sl["hand_idx"] < 0:
		return {"filled": false, "ok": false, "reason": "Пусто"}
	var reason := card_reason(state, sl["hand_idx"], slot_i)
	if reason == "" and sl["target"] == Pitch.NONE:
		reason = "Выберите направление: нажмите слот, затем клетку."
	return {"filled": true, "ok": reason == "", "reason": reason,
		"card": state["hand"][sl["hand_idx"]], "target": sl["target"]}


static func ready_reason(state: Dictionary) -> String:
	if state["over"]:
		return "Атака уже разыграна."
	for i in 2:
		var st := slot_status(state, i)
		if not st["filled"]:
			return "Заполните слот «%s»." % SLOT_NAMES[i]
		if not st["ok"]:
			return "Слот «%s»: %s" % [SLOT_NAMES[i], st["reason"]]
	var final_cell: Vector2i = state["slots"][1]["target"]
	if not cfg()["shot_lines"].has(final_cell.y):
		return "С линии %d удар невозможен — план должен довести мяч до линии 3 или 4." % [final_cell.y + 1]
	return ""


## Полный прогон плана. Ничего не меняет. Используется и для предпросмотра, и для исполнения.
static func simulate(state: Dictionary) -> Dictionary:
	var out := {"steps": [], "shot": {}, "outcome": "", "broke_at": -1, "complete": false,
		"final_ball": state["start"], "quality": 0}
	var pos: Vector2i = state["start"]
	var q := 0
	for i in 2:
		var st := slot_status(state, i)
		if not st["ok"]:
			out["final_ball"] = pos
			out["quality"] = q
			return out
		var d := card_def(st["card"])
		var res := Moves.resolve(d, pos, st["target"], danger(state, i))
		var step := {"slot": i, "card": st["card"], "name": d["name"], "from": pos, "to": st["target"],
			"path": res["path"], "beaten": res["beaten"], "intercepted": res["intercepted"],
			"cell": res["cell"], "quality_gain": res["quality"]}
		out["steps"].append(step)
		if res["intercepted"]:
			out["outcome"] = "intercept"
			out["broke_at"] = i
			out["complete"] = true
			out["final_ball"] = pos
			out["quality"] = q
			return out
		pos = st["target"]
		q += int(res["quality"])
		step["quality_after"] = q
	var shot := Moves.shot_eval(cfg(), q, pos, danger(state, 2), int(state["plan"]["extra_pressure"]))
	out["shot"] = shot
	out["final_ball"] = pos
	out["quality"] = q
	out["complete"] = true
	if not shot["available"]:
		out["outcome"] = "no_shot"
		out["broke_at"] = 2
	else:
		out["outcome"] = "goal" if shot["goal"] else "save"
	return out


## Предпросмотр «а что если поставить эту карту сюда» — на копии.
static func preview_place(state: Dictionary, slot_i: int, hand_idx: int, target: Vector2i) -> Dictionary:
	var copy: Dictionary = state.duplicate(true)
	if not place(copy, slot_i, hand_idx, target):
		return {}
	var sim := simulate(copy)
	sim["after"] = copy
	return sim


static func execute(state: Dictionary) -> Dictionary:
	if ready_reason(state) != "":
		return {}
	var sim := simulate(state)
	state["over"] = true
	state["outcome"] = "lost" if sim["outcome"] == "no_shot" else sim["outcome"]
	state["end_cell"] = sim["final_ball"]
	match sim["outcome"]:
		"intercept":
			var st: Dictionary = sim["steps"][sim["broke_at"]]
			state["end_cell"] = st["cell"]
			state["end_reason"] = "План сломался на шаге %d («%s»): «%s» перехвачен — %s." % [
				sim["broke_at"] + 1, SLOT_NAMES[sim["broke_at"]], st["name"], Pitch.cell_name(st["cell"])]
		"no_shot":
			state["end_reason"] = "План сломался на шаге 3: с линии %d удар невозможен (нужны линии 3–4)." % [sim["final_ball"].y + 1]
		"goal":
			state["end_reason"] = "Гол! " + Moves.shot_breakdown(sim["shot"])
		"save":
			state["end_reason"] = "Вратарь спас. " + Moves.shot_breakdown(sim["shot"])
	return sim
