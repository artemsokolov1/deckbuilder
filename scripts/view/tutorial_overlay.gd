class_name TutorialOverlay
extends Control
## Короткое обучение: несколько страниц с картинкой-подсказкой текстом.

signal finished(skipped: bool)

var pages: Array = []  # [{title, text}]
var final_label := "Начать"
var allow_skip := true
var _i := 0
var _title: Label
var _body: RichTextLabel
var _dots: Label
var _next: Button
var _back: Button


func _init() -> void:
	size = Vector2(1280, 720)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.01, 0.72)
	dim.size = size
	add_child(dim)
	var panel := Panel.new()
	panel.position = Vector2(300, 150)
	panel.size = Vector2(680, 420)
	panel.add_theme_stylebox_override("panel", Game.box(Game.C_PANEL_LIGHT, Game.C_ACCENT, 14, 3))
	add_child(panel)
	_title = Label.new()
	_title.position = Vector2(28, 20)
	_title.size = Vector2(624, 40)
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", Game.C_ACCENT)
	panel.add_child(_title)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.position = Vector2(28, 70)
	_body.size = Vector2(624, 270)
	_body.add_theme_font_size_override("normal_font_size", 19)
	_body.add_theme_font_size_override("bold_font_size", 19)
	_body.scroll_active = false
	panel.add_child(_body)
	_dots = Label.new()
	_dots.position = Vector2(28, 365)
	_dots.add_theme_color_override("font_color", Game.C_MUTED)
	panel.add_child(_dots)
	_back = Button.new()
	_back.text = "Назад"
	_back.position = Vector2(300, 356)
	_back.size = Vector2(110, 44)
	_back.pressed.connect(func(): _go(-1))
	panel.add_child(_back)
	_next = Button.new()
	_next.position = Vector2(422, 356)
	_next.size = Vector2(230, 44)
	_next.add_theme_font_size_override("font_size", 19)
	_next.pressed.connect(func(): _go(1))
	panel.add_child(_next)
	if allow_skip:
		var skip := Button.new()
		skip.text = "Пропустить обучение"
		skip.flat = true
		skip.position = Vector2(470, 18)
		skip.size = Vector2(190, 32)
		skip.add_theme_color_override("font_color", Game.C_MUTED)
		skip.pressed.connect(func():
			Sfx.play("click")
			finished.emit(true)
			queue_free())
		panel.add_child(skip)
	_show()
	_next.grab_focus()


func _go(d: int) -> void:
	if _i >= pages.size():
		return
	Sfx.play("click")
	_i += d
	if _i >= pages.size():
		finished.emit(false)
		queue_free()
		return
	_i = maxi(0, _i)
	_show()


func _show() -> void:
	_title.text = pages[_i]["title"]
	_body.text = pages[_i]["text"]
	var dots := ""
	for k in pages.size():
		dots += "● " if k == _i else "○ "
	_dots.text = dots + "  %d / %d" % [_i + 1, pages.size()]
	_back.disabled = _i == 0
	_next.text = final_label if _i == pages.size() - 1 else "Далее ▶"


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if _i >= pages.size():
		return
	if event.is_pressed() and (event.is_action("ui_accept") or (event is InputEventKey and event.keycode == KEY_RIGHT)):
		get_viewport().set_input_as_handled()
		_go(1)
