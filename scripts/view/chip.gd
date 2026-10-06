class_name Chip
extends Node2D
## Фишка футболиста: круг с номером и длинной вечерней тенью.

const RADIUS := 16.0

var team := "att"  # att / def / gk
var number := 7
var glow := 0.0  # подсветка носителя мяча
var dim := false


func _draw() -> void:
	var body: Color
	var rim: Color
	var num_col: Color
	match team:
		"att":
			body = Color("f2a33a")
			rim = Color("fff1d6")
			num_col = Color("2a1a0c")
		"def":
			body = Color("33609f")
			rim = Color("cfe0f7")
			num_col = Color.WHITE
		_:
			body = Color("3aa37a")
			rim = Color("e6fff2")
			num_col = Color.WHITE
	if dim:
		body = body.darkened(0.35)
	# Тень от низкого солнца справа сверху — вытянута влево вниз.
	draw_set_transform(Vector2(-9, 7), -0.35, Vector2(1.55, 0.6))
	draw_circle(Vector2.ZERO, RADIUS, Color(0, 0, 0, 0.32))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	if glow > 0.01:
		draw_circle(Vector2.ZERO, RADIUS + 7, Color(1, 0.9, 0.5, 0.28 * glow))
	draw_circle(Vector2.ZERO, RADIUS, rim)
	draw_circle(Vector2.ZERO, RADIUS - 2.5, body)
	draw_circle(Vector2(-4, -5), RADIUS * 0.45, Color(1, 1, 1, 0.12))
	var f := ThemeDB.fallback_font
	var s := str(number)
	var fs := 15
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, Vector2(-w / 2.0, 5.5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, num_col)
