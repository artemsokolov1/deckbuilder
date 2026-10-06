extends Node
## Автозагрузка Sfx: все звуки синтезируются при запуске (никаких внешних файлов).
## Различимые звуки: пас, перехват, удар, гол, сейв, свисток, клик, ошибка, события режима C.

const RATE := 22050
const VOICES := 8

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _noise := RandomNumberGenerator.new()  # декоративная случайность, не игровая


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_noise.seed = 4242
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_streams["click"] = _make(0.06, _click)
	_streams["hover"] = _make(0.035, _hover)
	_streams["pass"] = _make(0.16, _pass)
	_streams["intercept"] = _make(0.42, _intercept)
	_streams["shot"] = _make(0.28, _shot)
	_streams["goal"] = _make(1.7, _goal)
	_streams["save"] = _make(0.5, _save)
	_streams["whistle"] = _make(0.45, _whistle)
	_streams["error"] = _make(0.14, _error)
	_streams["safe"] = _make(0.18, _safe)
	_streams["pressure"] = _make(0.3, _pressure)
	_streams["card"] = _make(0.09, _card)
	_streams["lost"] = _make(0.5, _lost)


func play(name: String, pitch: float = 1.0) -> void:
	if not _streams.has(name):
		return
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[name]
	p.pitch_scale = pitch
	p.play()


func _make(dur: float, fn: Callable) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var state := {"lp": 0.0, "lp2": 0.0}
	for i in n:
		var t := float(i) / RATE
		var v: float = clampf(fn.call(t, dur, state), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


func _rnd() -> float:
	return _noise.randf() * 2.0 - 1.0


func _env(t: float, attack: float, decay: float) -> float:
	if t < attack:
		return t / attack
	return exp(-(t - attack) / decay)


func _click(t: float, _d: float, _s: Dictionary) -> float:
	return sin(TAU * 880.0 * t) * _env(t, 0.002, 0.015) * 0.5


func _hover(t: float, _d: float, _s: Dictionary) -> float:
	return sin(TAU * 1320.0 * t) * _env(t, 0.002, 0.008) * 0.18


func _card(t: float, _d: float, s: Dictionary) -> float:
	s["lp"] = lerpf(s["lp"], _rnd(), 0.25)
	return s["lp"] * _env(t, 0.01, 0.03) * 0.6


func _pass(t: float, _d: float, s: Dictionary) -> float:
	# глухой удар по мячу: низкий тон + короткий щелчок
	s["lp"] = lerpf(s["lp"], _rnd(), 0.5)
	var body := sin(TAU * (190.0 - 60.0 * t / 0.16) * t) * _env(t, 0.002, 0.05)
	return body * 0.8 + s["lp"] * _env(t, 0.001, 0.01) * 0.5


func _shot(t: float, _d: float, s: Dictionary) -> float:
	s["lp"] = lerpf(s["lp"], _rnd(), 0.35)
	var body := sin(TAU * (120.0 - 50.0 * t) * t) * _env(t, 0.002, 0.08)
	var whoosh: float = s["lp"] * _env(t, 0.03, 0.12) * 0.45
	return body * 0.95 + whoosh


func _intercept(t: float, _d: float, _s: Dictionary) -> float:
	# резкий нисходящий «бззт»
	var f := 330.0 - 180.0 * t / 0.42
	var sq := 1.0 if fmod(t * f, 1.0) < 0.5 else -1.0
	return sq * _env(t, 0.005, 0.16) * 0.32 + _rnd() * _env(t, 0.001, 0.03) * 0.3


func _save(t: float, _d: float, s: Dictionary) -> float:
	s["lp"] = lerpf(s["lp"], _rnd(), 0.06)
	var thud := sin(TAU * 85.0 * t) * _env(t, 0.002, 0.07)
	var ooh: float = s["lp"] * 2.2 * _env(t, 0.12, 0.2) * (1.0 if t > 0.08 else 0.0)
	return thud * 0.8 + ooh * 0.5


func _goal(t: float, _d: float, s: Dictionary) -> float:
	# шум толпы с нарастанием + два тона гудка + сетка
	s["lp"] = lerpf(s["lp"], _rnd(), 0.12)
	s["lp2"] = lerpf(s["lp2"], s["lp"], 0.3)
	var crowd: float = s["lp2"] * 2.4 * minf(1.0, t / 0.25) * exp(-maxf(0.0, t - 0.6) / 0.5)
	var horn := 0.0
	if t > 0.05 and t < 0.75:
		var h := fmod(t * 392.0, 1.0) * 2.0 - 1.0
		var h2 := fmod(t * 494.0, 1.0) * 2.0 - 1.0
		horn = (h + h2) * 0.12 * minf(1.0, (t - 0.05) / 0.03) * minf(1.0, (0.75 - t) / 0.08)
	var net := _rnd() * _env(t, 0.001, 0.05) * 0.4
	return crowd * 0.7 + horn + net


func _whistle(t: float, _d: float, _s: Dictionary) -> float:
	var trill := 0.6 + 0.4 * sin(TAU * 28.0 * t)
	var a := minf(1.0, t / 0.02) * minf(1.0, (0.45 - t) / 0.05)
	return sin(TAU * (2750.0 + 60.0 * sin(TAU * 28.0 * t)) * t) * trill * a * 0.28


func _error(t: float, _d: float, _s: Dictionary) -> float:
	var sq := 1.0 if fmod(t * 140.0, 1.0) < 0.5 else -1.0
	return sq * _env(t, 0.003, 0.05) * 0.22


func _safe(t: float, _d: float, _s: Dictionary) -> float:
	return (sin(TAU * 660.0 * t) + 0.5 * sin(TAU * 990.0 * t)) * _env(t, 0.003, 0.06) * 0.3


func _pressure(t: float, _d: float, s: Dictionary) -> float:
	s["lp"] = lerpf(s["lp"], _rnd(), 0.2)
	var low := sin(TAU * 150.0 * t) * _env(t, 0.01, 0.1)
	return low * 0.6 + s["lp"] * _env(t, 0.005, 0.06) * 0.4


func _lost(t: float, _d: float, _s: Dictionary) -> float:
	var f := 260.0 - 120.0 * t
	return sin(TAU * f * t) * _env(t, 0.01, 0.18) * 0.4
