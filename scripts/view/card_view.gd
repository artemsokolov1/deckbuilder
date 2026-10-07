class_name CardView
extends Control
## Крупная карта: стоимость, название, значок, короткое описание.
## Наведение — подъём и подсветка; нажатие — сигнал pressed. Состояние правил карта не меняет.

signal pressed(card: CardView)
signal hovered(card: CardView, on: bool)

const SIZE := Vector2(150, 176)
const LIFT := 18.0

var card_id := ""
var hand_idx := -1
var title := ""
var cost := -1  # -1 — без стоимости
var desc := ""
var tag := ""  # короткая пометка (например, «в слоте 1»)
var selected := false:
	set(v):
		selected = v
		_update_lift()
		queue_redraw()
var disabled := false:
	set(v):
		disabled = v
		modulate = Color(0.62, 0.6, 0.58) if v else Color.WHITE
		queue_redraw()
var marked := false:
	set(v):
		marked = v
		queue_redraw()
var used := false:
	set(v):
		used = v
		queue_redraw()

var base_y := 0.0
var _hover := false
var _title_lb: Label
var _desc_lb: Label
var _skill_lb: Label

# Карта футболиста (режим A)
var player: Dictionary = {}
var defense_mode := false  # в защите главное — отбор
var mastery := 0
var mastery_stat := ""

const POS_COLORS := {"ЗЩ": Color("7fa8dc"), "ПЗ": Color("8fd27a"), "НП": Color("f2a33a")}
const POS_NAMES := {"ЗЩ": "защитник", "ПЗ": "полузащитник", "НП": "нападающий"}
const STAT_NAMES := [["pass", "Пас"], ["drib", "Дриблинг"], ["shot", "Удар"], ["tackle", "Отбор"]]
var _tw: Tween

const ACCENTS := {
	"short_pass": Color("f2a33a"), "pass": Color("f2a33a"),
	"switch": Color("7cc3e8"), "switch_c": Color("7cc3e8"),
	"dribble": Color("b48ce6"), "sprint": Color("e67f5c"),
	"through": Color("e6c34a"), "risky": Color("e4553f"),
	"one_two": Color("86d46f"), "shield": Color("86d46f"),
	"feint": Color("e88fb8"), "pause": Color("a9b4bd"),
}


func setup(id: String, def: Dictionary, idx: int) -> void:
	card_id = id
	hand_idx = idx
	title = def["name"]
	cost = int(def.get("cost", -1))
	desc = def["text"]
	if _title_lb:
		_title_lb.text = title
		_desc_lb.text = desc
		_fit_title()
	queue_redraw()


## Карта футболиста. def — RulesA.card_def(id) (умение с мастерством).
## defense=true — карта в руке защиты: подчёркнут отбор и линии, где игрок может встать.
func setup_player(id: String, def: Dictionary, idx: int, defense: bool, lines_text: String = "") -> void:
	card_id = id
	hand_idx = idx
	player = def["player"]
	defense_mode = defense
	mastery = int(def.get("mastery", 0))
	mastery_stat = def.get("mastery_stat", "")
	title = player["name"]
	cost = -1 if defense else int(def["cost"])
	if defense:
		desc = "Отбор %d ≥ дриблинга — мяч ваш.\nСтоит на %s %s." % [player["tackle"], "линиях" if "–" in lines_text else "линии", lines_text]
	else:
		desc = def["short"] + ("\nМастерство +%d" % mastery if mastery > 0 else "")
	if _title_lb:
		_apply_player_layout()
	queue_redraw()


