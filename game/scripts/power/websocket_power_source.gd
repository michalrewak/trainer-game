class_name WebSocketPowerSource
extends PowerSource
## Moc z prawdziwego trenażera przez mostek (katalog bridge/, Python): BLE FTMS <-> WebSocket.
## Protokół v1 (JSON w ramkach tekstowych):
##   mostek -> gra: {"type":"data","power":W,"cadence":obr/min,"speed":km/h,"timestamp":s} co 250 ms,
##                  {"type":"status","state":"searching|connecting|connected|disconnected|sim",
##                   "device":nazwa|null,"erg":W|null,"grade":%|null} po połączeniu i przy każdej zmianie,
##                  {"type":"pong"}, {"type":"error","message":...}
##   gra -> mostek: {"cmd":"erg","watts":N} (N <= 0 wyłącza ERG), {"cmd":"slope","grade":G}, {"cmd":"ping"}
## Połączenie jest nieblokujące: update() raz na klatkę odpytuje gniazdo, a po zerwaniu ponawia
## próbę po 1 s, 2 s, 4 s, potem co 5 s. Stan: CONNECTING do pierwszych danych, ACTIVE gdy dane
## są świeże (< 2 s), LOST gdy mostek zgłasza rozłączony trenażer albo dane ustały.
## Uwaga dla gry: w czasie pauzy też trzeba wołać update(), inaczej połączenie się nie odnowi.

const DEFAULT_URL := "ws://127.0.0.1:8765"
## Dane starsze niż tyle sekund = brak trenażera (mostek nadaje co 0,25 s).
const STALE_AFTER_S := 2.0
const RECONNECT_MIN_S := 1.0
const RECONNECT_MAX_S := 5.0
## Tyle czekamy na otwarcie połączenia, zanim zaczniemy od nowa.
const CONNECT_TIMEOUT_S := 4.0
## Wygładzanie mocy i kadencji (dane przychodzą 4 razy na sekundę, fizyka liczy co klatkę).
const POWER_TAU_S := 0.3
const CADENCE_TAU_S := 0.6
## Nachylenie wysyłamy z dokładnością 0,1 % i w zakresie ±20 % (tak samo przycina mostek).
const GRADE_LIMIT := 20.0
const GRADE_STEP := 0.1

const BRIDGE_SEARCHING := "searching"
const BRIDGE_CONNECTING := "connecting"
const BRIDGE_CONNECTED := "connected"
const BRIDGE_DISCONNECTED := "disconnected"
const BRIDGE_SIM := "sim"

enum Socket { IDLE, CONNECTING, OPEN }


## Warstwa gniazda – osobno, żeby testy mogły podstawić atrapę bez sieci.
class Transport:
	extends RefCounted

	func open(_url: String) -> Error:
		return ERR_UNAVAILABLE

	func poll() -> void:
		pass

	## Stan jak w WebSocketPeer.State.
	func get_state() -> int:
		return WebSocketPeer.STATE_CLOSED

	## Ramki tekstowe odebrane od ostatniego wywołania.
	func receive() -> PackedStringArray:
		return PackedStringArray()

	func send_text(_text: String) -> Error:
		return ERR_UNAVAILABLE

	func close() -> void:
		pass


## Prawdziwe gniazdo: WebSocketPeer z Godota.
class PeerTransport:
	extends Transport

	var _peer: WebSocketPeer = null

	func open(url: String) -> Error:
		close()
		_peer = WebSocketPeer.new()
		return _peer.connect_to_url(url)

	func poll() -> void:
		if _peer != null:
			_peer.poll()

	func get_state() -> int:
		if _peer == null:
			return WebSocketPeer.STATE_CLOSED
		return _peer.get_ready_state()

	func receive() -> PackedStringArray:
		var out := PackedStringArray()
		if _peer == null:
			return out
		while _peer.get_available_packet_count() > 0:
			var packet := _peer.get_packet()
			if _peer.was_string_packet():
				out.append(packet.get_string_from_utf8())
		return out

	func send_text(text: String) -> Error:
		if _peer == null or _peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
			return ERR_UNCONFIGURED
		return _peer.send_text(text)

	func close() -> void:
		if _peer != null:
			_peer.close()
			_peer = null


