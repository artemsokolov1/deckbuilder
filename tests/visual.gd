extends SceneTree
## Визуальный прогон под Xvfb: открывает сцены, кликает и сохраняет скриншоты.
## godot --path . --rendering-driver opengl3 -s tests/visual.gd -- out=DIR scenario=a

var out := "user://shots"
var scenario := "menu"
var frame := 0
var steps: Array = []
var step_i := 0
var wait_frames := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
		if a.begins_with("scenario="):
			scenario = a.substr(9)
	DirAccess.make_dir_recursive_absolute(out)
	var script: Script = load("res://tests/visual_scenarios.gd")
	steps = script.new().get_steps(scenario, self)


func _process(_delta: float) -> bool:
	frame += 1
	if wait_frames > 0:
		wait_frames -= 1
		return false
	if step_i >= steps.size():
		return true
	var s: Array = steps[step_i]
	step_i += 1
	match s[0]:
		"wait":
			wait_frames = s[1]
		"shot":
			get_root().get_texture().get_image().save_png("%s/%s.png" % [out, s[1]])
			print("shot ", s[1])
		"call":
			s[1].call()
	return false