func _apply_player_layout() -> void:
	_title_lb.position = Vector2(40, 4)
	_title_lb.size = Vector2(SIZE.x - 78, 24)
	_title_lb.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title_lb.text = title
	var f := ThemeDB.fallback_font
	var fs := 16
	while fs > 11 and f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > _title_lb.size.x:
		fs -= 1
	_title_lb.add_theme_font_size_override("font_size", fs)
	if _skill_lb == null:
		_skill_lb = Label.new()
		_skill_lb.add_theme_font_size_override("font_size", 14)
		_skill_lb.add_theme_color_override("font_color", Color("2b1d10"))
		_skill_lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_skill_lb)
	_skill_lb.position = Vector2(9, 100)
	_skill_lb.size = Vector2(SIZE.x - 18, 20)
	_skill_lb.text = "В защите" if defense_mode else GameData.card("a", player["action"])["name"]
	_desc_lb.position = Vector2(9, 120)
	_desc_lb.size = Vector2(SIZE.x - 18, 52)
	_desc_lb.text = desc


func _fit_title() -> void:
	# Длинные названия («Разрезающий пас») уменьшаем, чтобы слово не рвалось.
	var f := ThemeDB.fallback_font
	var fs := 16
	for word in title.split(" "):
		while fs > 11 and f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > _title_lb.size.x - 2:
			fs -= 1
	_title_lb.add_theme_font_size_override("font_size", fs)


func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	pivot_offset = Vector2(SIZE.x / 2, SIZE.y)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _ready() -> void:
	_title_lb = Label.new()
	_title_lb.position = Vector2(10, 8)
	_title_lb.size = Vector2(SIZE.x - (52 if cost >= 0 else 20), 40)
	_title_lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_lb.add_theme_font_size_override("font_size", 16)
	_title_lb.add_theme_color_override("font_color", Color("2b1d10"))
	_title_lb.add_theme_constant_override("line_spacing", -4)
	_title_lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_lb.text = title
	add_child(_title_lb)
	_fit_title()
	_desc_lb = Label.new()
	_desc_lb.position = Vector2(9, 92)
	_desc_lb.size = Vector2(SIZE.x - 18, 80)
	_desc_lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_lb.add_theme_font_size_override("font_size", 12)
	_desc_lb.add_theme_color_override("font_color", Color("3a2b1c"))
	_desc_lb.add_theme_constant_override("line_spacing", -3)
	_desc_lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc_lb.text = desc
	add_child(_desc_lb)
	if not player.is_empty():
		_apply_player_layout()
	mouse_entered.connect(_on_enter)
	mouse_exited.connect(_on_exit)


func _on_enter() -> void:
	_hover = true
	_update_lift()
	Sfx.play("hover")
	hovered.emit(self, true)
	queue_redraw()


func _on_exit() -> void:
	_hover = false
	_update_lift()
	hovered.emit(self, false)
	queue_redraw()


func _update_lift() -> void:
	if not is_inside_tree():
		return
	var target_y := base_y
	var sc := 1.0
	if selected:
		target_y = base_y - LIFT - 8
		sc = 1.06
	elif _hover:
		target_y = base_y - LIFT
		sc = 1.04
	if _tw and _tw.is_valid():
		_tw.kill()
	_tw = create_tween().set_parallel(true)
	_tw.tween_property(self, "position:y", target_y, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tw.tween_property(self, "scale", Vector2(sc, sc), 0.12)
	z_index = 10 if (selected or _hover) else 0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		pressed.emit(self)


func _draw() -> void:
	if not player.is_empty():
		_draw_player()
		return
	var r := Rect2(Vector2.ZERO, SIZE)
	var accent: Color = ACCENTS.get(card_id, Game.C_ACCENT)
	# тень
	draw_style_box(Game.box(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 12, 0), Rect2(Vector2(-4, 6), SIZE))
	# тело
	var paper := Color("efe3c9") if not used else Color("8e877a")
	var border := accent.darkened(0.35)
	if selected:
		border = Color("fff6c8")
	elif marked:
		border = Game.C_INFO
	var bw := 4 if (selected or marked) else 2
	draw_style_box(Game.box(paper, border, 12, bw), r)
	# цветная шапка
	draw_style_box(Game.box(accent.lightened(0.15), Color(0, 0, 0, 0), 10, 0), Rect2(4, 4, SIZE.x - 8, 44))
	# стоимость
	if cost >= 0:
		var c := Vector2(SIZE.x - 22, 24)
		draw_circle(c, 16, Color("2b1d10"))
		draw_circle(c, 13.5, Color("f7d27a"))
		var f := ThemeDB.fallback_font
		draw_string(f, c + Vector2(-5, 7), str(cost), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("2b1d10"))
	# значок
	_draw_icon(Rect2(10, 50, SIZE.x - 20, 40), accent.darkened(0.25))
	if marked:
		draw_style_box(Game.box(Game.C_INFO, Color(0, 0, 0, 0), 6, 0), Rect2(8, 52, 74, 20))
		draw_string(ThemeDB.fallback_font, Vector2(14, 67), "на обмен", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("10202a"))
	if tag != "":
		var f2 := ThemeDB.fallback_font
		var tw := f2.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_style_box(Game.box(Color("2b1d10"), Color(0, 0, 0, 0), 6, 0), Rect2(SIZE.x - tw - 22, 50, tw + 14, 20))
		draw_string(f2, Vector2(SIZE.x - tw - 15, 65), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("f7d27a"))
	if _hover and not selected:
		draw_style_box(Game.box(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.5), 12, 2), r)