var url := DEFAULT_URL
## Zegar rzeczywisty (odporny na Engine.time_scale i pauzę). Testy ustawiają false
## i przesuwają czas wyłącznie przez update(delta).
var use_real_clock := true

var _transport: Transport
var _socket := Socket.IDLE
var _retry_at := 0.0
var _backoff := RECONNECT_MIN_S
var _connect_started := 0.0
var _manual_clock := 0.0
var _connections := 0
var _failed_attempts := 0
var _data_count := 0

var _bridge_state := ""
var _device := ""
var _bridge_erg := 0.0
var _last_data_at := -1.0
var _raw_power := 0.0
var _raw_cadence := 0.0
var _raw_speed := 0.0
var _power := 0.0
var _cadence := 0.0
var _ever_active := false
var _was_active := false
var _last_error := ""

## Cele zadane przez grę: -1 = ERG nigdy nie ustawiany.
var _erg_target := -1
var _grade := 0.0
var _grade_set := false


func _init(p_url: String = DEFAULT_URL, p_transport: Transport = null) -> void:
	url = p_url
	_transport = p_transport if p_transport != null else PeerTransport.new()


# --- PowerSource ----------------------------------------------------------------

func update(delta: float) -> void:
	if delta > 0.0:
		_manual_clock += delta
	_service_socket()
	_smooth(delta)
	_track_activity()


## Samo utrzymanie połączenia (bez wygładzania mocy) – do wołania w czasie pauzy wyprawy,
## gdy drzewo sceny stoi i update() nie jest wołane. Dzięki temu po zerwaniu łącza status
## wraca do ACTIVE sam, a mostek nie zamyka nieodpytywanego połączenia.
func poll_connection() -> void:
	_service_socket()
	_track_activity()


func get_power_watts() -> float:
	return _power


func get_cadence() -> float:
	return _cadence


func get_status() -> Status:
	if _is_live():
		return Status.ACTIVE
	if _ever_active or _bridge_state == BRIDGE_DISCONNECTED:
		return Status.LOST
	return Status.CONNECTING


func get_label() -> String:
	return "TRENAŻER"


func get_hint() -> String:
	match get_status():
		Status.ACTIVE:
			if _erg_target > 0:
				return "ERG %d W" % _erg_target
			if _bridge_state == BRIDGE_SIM:
				return "SYMULATOR TRENAŻERA"
			return ""
		Status.CONNECTING:
			return "ŁĄCZĘ Z TRENAŻEREM…"
	return "BRAK TRENAŻERA"


func supports_resistance_control() -> bool:
	return true


func set_erg_target(watts: float) -> void:
	var w := maxi(roundi(watts), 0)
	if w == _erg_target:
		return
	_erg_target = w
	_send({"cmd": "erg", "watts": w})


func set_grade(grade_percent: float) -> void:
	var g := snappedf(clampf(grade_percent, -GRADE_LIMIT, GRADE_LIMIT), GRADE_STEP)
	if _grade_set and is_equal_approx(g, _grade):
		return
	_grade = g
	_grade_set = true
	_send({"cmd": "slope", "grade": g})


# --- Dodatkowe informacje (HUD, menu, diagnostyka) ---------------------------------

## Prędkość podawana przez trenażer (km/h) – tylko informacyjnie, grę napędza moc.
func get_speed_kmh() -> float:
	return _raw_speed if _is_live() else 0.0


## Ostatni stan zgłoszony przez mostek ("" = brak połączenia z mostkiem).
func get_bridge_state() -> String:
	return _bridge_state


func get_device_name() -> String:
	return _device


## Cel ERG potwierdzony przez mostek (0 = wyłączony).
func get_bridge_erg() -> float:
	return _bridge_erg


## Cel ERG zadany przez grę (-1 = nigdy nie ustawiany, 0 = wyłączony).
func get_erg_target() -> int:
	return _erg_target


func is_bridge_connected() -> bool:
	return _socket == Socket.OPEN


