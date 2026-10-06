class_name GameBase
extends Control
## Общая оболочка игровых экранов: верхняя панель, поле, область руки, обучение,
## итог атаки, настройки, Esc, блокировка ввода во время анимаций.
## Подклассы режимов реализуют: _mode_id(), _build_mode_ui(), _start_attack(tutorial),
## _tutorial_pages(), _template_name().

const PITCH_POS := Vector2(16, 56)
const PANEL_RECT := Rect2(632, 56, 632, 476)
const HAND_Y := 536.0

var pitch: PitchView
var right: Control  # контейнер правой панели
var hand_box: Control  # область карт
var busy := false  # идёт анимация/исполнение — ввод игнорируется
var tutorial_active := false
var attack_idx := 0
var attack_over := false
var _title_lb: Label
var _attack_lb: Label
var _pips: Control
var _seed_lb: Label
var _result_panel: Control
var _overlay: Control
var _hint_lb: RichTextLabel
var _deco := RandomNumberGenerator.new()


func _ready() -> void:
	theme = Game.theme
	size = Vector2(1280, 720)
	_deco.randomize()
	var bg := ColorRect.new()
	bg.color = Game.C_BG
	bg.size = size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_build_top_bar()
	pitch = PitchView.new()
	pitch.position = PITCH_POS
	add_child(pitch)
	right = Control.new()
	right.position = PANEL_RECT.position
	right.size = PANEL_RECT.size
	add_child(right)
	hand_box = Control.new()
	hand_box.position = Vector2(0, HAND_Y)
	hand_box.size = Vector2(1280, 720 - HAND_Y)
	hand_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hand_box)
	_build_mode_ui()
	_hint_lb = RichTextLabel.new()
	_hint_lb.bbcode_enabled = true
	_hint_lb.fit_content = true
	_hint_lb.position = PITCH_POS + Vector2(60, 4)
	_hint_lb.size = Vector2(480, 30)
	_hint_lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_lb.add_theme_stylebox_override("normal", Game.box(Color(0.1, 0.25, 0.35, 0.94), Game.C_INFO, 8, 2))
	_hint_lb.visible = false
	add_child(_hint_lb)
	if Game.want_tutorial:
		_show_tutorial(true)
	else:
		_begin_series()


# ------------------------------------------------------------------ виртуальные
func _mode_id() -> String:
	return "a"


func _build_mode_ui() -> void:
	pass


func _start_attack(_tutorial: bool) -> void:
	pass


func _tutorial_pages() -> Array:
	return []


func _template_name() -> String:
	return ""


# ------------------------------------------------------------------ верхняя панель
func _build_top_bar() -> void:
	var bar := Panel.new()
	bar.position = Vector2(0, 0)
	bar.size = Vector2(1280, 48)
	bar.add_theme_stylebox_override("panel", Game.box(Color("100c0a"), Color("3a2c1f"), 0, 1))
	add_child(bar)
	_title_lb = Label.new()
	_title_lb.position = Vector2(16, 9)
	_title_lb.add_theme_font_size_override("font_size", 20)
	_title_lb.add_theme_color_override("font_color", Game.C_ACCENT)
	_title_lb.text = "Последняя атака · " + Game.mode_title(_mode_id())
	bar.add_child(_title_lb)
	_attack_lb = Label.new()
	_attack_lb.position = Vector2(400, 11)
	_attack_lb.add_theme_font_size_override("font_size", 18)
	bar.add_child(_attack_lb)
	_pips = Control.new()
	_pips.position = Vector2(515, 8)
	_pips.size = Vector2(250, 32)
	_pips.draw.connect(_draw_pips)
	_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_pips)
	_seed_lb = Label.new()
	_seed_lb.position = Vector2(838, 15)
	_seed_lb.add_theme_font_size_override("font_size", 12)
	_seed_lb.add_theme_color_override("font_color", Game.C_MUTED)
	bar.add_child(_seed_lb)
	var x := 925.0
	for spec in [["Правила", _on_rules, 96.0], ["Настройки", _on_settings, 112.0], ["Меню (Esc)", Game.go_menu, 118.0]]:
		var b := Button.new()
		b.text = spec[0]
		b.position = Vector2(x, 6)
		b.size = Vector2(spec[2], 36)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(spec[1])
		bar.add_child(b)
		x += spec[2] + 8
	_update_top()


