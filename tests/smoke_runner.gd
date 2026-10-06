extends RefCounted
## Логика прогона интерфейса (загружается из tests/smoke.gd после регистрации автозагрузок).

var tree: SceneTree
var fails := 0
var g: Node


func check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   ", label)
	else:
		fails += 1
		print("  FAIL ", label)


func frames(n: int) -> void:
	for i in n:
		await tree.process_frame


func until(cond: Callable, max_frames: int = 2000) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await tree.process_frame
	return false


func scene() -> Node:
	return tree.current_scene


func run(t: SceneTree) -> void:
	tree = t
	g = tree.root.get_node("Game")
	g.settings["fast"] = true
	g.settings["volume"] = 0.0
	for m in g.tutorial_seen:
		g.tutorial_seen[m] = true
	print("=== Прогон интерфейса ===")
	for mode in ["a", "b", "c"]:
		await _series(mode, 1000 + mode.unicode_at(0))
	await _tutorial_flow()
	await _escape_during_animation()
	await _double_clicks()
	await _replay_same_seed()
	print("=== Итог прогона: %s ===" % ("OK" if fails == 0 else "%d провалов" % fails))
	tree.quit(1 if fails > 0 else 0)


func _series(mode: String, sd: int) -> void:
	print("-- серия режима ", mode)
	g.start_mode(mode, sd)
	await frames(3)
	for k in 5:
		var ok := await until(func(): return scene() is GameBase and scene().state.size() > 0 and not scene().busy)
		if not ok:
			check(false, "%s: атака %d не началась" % [mode, k + 1])
			return
		var s: GameBase = scene()
		match mode:
			"a": await _bot_a(s)
			"b": await _bot_b(s)
			"c": await _bot_c(s)
		var ended := await until(func(): return scene().attack_over, 3000)
		check(ended, "%s: атака %d завершилась (%s)" % [mode, k + 1, s.state.get("outcome", "?")])
		s._continue()
		await frames(2)
	var at_results := await until(func(): return scene() != null and scene().scene_file_path.ends_with("results.tscn"))
	check(at_results, "%s: после 5 атак показан экран итогов" % mode)
	check(g.attacks.size() == 5, "%s: записано 5 атак (голов: %d)" % [mode, g.goals()])
	await frames(5)


func _bot_a(s: GameBase) -> void:
	for guard in 12:
		if s.attack_over or s.state["over"]:
			return
		await until(func(): return not s.busy)
		if s.state["over"]:
			return
		var info := RulesA.shot_info(s.state)
		if info["available"] and (info["goal"] or int(s.state["tempo"]) <= 1):
			s._on_shot()
			return
		var played := false
		for i in s.state["hand"].size():
			for t in RulesA.card_targets(s.state, i):
				var p := RulesA.preview_card(s.state, i, t)
				if not p["intercepted"] and int(p["after"]["tempo"]) >= 1:
					s._on_card_pressed(s.cards[i])
					s._on_cell_clicked(t)
					played = true
					break
			if played:
				break
		if not played:
			if info["available"]:
				s._on_shot()
				return
			for i in s.state["hand"].size():
				var ts := RulesA.card_targets(s.state, i)
				if not ts.is_empty():
					s._on_card_pressed(s.cards[i])
					s._on_cell_clicked(ts[0])
					played = true
					break
			if not played:
				return
		await frames(2)


func _bot_b(s: GameBase) -> void:
	# ищем голевой план, иначе любой допустимый
	var best: Array = []
	for i in 6:
		for t1 in RulesB.card_targets(s.state, i, 0):
			var s1: Dictionary = s.state.duplicate(true)
			RulesB.place(s1, 0, i, t1)
			for j in 6:
				if j == i:
					continue
				for t2 in RulesB.card_targets(s1, j, 1):
					var s2: Dictionary = s1.duplicate(true)
					RulesB.place(s2, 1, j, t2)
					if RulesB.ready_reason(s2) != "":
						continue
					var goal: bool = RulesB.simulate(s2)["outcome"] == "goal"
					if best.is_empty() or (goal and not best[4]):
						best = [i, t1, j, t2, goal]
	if best.is_empty():
		check(false, "B: нет допустимого плана")
		return
	s._on_card_pressed(s.cards[best[0]])
	s._on_cell_clicked(best[1])
	s._on_card_pressed(s.cards[best[2]])
	s._on_cell_clicked(best[3])
	check(RulesB.ready_reason(s.state) == "", "B: план собран через интерфейс")
	s._on_play()


func _bot_c(s: GameBase) -> void:
	for i in s.state["hand"].size():
		if RulesC.card_block_reason(s.state, i) == "":
			s._on_card_pressed(s.cards[i])
			s._on_card_pressed(s.cards[i])
			break
	await until(func(): return not s.busy)
	if not s.state["over"]:
		s._on_shot()