func _draw_icon(r: Rect2, col: Color) -> void:
	var c := r.get_center()
	var w := 3.0
	match card_id:
		"short_pass", "pass":
			_arrow(c + Vector2(-26, 14), c + Vector2(22, -12), col, w)
			draw_circle(c + Vector2(-30, 16), 5, col)
		"switch", "switch_c":
			_arrow(c + Vector2(-34, 0), c + Vector2(34, 0), col, w)
			_arrow(c + Vector2(34, 0), c + Vector2(-34, 0), col, w)
		"dribble":
			var pts := PackedVector2Array([c + Vector2(-30, 16), c + Vector2(-14, 4), c + Vector2(-24, -4), c + Vector2(-4, -14), c + Vector2(20, -16)])
			draw_polyline(pts, col, w)
			_arrow(c + Vector2(10, -16), c + Vector2(26, -16), col, w)
			draw_circle(c + Vector2(4, 4), 7, Color(col, 0.35))
		"through":
			_arrow(c + Vector2(0, 18), c + Vector2(0, -18), col, w)
			draw_polyline(PackedVector2Array([c + Vector2(-14, 2), c + Vector2(0, -10), c + Vector2(14, 2)]), col, w)
			draw_circle(c + Vector2(-26, -4), 6, Color(col, 0.35))
			draw_circle(c + Vector2(26, -4), 6, Color(col, 0.35))
		"one_two":
			_arrow(c + Vector2(-28, 16), c + Vector2(10, 6), col, w)
			_arrow(c + Vector2(10, 6), c + Vector2(-6, -16), col, w)
			draw_circle(c + Vector2(16, 6), 5, col)
		"feint":
			draw_arc(c + Vector2(-8, 0), 14, PI * 0.2, PI * 1.6, 18, col, w)
			_arrow(c + Vector2(4, -14), c + Vector2(20, -14), col, w)
		"sprint":
			for k in 3:
				draw_polyline(PackedVector2Array([c + Vector2(-14, 14 - k * 12), c + Vector2(0, 4 - k * 12), c + Vector2(14, 14 - k * 12)]), col, w)
		"shield":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-16, -16), c + Vector2(16, -16), c + Vector2(14, 4), c + Vector2(0, 18), c + Vector2(-14, 4)]), Color(col, 0.6))
		"pause":
			draw_rect(Rect2(c + Vector2(-12, -14), Vector2(8, 28)), col)
			draw_rect(Rect2(c + Vector2(4, -14), Vector2(8, 28)), col)
		"risky":
			_arrow(c + Vector2(-30, 16), c + Vector2(26, -16), col, w)
			draw_string(ThemeDB.fallback_font, c + Vector2(10, 16), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, col)