## Ile razy udało się połączyć z mostkiem (diagnostyka i testy).
func get_connection_count() -> int:
	return _connections


## Ile ramek z danymi odebrano od początku (diagnostyka i testy).
func get_data_count() -> int:
	return _data_count


func get_last_error() -> String:
	return _last_error


## Opis stanu po polsku, np. jako powód pauzy wyprawy.
func describe_connection() -> String:
	if _socket != Socket.OPEN:
		if _connections == 0:
			if _failed_attempts == 0:
				return "Łączę z mostkiem trenażera (%s)…" % url
			return "Brak mostka trenażera – uruchom bridge (%s)" % url
		return "Utracono połączenie z mostkiem – ponawiam…"
	match _bridge_state:
		BRIDGE_SEARCHING:
			return "Mostek szuka trenażera – zakręć korbą, żeby go wybudzić"
		BRIDGE_CONNECTING:
			return "Łączę z trenażerem %s…" % _device_label()
		BRIDGE_DISCONNECTED:
			return "Trenażer %s rozłączony – mostek ponawia połączenie" % _device_label()
	if _last_data_at < 0.0:
		return "Czekam na dane z trenażera…"
	if not _is_live():
		return "Brak danych z trenażera"
	if _bridge_state == BRIDGE_SIM:
		return "Symulator trenażera (mostek uruchomiony z --sim)"
	return "Trenażer połączony: %s" % _device_label()


func ping() -> void:
	_send({"cmd": "ping"})


## Zamyka połączenie z mostkiem (np. przy zmianie źródła mocy). Następny update() połączy znowu.
func close() -> void:
	_transport.close()
	_socket = Socket.IDLE
	_bridge_state = ""
	_last_data_at = -1.0
	_retry_at = _now() + RECONNECT_MIN_S


## Przetwarza jedną ramkę od mostka (publiczne dla testów).
func handle_message(text: String) -> void:
	var msg := parse_message(text)
	match str(msg["type"]):
		"data":
			_raw_power = float(msg["power"])
			_raw_cadence = float(msg["cadence"])
			_raw_speed = float(msg["speed"])
			_last_data_at = _now()
			_data_count += 1
		"status":
			_bridge_state = str(msg["state"])
			_device = str(msg["device"])
			_bridge_erg = float(msg["erg"])
		"error":
			_last_error = "Mostek: %s" % str(msg["message"])
			push_warning(_last_error)


# --- Protokół (statycznie, bez sieci) ------------------------------------------------