func _tutorial_flow() -> void:
	print("-- обучение")
	for mode in ["a", "b", "c"]:
		g.start_mode(mode, 5, true)
		await frames(3)
		var ov: Node = null
		for c in scene().get_children():
			if c is TutorialOverlay:
				ov = c
		check(ov != null, "%s: обучение показано" % mode)
		if ov == null:
			continue
		for k in ov.pages.size():
			ov._go(1)
		await frames(2)
		var s: GameBase = scene()
		check(s.tutorial_active and s.state.size() > 0 and s.state["tutorial"], "%s: тренировочная атака с заданной рукой" % mode)
		check(g.attacks.is_empty(), "%s: тренировка не идёт в счёт" % mode)


func _escape_during_animation() -> void:
	print("-- выход во время анимации")
	g.settings["fast"] = false
	for mode in ["a", "b", "c"]:
		g.start_mode(mode, 77)
		await frames(3)
		var s: GameBase = scene()
		match mode:
			"a":
				var info := RulesA.shot_info(s.state)
				for i in s.state["hand"].size():
					var ts := RulesA.card_targets(s.state, i)
					if not ts.is_empty():
						s._on_card_pressed(s.cards[i])
						s._on_cell_clicked(ts[0])
						break
			"b":
				await _bot_b(s)
			"c":
				s._on_shot()
		await frames(4)
		check(s.busy, "%s: анимация идёт" % mode)
		var ev := InputEventAction.new()
		ev.action = "ui_cancel"
		ev.pressed = true
		Input.parse_input_event(ev)
		await frames(4)
		check(scene() != null and scene().scene_file_path.ends_with("main_menu.tscn"), "%s: Esc во время анимации вернул в меню" % mode)
		await frames(120)  # отложенные твины не должны «ожить» после выхода
		check(scene().scene_file_path.ends_with("main_menu.tscn"), "%s: после выхода ничего не продолжилось" % mode)
	g.settings["fast"] = true


func _double_clicks() -> void:
	print("-- быстрые повторные нажатия")
	# B: два нажатия «Разыграть» подряд
	g.start_mode("b", 31)
	await frames(3)
	var s: GameBase = scene()
	await _bot_b_place_only(s)
	s._on_play()
	s._on_play()
	s._on_play()
	await until(func(): return s.attack_over, 3000)
	check(g.attacks.size() == 1, "B: тройное «Разыграть» исполнило план один раз")
	# A: двойной удар и клик по клетке во время анимации
	g.start_mode("a", 31)
	await frames(3)
	s = scene()
	var played := false
	for i in s.state["hand"].size():
		var ts := RulesA.card_targets(s.state, i)
		if not ts.is_empty():
			s._on_card_pressed(s.cards[i])
			s._on_cell_clicked(ts[0])
			var actions: int = s.state["actions"]
			# повторные клики во время анимации
			if s.cards.size() > 0:
				s._on_card_pressed(s.cards[0])
			s._on_cell_clicked(ts[0])
			s._on_shot()
			check(s.state["actions"] == actions and s.busy, "A: клики во время анимации игнорируются")
			played = true
			break
	check(played, "A: первый ход сделан")
	# C: двойной удар
	g.start_mode("c", 31)
	await frames(3)
	s = scene()
	s._on_shot()
	s._on_shot()
	await until(func(): return s.attack_over, 3000)
	check(g.attacks.size() == 1, "C: двойной удар засчитан один раз")


func _bot_b_place_only(s: GameBase) -> void:
	for i in 6:
		for t1 in RulesB.card_targets(s.state, i, 0):
			var s1: Dictionary = s.state.duplicate(true)
			RulesB.place(s1, 0, i, t1)
			for j in 6:
				if j == i:
					continue
				for t2 in RulesB.card_targets(s1, j, 1):
					var s2: Dictionary = s1.duplicate(true)
					RulesB.place(s2, 1, j, t2)
					if RulesB.ready_reason(s2) == "":
						s._on_card_pressed(s.cards[i])
						s._on_cell_clicked(t1)
						s._on_card_pressed(s.cards[j])
						s._on_cell_clicked(t2)
						return


func _replay_same_seed() -> void:
	print("-- повтор того же seed")
	for mode in ["a", "b", "c"]:
		g.start_mode(mode, 4321)
		await frames(3)
		var first := var_to_str(scene().state)
		g.start_mode(mode, 4321)
		await frames(3)
		check(var_to_str(scene().state) == first, "%s: «Повторить те же условия» даёт ту же атаку" % mode)
