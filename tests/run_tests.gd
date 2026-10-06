extends SceneTree
## Автоматические проверки правил и вероятностей.
## Запуск: godot --headless --path . -s tests/run_tests.gd

var _fails := 0
var _passes := 0


func _initialize() -> void:
	print("=== Последняя атака: проверки правил ===")
	_test_a()
	_test_b()
	_test_c()
	print("=== Итог: %d прошло, %d провалено ===" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)


func check(cond: bool, label: String) -> void:
	if cond:
		_passes += 1
		print("  ok   ", label)
	else:
		_fails += 1
		print("  FAIL ", label)
		push_error("FAIL: " + label)


func idx_of(state: Dictionary, id: String) -> int:
	return state["hand"].find(id)


# Состояние A с заданной рукой и планом обороны.
func a_state(hand: Array, states: Array, start := Vector2i(1, 0), tempo := 5) -> Dictionary:
	var s := RulesA.new_attack(1, 0)
	s["hand"] = hand.duplicate()
	s["plan"] = {"id": "test", "name": "Тест", "hint": "", "extra_pressure": 0, "mirrored": false, "states": states}
	s["ball"] = start
	s["tempo"] = tempo
	return s


# ---------------------------------------------------------------- A
func _test_a() -> void:
	print("-- Режим A")
	var c := RulesA.cfg()
	var free := [[Vector2i(0, 3)], [Vector2i(0, 3)], [Vector2i(0, 3)], [Vector2i(0, 3)], [Vector2i(0, 3)], [Vector2i(0, 3)]]

	# Успешная комбинация 1: пас, стеночка, пас, удар из центра у ворот.
	var s := a_state(["short_pass", "one_two", "short_pass", "feint", "switch"], free)
	var r := RulesA.play_card(s, idx_of(s, "short_pass"), Vector2i(1, 1))
	check(r["legal"] and not r["intercepted"] and s["quality"] == 1 and s["step"] == 1, "A: короткий пас продвигает, +1 качество, оборона +1 шаг")
	r = RulesA.play_card(s, idx_of(s, "one_two"), Vector2i(1, 2))
	check(r["legal"] and s["quality"] == 2 and s["ball"] == Vector2i(1, 2), "A: стеночка после паса")
	r = RulesA.play_card(s, idx_of(s, "short_pass"), Vector2i(1, 3))
	r = RulesA.play_card(s, idx_of(s, "feint"), Vector2i(1, 3))
	check(s["quality"] == 4 and s["tempo"] == 1 and s["step"] == 4, "A: финт +1 качество и ровно один шаг обороны")
	var info := RulesA.shot_info(s)
	check(info["available"] and info["value"] == 4 + int(c["position_bonus"][3][1]), "A: формула удара качество+позиция−давление")
	var expect_goal: bool = info["value"] >= int(c["keeper_threshold"])
	RulesA.shoot(s)
	check(s["over"] and s["outcome"] == ("goal" if expect_goal else "save") and expect_goal, "A: комбинация 1 заканчивается голом")

	# Успешная комбинация 2: разрезающий по флангу + пас + удар.
	s = a_state(["through", "short_pass", "feint", "switch", "dribble"],
		[[Vector2i(1, 1), Vector2i(1, 2)], [Vector2i(1, 2), Vector2i(1, 3)], [Vector2i(1, 3)], [Vector2i(1, 3)], [Vector2i(1, 3)], [Vector2i(1, 3)]])
	r = RulesA.play_card(s, idx_of(s, "through"), Vector2i(0, 2))
	check(not r["intercepted"] and s["quality"] == 2 and s["ball"] == Vector2i(0, 2), "A: разрезающий по флангу обходит центр")
	RulesA.play_card(s, idx_of(s, "short_pass"), Vector2i(0, 3))
	RulesA.play_card(s, idx_of(s, "feint"), Vector2i(0, 3))
	info = RulesA.shot_info(s)
	check(info["value"] == 4 + int(c["position_bonus"][3][0]), "A: удар с фланга считает фланговый бонус")

	# Неуспешная: перехват посреди комбинации.
	s = a_state(["short_pass", "through", "feint", "switch", "dribble"],
		[[Vector2i(2, 3)], [Vector2i(1, 2), Vector2i(1, 3)], [Vector2i(1, 3)], [Vector2i(1, 3)], [Vector2i(1, 3)], [Vector2i(1, 3)]])
	RulesA.play_card(s, idx_of(s, "short_pass"), Vector2i(1, 1))
	var step_before: int = s["step"]
	r = RulesA.play_card(s, idx_of(s, "through"), Vector2i(1, 3))
	check(r["intercepted"] and r["cell"] == Vector2i(1, 2), "A: разрезающий перехвачен на первой опасной клетке пути")
	check(s["over"] and s["outcome"] == "intercept" and s["step"] == step_before, "A: после перехвата атака окончена, оборона не двигается")
	check(RulesA.card_block_reason(s, 0) != "" and not RulesA.shot_info(s)["available"], "A: после конца атаки действия недоступны")

	# Обводка защищает от одной опасной зоны.
	s = a_state(["dribble", "short_pass"], [[Vector2i(1, 1)], [Vector2i(1, 2)], [], [], [], []])
	r = RulesA.play_card(s, 0, Vector2i(1, 1))
	check(not r["intercepted"] and r["beaten"].size() == 1 and s["quality"] == 1, "A: обводка проходит опасную зону, +1 за обыгранного")
	r = RulesA.play_card(s, 0, Vector2i(1, 2))
	check(r["intercepted"], "A: обычный пас в опасную зону — перехват")

	# Стеночка только сразу после короткого паса.
	s = a_state(["one_two", "feint", "short_pass"], free)
	check(RulesA.card_block_reason(s, 0) != "", "A: стеночка недоступна без паса")
	RulesA.play_card(s, idx_of(s, "short_pass"), Vector2i(1, 1))
	check(RulesA.card_block_reason(s, idx_of(s, "one_two")) == "", "A: стеночка доступна сразу после паса")
	RulesA.play_card(s, idx_of(s, "feint"), Vector2i(1, 1))
	check(RulesA.card_block_reason(s, idx_of(s, "one_two")) != "", "A: стеночка недоступна, если между ними был финт")

	# Нет допустимых действий: темп кончился до удара.
	s = a_state(["through", "through", "feint"], free, Vector2i(1, 0), 4)
	RulesA.play_card(s, 0, Vector2i(1, 2))
	r = RulesA.play_card(s, 0, Vector2i(2, 3)) # bad: through needs line+2, should be illegal
	check(not r["legal"], "A: нельзя разрезающим уйти за пределы поля")
	s = a_state(["through", "dribble", "feint"], free, Vector2i(1, 0), 4)
	RulesA.play_card(s, 0, Vector2i(1, 2))
	r = RulesA.play_card(s, 0, Vector2i(1, 3))
	check(r["ends"] and s["outcome"] == "lost" and s["tempo"] == 0, "A: темп кончился без удара — потеря")
	s = a_state(["switch"], free, Vector2i(1, 0), 1)
	r = RulesA.play_card(s, 0, Vector2i(0, 0))
	check(s["over"] and s["outcome"] == "lost", "A: после последнего действия нет ходов — потеря")

	# Удар только с двух ближайших линий.
	s = a_state(["feint"], free, Vector2i(1, 1))
	check(not RulesA.shot_info(s)["available"], "A: с линии 2 удар недоступен")
	s = a_state(["feint"], free, Vector2i(1, 2))
	check(RulesA.shot_info(s)["available"], "A: с линии 3 удар доступен")

	# Предпросмотр не меняет состояние.
	s = RulesA.new_attack(424242, 2)
	var before := var_to_str(s)
	for i in s["hand"].size():
		for t in RulesA.card_targets(s, i):
			RulesA.preview_card(s, i, t)
	RulesA.shot_info(s)
	check(var_to_str(s) == before, "A: предпросмотр (наведение) не меняет состояние")

	# Предпросмотр = исполнение.
	s = RulesA.new_attack(5, 1)
	var same := true
	for i in s["hand"].size():
		for t in RulesA.card_targets(s, i):
			var p := RulesA.preview_card(s, i, t)
			var copy: Dictionary = s.duplicate(true)
			var real := RulesA.play_card(copy, i, t)
			if var_to_str(p["after"]) != var_to_str(copy) or p["intercepted"] != real["intercepted"]:
				same = false
	check(same, "A: предпросмотр совпадает с исполнением для всех карт и целей")

	# Воспроизводимость seed.
	check(var_to_str(RulesA.new_attack(777, 3)) == var_to_str(RulesA.new_attack(777, 3)), "A: тот же seed — та же атака")
	var differs := false
	for k in 5:
		if var_to_str(RulesA.new_attack(777, k)) != var_to_str(RulesA.new_attack(778, k)):
			differs = true
	check(differs, "A: другой seed — другие атаки")
	var tpls := {}
	for k in 3:
		tpls[RulesA.new_attack(31337, k)["plan"]["id"]] = true
	check(tpls.size() == 3, "A: первые три атаки серии — три разных шаблона обороны")

	# Обмен.
	s = RulesA.new_attack(99, 0)
	var deck_before: int = s["deck"].size()
	var old0: String = s["hand"][0]
	check(RulesA.mulligan(s, [0, 3]) and s["hand"].size() == 5 and s["deck"].size() == deck_before, "A: обмен двух карт")
	check(s["deck"][-1] != "" and s["deck"].slice(-2).has(old0), "A: обменянные карты ушли под колоду")
	check(not RulesA.mulligan(s, [1]), "A: второй обмен запрещён")
	s = RulesA.new_attack(99, 0)
	check(not RulesA.mulligan(s, [0, 1, 2]), "A: нельзя обменять больше двух")

	# Обучение.
	s = RulesA.new_attack(1, 0, true)
	check(s["hand"] == c["tutorial"]["hand"] and s["plan"]["id"] == "tutorial", "A: обучающая рука задана вручную")