## Parsuje ramkę mostka do słownika o ustalonych typach. Pole "type":
##   "data"    – power, cadence, speed, timestamp (float, >= 0)
##   "status"  – state (String), device (String, "" gdy brak), erg (float, 0 = wyłączony),
##               has_grade (bool), grade (float)
##   "pong", "error" – message (String)
##   "invalid" – reason (String): nie JSON, nie obiekt, brak pól, złe typy, nieznany typ.
static func parse_message(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return _invalid("niepoprawny JSON")
	var root: Variant = json.data
	if not (root is Dictionary):
		return _invalid("oczekiwano obiektu JSON")
	var d: Dictionary = root
	var kind: Variant = d.get("type")
	if not (kind is String):
		return _invalid("brak pola type")
	match kind:
		"data":
			var power: Variant = d.get("power")
			if not _is_number(power):
				return _invalid("dane bez mocy")
			return {
				"type": "data",
				"power": maxf(float(power), 0.0),
				"cadence": _non_negative(d.get("cadence")),
				"speed": _non_negative(d.get("speed")),
				"timestamp": _non_negative(d.get("timestamp")),
			}
		"status":
			var state: Variant = d.get("state")
			if not (state is String):
				return _invalid("status bez stanu")
			var device: Variant = d.get("device")
			var grade: Variant = d.get("grade")
			var has_grade := _is_number(grade)
			return {
				"type": "status",
				"state": state,
				"device": device if device is String else "",
				"erg": _non_negative(d.get("erg")),
				"has_grade": has_grade,
				"grade": float(grade) if has_grade else 0.0,
			}
		"pong":
			return {"type": "pong"}
		"error":
			var message: Variant = d.get("message")
			return {"type": "error", "message": message if message is String else ""}
	return _invalid("nieznany typ wiadomości: %s" % str(kind))


## Kolejna przerwa przed ponownym łączeniem: 1 -> 2 -> 4 -> 5 -> 5 s.
static func next_backoff(current_s: float) -> float:
	return minf(current_s * 2.0, RECONNECT_MAX_S)


static func _invalid(reason: String) -> Dictionary:
	return {"type": "invalid", "reason": reason}


static func _is_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


static func _non_negative(value: Variant) -> float:
	return maxf(float(value), 0.0) if _is_number(value) else 0.0


# --- Wnętrze ---------------------------------------------------------------------

func _now() -> float:
	if use_real_clock:
		return Time.get_ticks_usec() / 1000000.0
	return _manual_clock


func _service_socket() -> void:
	var now := _now()
	if _socket == Socket.IDLE:
		if now >= _retry_at:
			_open_socket(now)
		return
	_transport.poll()
	var state := _transport.get_state()
	if state == WebSocketPeer.STATE_OPEN and _socket == Socket.CONNECTING:
		_socket = Socket.OPEN
		_backoff = RECONNECT_MIN_S
		_failed_attempts = 0
		_connections += 1
		_on_open()
	for text: String in _transport.receive():
		handle_message(text)
	if state == WebSocketPeer.STATE_CLOSED:
		_on_closed(now)
	elif _socket == Socket.CONNECTING and now - _connect_started > CONNECT_TIMEOUT_S:
		_transport.close()
		_on_closed(now)


func _open_socket(now: float) -> void:
	_connect_started = now
	var err := _transport.open(url)
	if err != OK:
		_last_error = "Nie mogę połączyć z %s (błąd %d)" % [url, err]
		_failed_attempts += 1
		_schedule_retry(now)
		return
	_socket = Socket.CONNECTING


func _on_open() -> void:
	# Mostek mógł zostać uruchomiony od nowa – przypominamy mu cele gry.
	if _grade_set:
		_send({"cmd": "slope", "grade": _grade})
	if _erg_target >= 0:
		_send({"cmd": "erg", "watts": _erg_target})


func _on_closed(now: float) -> void:
	if _socket == Socket.CONNECTING:
		_failed_attempts += 1
	_socket = Socket.IDLE
	_bridge_state = ""
	_last_data_at = -1.0
	_schedule_retry(now)


func _schedule_retry(now: float) -> void:
	_retry_at = now + _backoff
	_backoff = next_backoff(_backoff)


func _send(msg: Dictionary) -> bool:
	if _socket != Socket.OPEN:
		return false  # wyślemy po połączeniu (_on_open)
	return _transport.send_text(JSON.stringify(msg)) == OK


func _is_live() -> bool:
	if _socket != Socket.OPEN or _last_data_at < 0.0:
		return false
	if _now() - _last_data_at > STALE_AFTER_S:
		return false
	return not (_bridge_state in [BRIDGE_SEARCHING, BRIDGE_CONNECTING, BRIDGE_DISCONNECTED])


func _smooth(delta: float) -> void:
	if delta <= 0.0:
		return
	var live := _is_live()
	_power = _approach(_power, _raw_power if live else 0.0, delta, POWER_TAU_S)
	_cadence = _approach(_cadence, _raw_cadence if live else 0.0, delta, CADENCE_TAU_S)


static func _approach(current: float, target: float, delta: float, tau: float) -> float:
	var out := current + (target - current) * (1.0 - exp(-delta / tau))
	return target if absf(out - target) < 0.05 else out


func _track_activity() -> void:
	var active := _is_live()
	if active and not _was_active:
		if _bridge_state == BRIDGE_SIM:
			push_notice("Trenażer: symulator mostka (dane testowe)")
		elif _ever_active:
			push_notice("Trenażer znów połączony")
		else:
			push_notice("Trenażer połączony: %s" % _device_label())
		_ever_active = true
	_was_active = active


func _device_label() -> String:
	return _device if _device != "" else "SUITO"
