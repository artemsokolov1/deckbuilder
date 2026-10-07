class_name RulesA
extends RefCounted
## Режим A «Комбинация». Только правила, без отображения.
##
## Порядок разрешения карты (фиксирован):
##   1. Проверка легальности (темп, условие карты, цель).
##   2. Оплата темпа, карта уходит из руки.
##   3. Проверка перехвата по клеткам пути против ТЕКУЩЕГО состояния обороны.
##      Перехват → атака окончена, оборона больше не двигается.
##   4. Мяч перемещается, качество растёт.
##   5. Оборона делает ровно один шаг плана (Финт — тоже ровно один шаг).
##   6. Если не осталось ни одного легального действия (включая удар) — потеря.
## Удар не двигает оборону и разрешается против текущего состояния.
##
## Карты — футболисты. Каждый умеет одно действие (cards.a.<action>). Мяч уходит к сыгранному
## футболисту, он становится владельцем мяча. Мастерство: если нужная действию характеристика
## (пас или дриблинг) не ниже mastery_from — +mastery_bonus к качеству при успехе.
## Удар: + (удар владельца − shooter_base).

const MODE := "a"


static func cfg() -> Dictionary:
	return GameData.mode(MODE)


static func action_def(action_id: String) -> Dictionary:
	return GameData.card(MODE, action_id)


## Определение карты: для футболиста — его умение с учётом мастерства;
## для id действия (обучение старых версий, тесты) — само действие.
static func card_def(id: String) -> Dictionary:
	if not GameData.is_player(id):
		var a := action_def(id).duplicate()
		a["action"] = id
		a["action_name"] = a["name"]
		a["mastery"] = 0
		return a
	var pl := GameData.player(id)
	var d := action_def(pl["action"]).duplicate()
	var c := cfg()
	var stat: String = c["mastery_stat"][pl["action"]]
	var mastery := int(c["mastery_bonus"]) if int(pl[stat]) >= int(c["mastery_from"]) else 0
	d["action"] = pl["action"]
	d["action_name"] = d["name"]
	d["name"] = "%s · %s" % [d["name"], pl["name"]]
	d["player"] = pl
	d["player_id"] = id
	d["mastery"] = mastery
	d["mastery_stat"] = stat
	d["quality"] = int(d["quality"]) + mastery
	return d


## Поправка к удару от владельца мяча.
static func shooter_bonus(holder: String) -> int:
	if holder == "" or not GameData.is_player(holder):
		return 0
	return int(GameData.player(holder)["shot"]) - int(cfg()["shooter_base"])


static func new_attack(series_seed: int, attack_idx: int, tutorial: bool = false) -> Dictionary:
	var c := cfg()
	var rng := Seeds.rng_for(series_seed, "a_deck", attack_idx)
	var deck: Array = c["squad"].duplicate()
	Seeds.shuffle(deck, rng)
	var plan: Dictionary
	var hand: Array
	if tutorial:
		plan = Defense.build(MODE, c["tutorial"]["template"], false)
		hand = c["tutorial"]["hand"].duplicate()
		for id in hand:
			deck.erase(id)
	else:
		plan = Defense.pick_for_attack(MODE, series_seed, attack_idx)
		hand = deck.slice(0, int(c["hand_size"]))
		deck = deck.slice(int(c["hand_size"]))
	return {
		"mode": MODE,
		"seed": series_seed,
		"attack": attack_idx,
		"tutorial": tutorial,
		"ball": c["start"],
		"tempo": int(c["tempo"]),
		"quality": 0,
		"hand": hand,
		"deck": deck,
		"plan": plan,
		"step": 0,
		"prev": "",
		"holder": "",
		"actions": 0,
		"mulligan_used": tutorial,
		"over": false,
		"outcome": "",
		"end_reason": "",
		"end_cell": Pitch.NONE,
		"history": [],
	}


static func danger(state: Dictionary, offset: int = 0) -> Array:
	return Defense.state_at(state["plan"], int(state["step"]) + offset)


## Пустая строка — карта играбельна. Иначе — объяснение для игрока.
static func card_block_reason(state: Dictionary, idx: int) -> String:
	if state["over"]:
		return "Атака завершена."
	var id: String = state["hand"][idx]
	var d := card_def(id)
	var cost := int(d["cost"])
	if cost > int(state["tempo"]):
		return "Нужно темпа: %d, осталось: %d." % [cost, state["tempo"]]
	var req := String(d.get("requires_prev", ""))
	if req != "" and state["prev"] != req:
		return "Только сразу после «%s». Предыдущее действие: %s." % [
			action_def(req)["name"], action_def(state["prev"])["name"] if state["prev"] != "" else "не было"]
	if Moves.targets(d, state["ball"]).is_empty():
		return "Некуда продвигаться: мяч уже на последней линии."
	return ""


static func card_targets(state: Dictionary, idx: int) -> Array:
	if card_block_reason(state, idx) != "":
		return []
	return Moves.targets(card_def(state["hand"][idx]), state["ball"])


## Предпросмотр: тот же код, что и исполнение, но на копии состояния.
static func preview_card(state: Dictionary, idx: int, target: Vector2i) -> Dictionary:
	var copy: Dictionary = state.duplicate(true)
	var r := _apply_card(copy, idx, target)
	r["after"] = copy
	return r


static func play_card(state: Dictionary, idx: int, target: Vector2i) -> Dictionary:
	return _apply_card(state, idx, target)