# ---------------------------------------------------------------- B
func b_state(hand: Array, states: Array, start := Vector2i(1, 1)) -> Dictionary:
	var s := RulesB.new_attack(1, 0)
	s["hand"] = hand.duplicate()
	s["start"] = start
	s["plan"] = {"id": "test", "name": "Тест", "hint": "", "extra_pressure": 0, "mirrored": false, "states": states}
	return s


func _test_b() -> void:
	print("-- Режим B")
	var c := RulesB.cfg()
	# Удачный план: пас вперёд-влево, стеночка, удар.
	var s := b_state(["short_pass", "one_two", "through", "switch", "feint", "dribble"],
		[[Vector2i(1, 2)], [Vector2i(1, 3)], [Vector2i(1, 3)]])
	check(RulesB.card_reason(s, 1, 0) != "", "B: стеночка не ставится в первый слот")
	check(RulesB.place(s, 0, 0, Vector2i(0, 2)), "B: пас в слот 1")
	check(RulesB.place(s, 1, 1, Vector2i(0, 3)), "B: стеночка в слот 2 после паса")
	var sim := RulesB.simulate(s)
	var exp_val: int = int(RulesB.card_def("short_pass")["quality"]) + int(RulesB.card_def("one_two")["quality"]) + int(c["position_bonus"][3][0])
	check(sim["outcome"] == ("goal" if exp_val >= int(c["keeper_threshold"]) else "save") and sim["shot"]["value"] == exp_val, "B: предпросмотр удара учитывает будущую позицию")
	var before := var_to_str(s)
	RulesB.simulate(s)
	RulesB.preview_place(s, 0, 2, Vector2i(1, 3))
	check(var_to_str(s) == before, "B: предпросмотр не меняет состояние")
	var ex := RulesB.execute(s)
	check(s["over"] and ex["outcome"] == sim["outcome"], "B: исполнение совпадает с предпросмотром")
	check(RulesB.execute(s).is_empty(), "B: повторный запуск не исполняется")
	check(not RulesB.place(s, 0, 2, Vector2i(1, 3)), "B: после запуска карты менять нельзя")

	# Перехват на шаге 2: состояние обороны 1 закрывает цель второго действия.
	s = b_state(["short_pass", "short_pass", "feint", "switch", "feint", "dribble"],
		[[Vector2i(2, 3)], [Vector2i(1, 3)], []])
	RulesB.place(s, 0, 0, Vector2i(1, 2))
	RulesB.place(s, 1, 1, Vector2i(1, 3))
	ex = RulesB.execute(s)
	check(ex["outcome"] == "intercept" and ex["broke_at"] == 1 and ex["steps"].size() == 2 and ex["shot"].is_empty(), "B: перехват на шаге 2 отменяет удар")
	check(s["end_reason"].contains("шаге 2"), "B: объяснение называет шаг поломки")

	# Каждое действие проверяется против своего состояния обороны.
	s = b_state(["short_pass", "short_pass", "feint", "switch", "feint", "dribble"],
		[[Vector2i(1, 3)], [Vector2i(1, 2)], []])
	RulesB.place(s, 0, 0, Vector2i(1, 2))
	RulesB.place(s, 1, 1, Vector2i(1, 3))
	sim = RulesB.simulate(s)
	check(sim["outcome"] != "intercept", "B: опасная зона следующего шага не мешает текущему действию")

	# Ограничение разрезающего: только с линии 2 и ниже.
	s = b_state(["short_pass", "through", "feint", "switch", "feint", "dribble"], [[], [], []])
	RulesB.place(s, 0, 0, Vector2i(1, 2))
	check(RulesB.card_reason(s, 1, 1) != "", "B: разрезающий недоступен с линии 3")
	check(RulesB.card_reason(s, 1, 0) == "", "B: разрезающий доступен с линии 2")

	# Перестановка слотов сбрасывает ставшую недопустимой цель.
	s = b_state(["short_pass", "switch", "feint", "switch", "feint", "dribble"], [[], [], []])
	RulesB.place(s, 0, 0, Vector2i(1, 2))
	RulesB.place(s, 1, 1, Vector2i(0, 2))
	RulesB.swap(s)
	check(s["slots"][0]["target"] == Pitch.NONE or RulesB.card_targets(s, s["slots"][0]["hand_idx"], 0).has(s["slots"][0]["target"]), "B: после перестановки цели проверены заново")
	check(RulesB.ready_reason(s) != "", "B: план с недопустимой целью нельзя запустить")

	# План, который не доходит до линии удара, запустить нельзя.
	s = b_state(["switch", "feint", "feint", "switch", "feint", "dribble"], [[], [], []])
	RulesB.place(s, 0, 0, Vector2i(0, 1))
	RulesB.place(s, 1, 1, Vector2i(0, 1))
	check(RulesB.ready_reason(s).contains("удар невозможен"), "B: без выхода на линию удара запуск заблокирован")

	check(var_to_str(RulesB.new_attack(55, 2)) == var_to_str(RulesB.new_attack(55, 2)), "B: тот же seed — та же атака")


