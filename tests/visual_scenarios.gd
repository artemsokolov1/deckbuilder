extends RefCounted
## Сценарии для tests/visual.gd. Каждый шаг: ["wait", кадры] / ["shot", имя] / ["call", Callable].

var tree: SceneTree


func scene() -> Node:
	return tree.current_scene


func practice() -> void:
	for c in scene().get_children():
		if c is TutorialOverlay:
			c.finished.emit(false)
			c.queue_free()


func get_steps(name: String, t: SceneTree) -> Array:
	tree = t
	var g: Node = t.root.get_node("Game")
	var steps: Array = []
	match name:
		"menu":
			steps = [["call", func(): t.change_scene_to_file("res://scenes/main_menu.tscn")], ["wait", 30], ["shot", "menu"]]
		"a":
			steps = [
				["call", func():
					for m in g.tutorial_seen: g.tutorial_seen[m] = true
					g.start_mode("a", 12345)],
				["wait", 30], ["shot", "a_start"],
				["call", func():
					var s = scene()
					s._on_card_hovered(s.cards[0], true)],
				["wait", 10], ["shot", "a_hover_card"],
				["call", func():
					var s = scene()
					s._on_card_pressed(s.cards[0])
					var tg = s.pitch.targets.keys()
					s.pitch.hover_cell = tg[0]
					s._on_cell_hovered(tg[0])],
				["wait", 10], ["shot", "a_target_preview"],
				["call", func():
					var s = scene()
					s._on_cell_clicked(s.pitch.targets.keys()[0])],
				["wait", 8], ["shot", "a_anim_mid"],
				["wait", 60], ["shot", "a_after_move"],
				["call", func():
					var s = scene()
					s._on_shot_hover(true)],
				["wait", 5], ["shot", "a_shot_hover"],
			]
		"a_tutorial":
			steps = [
				["call", func():
					g.start_mode("a", 1, true)],
				["wait", 30], ["shot", "a_tut_page1"],
				["call", func():
					var s = scene()
					for c in s.get_children():
						if c is TutorialOverlay:
							c._go(1); c._go(1); c._go(1)],
				["wait", 10], ["shot", "a_tut_page4"],
				["call", func():
					var s = scene()
					for c in s.get_children():
						if c is TutorialOverlay:
							c._go(1); c._go(1)],
				["wait", 30], ["shot", "a_tut_practice"],
			]
		"b":
			steps = [
				["call", func():
					for m in g.tutorial_seen: g.tutorial_seen[m] = true
					g.start_mode("b", 1, true)],
				["wait", 5], ["call", practice], ["wait", 30], ["shot", "b_start"],
				["call", func():
					var s = scene()
					s._on_card_pressed(s.cards[0])
					s.pitch.hover_cell = Vector2i(0, 2)
					s._on_cell_hovered(Vector2i(0, 2))],
				["wait", 10], ["shot", "b_select"],
				["call", func():
					var s = scene()
					s._on_cell_clicked(Vector2i(0, 2))
					s._on_card_pressed(s.cards[1])
					s._on_cell_clicked(Vector2i(0, 3))],
				["wait", 20], ["shot", "b_ready"],
				["call", func(): scene()._on_play()],
				["wait", 25], ["shot", "b_exec"],
				["wait", 200], ["shot", "b_result"],
			]
		"b_series":
			steps = [
				["call", func():
					for m in g.tutorial_seen: g.tutorial_seen[m] = true
					g.start_mode("b", 4242)],
				["wait", 30], ["shot", "b_series_start"],
				["call", func(): scene()._on_slot_hover(2, true)],
				["wait", 10], ["shot", "b_slot_hover"],
			]
		"c":
			steps = [
				["call", func():
					for m in g.tutorial_seen: g.tutorial_seen[m] = true
					g.start_mode("c", 1, true)],
				["wait", 5], ["call", practice], ["wait", 30], ["shot", "c_start"],
				["call", func():
					var s = scene()
					s._on_card_hovered(s.cards[3], true)],
				["wait", 10], ["shot", "c_hover"],
				["call", func():
					var s = scene()
					s._on_card_hovered(s.cards[3], false)
					s._on_card_pressed(s.cards[0])
					s._on_card_pressed(s.cards[0])],
				["wait", 20], ["shot", "c_reveal"],
				["wait", 90], ["shot", "c_after"],
				["call", func():
					var s = scene()
					s._on_card_pressed(s.cards[3])
					s._on_card_pressed(s.cards[3])],
				["wait", 150], ["shot", "c_after2"],
			]
		"a_match":
			steps = [
				["call", func():
					for m in g.tutorial_seen: g.tutorial_seen[m] = true
					g.start_mode("a", 1, true)],
				["wait", 5], ["call", practice], ["wait", 30], ["shot", "m_attack_start"],
				["call", func():
					var s = scene()
					s._on_card_hovered(s.cards[0], true)],
				["wait", 8], ["shot", "m_card_hover"],
				["call", func():
					var s = scene()
					s._on_card_hovered(s.cards[0], false)
					s._on_card_pressed(s.cards[s.state["hand"].find("sokolov")])
					s._on_cell_clicked(Vector2i(0, 1))],
				["wait", 60],
				["call", func():
					var s = scene()
					s._on_card_pressed(s.cards[s.state["hand"].find("zaitsev")])
					s._on_cell_clicked(Vector2i(0, 2))],
				["wait", 60],
				["call", func():
					var s = scene()
					s._on_card_pressed(s.cards[s.state["hand"].find("titov")])
					s._on_cell_clicked(Vector2i(0, 3))],
				["wait", 60], ["shot", "m_before_shot"],
				["call", func(): scene()._on_shot()],
				["wait", 200], ["shot", "m_attack_result"],
				["call", func(): scene()._continue()],
				["wait", 30], ["shot", "m_defense_start"],
				["call", func():
					var s = scene()
					s._on_card_pressed(s.cards[0])
					var c = RulesDefend.step_cell(s.dstate, 2)
					s.pitch.hover_cell = c
					s._on_cell_hovered(c)],
				["wait", 10], ["shot", "m_defense_select"],
				["call", func():
					var s = scene()
					s._on_cell_clicked(RulesDefend.step_cell(s.dstate, 2))],
				["wait", 30], ["shot", "m_defense_placed"],
				["call", func(): scene()._on_defend()],
				["wait", 40], ["shot", "m_defense_exec"],
				["wait", 150], ["shot", "m_defense_result"],
			]
		"misc":
			steps = [
				["call", func():
					for m in g.tutorial_seen: g.tutorial_seen[m] = true
					g.start_mode("a", 999)],
				["wait", 20],
				["call", func():
					var s = scene()
					s._on_mulligan()
					s._on_card_pressed(s.cards[1])
					s._on_card_pressed(s.cards[3])],
				["wait", 10], ["shot", "a_mulligan"],
				["call", func():
					var s = scene()
					s._cancel_mulligan()
					# найдём ход в опасную зону и сыграем его
					for i in s.state["hand"].size():
						for tg in RulesA.card_targets(s.state, i):
							if RulesA.preview_card(s.state, i, tg)["intercepted"] and s.state["actions"] == 0:
								s._on_card_pressed(s.cards[i])
								s.pitch.hover_cell = tg
								s._on_cell_hovered(tg)
								return],
				["wait", 10], ["shot", "a_risk_preview"],
				["call", func():
					var s = scene()
					if s.selected >= 0:
						s._on_cell_clicked(s.pitch.hover_cell)],
				["wait", 150], ["shot", "a_intercept_result"],
				["call", func(): scene()._on_settings()],
				["wait", 10], ["shot", "settings"],
				["call", func():
					g.start_mode("c", 5, true)],
				["wait", 20], ["shot", "c_tut_page"],
			]
		"results":
			steps = [
				["call", func():
					g.mode = "a"
					g.series_seed = 777
					g.attacks = [{"outcome": "goal", "reason": "Гол! качество 4 + позиция 3 − давление 0 = 7 против порога 5", "template": "Прессинг"},
						{"outcome": "intercept", "reason": "«Короткий пас» перехвачен: центр, линия 3.", "template": "Центр закрыт"},
						{"outcome": "goal", "reason": "Гол!", "template": "Низкий блок"},
						{"outcome": "save", "reason": "Вратарь спас.", "template": "Прессинг"},
						{"outcome": "lost", "reason": "Темп закончился, а удара не было — мяч потерян.", "template": "Низкий блок"}]
					g.series_start_ms = Time.get_ticks_msec() - 245000
					g.series_end_ms = Time.get_ticks_msec()
					t.change_scene_to_file("res://scenes/results.tscn")],
				["wait", 30], ["shot", "results"],
			]
	return steps
