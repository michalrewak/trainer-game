extends SceneTree
## Ręczny test end-to-end gra <-> mostek trenażera (NIE wchodzi do run_tests.gd):
##   1) mostek:  cd bridge  ->  .venv\Scripts\python -m wasteland_bridge --sim
##   2) sonda:   godot --headless --path game --script res://tests/integration/bridge_probe.gd -- --seconds=6
## Opcje (po "--"):
##   --url=ws://127.0.0.1:8765  adres mostka
##   --seconds=N                czas działania sondy (domyślnie 6)
##   --erg=W                    cel ERG wysyłany po --erg-at sekundach aktywności (domyślnie 250, 0 = bez ERG)
##   --erg-at=S                 (domyślnie 1)
##   --slope=G                  nachylenie wysyłane razem z ERG (domyślnie 3)
##   --min-connections=K        ile udanych połączeń z mostkiem wymagać (2 = test ponownego łączenia)
## Co 0,5 s wypisuje stan źródła, moc i kadencję, a każdą zmianę stanu osobno.
## Kod wyjścia: 0 = połączono, dane płynęły, mostek potwierdził ERG i moc doszła do celu; 1 = błąd.

var _source: WebSocketPowerSource
var _seconds := 6.0
var _erg := 250
var _erg_at := 1.0
var _slope := 3.0
var _min_connections := 1

var _elapsed := 0.0
var _next_print := 0.0
var _active_time := 0.0
var _targets_sent := false
var _last_status := -1
var _seen: Dictionary = {}
var _done := false


func _initialize() -> void:
	var url := WebSocketPowerSource.DEFAULT_URL
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=", true, 1)
		var value := parts[1] if parts.size() > 1 else ""
		match parts[0]:
			"--url":
				url = value
			"--seconds":
				_seconds = maxf(value.to_float(), 1.0)
			"--erg":
				_erg = maxi(value.to_int(), 0)
			"--erg-at":
				_erg_at = maxf(value.to_float(), 0.0)
			"--slope":
				_slope = value.to_float()
			"--min-connections":
				_min_connections = maxi(value.to_int(), 1)
	Engine.max_fps = 60
	_source = WebSocketPowerSource.new(url)
	print("Sonda mostka: %s, %.0f s, ERG %d W i nachylenie %.1f %% po %.1f s jazdy" % [url, _seconds, _erg, _slope, _erg_at])


func _process(delta: float) -> bool:
	if _done:
		return false
	_elapsed += delta
	_source.update(delta)
	var status := _source.get_status()
	_seen[status] = true
	if status != _last_status:
		print("t=%5.2f s  stan -> %s  (%s)" % [_elapsed, _status_name(status), _source.describe_connection()])
		_last_status = status
	for notice in _source.take_notices():
		print("t=%5.2f s  komunikat: %s" % [_elapsed, notice])
	if status == PowerSource.Status.ACTIVE:
		_active_time += delta
	if not _targets_sent and _active_time >= _erg_at:
		_targets_sent = true
		_source.set_grade(_slope)
		if _erg > 0:
			_source.set_erg_target(_erg)
		_source.ping()
		print("t=%5.2f s  wysłano: nachylenie %.1f %%%s" % [_elapsed, _slope, ", ERG %d W" % _erg if _erg > 0 else ""])
	if _elapsed >= _next_print:
		_next_print += 0.5
		print("t=%5.2f s  %-10s mostek=%-12s moc=%6.1f W  kadencja=%5.1f  prędkość=%5.1f km/h  ERG(mostek)=%3.0f W  ramek=%d" % [
			_elapsed, _status_name(status), _source.get_bridge_state(), _source.get_power_watts(),
			_source.get_cadence(), _source.get_speed_kmh(), _source.get_bridge_erg(), _source.get_data_count()])
	if _elapsed >= _seconds:
		_done = true
		quit(_verdict())
	return false


func _verdict() -> int:
	var problems: Array[String] = []
	if not _seen.has(PowerSource.Status.ACTIVE):
		problems.append("źródło ani razu nie było ACTIVE (czy mostek działa?)")
	if _source.get_data_count() < 4:
		problems.append("za mało ramek z danymi: %d" % _source.get_data_count())
	if _source.get_connection_count() < _min_connections:
		problems.append("połączeń z mostkiem: %d, wymagano %d" % [_source.get_connection_count(), _min_connections])
	if _erg > 0:
		if not _targets_sent:
			problems.append("nie wysłano ERG (za krótka aktywność)")
		elif roundi(_source.get_bridge_erg()) != _erg:
			problems.append("mostek nie potwierdził ERG: %.0f W zamiast %d W" % [_source.get_bridge_erg(), _erg])
		elif _source.get_status() == PowerSource.Status.ACTIVE and absf(_source.get_power_watts() - _erg) > 0.12 * _erg:
			problems.append("moc %.0f W daleko od celu ERG %d W" % [_source.get_power_watts(), _erg])
	var names := PackedStringArray()
	for status: int in _seen.keys():
		names.append(_status_name(status))
	print("")
	print("Podsumowanie: stany=%s, połączeń=%d, ramek=%d, moc=%.0f W, ERG(mostek)=%.0f W" % [
		", ".join(names), _source.get_connection_count(), _source.get_data_count(),
		_source.get_power_watts(), _source.get_bridge_erg()])
	if problems.is_empty():
		print("WYNIK: OK")
		return 0
	for p in problems:
		print("WYNIK: BŁĄD – ", p)
	return 1


func _status_name(status: int) -> String:
	match status:
		PowerSource.Status.ACTIVE:
			return "ACTIVE"
		PowerSource.Status.CONNECTING:
			return "CONNECTING"
		PowerSource.Status.LOST:
			return "LOST"
	return "?"
