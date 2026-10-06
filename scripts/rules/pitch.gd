class_name Pitch
extends RefCounted
## Геометрия поля в терминах правил: 3 коридора × 4 линии.
## Vector2i(x = коридор 0..2, y = линия 0..3). Линия 3 — у ворот.

const LANES := 3
const LINES := 4
const LANE_NAMES := ["левый коридор", "центр", "правый коридор"]
const LANE_SHORT := ["слева", "по центру", "справа"]
const NONE := Vector2i(-1, -1)


static func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < LANES and c.y >= 0 and c.y < LINES


static func cell_name(c: Vector2i) -> String:
	if not in_bounds(c):
		return "—"
	return "%s, линия %d" % [LANE_NAMES[c.x], c.y + 1]


static func cells_text(cells: Array) -> String:
	var parts: PackedStringArray = []
	for c in cells:
		parts.append(cell_name(c))
	return "; ".join(parts)
