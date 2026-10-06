extends Control
## Главное меню: три режима, по одному предложению объяснения, сводка сыгранного.

var _seed_edit: LineEdit
var _overlay: Control


func _ready() -> void:
	theme = Game.theme
	size = Vector2(1280, 720)
	var bg := _Backdrop.new()
	bg.size = size
	add_child(bg)
	var title := Label.new()
	title.text = "ПОСЛЕДНЯЯ АТАКА"
	title.position = Vector2(0, 42)
	title.size = Vector2(1280, 70)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Game.C_ACCENT)
	title.add_theme_color_override("font_outline_color", Color("1a120c"))
	title.add_theme_constant_override("outline_size", 12)
	add_child(title)
	var sub := Label.new()
	sub.text = "Дворовый футбол, короткие атаки. Три прототипа — сыграйте каждый и сравните."
	sub.position = Vector2(0, 116)
	sub.size = Vector2(1280, 30)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Game.C_MUTED)
	add_child(sub)
	var tags := {"a": "основной", "b": "головоломка", "c": "риск и шанс"}
	for i in 3:
		var m: String = Game.MODE_IDS[i]
		_mode_card(m, Rect2(40 + i * 408, 170, 384, 380), tags[m])
	# нижняя строка
	var seed_l := Label.new()
	seed_l.text = "Seed (необязательно):"
	seed_l.position = Vector2(40, 590)
	seed_l.add_theme_color_override("font_color", Game.C_MUTED)
	add_child(seed_l)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "случайный"
	_seed_edit.position = Vector2(232, 584)
	_seed_edit.size = Vector2(150, 36)
	_seed_edit.tooltip_text = "Одинаковый seed даёт одинаковые руки и планы обороны в одном режиме."
	add_child(_seed_edit)
	var settings := Button.new()
	settings.text = "Настройки"
	settings.position = Vector2(930, 582)
	settings.size = Vector2(150, 42)
	settings.pressed.connect(_on_settings)
	add_child(settings)
	var quit := Button.new()
	quit.text = "Выход"
	quit.position = Vector2(1090, 582)
	quit.size = Vector2(150, 42)
	quit.pressed.connect(func(): get_tree().quit())
	add_child(quit)
	var foot := Label.new()
	foot.text = "Управление: мышь — нажать карту, затем клетку. Esc — в меню из любого режима. Оценки и история хранятся только локально."
	foot.position = Vector2(40, 650)
	foot.size = Vector2(1200, 30)
	foot.add_theme_font_size_override("font_size", 14)
	foot.add_theme_color_override("font_color", Game.C_MUTED)
	add_child(foot)
	var ver := Label.new()
	ver.text = "прототип · Godot %s" % Engine.get_version_info()["string"]
	ver.position = Vector2(40, 680)
	ver.add_theme_font_size_override("font_size", 12)
	ver.add_theme_color_override("font_color", Color(Game.C_MUTED, 0.6))
	add_child(ver)


func _mode_card(m: String, r: Rect2, tag: String) -> void:
	var p := Panel.new()
	p.position = r.position
	p.size = r.size
	p.add_theme_stylebox_override("panel", Game.box(Game.C_PANEL, Game.C_ACCENT if m == "a" else Game.C_BORDER, 14, 3 if m == "a" else 2))
	add_child(p)
	var cfg := GameData.mode(m)
	var t := Label.new()
	t.text = cfg["title"]
	t.position = Vector2(22, 18)
	t.add_theme_font_size_override("font_size", 27)
	t.add_theme_color_override("font_color", Game.C_TEXT)
	p.add_child(t)
	var tg := Label.new()
	tg.text = tag
	tg.position = Vector2(24, 58)
	tg.add_theme_font_size_override("font_size", 14)
	tg.add_theme_color_override("font_color", Game.C_ACCENT)
	p.add_child(tg)
	var d := Label.new()
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.position = Vector2(22, 90)
	d.size = Vector2(r.size.x - 44, 110)
	d.text = cfg["menu_line"]
	d.add_theme_font_size_override("font_size", 18)
	p.add_child(d)
	var s := Game.mode_summary(m)
	var st := Label.new()
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st.position = Vector2(22, 206)
	st.size = Vector2(r.size.x - 44, 60)
	st.add_theme_font_size_override("font_size", 14)
	st.add_theme_color_override("font_color", Game.C_MUTED)
	if s["series"] == 0:
		st.text = "Ещё не сыграно." + ("" if Game.tutorial_seen[m] else " Начнётся с короткого обучения.")
	else:
		st.text = "Серий: %d · побед: %d · голов в среднем: %.1f" % [s["series"], s["wins"], float(s["goals"]) / s["series"]]
		if s["ratings"] > 0:
			st.text += "\nОценки (понятно / футбол / повторить): %.1f / %.1f / %.1f" % [s["clarity"], s["football"], s["replay"]]
	p.add_child(st)
	var play := Button.new()
	play.text = "Играть"
	play.position = Vector2(22, 276)
	play.size = Vector2(r.size.x - 44, 56)
	play.add_theme_font_size_override("font_size", 24)
	play.pressed.connect(func(): _start(m, false))
	p.add_child(play)
	var tut := Button.new()
	tut.text = "С обучением"
	tut.flat = true
	tut.position = Vector2(22, 336)
	tut.size = Vector2(r.size.x - 44, 32)
	tut.add_theme_font_size_override("font_size", 15)
	tut.add_theme_color_override("font_color", Game.C_MUTED)
	tut.pressed.connect(func(): _start(m, true))
	p.add_child(tut)
	if m == "a":
		play.grab_focus.call_deferred()


func _start(m: String, tutorial: bool) -> void:
	Sfx.play("click")
	var sd := -1
	var txt := _seed_edit.text.strip_edges()
	if txt.is_valid_int():
		sd = absi(int(txt))
	Game.start_mode(m, sd, tutorial)


func _on_settings() -> void:
	if _overlay and is_instance_valid(_overlay):
		return
	Sfx.play("click")
	var s := SettingsPanel.new()
	add_child(s)
	_overlay = s


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _overlay and is_instance_valid(_overlay):
		get_viewport().set_input_as_handled()
		_overlay.close_panel()
		_overlay = null


## Фон: вечерний двор — асфальт, тёплый свет, силуэт ограды.
class _Backdrop:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Game.C_BG)
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(0, size.y)]),
			PackedColorArray([Color(0.45, 0.22, 0.08, 0.5), Color(0.75, 0.42, 0.15, 0.55), Color(0.12, 0.08, 0.06, 0.2), Color(0.05, 0.04, 0.05, 0.3)]))
		# ограда
		var y := 150.0
		var x := 0.0
		while x < size.x:
			draw_line(Vector2(x, y), Vector2(x + 24, y - 24), Color(0, 0, 0, 0.18), 1.5)
			draw_line(Vector2(x + 24, y), Vector2(x, y - 24), Color(0, 0, 0, 0.18), 1.5)
			x += 24
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0, 0, 0.35), 3)
		draw_line(Vector2(0, y - 24), Vector2(size.x, y - 24), Color(0, 0, 0, 0.35), 3)
		draw_rect(Rect2(0, 560, size.x, 160), Color(0, 0, 0, 0.25))
