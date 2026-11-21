class_name Sfx
extends Node
## Efekty dźwiękowe generowane w grze (bez plików audio): krótkie próbki składane z sinusów
## i szumu przy starcie. Zbieranie zębatek gra coraz wyższą nutą, gdy rośnie passa – ucho
## samo podpowiada, że idzie dobrze. Odtwarzanie przez małą pulę odtwarzaczy.

const RATE := 22050
const VOICES := 8
## Głośność ogólna [dB] – efekty mają towarzyszyć jeździe, nie zagłuszać muzyki gracza.
const MASTER_DB := -8.0

var enabled := true

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _combo := 0
var _combo_left := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_streams = build_streams()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func _process(delta: float) -> void:
	_combo_left = maxf(0.0, _combo_left - delta)
	if _combo_left <= 0.0:
		_combo = 0


func play(sound: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not enabled or _players.is_empty() or not _streams.has(sound):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sound]
	p.pitch_scale = clampf(pitch, 0.25, 4.0)
	p.volume_db = MASTER_DB + volume_db
	p.play()


## Zębatka: kolejne zebrane w krótkim odstępie grają o pół tonu wyżej (do oktawy),
## a wyższy próg passy podnosi cały motyw.
func pickup(streak_tier: int = 0) -> void:
	play("pickup", pow(2.0, (_combo % 12) / 12.0) * (1.0 + 0.05 * streak_tier), -4.0)
	_combo += 1
	_combo_left = 1.2


## Wszystkie próbki: nazwa -> AudioStreamWAV. Statyczne, żeby dało się je sprawdzić w testach.
static func build_streams() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var out := {}
	# Zębatka: krótki, jasny brzdęk.
	out["pickup"] = _render(0.11, func(t: float, k: float) -> float:
		return (sin(TAU * 880.0 * t) * 0.6 + sin(TAU * 1760.0 * t) * 0.3) * pow(1.0 - k, 2.0))
	# Kanister / duży złom: dwie nuty.
	out["big"] = _render(0.28, func(t: float, k: float) -> float:
		var f := 660.0 if k < 0.4 else 990.0
		return sin(TAU * f * t) * 0.6 * pow(1.0 - fmod(k, 0.4) / 0.6, 1.5) * (1.0 - k * 0.5))
	# Strzał: trzask z niskim stuknięciem.
	out["shot"] = _render(0.09, func(t: float, k: float) -> float:
		return (rng.randf_range(-1.0, 1.0) * 0.6 + signf(sin(TAU * 140.0 * t)) * 0.4) * pow(1.0 - k, 3.0))
	# Uderzenie: głuche łupnięcie.
	out["hit"] = _render(0.3, func(t: float, k: float) -> float:
		return (sin(TAU * lerpf(110.0, 45.0, k) * t) * 0.8 + rng.randf_range(-1.0, 1.0) * 0.35 * (1.0 - k)) * pow(1.0 - k, 1.5))
	# Wybuch: długi, niski szum.
	var boom_state := [0.0]
	out["boom"] = _render(0.7, func(t: float, k: float) -> float:
		boom_state[0] = lerpf(boom_state[0], rng.randf_range(-1.0, 1.0), lerpf(0.5, 0.05, k))
		return (boom_state[0] * 1.2 + sin(TAU * lerpf(70.0, 30.0, k) * t) * 0.5) * pow(1.0 - k, 1.3))
	# Ostrzeżenie: dwa piknięcia.
	out["warn"] = _render(0.26, func(t: float, k: float) -> float:
		return signf(sin(TAU * 980.0 * t)) * 0.35 if fmod(k, 0.5) < 0.3 else 0.0)
	# Dopalacz: narastający świst.
	var whoosh := [0.0]
	out["boost"] = _render(0.8, func(t: float, k: float) -> float:
		whoosh[0] = lerpf(whoosh[0], rng.randf_range(-1.0, 1.0), lerpf(0.08, 0.6, k))
		return (whoosh[0] * 0.8 + sin(TAU * lerpf(120.0, 520.0, k * k) * t) * 0.3) * sin(PI * minf(k * 1.4, 1.0)))
	# Wyższy próg passy: trzy nuty w górę.
	out["tier"] = _arpeggio([523.0, 659.0, 784.0], 0.09, 0.14)
	# Passa przerwana: dwie nuty w dół.
	out["lost"] = _arpeggio([392.0, 262.0], 0.14, 0.2)
	# Zlecenie, rekord, przejęta galera: fanfara.
	out["fanfare"] = _arpeggio([523.0, 659.0, 784.0, 1047.0], 0.11, 0.4)
	# Skrzynia: iskierki.
	out["crate"] = _render(0.4, func(t: float, k: float) -> float:
		var step := floorf(k * 8.0)
		return sin(TAU * (900.0 + fmod(step * 377.0, 900.0)) * t) * 0.5 * pow(1.0 - fmod(k * 8.0, 1.0), 2.0))
	# Radio przed kwestią postaci: krótki trzask.
	out["radio"] = _render(0.07, func(_t: float, k: float) -> float:
		return rng.randf_range(-1.0, 1.0) * 0.3 * (1.0 - k))
	return out


## Nuty jedna po drugiej, ostatnia wybrzmiewa dłużej.
static func _arpeggio(notes: Array, step_s: float, tail_s: float) -> AudioStreamWAV:
	var total := step_s * (notes.size() - 1) + tail_s
	return _render(total, func(t: float, _k: float) -> float:
		var i := mini(notes.size() - 1, floori(t / step_s))
		var local := t - i * step_s
		var length := tail_s if i == notes.size() - 1 else step_s
		var env := pow(maxf(0.0, 1.0 - local / length), 1.2)
		var f: float = notes[i]
		return (sin(TAU * f * t) * 0.5 + sin(TAU * f * 2.0 * t) * 0.2) * env)


static func _render(duration_s: float, wave: Callable) -> AudioStreamWAV:
	var n := int(duration_s * RATE)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var v := clampf(float(wave.call(float(i) / RATE, float(i) / n)), -1.0, 1.0)
		bytes.encode_s16(i * 2, int(v * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	return s