func _update_top() -> void:
	var n: int = GameData.series()["attacks"]
	if tutorial_active:
		_attack_lb.text = "Тренировка"
	else:
		_attack_lb.text = "Атака %d из %d" % [mini(attack_idx + 1, n), n]
	_seed_lb.text = "seed %d" % Game.series_seed
	_pips.queue_redraw()


func _draw_pips() -> void:
	var n: int = GameData.series()["attacks"]
	var need: int = GameData.series()["goals_to_win"]
	var f := ThemeDB.fallback_font
	for i in n:
		var c := Vector2(14 + i * 30, 16)
		var col := Color(1, 1, 1, 0.15)
		var txt := ""
		if i < Game.attacks.size() and not tutorial_active:
			match Game.attacks[i]["outcome"]:
				"goal":
					col = Game.C_SAFE
					txt = "Г"
				"save":
					col = Game.C_WARN
					txt = "С"
				"intercept":
					col = Game.C_DANGER
					txt = "П"
				_:
					col = Color(0.6, 0.55, 0.5)
					txt = "—"
		_pips.draw_circle(c, 12, col)
		if i == attack_idx and not tutorial_active and not attack_over:
			_pips.draw_arc(c, 14, 0, TAU, 20, Game.C_ACCENT, 2.0)
		if txt != "":
			_pips.draw_string(f, c + Vector2(-5, 5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("1a120c"))
	_pips.draw_string(f, Vector2(14 + n * 30, 22), "голы %d · нужно %d" % [Game.goals(), need],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Game.C_TEXT)


# ------------------------------------------------------------------ поток серии
func _show_tutorial(then_practice: bool) -> void:
	var t := TutorialOverlay.new()
	t.pages = _tutorial_pages()
	t.final_label = "К тренировке ▶" if then_practice else "Понятно"
	t.allow_skip = then_practice
	add_child(t)
	_overlay = t
	if then_practice:
		t.finished.connect(func(skipped: bool):
			_overlay = null
			Game.mark_tutorial_seen(_mode_id())
			if skipped:
				_begin_series()
			else:
				tutorial_active = true
				attack_idx = 0
				_new_attack())
	else:
		t.finished.connect(func(_s: bool): _overlay = null)


func _begin_series() -> void:
	tutorial_active = false
	Game.begin_series_clock()
	attack_idx = 0
	_new_attack()


func _new_attack() -> void:
	attack_over = false
	busy = false
	if _result_panel:
		_result_panel.queue_free()
		_result_panel = null
	_update_top()
	_hint_lb.visible = tutorial_active
	_start_attack(tutorial_active)
	Sfx.play("whistle")


## Подклассы вызывают после завершения атаки (после анимации).
func end_attack(outcome: String, reason: String) -> void:
	attack_over = true
	busy = false
	if not tutorial_active:
		Game.record_attack(outcome, reason, _template_name())
	_update_top()
	_hint_lb.visible = false
	_show_result(outcome, reason)


func _show_result(outcome: String, reason: String) -> void:
	var titles := {"goal": "ГОЛ!", "save": "Сейв вратаря", "intercept": "Перехват", "lost": "Потеря мяча"}
	var cols := {"goal": Game.C_SAFE, "save": Game.C_WARN, "intercept": Game.C_DANGER, "lost": Color(0.75, 0.7, 0.65)}
	var p := Panel.new()
	p.position = Vector2(16, HAND_Y - 4)
	p.size = Vector2(1248, 176)
	p.add_theme_stylebox_override("panel", Game.box(Color(0.1, 0.075, 0.06, 0.97), cols.get(outcome, Game.C_BORDER), 12, 3))
	add_child(p)
	_result_panel = p
	var t := Label.new()
	t.text = titles.get(outcome, outcome)
	t.position = Vector2(24, 14)
	t.add_theme_font_size_override("font_size", 34)
	t.add_theme_color_override("font_color", cols.get(outcome, Game.C_TEXT))
	p.add_child(t)
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.position = Vector2(24, 64)
	body.size = Vector2(860, 100)
	body.add_theme_font_size_override("normal_font_size", 18)
	body.add_theme_font_size_override("bold_font_size", 18)
	body.text = reason
	p.add_child(body)
	var n: int = GameData.series()["attacks"]
	var btn := Button.new()
	btn.add_theme_font_size_override("font_size", 20)
	btn.position = Vector2(920, 60)
	btn.size = Vector2(300, 60)
	if tutorial_active:
		btn.text = "Начать серию ▶"
		var again := Button.new()
		again.text = "Повторить тренировку"
		again.position = Vector2(920, 126)
		again.size = Vector2(300, 36)
		again.pressed.connect(func():
			Sfx.play("click")
			_new_attack())
		p.add_child(again)
	elif attack_idx + 1 >= n:
		btn.text = "Итоги серии ▶"
	else:
		btn.text = "Следующая атака ▶"
	btn.pressed.connect(_continue)
	p.add_child(btn)
	var hint := Label.new()
	hint.text = "Пробел / Enter — продолжить"
	hint.position = Vector2(925, 22)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Game.C_MUTED)
	p.add_child(hint)
	btn.grab_focus()


