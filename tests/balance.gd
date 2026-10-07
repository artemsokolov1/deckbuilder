extends SceneTree
## Отчёт по балансу: полный перебор решений в A и B, оптимальная стратегия в C.
## Запуск: godot --headless --path . -s tests/balance.gd [-- samples=200]
## Использует те же функции правил (Moves, RulesA/B/C), что и игра.

var samples := 200
var _memo := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("samples="):
			samples = int(a.substr(8))
	print("=== Баланс (выборка: %d атак на шаблон) ===" % samples)
	_balance_a()
	_balance_defense()
	_balance_b()
	_balance_c()
	quit()


# ----------------------------------------------------------------- A
# Быстрый перебор с мемоизацией. Переходы через Moves.resolve / Moves.shot_eval (как в RulesA).
func _a_dfs(plan: Dictionary, ball: Vector2i, tempo: int, q: int, hand: Array, step: int, prev: String, holder: String = "") -> Dictionary:
	var sorted_hand := hand.duplicate()
	sorted_hand.sort()
	var key := "%d,%d,%d,%d,%d,%s,%s,%s" % [ball.x, ball.y, tempo, q, step, prev, holder, ",".join(sorted_hand)]
	if _memo.has(key):
		return _memo[key]
	var c := RulesA.cfg()
	var res := {"goals": 0, "best": -99, "any_action": false}
	var dz := Defense.state_at(plan, step)
	if c["shot_lines"].has(ball.y) and tempo >= int(c["shot_cost"]):
		var info := Moves.shot_eval(c, q, ball, dz, int(plan["extra_pressure"]), RulesA.shooter_bonus(holder))
		res["any_action"] = true
		res["best"] = info["value"] - info["threshold"]
		if info["goal"]:
			res["goals"] += 1
	var seen := {}
	for i in hand.size():
		var id: String = hand[i]
		if seen.has(id):
			continue
		seen[id] = true
		var d := RulesA.card_def(id)
		if int(d["cost"]) > tempo:
			continue
		var req := String(d.get("requires_prev", ""))
		if req != "" and prev != req:
			continue
		for t in Moves.targets(d, ball):
			res["any_action"] = true
			var r := Moves.resolve(d, ball, t, dz)
			if r["intercepted"]:
				continue
			var h2 := hand.duplicate()
			h2.remove_at(i)
			var sub := _a_dfs(plan, t, tempo - int(d["cost"]), q + int(r["quality"]), h2, step + 1, d["action"], id)
			res["goals"] += sub["goals"]
			res["best"] = maxi(res["best"], sub["best"])
	_memo[key] = res
	return res


func _a_eval(state: Dictionary) -> Dictionary:
	_memo = {}
	return _a_dfs(state["plan"], state["ball"], state["tempo"], state["quality"], state["hand"], state["step"], state["prev"], state["holder"])


func _balance_a() -> void:
	print("\n--- Режим A «Комбинация»: порог %d, бонусы %s" % [RulesA.cfg()["keeper_threshold"], str(RulesA.cfg()["position_bonus"])])
	var per_tpl := {}
	var total := 0
	var solvable := 0
	var solvable_mull := 0
	var few_choice := 0
	var multi := 0
	for k in samples * 3:
		var seed := 1000 + k
		var s := RulesA.new_attack(seed, k % 3)
		var tid: String = s["plan"]["id"]
		if not per_tpl.has(tid):
			per_tpl[tid] = {"n": 0, "ok": 0, "okm": 0, "paths": 0}
		var ev := _a_eval(s)
		var ok: bool = ev["goals"] > 0
		var okm := ok
		if not ok:
			# Оптимистичный обмен: перебираем все подмножества до 2 карт (порядок колоды известен симулятору).
			for a in 5:
				for b in range(a, 5):
					var t: Dictionary = s.duplicate(true)
					var idx := [a] if a == b else [a, b]
					RulesA.mulligan(t, idx)
					if _a_eval(t)["goals"] > 0:
						okm = true
						break
				if okm:
					break
		# Осмысленный выбор: сколько разных безопасных первых действий есть в руке.
		var safe_first := {}
		var winning_first := {}
		for i in s["hand"].size():
			for tg in RulesA.card_targets(s, i):
				var p := RulesA.preview_card(s, i, tg)
				if not p["intercepted"] and not p["ends"]:
					safe_first["%s>%s" % [s["hand"][i], tg]] = true
					if ok and _a_eval(p["after"])["goals"] > 0:
						winning_first["%s>%s" % [s["hand"][i], tg]] = true
		if safe_first.size() <= 2:
			few_choice += 1
		if winning_first.size() >= 2:
			multi += 1
		total += 1
		per_tpl[tid]["n"] += 1
		if ok:
			solvable += 1
			per_tpl[tid]["ok"] += 1
			per_tpl[tid]["paths"] += ev["goals"]
		if okm:
			solvable_mull += 1
			per_tpl[tid]["okm"] += 1
	for tid in per_tpl:
		var p: Dictionary = per_tpl[tid]
		print("  %-14s гол возможен: %5.1f%%  (с обменом: %5.1f%%)  среднее число голевых последовательностей: %.1f" % [
			tid, 100.0 * p["ok"] / p["n"], 100.0 * p["okm"] / p["n"], float(p["paths"]) / maxi(1, p["ok"])])
	print("  ВСЕГО: гол возможен в %.1f%% атак, с обменом — %.1f%%" % [100.0 * solvable / total, 100.0 * solvable_mull / total])
	print("  Рук с ≤2 безопасными первыми ходами: %.1f%%" % [100.0 * few_choice / total])
	print("  Атак с ≥2 разными первыми ходами, ведущими к голу: %.1f%%" % [100.0 * multi / total])
	# «Осторожный новичок»: бьёт, как только предпросмотр показывает гол; иначе — случайное
	# безопасное действие, которое не обрывает атаку; если таких нет — бьёт или делает что угодно.
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var goals := 0
	for k in samples * 3:
		var s := RulesA.new_attack(20000 + k, k % 3)
		while not s["over"]:
			var shot := RulesA.shot_info(s)
			if shot["available"] and shot["goal"]:
				RulesA.shoot(s)
				break
			var opts: Array = []
			for i in s["hand"].size():
				for tg in RulesA.card_targets(s, i):
					var p := RulesA.preview_card(s, i, tg)
					var keeps_shot: bool = p["after"]["tempo"] >= 1
					if not p["intercepted"] and not p["ends"] and keeps_shot:
						opts.append([i, tg])
			if opts.is_empty():
				if shot["available"]:
					RulesA.shoot(s)
				else:
					var any := false
					for i in s["hand"].size():
						var t := RulesA.card_targets(s, i)
						if not t.is_empty():
							RulesA.play_card(s, i, t[0])
							any = true
							break
					if not any:
						break
				continue
			var o: Array = opts[rng.randi_range(0, opts.size() - 1)]
			RulesA.play_card(s, o[0], o[1])
		if s["outcome"] == "goal":
			goals += 1
	print("  «Осторожный новичок» (случайные безопасные ходы, удар при показанном голе): %.1f%% голов" % [100.0 * goals / (samples * 3)])