func _arrow(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	draw_line(a, b, col, w)
	var dir := (b - a).normalized()
	var n := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([b + dir * 4, b - dir * 9 + n * 6, b - dir * 9 - n * 6]), col)


func _draw_player() -> void:
	var r := Rect2(Vector2.ZERO, SIZE)
	var f := ThemeDB.fallback_font
	var pc: Color = POS_COLORS.get(player["pos"], Game.C_ACCENT)
	draw_style_box(Game.box(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 12, 0), Rect2(Vector2(-4, 6), SIZE))
	var paper := Color("efe3c9") if not used else Color("8e877a")
	var border := pc.darkened(0.4)
	if selected:
		border = Color("fff6c8")
	elif marked:
		border = Game.C_INFO
	draw_style_box(Game.box(paper, border, 12, 4 if (selected or marked) else 2), r)
	# шапка: номер, фамилия, позиция
	draw_style_box(Game.box(pc.lightened(0.1), Color(0, 0, 0, 0), 10, 0), Rect2(4, 4, SIZE.x - 8, 42))
	var nc := Vector2(22, 24)
	draw_circle(nc, 15, Color("fff1d6"))
	draw_circle(nc, 12.5, Color("f2a33a"))
	var num := str(player["num"])
	var nw := f.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string(f, nc + Vector2(-nw / 2.0, 5.5), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("2a1a0c"))
	draw_string(f, Vector2(41, 41), POS_NAMES.get(player["pos"], player["pos"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("2b1d10").lightened(0.15))
	if cost >= 0:
		var c := Vector2(SIZE.x - 20, 22)
		draw_circle(c, 14, Color("2b1d10"))
		draw_circle(c, 11.5, Color("f7d27a"))
		draw_string(f, c + Vector2(-4.5, 6), str(cost), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("2b1d10"))
	elif defense_mode:
		var c2 := Vector2(SIZE.x - 22, 24)
		draw_colored_polygon(PackedVector2Array([c2 + Vector2(-13, -14), c2 + Vector2(13, -14), c2 + Vector2(12, 4), c2 + Vector2(0, 15), c2 + Vector2(-12, 4)]), Color("2b1d10"))
		draw_string(f, c2 + Vector2(-5, 6), str(player["tackle"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("f7d27a"))
	# характеристики 2×2
	for i in 4:
		var key: String = STAT_NAMES[i][0]
		var col := i % 2
		var row := i / 2
		var p := Vector2(9 + col * 68, 52 + row * 22)
		var hot := (defense_mode and key == "tackle") or (not defense_mode and (key == mastery_stat or key == "shot"))
		var ink := Color("2b1d10") if hot else Color("2b1d10").lerp(paper, 0.45)
		draw_string(f, p + Vector2(0, 11), STAT_NAMES[i][1] if STAT_NAMES[i][1].length() <= 5 else STAT_NAMES[i][1].substr(0, 4) + ".", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)
		var v := int(player[key])
		for k in 5:
			var dc := p + Vector2(4 + k * 9, 18)
			draw_circle(dc, 3.2, (pc.darkened(0.35) if hot else ink) if k < v else Color(0, 0, 0, 0.12))
	draw_line(Vector2(8, 97), Vector2(SIZE.x - 8, 97), Color(0, 0, 0, 0.15), 1)
	if marked:
		draw_style_box(Game.box(Game.C_INFO, Color(0, 0, 0, 0), 6, 0), Rect2(SIZE.x - 82, 48, 74, 20))
		draw_string(f, Vector2(SIZE.x - 76, 63), "на обмен", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("10202a"))
	if tag != "":
		var tw := f.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_style_box(Game.box(Color("2b1d10"), Color(0, 0, 0, 0), 6, 0), Rect2(SIZE.x - tw - 22, 100, tw + 14, 20))
		draw_string(f, Vector2(SIZE.x - tw - 15, 115), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("f7d27a"))
	if _hover and not selected:
		draw_style_box(Game.box(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.5), 12, 2), r)
