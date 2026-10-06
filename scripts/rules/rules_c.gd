class_name RulesC
extends RefCounted
## Режим C «Ещё один пас». Прозрачная случайность.
##
## Колода событий обороны (на одну атаку) перемешивается при старте атаки генератором атаки.
## События открываются сверху без возвращения. Игрок видит только состав остатка.
## Вероятности в предпросмотре считаются точным перебором по этому составу.
##
## Порядок разрешения карты:
##   1. Снятие давления (Перевод, Пауза).
##   2. События открываются по одному. Перехват — сразу конец атаки.
##      Давление: +1 (если карта не игнорирует его). Достигнут предел — конец атаки.
##      Если потеря случилась на первом событии, второе не открывается.
##   3. Мяч сохранён → +качество.
## Удар: один бросок 0..99 из генератора атаки; гол, если бросок < показанного шанса.

const MODE := "c"
const EVENT_NAMES := {"safe": "Безопасно", "pressure": "Давление", "intercept": "Перехват"}


static func cfg() -> Dictionary:
	return GameData.mode(MODE)


static func card_def(id: String) -> Dictionary:
	return GameData.card(MODE, id)


static func new_attack(series_seed: int, attack_idx: int, tutorial: bool = false) -> Dictionary:
	var c := cfg()
	var rng := Seeds.rng_for(series_seed if not tutorial else 7, "c_attack", attack_idx)
	var deck := Seeds.deck_from_counts(c["deck"])
	Seeds.shuffle(deck, rng)
	var events: Array = []
	for t in ["safe", "pressure", "intercept"]:
		for i in int(c["events"][t]):
			events.append(t)
	Seeds.shuffle(events, rng)
	var hand: Array = c["tutorial"]["hand"].duplicate() if tutorial else deck.slice(0, int(c["hand_size"]))
	var used: Array = []
	used.resize(hand.size())
	used.fill(false)
	return {
		"mode": MODE,
		"seed": series_seed,
		"attack": attack_idx,
		"tutorial": tutorial,
		"hand": hand,
		"used": used,
		"played": 0,
		"quality": 0,
		"pressure": 0,
		"events": events,
		"drawn": [],
		# Бросок удара фиксируется при старте атаки и скрыт; от действий игрока он не зависит.
		"shot_roll": rng.randi_range(0, 99),
		"over": false,
		"outcome": "",
		"end_reason": "",
		"history": [],
	}


static func goal_chance(quality: int) -> int:
	var c := cfg()
	return mini(int(c["max_chance"]), int(c["base_chance"]) + int(c["chance_per_quality"]) * quality)


static func counts(state: Dictionary) -> Dictionary:
	var out := {"safe": 0, "pressure": 0, "intercept": 0}
	for e in state["events"]:
		out[e] += 1
	return out


static func card_block_reason(state: Dictionary, idx: int) -> String:
	if state["over"]:
		return "Атака завершена."
	if state["used"][idx]:
		return "Эта карта уже сыграна в этой атаке."
	var c := cfg()
	if int(state["played"]) >= int(c["max_cards_played"]):
		return "Сыграно %d карты — остался только удар." % c["max_cards_played"]
	var d := card_def(state["hand"][idx])
	if d.get("needs_pressure", false) and int(state["pressure"]) == 0:
		return "Давления нет — пауза ничего не даст."
	if int(d["draw_count"]) > state["events"].size():
		return "В колоде обороны не хватает событий."
	return ""


## Точное распределение исходов карты по составу остатка колоды (выбор без возвращения).
## Возвращает дроби с общим знаменателем: loss_intercept, loss_pressure, keep.
static func odds(state: Dictionary, idx: int) -> Dictionary:
	var d := card_def(state["hand"][idx])
	var cnt := counts(state)
	var n: int = cnt["safe"] + cnt["pressure"] + cnt["intercept"]
	var draws := int(d["draw_count"])
	var limit := int(cfg()["pressure_limit"])
	var p0 := maxi(0, int(state["pressure"]) - int(d["relief"]))
	var ignore := bool(d["ignore_pressure"])
	var res := {"intercept": 0, "pressure": 0, "keep": 0, "den": 1}
	if draws == 0:
		res["keep"] = 1
	else:
		var den := 1
		for k in draws:
			den *= (n - k)
		res["den"] = den
		_enumerate(cnt, n, draws, p0, limit, ignore, 1, den, res)
	var loss: int = res["intercept"] + res["pressure"]
	res["loss"] = loss
	res["p_loss"] = float(loss) / float(res["den"])
	res["p_keep"] = float(res["keep"]) / float(res["den"])
	res["quality_gain"] = int(d["quality"])
	res["pressure_after_relief"] = p0
	return res