# ----------------------------------------------------------------- B
func _balance_b() -> void:
	print("\n--- Режим B «Три касания»: порог %d, старт %s" % [RulesB.cfg()["keeper_threshold"], str(RulesB.cfg()["start"])])
	var per_tpl := {}
	var combo_wins := {}
	var total_ok := 0
	var total := 0
	for k in samples * 3:
		var s := RulesB.new_attack(5000 + k, k % 3)
		var tid: String = s["plan"]["id"]
		if not per_tpl.has(tid):
			per_tpl[tid] = {"n": 0, "ok": 0, "plans": 0, "win_plans": 0}
		var wins := 0
		var plans := 0
		var win_pairs := {}
		for i in 6:
			for t1 in RulesB.card_targets(s, i, 0):
				var s1: Dictionary = s.duplicate(true)
				RulesB.place(s1, 0, i, t1)
				for j in 6:
					if j == i:
						continue
					for t2 in RulesB.card_targets(s1, j, 1):
						var s2: Dictionary = s1.duplicate(true)
						RulesB.place(s2, 1, j, t2)
						if RulesB.ready_reason(s2) != "":
							continue
						plans += 1
						var sim := RulesB.simulate(s2)
						if sim["outcome"] == "goal":
							wins += 1
							win_pairs["%s+%s" % [s["hand"][i], s["hand"][j]]] = true
		for pkey in win_pairs:
			combo_wins[pkey] = combo_wins.get(pkey, 0) + 1
		per_tpl[tid]["n"] += 1
		per_tpl[tid]["plans"] += plans
		per_tpl[tid]["win_plans"] += wins
		total += 1
		if wins > 0:
			per_tpl[tid]["ok"] += 1
			total_ok += 1
	for tid in per_tpl:
		var p: Dictionary = per_tpl[tid]
		print("  %-14s гол возможен: %5.1f%%  голевых планов: %.1f из %.1f допустимых (%.0f%%)" % [
			tid, 100.0 * p["ok"] / p["n"], float(p["win_plans"]) / p["n"], float(p["plans"]) / p["n"],
			100.0 * p["win_plans"] / maxi(1, p["plans"])])
	print("  ВСЕГО: гол возможен в %.1f%% атак" % [100.0 * total_ok / total])
	var all_plans := 0
	var all_wins := 0
	for tid in per_tpl:
		all_plans += per_tpl[tid]["plans"]
		all_wins += per_tpl[tid]["win_plans"]
	print("  Случайный допустимый план забивает в %.1f%% случаев" % [100.0 * all_wins / maxi(1, all_plans)])
	var keys := combo_wins.keys()
	keys.sort_custom(func(a, b): return combo_wins[a] > combo_wins[b])
	var top: PackedStringArray = []
	for i in mini(8, keys.size()):
		top.append("%s: %d" % [keys[i], combo_wins[keys[i]]])
	print("  Чаще всего голевые пары карт (в скольких атаках срабатывали): ", ", ".join(top))


