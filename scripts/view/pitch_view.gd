class_name PitchView
extends Control
## Общее для всех режимов поле: двор, ограда, ворота, зрители, коридоры и линии,
## опасные зоны, подсветка целей, линия паса, фишки и мяч, анимации.
## Отображение ничего не решает — оно только показывает состояние правил.

signal cell_clicked(cell: Vector2i)
signal cell_hovered(cell: Vector2i)

const VIEW := Vector2(600, 480)
const FIELD := Rect2(44, 84, 512, 368)
const CW := 512.0 / 3.0
const CH := 92.0
const ATT_OFF := Vector2(-22, 14)
const DEF_OFF := Vector2(22, -14)
const GOAL_RECT := Rect2(205, 52, 190, 32)

# --- данные подсветки (задаёт контроллер режима)
var danger_now: Array = []
var danger_next: Array = []
var targets: Dictionary = {}  # Vector2i -> "safe" | "risk" | "protected"
var hover_cell := Pitch.NONE
var preview: Dictionary = {}  # from, cells[], ok, bad, to
var route: Array = []  # [{from,to,ok,num}] — план режима B
var pressure_cells: Array = []
var shot_lines: Array = [2, 3]
var show_shot_band := true
var dim_field := false

var net_shake := 0.0:
	set(v):
		net_shake = v
		if _goal_layer:
			_goal_layer.queue_redraw()
var crowd_jump := 0.0:
	set(v):
		crowd_jump = v
		if _crowd_layer:
			_crowd_layer.queue_redraw()

var attackers: Array[Chip] = []
var defenders: Array[Chip] = []
var keeper: Chip
var ball: BallNode
var carrier: Chip

var _deco := RandomNumberGenerator.new()  # декоративная случайность
var _patches: Array = []
var _cracks: Array = []
var _crowd: Array = []
var _pulse := 0.0
var _crowd_layer: DrawLayer
var _zone_layer: DrawLayer
var _goal_layer: DrawLayer
var _chip_layer: Node2D
var _arrow_layer: DrawLayer
var _light_layer: DrawLayer
var _fx_layer: Node2D


class DrawLayer:
	extends Node2D
	var fn: Callable

	func _draw() -> void:
		if fn.is_valid():
			fn.call(self)


func _init() -> void:
	custom_minimum_size = VIEW
	size = VIEW
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _ready() -> void:
	_deco.seed = 20241006
	_make_decor()
	_crowd_layer = _layer(_draw_crowd)
	_goal_layer = _layer(_draw_goal)
	_zone_layer = _layer(_draw_zones)
	_chip_layer = Node2D.new()
	add_child(_chip_layer)
	_arrow_layer = _layer(_draw_arrows)
	_light_layer = _layer(_draw_light)
	_fx_layer = Node2D.new()
	add_child(_fx_layer)
	keeper = _chip("gk", 1)
	keeper.position = Vector2(300, FIELD.position.y + 8)
	for i in 5:
		defenders.append(_chip("def", [4, 5, 6, 3, 8][i]))
		defenders[i].position = Vector2(300, -40)
		defenders[i].modulate.a = 0.0
	for i in 5:
		attackers.append(_chip("att", [7, 8, 9, 10, 11][i]))
	ball = BallNode.new()
	_chip_layer.add_child(ball)
	mouse_exited.connect(func():
		if hover_cell != Pitch.NONE:
			hover_cell = Pitch.NONE
			cell_hovered.emit(Pitch.NONE))


func _layer(fn: Callable) -> DrawLayer:
	var l := DrawLayer.new()
	l.fn = fn
	add_child(l)
	return l


func _chip(team: String, num: int) -> Chip:
	var c := Chip.new()
	c.team = team
	c.number = num
	_chip_layer.add_child(c)
	return c


func _process(delta: float) -> void:
	if not targets.is_empty() or not route.is_empty() or not preview.is_empty():
		_pulse += delta
		_zone_layer.queue_redraw()
		_arrow_layer.queue_redraw()