static func _enumerate(cnt: Dictionary, n: int, left: int, p: int, limit: int, ignore: bool,
		weight: int, den_left: int, res: Dictionary) -> void:
	# weight — число упорядоченных последовательностей до этой точки; den_left — сколько
	# вариантов «добивают» ветку до общего знаменателя, если она закончилась раньше.
	if left == 0:
		res["keep"] += weight
		return
	var rest := den_left / n  # варианты для оставшихся событий после этого
	for t in ["safe", "pressure", "intercept"]:
		var k: int = cnt[t]
		if k == 0:
			continue
		var w := weight * k
		if t == "intercept":
			res["intercept"] += w * rest
			continue
		var np := p
		if t == "pressure" and not ignore:
			np += 1
			if np >= limit:
				res["pressure"] += w * rest
				continue
		var c2 := cnt.duplicate()
		c2[t] -= 1
		_enumerate(c2, n - 1, left - 1, np, limit, ignore, w, rest, res)


static func preview_card(state: Dictionary, idx: int) -> Dictionary:
	var reason := card_block_reason(state, idx)
	if reason != "":
		return {"legal": false, "reason": reason}
	var o := odds(state, idx)
	var q_after := int(state["quality"]) + int(o["quality_gain"])
	o["legal"] = true
	o["reason"] = ""
	o["chance_now"] = goal_chance(int(state["quality"]))
	o["chance_after"] = goal_chance(q_after)
	o["quality_after"] = q_after
	return o


static func play_card(state: Dictionary, idx: int) -> Dictionary:
	var reason := card_block_reason(state, idx)
	if reason != "":
		return {"legal": false, "reason": reason}
	var d := card_def(state["hand"][idx])
	var limit := int(cfg()["pressure_limit"])
	var r := {"legal": true, "card": state["hand"][idx], "name": d["name"], "draws": [],
		"relieved": 0, "lost": false, "outcome": "", "quality_gain": 0}
	state["used"][idx] = true
	state["played"] = int(state["played"]) + 1
	var before := int(state["pressure"])
	state["pressure"] = maxi(0, before - int(d["relief"]))
	r["relieved"] = before - int(state["pressure"])
	for k in int(d["draw_count"]):
		var ev: String = state["events"].pop_front()
		state["drawn"].append(ev)
		var rec := {"type": ev, "ignored": false}
		if ev == "intercept":
			r["draws"].append(rec)
			r["lost"] = true
			r["outcome"] = "intercept"
			break
		if ev == "pressure":
			if d["ignore_pressure"]:
				rec["ignored"] = true
			else:
				state["pressure"] = int(state["pressure"]) + 1
		rec["pressure_after"] = state["pressure"]
		r["draws"].append(rec)
		if int(state["pressure"]) >= limit:
			r["lost"] = true
			r["outcome"] = "lost"
			break
	if r["lost"]:
		state["over"] = true
		state["outcome"] = r["outcome"]
		state["end_reason"] = ("«%s»: перехват — атака окончена." % d["name"]) if r["outcome"] == "intercept" \
			else ("«%s»: второе давление — мяч отобран." % d["name"])
	else:
		r["quality_gain"] = int(d["quality"])
		state["quality"] = int(state["quality"]) + int(d["quality"])
	r["pressure"] = state["pressure"]
	r["quality"] = state["quality"]
	state["history"].append({"card": r["card"], "draws": r["draws"], "lost": r["lost"]})
	return r


static func shot_info(state: Dictionary) -> Dictionary:
	return {"available": not state["over"], "chance": goal_chance(int(state["quality"])),
		"reason": "Атака завершена." if state["over"] else ""}


static func shoot(state: Dictionary) -> Dictionary:
	var info := shot_info(state)
	if not info["available"]:
		return info
	info["roll"] = int(state["shot_roll"])
	info["goal"] = info["roll"] < int(info["chance"])
	state["over"] = true
	state["outcome"] = "goal" if info["goal"] else "save"
	state["end_reason"] = ("Гол! " if info["goal"] else "Вратарь спас. ") + \
		"Шанс был %d%%, выпало %d (гол при числе меньше %d)." % [info["chance"], info["roll"], info["chance"]]
	state["history"].append({"card": "shot", "roll": info["roll"], "chance": info["chance"]})
	return info
