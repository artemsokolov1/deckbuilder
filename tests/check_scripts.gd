extends SceneTree
## Загружает все скрипты и сцены проекта — ловит ошибки разбора.
func _initialize() -> void:
	var bad := 0
	for dir in ["res://scripts/core", "res://scripts/rules", "res://scripts/view", "res://scenes"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd") or f.ends_with(".tscn"):
				var r = load(dir + "/" + f)
				if r == null:
					bad += 1
					print("FAILED: ", dir + "/" + f)
				elif r is Script and not r.can_instantiate():
					bad += 1
					print("CANNOT INSTANTIATE: ", dir + "/" + f)
	print("check done, bad=", bad)
	quit(bad)