# ------------------------------------------------------------------ геометрия
static func cell_rect(c: Vector2i) -> Rect2:
	return Rect2(FIELD.position.x + c.x * CW, FIELD.position.y + (Pitch.LINES - 1 - c.y) * CH, CW, CH)


static func cell_center(c: Vector2i) -> Vector2:
	return cell_rect(c).get_center()


static func att_pos(c: Vector2i) -> Vector2:
	return cell_center(c) + ATT_OFF


static func def_pos(c: Vector2i) -> Vector2:
	return cell_center(c) + DEF_OFF


func cell_at(p: Vector2) -> Vector2i:
	if not FIELD.has_point(p):
		return Pitch.NONE
	var x := int((p.x - FIELD.position.x) / CW)
	var y := Pitch.LINES - 1 - int((p.y - FIELD.position.y) / CH)
	var c := Vector2i(clampi(x, 0, 2), clampi(y, 0, 3))
	return c


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var c := cell_at(event.position)
		if c != hover_cell:
			hover_cell = c
			_zone_layer.queue_redraw()
			cell_hovered.emit(c)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var c := cell_at(event.position)
		if c != Pitch.NONE:
			cell_clicked.emit(c)
			accept_event()


# ------------------------------------------------------------------ установка подсветки
func refresh() -> void:
	_zone_layer.queue_redraw()
	_arrow_layer.queue_redraw()


func set_danger(now: Array, next: Array) -> void:
	danger_now = now.duplicate()
	danger_next = next.duplicate()
	_zone_layer.queue_redraw()


func set_targets(t: Dictionary) -> void:
	targets = t
	refresh()


func set_preview(p: Dictionary) -> void:
	preview = p
	refresh()


func set_route(r: Array) -> void:
	route = r
	refresh()


func set_pressure(cells: Array) -> void:
	pressure_cells = cells.duplicate()
	refresh()


func clear_marks() -> void:
	targets = {}
	preview = {}
	pressure_cells = []
	refresh()


# ------------------------------------------------------------------ рисование
func _make_decor() -> void:
	for i in 26:
		var center := Vector2(_deco.randf_range(FIELD.position.x, FIELD.end.x), _deco.randf_range(FIELD.position.y, FIELD.end.y))
		if i < 6:
			# протоптанные места у ворот и в центре
			center = Vector2(300 + _deco.randf_range(-90, 90), FIELD.position.y + _deco.randf_range(10, 120))
		_patches.append({"c": center, "r": Vector2(_deco.randf_range(18, 48), _deco.randf_range(10, 26)),
			"a": _deco.randf_range(0.07, 0.18), "rot": _deco.randf_range(0, PI)})
	for i in 9:
		var p := Vector2(_deco.randf_range(0, VIEW.x), _deco.randf_range(0, VIEW.y))
		var pts := PackedVector2Array([p])
		for k in 4:
			p += Vector2(_deco.randf_range(-22, 22), _deco.randf_range(-22, 22))
			pts.append(p)
		_cracks.append(pts)
	var shirt_cols := [Color("c0563b"), Color("d9b44a"), Color("4f7fb0"), Color("7a5aa0"), Color("dfe3e6"), Color("3e8a5b"), Color("b8743a")]
	for i in 21:
		_crowd.append({"x": 24 + i * 26.5 + _deco.randf_range(-4, 4), "col": shirt_cols[_deco.randi() % shirt_cols.size()],
			"skin": Color(0.85, 0.66, 0.5).darkened(_deco.randf_range(0, 0.45)), "ph": _deco.randf_range(0, TAU),
			"h": _deco.randf_range(0, 5)})


