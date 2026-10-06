class_name BallNode
extends Node2D
## Мяч: при полёте «поднимается» (height), тень остаётся на земле.

var height := 0.0:
	set(v):
		height = v
		queue_redraw()
var spin := 0.0:
	set(v):
		spin = v
		queue_redraw()


func _draw() -> void:
	var k := 1.0 / (1.0 + height / 40.0)
	draw_set_transform(Vector2(-3, 3), 0, Vector2(1.3 * k, 0.6 * k))
	draw_circle(Vector2.ZERO, 7, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2(0, -height), spin, Vector2.ONE * (1.0 + height / 120.0))
	draw_circle(Vector2.ZERO, 7.5, Color("1b1b1b"))
	draw_circle(Vector2.ZERO, 6.5, Color("fbfbf5"))
	draw_circle(Vector2(0, 0), 2.2, Color("2a2a2a"))
	for i in 5:
		var a := TAU * i / 5.0
		draw_circle(Vector2(cos(a), sin(a)) * 4.6, 1.1, Color("3a3a3a"))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
