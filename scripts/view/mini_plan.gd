class_name MiniPlan
extends Control
## Маленькая карта состояния обороны (3 коридора × 4 линии) с подписью.

var cells: Array = []
var ball := Pitch.NONE
var caption := ""
var highlight := false
var faded := false

const CELL := Vector2(26, 20)


func _init() -> void:
	custom_minimum_size = Vector2(CELL.x * 3 + 8, CELL.y * 4 + 30)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_data(p_cells: Array, p_ball: Vector2i, p_caption: String, p_highlight: bool) -> void:
	cells = p_cells
	ball = p_ball
	caption = p_caption
	highlight = p_highlight
	queue_redraw()


func _draw() -> void:
	var origin := Vector2((size.x - CELL.x * 3) / 2.0, 4)
	var grid := Rect2(origin, CELL * Vector2(3, 4))
	draw_rect(grid.grow(3), Color("2f4421") if not faded else Color("2a2a24"))
	for y in 4:
		for x in 3:
			var r := Rect2(origin + Vector2(x * CELL.x, (3 - y) * CELL.y), CELL).grow(-1)
			var col := Color("4b6a33") if y % 2 == 0 else Color("466330")
			if cells.has(Vector2i(x, y)):
				col = Color(0.9, 0.33, 0.24)
			draw_rect(r, col)
	if ball != Pitch.NONE:
		var bc := origin + Vector2((ball.x + 0.5) * CELL.x, (3 - ball.y + 0.5) * CELL.y)
		draw_circle(bc, 5, Color.WHITE)
		draw_circle(bc, 2, Color("222222"))
	draw_rect(Rect2(origin + Vector2(CELL.x * 0.9, -3), Vector2(CELL.x * 1.2, 3)), Color(1, 1, 1, 0.8))
	if highlight:
		draw_rect(grid.grow(4), Game.C_ACCENT, false, 2.0)
	var f := ThemeDB.fallback_font
	var w := f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(f, Vector2((size.x - w) / 2.0, grid.end.y + 18), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Game.C_ACCENT if highlight else Game.C_MUTED)
