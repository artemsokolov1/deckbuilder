class_name SettingsPanel
extends Control
## Настройки: громкость, быстрое исполнение, тряска экрана, сброс обучения.

signal closed


func _init() -> void:
	size = Vector2(1280, 720)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = size
	add_child(dim)
	var panel := Panel.new()
	panel.position = Vector2(400, 170)
	panel.size = Vector2(480, 380)
	panel.add_theme_stylebox_override("panel", Game.box(Game.C_PANEL_LIGHT, Game.C_ACCENT, 14, 3))
	add_child(panel)
	var v := VBoxContainer.new()
	v.position = Vector2(30, 22)
	v.size = Vector2(420, 340)
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var t := Label.new()
	t.text = "Настройки"
	t.add_theme_font_size_override("font_size", 28)
	t.add_theme_color_override("font_color", Game.C_ACCENT)
	v.add_child(t)
	var vol_row := HBoxContainer.new()
	var vol_l := Label.new()
	vol_l.text = "Громкость"
	vol_l.custom_minimum_size.x = 130
	vol_row.add_child(vol_l)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 1
	slider.step = 0.05
	slider.value = Game.settings["volume"]
	slider.custom_minimum_size = Vector2(220, 28)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pct := Label.new()
	pct.text = "%d%%" % int(Game.settings["volume"] * 100)
	slider.value_changed.connect(func(x: float):
		Game.settings["volume"] = x
		pct.text = "%d%%" % int(x * 100)
		Game.apply_volume()
		Sfx.play("click"))
	vol_row.add_child(slider)
	vol_row.add_child(pct)
	v.add_child(vol_row)
	var fast := CheckBox.new()
	fast.text = "Быстрое исполнение анимаций"
	fast.button_pressed = Game.settings["fast"]
	fast.toggled.connect(func(on: bool): Game.settings["fast"] = on)
	v.add_child(fast)
	var shake := CheckBox.new()
	shake.text = "Тряска экрана при голе и перехвате"
	shake.button_pressed = Game.settings["shake"]
	shake.toggled.connect(func(on: bool): Game.settings["shake"] = on)
	v.add_child(shake)
	var reset := Button.new()
	reset.text = "Снова показывать обучение во всех режимах"
	reset.pressed.connect(func():
		for m in Game.tutorial_seen:
			Game.tutorial_seen[m] = false
		Game.save_settings()
		reset.text = "Обучение будет показано при следующем запуске"
		reset.disabled = true)
	v.add_child(reset)
	var note := Label.new()
	note.text = "Оценки и история хранятся только на этом компьютере."
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Game.C_MUTED)
	v.add_child(note)
	var close := Button.new()
	close.text = "Закрыть"
	close.custom_minimum_size = Vector2(160, 42)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(close_panel)
	v.add_child(close)
	close.grab_focus()


func close_panel() -> void:
	Game.save_settings()
	Sfx.play("click")
	closed.emit()
	queue_free()
