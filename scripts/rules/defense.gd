class_name Defense
extends RefCounted
## Заранее заданные планы обороны для режимов A и B.
## План = список состояний; состояние = список опасных клеток.
## Зеркальный вариант меняет левый и правый коридоры местами.


static func build(mode_id: String, template_id: String, mirrored: bool) -> Dictionary:
	var tpl: Dictionary = GameData.defense(mode_id)[template_id]
	var states: Array = []
	for st in tpl["states"]:
		var cells: Array = []
		for c in st:
			cells.append(Vector2i(Pitch.LANES - 1 - c.x, c.y) if mirrored else c)
		states.append(cells)
	return {
		"id": template_id,
		"name": tpl["name"],
		"hint": tpl["hint"],
		"extra_pressure": int(tpl.get("extra_pressure", 0)),
		"mirrored": mirrored,
		"states": states,
	}


## Состояние плана на шаге step (план зациклен, но за атаку его длины хватает).
static func state_at(plan: Dictionary, step: int) -> Array:
	var states: Array = plan["states"]
	return states[step % states.size()]


## Выбор шаблона обороны для атаки: первые три атаки — все три шаблона
## в перемешанном порядке, далее — случайно. Всё от seed серии.
static func pick_for_attack(mode_id: String, series_seed: int, attack_idx: int) -> Dictionary:
	var order: Array = GameData.mode(mode_id)["template_order"].duplicate()
	var order_rng := Seeds.rng_for(series_seed, mode_id + "_order")
	Seeds.shuffle(order, order_rng)
	var rng := Seeds.rng_for(series_seed, mode_id + "_defense", attack_idx)
	var template_id: String
	if attack_idx < order.size():
		template_id = order[attack_idx]
	else:
		template_id = order[rng.randi_range(0, order.size() - 1)]
	var mirrored := rng.randi_range(0, 1) == 1
	return build(mode_id, template_id, mirrored)