func _draw() -> void:
	# асфальт двора
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color("2b2622"))
	for i in 12:
		draw_rect(Rect2(0, i * 40, VIEW.x, 20), Color(1, 1, 1, 0.012))
	for pts in _cracks:
		draw_polyline(pts, Color(0, 0, 0, 0.35), 1.2)
	# поле
	var grass := Color("4b6a33")
	draw_rect(FIELD.grow(10), Color("3b5228"))
	for y in Pitch.LINES:
		var r := cell_rect(Vector2i(0, y))
		r.size.x = FIELD.size.x
		draw_rect(r, grass.lightened(0.05 if y % 2 == 0 else 0.0))
	for p in _patches:
		draw_set_transform(p["c"], p["rot"], p["r"] / 10.0)
		draw_circle(Vector2.ZERO, 10, Color(0.62, 0.53, 0.33, p["a"]))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# зона удара — тёплая полоса на линиях 3–4
	if show_shot_band:
		var top := cell_rect(Vector2i(0, 3)).position.y
		var bottom := cell_rect(Vector2i(0, 2)).end.y
		draw_rect(Rect2(FIELD.position.x, top, FIELD.size.x, bottom - top), Color(1, 0.85, 0.4, 0.06))
	# разметка
	var line_col := Color(0.96, 0.94, 0.86, 0.55)
	draw_rect(FIELD, line_col, false, 2.0)
	draw_rect(Rect2(150, FIELD.position.y, 300, 70), line_col, false, 2.0)
	draw_arc(Vector2(300, FIELD.position.y + 70), 34, 0.15, PI - 0.15, 16, line_col, 2.0)
	draw_arc(Vector2(300, FIELD.end.y), 46, PI + 0.1, TAU - 0.1, 20, line_col, 2.0)
	# коридоры и линии продвижения — пунктир
	for x in [1, 2]:
		var px: float = FIELD.position.x + x * CW
		_dashed(Vector2(px, FIELD.position.y), Vector2(px, FIELD.end.y), Color(1, 1, 1, 0.22), 1.5, 10, 8)
	for y in [1, 2, 3]:
		var py: float = FIELD.position.y + y * CH
		_dashed(Vector2(FIELD.position.x, py), Vector2(FIELD.end.x, py), Color(1, 1, 1, 0.16), 1.5, 6, 10)
	# номера линий и подпись зоны удара
	var f := ThemeDB.fallback_font
	for y in Pitch.LINES:
		var c := Vector2(FIELD.position.x - 22, cell_center(Vector2i(0, y)).y)
		var inshot := shot_lines.has(y)
		draw_circle(c, 11, Color(1, 0.85, 0.4, 0.85) if inshot else Color(0.9, 0.86, 0.78, 0.55))
		draw_string(f, c + Vector2(-4.5, 5), str(y + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("2a1a0c"))
	var lane_names := ["ЛЕВЫЙ", "ЦЕНТР", "ПРАВЫЙ"]
	for x in 3:
		var cx := FIELD.position.x + (x + 0.5) * CW
		var w := f.get_string_size(lane_names[x], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(f, Vector2(cx - w / 2, FIELD.end.y + 18), lane_names[x], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.45))
	if show_shot_band:
		var sy := (cell_rect(Vector2i(0, 3)).position.y + cell_rect(Vector2i(0, 2)).end.y) / 2.0
		draw_set_transform(Vector2(FIELD.end.x + 26, sy), -PI / 2, Vector2.ONE)
		var label := "ЗОНА УДАРА"
		var lw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(f, Vector2(-lw / 2, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.85, 0.4, 0.8))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# ограда
	var fence := Rect2(14, 40, VIEW.x - 28, VIEW.y - 46)
	var mesh := Color(0.85, 0.8, 0.7, 0.07)
	var step := 14.0
	var xx := fence.position.x
	while xx < fence.end.x:
		draw_line(Vector2(xx, fence.position.y), Vector2(xx + 8, fence.position.y - 8), mesh, 1.0)
		xx += step
	draw_rect(fence, Color(0.1, 0.09, 0.08, 0.9), false, 3.0)
	var post := fence.position.x
	while post <= fence.end.x + 1:
		draw_rect(Rect2(post - 3, fence.position.y - 8, 6, 12), Color("1a1613"))
		post += 64
	if dim_field:
		draw_rect(FIELD, Color(0, 0, 0, 0.25))


func _dashed(a: Vector2, b: Vector2, col: Color, w: float, dash: float, gap: float) -> void:
	var d := a.distance_to(b)
	var dir := (b - a) / d
	var t := 0.0
	while t < d:
		draw_line(a + dir * t, a + dir * minf(t + dash, d), col, w)
		t += dash + gap


func _dashed_on(l: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float, dash: float, gap: float) -> void:
	var d := a.distance_to(b)
	if d < 0.5:
		return
	var dir := (b - a) / d
	var t := 0.0
	while t < d:
		l.draw_line(a + dir * t, a + dir * minf(t + dash, d), col, w)
		t += dash + gap


func _dashed_rect(l: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_dashed_on(l, r.position, Vector2(r.end.x, r.position.y), col, w, 8, 6)
	_dashed_on(l, Vector2(r.end.x, r.position.y), r.end, col, w, 8, 6)
	_dashed_on(l, r.end, Vector2(r.position.x, r.end.y), col, w, 8, 6)
	_dashed_on(l, Vector2(r.position.x, r.end.y), r.position, col, w, 8, 6)


func _draw_crowd(l: Node2D) -> void:
	# зрители за оградой у ворот
	for s in _crowd:
		var jump: float = crowd_jump * (6.0 + 4.0 * sin(s["ph"] + crowd_jump * 9.0))
		var base := Vector2(s["x"], 34 - s["h"] - jump)
		l.draw_rect(Rect2(base + Vector2(-8, -2), Vector2(16, 14)), s["col"].darkened(0.25))
		l.draw_circle(base + Vector2(0, -8), 6.5, s["skin"])
		if crowd_jump > 0.3:
			l.draw_line(base + Vector2(-7, 0), base + Vector2(-12, -14), s["col"].darkened(0.25), 3)
			l.draw_line(base + Vector2(7, 0), base + Vector2(12, -14), s["col"].darkened(0.25), 3)


func _draw_goal(l: Node2D) -> void:
	var r := GOAL_RECT
	var shake := net_shake
	# сетка
	var net := Color(0.95, 0.95, 0.95, 0.35)
	var x := r.position.x
	while x <= r.end.x:
		var bulge := sin((x - r.position.x) / r.size.x * PI) * shake * 8.0
		l.draw_line(Vector2(x, r.position.y - bulge), Vector2(x, r.end.y), net, 1.0)
		x += 10
	var y := r.position.y
	while y <= r.end.y:
		var bulge := shake * 6.0 * (1.0 - (y - r.position.y) / r.size.y)
		l.draw_line(Vector2(r.position.x, y - bulge * 0.3), Vector2(r.end.x, y - bulge * 0.3), net, 1.0)
		y += 8
	# каркас
	var post := Color("f4f1ea")
	l.draw_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.position.y), post, 4.0)
	l.draw_line(Vector2(r.end.x, r.end.y), Vector2(r.end.x, r.position.y), post, 4.0)
	l.draw_line(Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), post, 4.0)
	l.draw_line(Vector2(r.position.x - 2, r.end.y), Vector2(r.end.x + 2, r.end.y), post, 3.0)


