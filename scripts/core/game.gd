extends Node
## Автозагрузка Game: настройки, текущая серия, переходы между сценами,
## локальные оценки и история. Никакой сетевой телеметрии.

const SETTINGS_PATH := "user://settings.cfg"
const RATINGS_PATH := "user://ratings.cfg"
const HISTORY_PATH := "user://history.cfg"

const MENU_SCENE := "res://scenes/main_menu.tscn"
const RESULTS_SCENE := "res://scenes/results.tscn"
const MODE_SCENES := {
	"a": "res://scenes/game_a.tscn",
	"b": "res://scenes/game_b.tscn",
	"c": "res://scenes/game_c.tscn",
}
const MODE_IDS := ["a", "b", "c"]

# Палитра — общая для всех экранов.
const C_BG := Color("17120f")
const C_PANEL := Color(0.13, 0.10, 0.08, 0.94)
const C_PANEL_LIGHT := Color(0.20, 0.16, 0.12, 0.96)
const C_BORDER := Color("6b5236")
const C_TEXT := Color("f3e9d8")
const C_MUTED := Color("b9a68d")
const C_ACCENT := Color("f2a33a")
const C_DANGER := Color("e4553f")
const C_SAFE := Color("86d46f")
const C_WARN := Color("f0c04a")
const C_DEF := Color("3e6db0")
const C_INFO := Color("7cc3e8")

var settings := {"volume": 0.8, "fast": false, "shake": true}
var tutorial_seen := {"a": false, "b": false, "c": false}

# Текущая серия
var mode := "a"
var series_seed := 0
var want_tutorial := false
var attacks: Array = []  # {outcome, reason, template}
var series_start_ms := 0
var series_end_ms := 0

var theme: Theme


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	theme = _build_theme()
	apply_volume()


# ------------------------------------------------------------------ серия
func start_mode(mode_id: String, p_seed: int = -1, tutorial: bool = false) -> void:
	mode = mode_id
	series_seed = p_seed if p_seed >= 0 else Seeds.new_series_seed()
	want_tutorial = tutorial or not tutorial_seen.get(mode_id, false)
	attacks = []
	series_start_ms = 0
	series_end_ms = 0
	get_tree().change_scene_to_file(MODE_SCENES[mode_id])


func begin_series_clock() -> void:
	attacks = []
	series_start_ms = Time.get_ticks_msec()


func record_attack(outcome: String, reason: String, template: String) -> void:
	attacks.append({"outcome": outcome, "reason": reason, "template": template})


func goals() -> int:
	return count_outcome("goal")


func count_outcome(o: String) -> int:
	var n := 0
	for a in attacks:
		if a["outcome"] == o:
			n += 1
	return n


func finish_series() -> void:
	series_end_ms = Time.get_ticks_msec()
	_save_history()
	get_tree().change_scene_to_file(RESULTS_SCENE)


func duration_sec() -> float:
	var end := series_end_ms if series_end_ms > 0 else Time.get_ticks_msec()
	return maxf(0.0, (end - series_start_ms) / 1000.0)


func mark_tutorial_seen(mode_id: String) -> void:
	tutorial_seen[mode_id] = true
	save_settings()


func go_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func mode_title(mode_id: String) -> String:
	return GameData.mode(mode_id)["title"]


## Множитель длительности анимаций.
func speed() -> float:
	return 0.45 if settings["fast"] else 1.0


# ------------------------------------------------------------------ настройки
func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	for k in settings:
		settings[k] = cf.get_value("settings", k, settings[k])
	for m in tutorial_seen:
		tutorial_seen[m] = cf.get_value("tutorial", m, false)


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings:
		cf.set_value("settings", k, settings[k])
	for m in tutorial_seen:
		cf.set_value("tutorial", m, tutorial_seen[m])
	cf.save(SETTINGS_PATH)


func apply_volume() -> void:
	var v: float = settings["volume"]
	AudioServer.set_bus_mute(0, v <= 0.001)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.001)))