# ---------------------------------------------------------------- C
func c_state(hand: Array, events: Array) -> Dictionary:
	var s := RulesC.new_attack(1, 0)
	s["hand"] = hand.duplicate()
	s["used"] = []
	for h in hand:
		s["used"].append(false)
	s["events"] = events.duplicate()
	return s


func approx(a: float, b: float, eps := 1e-9) -> bool:
	return absf(a - b) < eps


func _test_c() -> void:
	print("-- Режим C")
	var full := ["safe", "safe", "safe", "safe", "safe", "safe", "pressure", "pressure", "pressure", "intercept"]
	var s := c_state(["pass", "sprint", "shield", "switch_c", "pause", "risky"], full)
	check(RulesC.goal_chance(0) == 35 and RulesC.goal_chance(1) == 47 and RulesC.goal_chance(5) == 90 and RulesC.goal_chance(9) == 90, "C: шанс 35% + 12 за качество, максимум 90%")
	var o := RulesC.odds(s, 0)
	check(approx(o["p_loss"], 0.1), "C: пас со свежей колодой — потеря ровно 10%")
	o = RulesC.odds(s, 1)
	check(approx(o["p_loss"], 0.2 + 6.0 / 90.0), "C: рывок — 1/10+1/10 перехват + 3/10·2/9 два давления")
	o = RulesC.odds(s, 2)
	check(approx(o["p_loss"], 0.1), "C: прикрыть мяч — только перехват 10%")
	s["pressure"] = 1
	o = RulesC.odds(s, 0)
	check(approx(o["p_loss"], 0.4), "C: пас при одном давлении — 1/10 перехват + 3/10 давление")
	o = RulesC.odds(s, 3)
	check(approx(o["p_loss"], 0.1), "C: перевод снимает давление до открытия события")
	o = RulesC.odds(s, 5)
	check(approx(o["p_loss"], 1.0 - (6.0 / 10.0) * (5.0 / 9.0)), "C: рискованный при давлении — нужно два безопасных подряд")
	s["pressure"] = 0
	check(RulesC.card_block_reason(s, 4) != "", "C: пауза без давления недоступна и объясняет почему")

	# Монте-Карло: настоящие розыгрыши совпадают с показанными вероятностями.
	var all_ok := true
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var setups := [[0, 0, full], [1, 0, full], [5, 1, full], [2, 1, full], [3, 1, full],
		[1, 1, ["safe", "safe", "pressure", "intercept"]], [5, 0, ["safe", "pressure", "pressure"]]]
	for setup in setups:
		var proto := c_state(["pass", "sprint", "shield", "switch_c", "pause", "risky"], setup[2])
		proto["pressure"] = setup[1]
		var shown: float = RulesC.odds(proto, setup[0])["p_loss"]
		var losses := 0
		var n := 20000
		for k in n:
			var t: Dictionary = proto.duplicate(true)
			Seeds.shuffle(t["events"], rng)
			if RulesC.play_card(t, setup[0])["lost"]:
				losses += 1
		var emp := float(losses) / n
		if absf(emp - shown) > 0.012:
			all_ok = false
			print("     карта %s: показано %.4f, вышло %.4f" % [proto["hand"][setup[0]], shown, emp])
	check(all_ok, "C: Монте-Карло (20000 розыгрышей) совпадает с показанными вероятностями")

	# Потеря на первом событии: второе не открывается, качество не растёт.
	s = c_state(["sprint"], ["intercept", "safe", "safe"])
	var r := RulesC.play_card(s, 0)
	check(r["lost"] and r["draws"].size() == 1 and s["events"].size() == 2 and s["quality"] == 0, "C: потеря на первом событии — второе не открыто, бонуса нет")
	s = c_state(["sprint"], ["pressure", "pressure", "safe"])
	r = RulesC.play_card(s, 0)
	check(r["lost"] and r["outcome"] == "lost" and s["quality"] == 0, "C: второе давление завершает атаку")
	s = c_state(["shield"], ["pressure", "safe"])
	s["pressure"] = 1
	r = RulesC.play_card(s, 0)
	check(not r["lost"] and s["pressure"] == 1 and s["quality"] == 1, "C: прикрыть мяч игнорирует давление")
	s = c_state(["shield"], ["intercept", "safe"])
	check(RulesC.play_card(s, 0)["lost"], "C: прикрыть мяч не спасает от перехвата")
	s = c_state(["switch_c"], ["pressure", "safe"])
	s["pressure"] = 1
	r = RulesC.play_card(s, 0)
	check(not r["lost"] and s["pressure"] == 1 and s["quality"] == 1, "C: перевод: сначала −1 давление, потом событие")

	# Не более 4 карт, потом только удар.
	s = c_state(["pass", "pass", "pass", "pass", "pass"], ["safe", "safe", "safe", "safe", "safe", "safe"])
	for i in 4:
		RulesC.play_card(s, i)
	check(s["played"] == 4 and RulesC.card_block_reason(s, 4) != "" and RulesC.shot_info(s)["available"], "C: после 4 карт остаётся только удар")
	check(RulesC.play_card(s, 0)["legal"] == false, "C: сыгранную карту нельзя сыграть снова")

	# Предпросмотр не трогает состояние и генератор.
	s = RulesC.new_attack(31, 1)
	var before := var_to_str(s)
	for i in s["hand"].size():
		RulesC.preview_card(s, i)
	RulesC.shot_info(s)
	check(var_to_str(s) == before, "C: предпросмотр не меняет состояние и колоду")

	# Бросок удара честен: доля голов ≈ показанному шансу.
	var goals := 0
	var n2 := 20000
	for k in n2:
		var t := RulesC.new_attack(k, 0)
		t["quality"] = 2 # 59%
		if RulesC.shoot(t)["goal"]:
			goals += 1
	check(absf(float(goals) / n2 - 0.59) < 0.015, "C: удар при 59%% даёт %.3f голов на 20000 атак" % (float(goals) / n2))

	# Воспроизводимость.
	var x := RulesC.new_attack(888, 4)
	var y := RulesC.new_attack(888, 4)
	RulesC.play_card(x, 0)
	RulesC.play_card(y, 0)
	check(var_to_str(x) == var_to_str(y), "C: тот же seed — те же события")