func _draw_zones(l: Node2D) -> void:
	var f := ThemeDB.fallback_font
	# давление на удар
	for c in pressure_cells:
		var r := cell_rect(c).grow(-3)
		l.draw_rect(r, Color(0.75, 0.35, 0.95, 0.18))
		l.draw_rect(r, Color(0.8, 0.45, 1.0, 0.9), false, 2.0)
	# опасные зоны сейчас
	for c in danger_now:
		var r := cell_rect(c).grow(-4)
		l.draw_rect(r, Color(0.89, 0.30, 0.22, 0.26))
		l.draw_rect(r, Color(0.95, 0.36, 0.26, 0.95), false, 3.0)
		# штриховка
		var k := 0.0
		while k < r.size.x + r.size.y:
			var a := r.position + Vector2(minf(k, r.size.x), maxf(0.0, k - r.size.x))
			var b := r.position + Vector2(maxf(0.0, k - r.size.y), minf(k, r.size.y))
			l.draw_line(a, b, Color(0.95, 0.36, 0.26, 0.12), 2.0)
			k += 16.0
	# следующий шаг обороны — пунктир
	for c in danger_next:
		var r := cell_rect(c).grow(-10)
		_dashed_rect(l, r, Color(1.0, 0.78, 0.25, 0.95), 2.0)
		l.draw_string(f, r.position + Vector2(5, 15), "след.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.82, 0.35))
	# допустимые цели
	var pulse := 0.5 + 0.5 * sin(_pulse * 5.0)
	for c in targets:
		var r := cell_rect(c).grow(-7)
		var kind: String = targets[c]
		var col := Color(0.53, 0.86, 0.43) if kind != "risk" else Color(0.98, 0.42, 0.3)
		if kind == "protected":
			col = Color(0.5, 0.8, 1.0)
		elif kind == "chance":
			col = Color(1.0, 0.75, 0.3)
		l.draw_rect(r, Color(col, 0.12 + 0.10 * pulse))
		l.draw_rect(r, Color(col, 0.65 + 0.35 * pulse), false, 3.0)
		if c == hover_cell:
			l.draw_rect(r.grow(2), Color(1, 1, 1, 0.9), false, 2.0)
	if hover_cell != Pitch.NONE and targets.is_empty():
		l.draw_rect(cell_rect(hover_cell).grow(-2), Color(1, 1, 1, 0.06))


func _arrow(l: Node2D, pts: PackedVector2Array, col: Color, w: float, dashed: bool) -> void:
	for i in pts.size() - 1:
		if dashed:
			_dashed_on(l, pts[i], pts[i + 1], col, w, 12, 7)
		else:
			l.draw_line(pts[i], pts[i + 1], col, w)
	if pts.size() >= 2:
		var tip := pts[-1]
		var dir := (pts[-1] - pts[-2]).normalized()
		var n := Vector2(-dir.y, dir.x)
		l.draw_colored_polygon(PackedVector2Array([tip, tip - dir * 14 + n * 7, tip - dir * 14 - n * 7]), col)


func _draw_arrows(l: Node2D) -> void:
	var f := ThemeDB.fallback_font
	# маршрут плана (режим B)
	for seg in route:
		var col: Color = Game.C_SAFE if seg.get("ok", true) else Game.C_DANGER
		if seg.get("dim", false):
			col = Color(0.8, 0.8, 0.8, 0.45)
		var a: Vector2 = att_pos(seg["from"]) if seg["from"] is Vector2i else seg["from"]
		var b: Vector2 = att_pos(seg["to"]) if seg["to"] is Vector2i else seg["to"]
		if a.distance_to(b) < 4:
			# действие на месте (финт) — кольцо
			l.draw_arc(a, 24, 0, TAU, 24, col, 3.0)
		else:
			_arrow(l, PackedVector2Array([a, b]), col, 4.0, false)
		var m := (a + b) / 2.0 + Vector2(0, -2)
		if a.distance_to(b) < 4:
			m = a + Vector2(24, -22)
		l.draw_circle(m, 12, Color(0.1, 0.08, 0.06, 0.95))
		l.draw_arc(m, 12, 0, TAU, 20, col, 2.0)
		l.draw_string(f, m + Vector2(-4.5, 5.5), str(seg["num"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
		if seg.has("bad"):
			_cross(l, def_pos(seg["bad"]) + Vector2(-10, 8), Game.C_DANGER)
	# предпросмотр текущего действия
	if not preview.is_empty():
		var pulse := 0.75 + 0.25 * sin(_pulse * 6.0)
		var ok: bool = preview.get("ok", true)
		var col := Color(Game.C_SAFE, pulse) if ok else Color(Game.C_DANGER, pulse)
		var pts := PackedVector2Array([att_pos(preview["from"])])
		for c in preview.get("cells", []):
			pts.append(att_pos(c))
			if not ok and c == preview.get("bad", Pitch.NONE):
				break
		if pts.size() == 1:
			if preview.has("to"):
				pts.append(att_pos(preview["to"]))
		if pts.size() >= 2 and pts[0].distance_to(pts[-1]) > 4:
			_arrow(l, pts, col, 4.0, true)
		else:
			l.draw_arc(pts[0], 26, 0, TAU, 28, col, 3.0)
		if not ok and preview.has("bad"):
			_cross(l, att_pos(preview["bad"]), Game.C_DANGER)
		for c in preview.get("beaten", []):
			l.draw_arc(def_pos(c), 22, 0, TAU, 20, Color(0.5, 0.8, 1.0), 3.0)


func _cross(l: Node2D, p: Vector2, col: Color) -> void:
	l.draw_circle(p, 15, Color(0, 0, 0, 0.6))
	l.draw_line(p + Vector2(-8, -8), p + Vector2(8, 8), col, 4.0)
	l.draw_line(p + Vector2(8, -8), p + Vector2(-8, 8), col, 4.0)


func _draw_light(l: Node2D) -> void:
	# тёплый вечерний свет справа сверху + мягкая виньетка
	var w := VIEW.x
	var h := VIEW.y
	l.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([Color(1.0, 0.62, 0.25, 0.10), Color(1.0, 0.72, 0.35, 0.20), Color(1.0, 0.55, 0.2, 0.06), Color(0.1, 0.05, 0.15, 0.16)]))
	l.draw_rect(Rect2(0, 0, w, 10), Color(0, 0, 0, 0.25))
	l.draw_rect(Rect2(0, h - 10, w, 10), Color(0, 0, 0, 0.25))


# ------------------------------------------------------------------ расстановка
func _attacker_spots(b: Vector2i) -> Array:
	var spots: Array = []
	var cand: Array = []
	if b.y < 3:
		cand = [Vector2i(b.x - 1, b.y + 1), Vector2i(b.x + 1, b.y + 1), Vector2i(b.x, b.y + 1)]
	else:
		cand = [Vector2i(b.x - 1, b.y), Vector2i(b.x + 1, b.y)]
	cand += [Vector2i(b.x - 1, b.y), Vector2i(b.x + 1, b.y), Vector2i(b.x, b.y - 1), Vector2i(b.x - 2, b.y + 1),
		Vector2i(b.x + 2, b.y + 1), Vector2i(b.x - 1, b.y - 1), Vector2i(b.x + 1, b.y - 1), Vector2i(b.x - 2, b.y), Vector2i(b.x + 2, b.y)]
	for c in cand:
		if Pitch.in_bounds(c) and c != b and not spots.has(c):
			spots.append(c)
		if spots.size() >= 4:
			break
	return spots


## Мгновенная расстановка без анимации.
func place_all(ball_cell: Vector2i, danger: Array) -> void:
	carrier = attackers[0]
	carrier.position = att_pos(ball_cell)
	var spots := _attacker_spots(ball_cell)
	for i in range(1, attackers.size()):
		attackers[i].position = att_pos(spots[(i - 1) % spots.size()]) + Vector2(0, 0 if i - 1 < spots.size() else 18)
	_update_carrier()
	ball.position = carrier.position + Vector2(10, 8)
	ball.height = 0
	_place_defenders(danger, 0.0)
	keeper.position = Vector2(300, FIELD.position.y + 6)
	keeper.rotation = 0


func _update_carrier() -> void:
	for a in attackers:
		a.glow = 1.0 if a == carrier else 0.0
		a.queue_redraw()


## Перерасставить атакующих вокруг мяча (носитель уже стоит на месте).
func relayout_attackers(ball_cell: Vector2i, dur: float) -> Tween:
	var spots := _attacker_spots(ball_cell)
	var free: Array = []
	for a in attackers:
		if a != carrier:
			free.append(a)
	var tw := create_tween().set_parallel(true)
	tw.tween_interval(0.01)
	for s in spots:
		if free.is_empty():
			break
		var best: Chip = free[0]
		for a in free:
			if a.position.distance_to(att_pos(s)) < best.position.distance_to(att_pos(s)):
				best = a
		free.erase(best)
		tw.tween_property(best, "position", att_pos(s), dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for a in free:
		tw.tween_property(a, "position", att_pos(Vector2i(ball_cell.x, maxi(0, ball_cell.y - 1))) + Vector2(30, 20), dur)
	return tw


func _place_defenders(cells: Array, dur: float) -> Tween:
	var pts: Array = []
	for c in cells:
		pts.append(def_pos(c))
	return _place_points(pts, dur)


func _place_points(points: Array, dur: float) -> Tween:
	var free: Array = defenders.duplicate()
	var tw: Tween = null
	if dur > 0:
		tw = create_tween().set_parallel(true)
		tw.tween_interval(0.01)
	for target in points:
		var best: Chip = null
		for d in free:
			if d.modulate.a > 0.5 and (best == null or d.position.distance_to(target) < best.position.distance_to(target)):
				best = d
		if best == null:
			best = free[0]
			best.position = Vector2(target.x, FIELD.position.y - 10)
		free.erase(best)
		if tw:
			tw.tween_property(best, "position", target, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.tween_property(best, "modulate:a", 1.0, dur * 0.6)
		else:
			best.position = target
			best.modulate.a = 1.0
	for d in free:
		if tw:
			tw.tween_property(d, "modulate:a", 0.0, dur * 0.6)
		else:
			d.modulate.a = 0.0
	return tw


## Защитники в произвольных точках (режим C: прессингующие стоят вплотную к мячу).
func move_defender_points(points: Array, dur: float) -> Tween:
	return _place_points(points, maxf(dur, 0.02))


func move_defenders(cells: Array, dur: float) -> Tween:
	return _place_defenders(cells, maxf(dur, 0.02))


## Передача: мяч летит по дуге, ближайший партнёр выбегает в клетку-цель.
## Если bad != NONE — мяч перехвачен в клетке bad.
func pass_ball(to_cell: Vector2i, dur: float, bad := Pitch.NONE, lob := false) -> Tween:
	var dest := att_pos(to_cell)
	var receiver: Chip = null
	for a in attackers:
		if a == carrier:
			continue
		if receiver == null or a.position.distance_to(dest) < receiver.position.distance_to(dest):
			receiver = a
	var tw := create_tween().set_parallel(true)
	var end_pos := dest + Vector2(10, 8)
	if bad != Pitch.NONE:
		end_pos = def_pos(bad) + Vector2(-6, 8)
	tw.tween_property(receiver, "position", dest, dur * 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(ball, "position", end_pos, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var peak := 26.0 if lob else 10.0
	tw.tween_method(func(t: float): ball.height = sin(t * PI) * peak, 0.0, 1.0, dur)
	tw.tween_property(ball, "spin", ball.spin + TAU * 1.5, dur)
	if bad == Pitch.NONE:
		tw.chain().tween_callback(func():
			carrier = receiver
			_update_carrier())
	return tw


## Носитель сам ведёт мяч в клетку (обводка) или стоит на месте (финт).
func carry_ball(to_cell: Vector2i, dur: float, bad := Pitch.NONE) -> Tween:
	var dest := att_pos(to_cell)
	var tw := create_tween().set_parallel(true)
	if bad != Pitch.NONE:
		dest = def_pos(bad) + Vector2(-28, 16)
	if carrier.position.distance_to(dest) < 2:
		# финт: короткое движение туда-обратно
		tw.tween_property(carrier, "position", dest + Vector2(14, -4), dur * 0.35)
		tw.chain().tween_property(carrier, "position", dest, dur * 0.35)
		tw.parallel().tween_property(ball, "position", dest + Vector2(-2, 8), dur * 0.35)
		tw.chain().tween_property(ball, "position", dest + Vector2(10, 8), dur * 0.3)
		return tw
	tw.tween_property(carrier, "position", dest, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(ball, "position", dest + Vector2(10, 8), dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(ball, "spin", ball.spin + TAU * 2.0, dur)
	return tw


## Защитник забирает мяч в клетке.
func steal_ball(cell: Vector2i, dur: float) -> Tween:
	var thief: Chip = null
	for d in defenders:
		if d.modulate.a > 0.5 and (thief == null or d.position.distance_to(def_pos(cell)) < thief.position.distance_to(def_pos(cell))):
			thief = d
	var tw := create_tween().set_parallel(true)
	if thief:
		tw.tween_property(thief, "position", ball.position + Vector2(8, -6), dur * 0.6)
		tw.chain().tween_property(ball, "position", ball.position + Vector2(30, -30), dur * 0.5)
	carrier = null
	_update_carrier()
	return tw


## Удар. goal=true — в сетку; false — вратарь отражает.
func shoot_ball(goal: bool, dur: float) -> Tween:
	var from := ball.position
	var side := -1.0 if from.x > 300 else 1.0
	var aim := Vector2(300 + side * 62, GOAL_RECT.position.y + 10)
	var tw := create_tween().set_parallel(true)
	if goal:
		tw.tween_property(ball, "position", aim, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(keeper, "position", keeper.position + Vector2(-side * 50, 0), dur * 0.8)
		tw.tween_property(keeper, "rotation", -side * 0.9, dur * 0.8)
	else:
		var save_pt := Vector2(300 + side * 55, FIELD.position.y + 4)
		tw.tween_property(keeper, "position", save_pt + Vector2(0, 4), dur * 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(keeper, "rotation", side * 0.9, dur * 0.85)
		tw.tween_property(ball, "position", save_pt, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.chain().tween_property(ball, "position", save_pt + Vector2(side * 120, 40), dur * 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(t: float): ball.height = sin(t * PI) * 18.0, 0.0, 1.0, dur)
	return tw


func celebrate(dur: float) -> Tween:
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(v: float): net_shake = v, 1.0, 0.0, dur * 0.8).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): crowd_jump = v, 0.0, 1.0, dur * 0.2)
	tw.chain().tween_method(func(v: float): crowd_jump = v, 1.0, 0.0, dur * 0.8)
	return tw


func crowd_sigh(dur: float) -> Tween:
	var tw := create_tween()
	tw.tween_method(func(v: float): crowd_jump = v, 0.0, 0.25, dur * 0.3)
	tw.tween_method(func(v: float): crowd_jump = v, 0.25, 0.0, dur * 0.7)
	return tw


## Всплывающая надпись над полем.
func float_text(text: String, pos: Vector2, col: Color, fs: int = 20, dur: float = 0.9) -> void:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", fs)
	lb.add_theme_color_override("font_color", col)
	lb.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lb.add_theme_constant_override("outline_size", 6)
	lb.position = pos - Vector2(60, 14)
	lb.size = Vector2(120, 28)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(lb)
	var tw := lb.create_tween().set_parallel(true)
	tw.tween_property(lb, "position:y", lb.position.y - 34, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lb, "modulate:a", 0.0, dur * 0.4).set_delay(dur * 0.6)
	tw.chain().tween_callback(lb.queue_free)


## Большая надпись по центру поля (ГОЛ!, ПЕРЕХВАТ).
func banner(text: String, col: Color, dur: float) -> void:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", 64)
	lb.add_theme_color_override("font_color", col)
	lb.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.03, 0.95))
	lb.add_theme_constant_override("outline_size", 14)
	lb.size = Vector2(VIEW.x, 90)
	lb.position = Vector2(0, VIEW.y / 2 - 45)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.pivot_offset = lb.size / 2
	lb.scale = Vector2(0.4, 0.4)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(lb)
	var tw := lb.create_tween()
	tw.tween_property(lb, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(dur)
	tw.tween_property(lb, "modulate:a", 0.0, 0.3)
	tw.tween_callback(lb.queue_free)
