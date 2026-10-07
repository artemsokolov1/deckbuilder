class_name RulesDefend
extends RefCounted
## Защита в режиме A: после вашей атаки атакует соперник.
##
## Маршрут его атаки виден целиком: старт и 3 шага к вашим воротам, на каждом шаге — его футболист
## с показателем дриблинга; после третьего шага бьёт тот, кто ведёт мяч.
## Вы ставите до defense_slots футболистов из руки защиты на клетки шагов маршрута.
## Позиция ограничивает линии: defend_lines[позиция].
##
## Порядок разрешения (детерминированный, весь исход виден до запуска):
##   шаги 1 → 2 → 3: если на шаге стоит ваш игрок и его отбор ≥ дриблинга соперника — мяч отобран,
##   атака окончена; иначе соперник проходит его.
##   После трёх шагов — удар: гол, если удар соперника больше реакции вашего вратаря, иначе сейв.

const MODE := "a"
const STEPS := 3


static func cfg() -> Dictionary:
	return GameData.mode(MODE)


static func opp_player(id: String) -> Dictionary:
	return GameData.opponent()["players"][id]


static func keeper() -> Dictionary:
	return cfg()["keeper"]


static func new_defense(series_seed: int, round_idx: int, deck_rest: Array, tutorial: bool = false) -> Dictionary:
	var c := cfg()
	var opp := GameData.opponent()
	var template_id: String
	var mirrored := false
	var attackers: Array = []
	var hand: Array = []
	if tutorial:
		template_id = c["tutorial"]["opp_attack"]
		attackers = c["tutorial"]["opp_players"].duplicate()
		hand = c["tutorial"]["defense_hand"].duplicate()
	else:
		var order: Array = c["opp_order"].duplicate()
		Seeds.shuffle(order, Seeds.rng_for(series_seed, "a_opp_order"))
		var rng := Seeds.rng_for(series_seed, "a_opp", round_idx)
		template_id = order[round_idx] if round_idx < order.size() else order[rng.randi_range(0, order.size() - 1)]
		mirrored = rng.randi_range(0, 1) == 1
		var mids: Array = []
		var fwds: Array = []
		var keys: Array = opp["players"].keys()
		keys.sort()
		for k in keys:
			(mids if opp["players"][k]["pos"] == "ПЗ" else fwds).append(k)
		Seeds.shuffle(mids, rng)
		attackers = [mids[0], mids[1], fwds[rng.randi_range(0, fwds.size() - 1)]]
		var n := int(c["defense_hand"])
		hand = deck_rest.slice(0, n)
		if hand.size() < n:
			# колода почти пуста — добираем тех, кого нет в руке, по порядку состава
			for id in c["squad"]:
				if hand.size() >= n:
					break
				if not hand.has(id):
					hand.append(id)
	var route: Array = []
	for cell in opp["attacks"][template_id]["route"]:
		var v := Vector2i(cell[0], cell[1])
		route.append(Vector2i(Pitch.LANES - 1 - v.x, v.y) if mirrored else v)
	return {
		"mode": "a_def",
		"seed": series_seed,
		"round": round_idx,
		"tutorial": tutorial,
		"template": template_id,
		"template_name": opp["attacks"][template_id]["name"],
		"route": route,
		"attackers": attackers,
		"hand": hand,
		"placed": [-1, -1, -1],
		"over": false,
		"outcome": "",
		"end_reason": "",
	}


static func step_cell(state: Dictionary, k: int) -> Vector2i:
	return state["route"][k + 1]


static func placed_count(state: Dictionary) -> int:
	var n := 0
	for p in state["placed"]:
		if p >= 0:
			n += 1
	return n


static func step_of(state: Dictionary, hand_idx: int) -> int:
	return state["placed"].find(hand_idx)


static func lines_text(lines: Array) -> String:
	var parts: PackedStringArray = []
	for l in lines:
		parts.append(str(int(l) + 1))
	return "–".join(parts) if parts.size() > 1 else parts[0]


