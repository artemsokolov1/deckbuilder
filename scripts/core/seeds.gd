class_name Seeds
extends RefCounted
## Воспроизводимая игровая случайность. Каждой атаке — свой генератор,
## выведенный из seed серии, поэтому порядок нажатий не влияет на другие атаки.
## Декоративная случайность (зрители, трава, частицы) живёт отдельно во view.


static func derive(series_seed: int, tag: String, index: int = 0) -> int:
	var h := ("%d|%s|%d" % [series_seed, tag, index]).hash()
	# Перемешиваем ещё раз, чтобы соседние индексы давали непохожие seed.
	return int(("%d#%d" % [h, index * 7919 + 17]).hash())


static func rng_for(series_seed: int, tag: String, index: int = 0) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = derive(series_seed, tag, index)
	return rng


static func shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t


static func deck_from_counts(counts: Dictionary) -> Array:
	var keys := counts.keys()
	keys.sort()
	var out: Array = []
	for k in keys:
		for i in int(counts[k]):
			out.append(k)
	return out


static func new_series_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(100000, 999999)
