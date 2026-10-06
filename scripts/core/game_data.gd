class_name GameData
extends RefCounted
## Загружает data/game_data.json один раз и отдаёт его разделы.
## Клетки [коридор, линия] превращаются в Vector2i.

const PATH := "res://data/game_data.json"

static var _cache: Dictionary = {}


static func get_data() -> Dictionary:
	if _cache.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f == null:
			push_error("Не найден файл данных: %s" % PATH)
			return {}
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("Ошибка разбора %s" % PATH)
			return {}
		_cache = _convert(parsed)
	return _cache


static func mode(id: String) -> Dictionary:
	return get_data()["modes"][id]


static func cards(id: String) -> Dictionary:
	return get_data()["cards"][id]


static func card(mode_id: String, card_id: String) -> Dictionary:
	return get_data()["cards"][mode_id][card_id]


static func defense(mode_id: String) -> Dictionary:
	return get_data()["defense"][mode_id]


static func series() -> Dictionary:
	return get_data()["series"]


## Для тестов баланса: позволяет временно подменить значения.
static func override(path: Array, value: Variant) -> void:
	var d: Variant = get_data()
	for i in path.size() - 1:
		d = d[path[i]]
	d[path[-1]] = value


static func reload() -> void:
	_cache = {}
	get_data()


static func _convert(d: Dictionary) -> Dictionary:
	# Числа из JSON приходят как float — приводим к int там, где это клетки и счётчики.
	var out: Dictionary = _ints(d)
	for m in out["modes"]:
		var md: Dictionary = out["modes"][m]
		if md.has("start"):
			md["start"] = Vector2i(md["start"][0], md["start"][1])
	for m in out["defense"]:
		for t in out["defense"][m]:
			var tpl: Dictionary = out["defense"][m][t]
			var states: Array = []
			for st in tpl["states"]:
				var cells: Array = []
				for c in st:
					cells.append(Vector2i(c[0], c[1]))
				states.append(cells)
			tpl["states"] = states
	return out


static func _ints(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			if is_equal_approx(v, roundf(v)):
				return int(v)
			return v
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[k] = _ints(v[k])
			return d
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(_ints(x))
			return a
	return v