# ------------------------------------------------------------------ оценки и история
func save_rating(clarity: int, football: int, replay: int, comment: String = "") -> void:
	var cf := ConfigFile.new()
	cf.load(RATINGS_PATH)
	var n := 0
	while cf.has_section("r%d" % n):
		n += 1
	var sec := "r%d" % n
	cf.set_value(sec, "mode", mode)
	cf.set_value(sec, "seed", series_seed)
	cf.set_value(sec, "goals", goals())
	cf.set_value(sec, "clarity", clarity)
	cf.set_value(sec, "football", football)
	cf.set_value(sec, "replay", replay)
	cf.set_value(sec, "comment", comment)
	cf.set_value(sec, "time", Time.get_datetime_string_from_system())
	cf.save(RATINGS_PATH)


func _save_history() -> void:
	var cf := ConfigFile.new()
	cf.load(HISTORY_PATH)
	var n := 0
	while cf.has_section("s%d" % n):
		n += 1
	var sec := "s%d" % n
	cf.set_value(sec, "mode", mode)
	cf.set_value(sec, "seed", series_seed)
	cf.set_value(sec, "goals", goals())
	cf.set_value(sec, "duration", duration_sec())
	cf.set_value(sec, "time", Time.get_datetime_string_from_system())
	cf.save(HISTORY_PATH)


## Сводка по режиму для меню и экрана результатов.
func mode_summary(mode_id: String) -> Dictionary:
	var out := {"series": 0, "wins": 0, "goals": 0, "ratings": 0, "clarity": 0.0, "football": 0.0, "replay": 0.0}
	var need: int = GameData.series()["goals_to_win"]
	var cf := ConfigFile.new()
	if cf.load(HISTORY_PATH) == OK:
		for sec in cf.get_sections():
			if cf.get_value(sec, "mode", "") == mode_id:
				out["series"] += 1
				var g: int = cf.get_value(sec, "goals", 0)
				out["goals"] += g
				if g >= need:
					out["wins"] += 1
	var rf := ConfigFile.new()
	if rf.load(RATINGS_PATH) == OK:
		for sec in rf.get_sections():
			if rf.get_value(sec, "mode", "") == mode_id:
				out["ratings"] += 1
				for k in ["clarity", "football", "replay"]:
					out[k] += float(rf.get_value(sec, k, 0))
	if out["ratings"] > 0:
		for k in ["clarity", "football", "replay"]:
			out[k] /= out["ratings"]
	return out


# ------------------------------------------------------------------ тема
func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 17
	t.set_color("font_color", "Label", C_TEXT)
	t.set_color("default_color", "RichTextLabel", C_TEXT)
	t.set_font_size("normal_font_size", "RichTextLabel", 16)
	t.set_font_size("bold_font_size", "RichTextLabel", 16)

	var btn := _box(Color("3a2c1f"), C_BORDER, 8, 2)
	var btn_hover := _box(Color("4d3a27"), C_ACCENT, 8, 2)
	var btn_pressed := _box(Color("2a2017"), C_ACCENT, 8, 2)
	var btn_disabled := _box(Color(0.18, 0.15, 0.12, 0.8), Color(0.3, 0.26, 0.22), 8, 2)
	var btn_focus := _box(Color(0, 0, 0, 0), C_ACCENT.darkened(0.2), 8, 1)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", btn_hover)
	t.set_stylebox("pressed", "Button", btn_pressed)
	t.set_stylebox("disabled", "Button", btn_disabled)
	t.set_stylebox("focus", "Button", btn_focus)
	t.set_color("font_color", "Button", C_TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", C_ACCENT)
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.5, 0.45))

	t.set_stylebox("panel", "Panel", _box(C_PANEL, C_BORDER, 10, 2))
	t.set_stylebox("panel", "PanelContainer", _box(C_PANEL, C_BORDER, 10, 2))
	t.set_color("font_color", "CheckBox", C_TEXT)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	t.set_stylebox("tooltip", "TooltipPanel", _box(Color("231b14"), C_ACCENT, 6, 1))
	t.set_color("font_color", "TooltipLabel", C_TEXT)
	return t


func _box(bg: Color, border: Color, radius: int, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


func box(bg: Color, border: Color, radius: int = 10, bw: int = 2) -> StyleBoxFlat:
	return _box(bg, border, radius, bw)