## Пустая строка — можно поставить. Иначе — объяснение.
static func place_reason(state: Dictionary, hand_idx: int, k: int) -> String:
	if state["over"]:
		return "Атака соперника уже разыграна."
	if k < 0 or k >= STEPS:
		return "Ставить можно только на шаги маршрута."
	var pl := GameData.player(state["hand"][hand_idx])
	var lines: Array = cfg()["defend_lines"][pl["pos"]]
	var cell := step_cell(state, k)
	if not lines.has(cell.y):
		return "%s (%s) защищается только на линиях %s." % [pl["name"], pl["pos"], lines_text(lines)]
	var already := step_of(state, hand_idx) >= 0
	if not already and state["placed"][k] < 0 and placed_count(state) >= int(cfg()["defense_slots"]):
		return "Можно поставить не больше %d защитников. Уберите одного (повторный клик по его шагу)." % cfg()["defense_slots"]
	return ""


static func legal_steps(state: Dictionary, hand_idx: int) -> Array:
	var out: Array = []
	for k in STEPS:
		if place_reason(state, hand_idx, k) == "":
			out.append(k)
	return out


static func place(state: Dictionary, hand_idx: int, k: int) -> bool:
	if place_reason(state, hand_idx, k) != "":
		return false
	var prev := step_of(state, hand_idx)
	if prev >= 0:
		state["placed"][prev] = -1
	state["placed"][k] = hand_idx
	return true


static func remove(state: Dictionary, k: int) -> void:
	if not state["over"] and k >= 0 and k < STEPS:
		state["placed"][k] = -1


## Полный исход атаки соперника при текущей расстановке. Ничего не меняет.
static func simulate(state: Dictionary) -> Dictionary:
	var out := {"steps": [], "outcome": "", "stopped_at": -1, "shot": {}}
	for k in STEPS:
		var att := opp_player(state["attackers"][k])
		var st := {"k": k, "cell": step_cell(state, k), "from": state["route"][k], "attacker": state["attackers"][k],
			"drib": int(att["drib"]), "defender": "", "tackle": 0, "tackled": false, "beaten": false}
		var hi: int = state["placed"][k]
		if hi >= 0:
			var pl := GameData.player(state["hand"][hi])
			st["defender"] = state["hand"][hi]
			st["tackle"] = int(pl["tackle"])
			if st["tackle"] >= st["drib"]:
				st["tackled"] = true
			else:
				st["beaten"] = true
		out["steps"].append(st)
		if st["tackled"]:
			out["outcome"] = "tackle"
			out["stopped_at"] = k
			return out
	var shooter := opp_player(state["attackers"][STEPS - 1])
	var reaction := int(keeper()["reaction"])
	var goal: bool = int(shooter["shot"]) > reaction
	out["shot"] = {"shooter": state["attackers"][STEPS - 1], "shot": int(shooter["shot"]), "reaction": reaction, "goal": goal}
	out["outcome"] = "goal" if goal else "save"
	return out


static func execute(state: Dictionary) -> Dictionary:
	if state["over"]:
		return {}
	var sim := simulate(state)
	state["over"] = true
	state["outcome"] = sim["outcome"]
	match sim["outcome"]:
		"tackle":
			var st: Dictionary = sim["steps"][sim["stopped_at"]]
			state["end_reason"] = "Отбор на шаге %d: у %s отбор %d, у соперника %s дриблинг %d." % [
				st["k"] + 1, GameData.player(st["defender"])["name"], st["tackle"], opp_player(st["attacker"])["name"], st["drib"]]
		"goal":
			state["end_reason"] = "Гол в ваши ворота: %s бьёт (удар %d) сильнее, чем реагирует %s (реакция %d)." % [
				opp_player(sim["shot"]["shooter"])["name"], sim["shot"]["shot"], keeper()["name"], sim["shot"]["reaction"]]
		"save":
			state["end_reason"] = "%s отбивает удар: реакция %d против удара %d." % [
				keeper()["name"], sim["shot"]["reaction"], sim["shot"]["shot"]]
	return sim
