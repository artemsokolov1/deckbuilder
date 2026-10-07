class_name Moves
extends RefCounted
## Общая для режимов A и B геометрия действий, проверка перехвата и формула удара.
## Всё здесь — чистые функции: ничего не меняют и не трогают генераторы случайных чисел.


## Допустимые клетки-цели для карты из позиции from.
static func targets(def: Dictionary, from: Vector2i) -> Array:
	var out: Array = []
	var line := from.y + int(def.get("advance", 0))
	if line >= Pitch.LINES:
		return out
	match String(def.get("lane", "same")):
		"none":
			out.append(from)
		"same":
			out.append(Vector2i(from.x, line))
		"adjacent":
			for dx in [-1, 0, 1]:
				var c := Vector2i(from.x + dx, line)
				if Pitch.in_bounds(c):
					out.append(c)
		"other":
			for x in Pitch.LANES:
				if x != from.x:
					out.append(Vector2i(x, line))
	return out


## Клетки, которые проверяются на перехват (по порядку движения мяча).
static func path_cells(def: Dictionary, from: Vector2i, to: Vector2i) -> Array:
	match String(def.get("path", "target")):
		"none":
			return []
		"run":
			var cells: Array = []
			for y in range(from.y + 1, to.y + 1):
				cells.append(Vector2i(to.x, y))
			return cells
	return [to]


## Разрешение одного действия против текущего состояния обороны.
## Возвращает: intercepted, cell (где перехват), beaten (обыгранные зоны), path, quality (прирост).
static func resolve(def: Dictionary, from: Vector2i, to: Vector2i, danger: Array) -> Dictionary:
	var path := path_cells(def, from, to)
	var protect := int(def.get("protect", 0))
	var beaten: Array = []
	for c in path:
		if danger.has(c):
			if protect > 0:
				protect -= 1
				beaten.append(c)
			else:
				return {"intercepted": true, "cell": c, "beaten": beaten, "path": path, "quality": 0}
	var q := int(def.get("quality", 0)) + int(def.get("quality_beat", 0)) * beaten.size()
	return {"intercepted": false, "cell": Pitch.NONE, "beaten": beaten, "path": path, "quality": q}


## Опасные зоны в коридоре удара от позиции мяча до ворот.
static func pressure_cells(ball: Vector2i, danger: Array) -> Array:
	var out: Array = []
	for c in danger:
		if c.x == ball.x and c.y >= ball.y:
			out.append(c)
	return out


## Детерминированный удар: качество + бонус позиции − давление ≥ порог вратаря.
## shooter_bonus — поправка за удар бьющего футболиста (режим A), в B всегда 0.
static func shot_eval(cfg: Dictionary, quality: int, ball: Vector2i, danger: Array, extra_pressure: int, shooter_bonus: int = 0) -> Dictionary:
	var info := {
		"available": cfg["shot_lines"].has(ball.y),
		"quality": quality,
		"pos_bonus": 0,
		"pressure": 0,
		"pressure_cells": [],
		"extra_pressure": extra_pressure,
		"shooter_bonus": shooter_bonus,
		"value": 0,
		"threshold": int(cfg["keeper_threshold"]),
		"goal": false,
	}
	if not info["available"]:
		return info
	var pc := pressure_cells(ball, danger)
	info["pos_bonus"] = int(cfg["position_bonus"][ball.y][ball.x])
	info["pressure_cells"] = pc
	info["pressure"] = pc.size() + extra_pressure
	info["value"] = quality + info["pos_bonus"] + shooter_bonus - info["pressure"]
	info["goal"] = info["value"] >= info["threshold"]
	return info


static func shot_breakdown(info: Dictionary) -> String:
	var sb := ""
	if info.has("shooter_name"):
		sb = " %s удар %s (%s)" % ["+" if info["shooter_bonus"] >= 0 else "−", absi(info["shooter_bonus"]), info["shooter_name"]]
	var s := "качество %d + позиция %d%s − давление %d = [b]%d[/b] против порога вратаря %d" % [
		info["quality"], info["pos_bonus"], sb, info["pressure"], info["value"], info["threshold"]]
	return s