# ----------------------------------------------------------------- C
var _cmemo := {}


func _c_value(hand: Array, used: int, q: int, p: int, cnt: Array, played: int) -> float:
	var key := "%d,%d,%d,%d,%d,%d,%d" % [used, q, p, cnt[0], cnt[1], cnt[2], played]
	if _cmemo.has(key):
		return _cmemo[key]
	var c := RulesC.cfg()
	var best := float(RulesC.goal_chance(q)) / 100.0
	if played < int(c["max_cards_played"]):
		for i in hand.size():
			if used & (1 << i):
				continue
			var d := RulesC.card_def(hand[i])
			if d.get("needs_pressure", false) and p == 0:
				continue
			var p0 := maxi(0, p - int(d["relief"]))
			var v := _c_branch(hand, used | (1 << i), q, p0, cnt, played + 1, int(d["draw_count"]), d)
			best = maxf(best, v)
	_cmemo[key] = best
	return best


func _c_branch(hand: Array, used: int, q: int, p: int, cnt: Array, played: int, left: int, d: Dictionary) -> float:
	if left == 0:
		return _c_value(hand, used, q + int(d["quality"]), p, cnt, played)
	var n: int = cnt[0] + cnt[1] + cnt[2]
	var v := 0.0
	for t in 3:
		if cnt[t] == 0:
			continue
		var pr := float(cnt[t]) / n
		if t == 2:
			continue  # перехват: 0
		var np := p
		if t == 1 and not d["ignore_pressure"]:
			np += 1
			if np >= int(RulesC.cfg()["pressure_limit"]):
				continue
		var c2 := cnt.duplicate()
		c2[t] -= 1
		v += pr * _c_branch(hand, used, q, np, c2, played, left - 1, d)
	return v


func _balance_c() -> void:
	var c := RulesC.cfg()
	print("\n--- Режим C «Ещё один пас»: база %d%%, +%d за качество, максимум %d%%" % [c["base_chance"], c["chance_per_quality"], c["max_chance"]])
	var sum := 0.0
	var mn := 1.0
	var mx := 0.0
	var ev: Dictionary = c["events"]
	for k in samples * 3:
		var s := RulesC.new_attack(9000 + k, 0)
		_cmemo = {}
		var v := _c_value(s["hand"], 0, 0, 0, [int(ev["safe"]), int(ev["pressure"]), int(ev["intercept"])], 0)
		sum += v
		mn = minf(mn, v)
		mx = maxf(mx, v)
	var avg := sum / (samples * 3)
	print("  Оптимальная игра: шанс гола за атаку %.1f%% (мин %.1f%%, макс %.1f%%); удар сразу: %d%%" % [100 * avg, 100 * mn, 100 * mx, c["base_chance"]])
	print("  Вероятность ≥3 голов из 5 при оптимальной игре: %.1f%%; при ударе сразу: %.1f%%" % [100 * _p_at_least(avg, 5, 3), 100 * _p_at_least(float(c["base_chance"]) / 100.0, 5, 3)])


func _p_at_least(p: float, n: int, k: int) -> float:
	var total := 0.0
	for i in range(k, n + 1):
		total += _binom(n, i) * pow(p, i) * pow(1.0 - p, n - i)
	return total


func _binom(n: int, k: int) -> float:
	var r := 1.0
	for i in k:
		r = r * (n - i) / (i + 1)
	return r


# ----------------------------------------------------------------- защита в A
func _balance_defense() -> void:
	var c := RulesA.cfg()
	print("\n--- Режим A, защита: рука %d, мест %d, реакция вратаря %d" % [c["defense_hand"], c["defense_slots"], c["keeper"]["reaction"]])
	var n := samples * 3
	var best_ok := 0
	var none_ok := 0
	var rand_ok := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in n:
		var a := RulesA.new_attack(30000 + k, k % 5)
		var s := RulesDefend.new_defense(30000 + k, k % 5, a["deck"])
		if RulesDefend.simulate(s)["outcome"] != "goal":
			none_ok += 1
		var best := false
		var options: Array = []
		# все расстановки: каждому из 3 игроков — шаг 0..2 или «не ставить»
		for p0 in range(-1, 3):
			for p1 in range(-1, 3):
				for p2 in range(-1, 3):
					var t: Dictionary = s.duplicate(true)
					var ok := true
					for pair in [[0, p0], [1, p1], [2, p2]]:
						if pair[1] >= 0 and not RulesDefend.place(t, pair[0], pair[1]):
							ok = false
					if not ok:
						continue
					options.append(t)
					if RulesDefend.simulate(t)["outcome"] != "goal":
						best = true
		if best:
			best_ok += 1
		var pick: Dictionary = options[rng.randi_range(0, options.size() - 1)]
		if RulesDefend.simulate(pick)["outcome"] != "goal":
			rand_ok += 1
	print("  Без защитников соперник не забивает: %.1f%%" % [100.0 * none_ok / n])
	print("  Лучшая расстановка спасает: %.1f%%; случайная допустимая: %.1f%%" % [100.0 * best_ok / n, 100.0 * rand_ok / n])