func _continue() -> void:
	if not attack_over or _result_panel == null:
		return
	Sfx.play("click")
	if tutorial_active:
		_begin_series()
		return
	var n: int = GameData.series()["attacks"]
	if attack_idx + 1 >= n:
		attack_over = false
		Game.finish_series()
		return
	attack_idx += 1
	_new_attack()


func set_hint(bb: String) -> void:
	if not tutorial_active:
		_hint_lb.visible = false
		return
	_hint_lb.visible = bb != ""
	_hint_lb.text = "[color=#cfefff]Подсказка:[/color] " + bb


# ------------------------------------------------------------------ ввод и оверлеи
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _overlay and is_instance_valid(_overlay):
			if _overlay is SettingsPanel:
				_overlay.close_panel()
				_overlay = null
				return
			if _overlay is TutorialOverlay and not Game.want_tutorial:
				_overlay.queue_free()
				_overlay = null
				return
		Game.go_menu()
	elif attack_over and _result_panel and event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		get_viewport().set_input_as_handled()
		_continue()


func _on_rules() -> void:
	if _overlay and is_instance_valid(_overlay):
		return
	Sfx.play("click")
	_show_tutorial(false)


func _on_settings() -> void:
	if _overlay and is_instance_valid(_overlay):
		return
	Sfx.play("click")
	var s := SettingsPanel.new()
	s.closed.connect(func(): _overlay = null)
	add_child(s)
	_overlay = s


# ------------------------------------------------------------------ утилиты анимации
## Пауза, привязанная к этой сцене: при выходе в меню твин уничтожается вместе со сценой,
## и отложенное продолжение никогда не выполнится.
func wait(sec: float) -> Signal:
	var tw := create_tween()
	tw.tween_interval(maxf(0.01, sec * Game.speed()))
	return tw.finished


func dur(sec: float) -> float:
	return sec * Game.speed()


func shake(strength: float = 8.0) -> void:
	if not Game.settings["shake"]:
		return
	var tw := create_tween()
	for i in 6:
		var off := Vector2(_deco.randf_range(-1, 1), _deco.randf_range(-1, 1)) * strength * (1.0 - i / 6.0)
		tw.tween_property(pitch, "position", PITCH_POS + off, 0.04)
	tw.tween_property(pitch, "position", PITCH_POS, 0.05)


# --- конструкторы интерфейса
func lbl(parent: Control, text: String, pos: Vector2, fs: int = 17, col: Color = Game.C_TEXT, w: float = 0.0) -> Label:
	var l := Label.new()
	if w > 0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size.x = w
	l.position = pos
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.text = text
	parent.add_child(l)
	return l


func rich(parent: Control, rect: Rect2, fs: int = 16) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.position = rect.position
	r.size = rect.size
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", fs)
	r.add_theme_font_size_override("bold_font_size", fs)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


func panel(parent: Control, rect: Rect2, border: Color = Game.C_BORDER) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.add_theme_stylebox_override("panel", Game.box(Game.C_PANEL, border, 10, 2))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


func button(parent: Control, text: String, rect: Rect2, cb: Callable, fs: int = 18) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", fs)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


static func pct(p: float) -> String:
	var v := p * 100.0
	if absf(v - roundf(v)) < 0.05:
		return "%d%%" % int(roundf(v))
	return ("%.1f%%" % v).replace(".", ",")


static func col_hex(c: Color) -> String:
	return "#" + c.to_html(false)