static func _apply_card(s: Dictionary, idx: int, target: Vector2i) -> Dictionary:
	var r := {"legal": false, "reason": ""}
	if idx < 0 or idx >= s["hand"].size():
		r["reason"] = "Нет такой карты."
		return r
	var reason := card_block_reason(s, idx)
	if reason != "":
		r["reason"] = reason
		return r
	var id: String = s["hand"][idx]
	var d := card_def(id)
	if not Moves.targets(d, s["ball"]).has(target):
		r["reason"] = "Эта клетка недоступна для «%s»." % d["name"]
		return r
	var from: Vector2i = s["ball"]
	var dz := danger(s)
	var res := Moves.resolve(d, from, target, dz)
	r["legal"] = true
	r["card"] = id
	r["name"] = d["name"]
	r["from"] = from
	r["to"] = target
	r["path"] = res["path"]
	r["beaten"] = res["beaten"]
	r["intercepted"] = res["intercepted"]
	r["cell"] = res["cell"]
	r["cost"] = int(d["cost"])
	r["step_before"] = s["step"]
	# 2. оплата
	s["tempo"] = int(s["tempo"]) - int(d["cost"])
	s["hand"].remove_at(idx)
	s["actions"] = int(s["actions"]) + 1
	if res["intercepted"]:
		# 3. перехват — конец атаки
		s["over"] = true
		s["outcome"] = "intercept"
		s["end_cell"] = res["cell"]
		s["end_reason"] = "«%s» перехвачен: %s." % [d["name"], Pitch.cell_name(res["cell"])]
		r["quality_gain"] = 0
		r["ends"] = true
		r["outcome"] = "intercept"
		s["history"].append({"card": id, "to": target, "result": "intercept"})
		return r
	# 4. мяч и качество
	s["ball"] = target
	s["quality"] = int(s["quality"]) + int(res["quality"])
	s["prev"] = d["action"]
	if GameData.is_player(id):
		s["holder"] = id
	r["quality_gain"] = res["quality"]
	# 5. ровно один шаг обороны
	s["step"] = int(s["step"]) + 1
	s["history"].append({"card": id, "to": target, "result": "ok"})
	# 6. остались ли действия
	if not has_legal_action(s):
		s["over"] = true
		s["outcome"] = "lost"
		s["end_cell"] = s["ball"]
		if int(s["tempo"]) <= 0:
			s["end_reason"] = "Темп закончился, а удара не было — мяч потерян."
		else:
			s["end_reason"] = "Не осталось ни одного доступного действия — мяч потерян."
		r["ends"] = true
		r["outcome"] = "lost"
	else:
		r["ends"] = false
		r["outcome"] = ""
	return r


static func shot_info(state: Dictionary) -> Dictionary:
	var c := cfg()
	var holder: String = state.get("holder", "")
	var info := Moves.shot_eval(c, int(state["quality"]), state["ball"], danger(state), int(state["plan"]["extra_pressure"]), shooter_bonus(holder))
	if GameData.is_player(holder):
		info["shooter_name"] = GameData.player(holder)["name"]
		info["shooter_shot"] = int(GameData.player(holder)["shot"])
	info["cost"] = int(c["shot_cost"])
	info["reason"] = ""
	if state["over"]:
		info["available"] = false
		info["reason"] = "Атака завершена."
	elif not c["shot_lines"].has(state["ball"].y):
		info["available"] = false
		info["reason"] = "Удар только с линий %d–%d. Мяч на линии %d." % [
			int(c["shot_lines"][0]) + 1, int(c["shot_lines"][-1]) + 1, state["ball"].y + 1]
	elif int(state["tempo"]) < info["cost"]:
		info["available"] = false
		info["reason"] = "На удар нужен %d темп." % info["cost"]
	return info


static func shoot(state: Dictionary) -> Dictionary:
	var info := shot_info(state)
	if not info["available"]:
		return info
	state["tempo"] = int(state["tempo"]) - int(info["cost"])
	state["over"] = true
	state["outcome"] = "goal" if info["goal"] else "save"
	state["end_cell"] = state["ball"]
	state["end_reason"] = ("Гол! " if info["goal"] else "Вратарь спас. ") + Moves.shot_breakdown(info)
	state["history"].append({"card": "shot", "to": state["ball"], "result": state["outcome"]})
	return info


static func has_legal_action(state: Dictionary) -> bool:
	if state["over"]:
		return false
	if shot_info(state)["available"]:
		return true
	for i in state["hand"].size():
		if card_block_reason(state, i) == "":
			return true
	return false


static func can_mulligan(state: Dictionary) -> bool:
	return not state["over"] and not state["mulligan_used"] and int(state["actions"]) == 0 and not state["deck"].is_empty()


## Обмен до mulligan_max карт: выбранные уходят под низ колоды, сверху берутся новые.
static func mulligan(state: Dictionary, indices: Array) -> bool:
	if not can_mulligan(state):
		return false
	var idx := indices.duplicate()
	idx.sort()
	if idx.size() > int(cfg()["mulligan_max"]) or idx.is_empty():
		return false
	if idx.size() > state["deck"].size():
		return false
	for k in idx.size():
		if idx[k] < 0 or idx[k] >= state["hand"].size() or (k > 0 and idx[k] == idx[k - 1]):
			return false
	var returned: Array = []
	for i in idx:
		returned.append(state["hand"][i])
		state["hand"][i] = state["deck"].pop_front()
	state["deck"].append_array(returned)
	state["mulligan_used"] = true
	return true
