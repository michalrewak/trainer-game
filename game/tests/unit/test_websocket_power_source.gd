extends TestCase
## WebSocketPowerSource bez sieci: atrapa gniazda (FakeTransport), czas sterowany przez update(delta).


class FakeTransport:
	extends WebSocketPowerSource.Transport

	var state := WebSocketPeer.STATE_CLOSED
	var opened := 0
	var open_result := OK
	var inbox := PackedStringArray()
	var sent: Array[String] = []

	func open(_url: String) -> Error:
		opened += 1
		if open_result == OK:
			state = WebSocketPeer.STATE_CONNECTING
		return open_result

	func get_state() -> int:
		return state

	func receive() -> PackedStringArray:
		var out := inbox
		inbox = PackedStringArray()
		return out

	func send_text(text: String) -> Error:
		if state != WebSocketPeer.STATE_OPEN:
			return ERR_UNCONFIGURED
		sent.append(text)
		return OK

	func close() -> void:
		state = WebSocketPeer.STATE_CLOSED


var fake: FakeTransport
var source: WebSocketPowerSource


func _setup() -> void:
	fake = FakeTransport.new()
	source = WebSocketPowerSource.new("ws://127.0.0.1:9", fake)
	source.use_real_clock = false


## Otwiera gniazdo: pierwszy update() łączy, drugi widzi stan OPEN.
func _open() -> void:
	source.update(0.0)
	fake.state = WebSocketPeer.STATE_OPEN
	source.update(0.0)


func _feed(text: String, dt: float = 0.0) -> void:
	fake.inbox.append(text)
	source.update(dt)


func _status(state: String, erg: Variant = null, grade: Variant = null) -> String:
	return JSON.stringify({"type": "status", "state": state, "device": "SUITO 12345", "erg": erg, "grade": grade})


func _data(power: float, cadence: float = 88.0) -> String:
	return JSON.stringify({"type": "data", "power": power, "cadence": cadence, "speed": 32.5, "timestamp": 1763236800.5})


## Połączony mostek, trenażer połączony, pierwsze dane przyszły.
func _active(power: float = 200.0) -> void:
	_setup()
	_open()
	_feed(_status("connected"))
	_feed(_data(power))


func _sent(index: int) -> Dictionary:
	var parsed: Variant = JSON.parse_string(fake.sent[index])
	return parsed if parsed is Dictionary else {}


# --- parse_message ----------------------------------------------------------------

func test_parse_data_message() -> void:
	var m := WebSocketPowerSource.parse_message('{"type":"data","power":212,"cadence":87.5,"speed":33.46,"timestamp":1763236800.123}')
	assert_eq(m["type"], "data")
	assert_eq(m["power"], 212.0)
	assert_near(m["cadence"], 87.5, 0.001)
	assert_near(m["speed"], 33.46, 0.001)
	assert_near(m["timestamp"], 1763236800.123, 0.01)


func test_parse_data_defaults_and_clamps() -> void:
	var m := WebSocketPowerSource.parse_message('{"type":"data","power":-15,"extra":"ignorowane"}')
	assert_eq(m["type"], "data")
	assert_eq(m["power"], 0.0, "ujemna moc -> 0")
	assert_eq(m["cadence"], 0.0, "brak kadencji -> 0")
	assert_eq(m["speed"], 0.0)


func test_parse_status_with_nulls() -> void:
	var m := WebSocketPowerSource.parse_message('{"type":"status","state":"searching","device":null,"erg":null,"grade":null}')
	assert_eq(m["type"], "status")
	assert_eq(m["state"], "searching")
	assert_eq(m["device"], "")
	assert_eq(m["erg"], 0.0)
	assert_false(m["has_grade"])


func test_parse_status_with_values() -> void:
	var m := WebSocketPowerSource.parse_message('{"type":"status","state":"connected","device":"SUITO 12345","erg":250,"grade":-2.5}')
	assert_eq(m["state"], "connected")
	assert_eq(m["device"], "SUITO 12345")
	assert_eq(m["erg"], 250.0)
	assert_true(m["has_grade"])
	assert_near(m["grade"], -2.5, 0.001)


func test_parse_pong_and_error() -> void:
	assert_eq(WebSocketPowerSource.parse_message('{"type":"pong"}')["type"], "pong")
	var e := WebSocketPowerSource.parse_message('{"type":"error","message":"nieznana komenda"}')
	assert_eq(e["type"], "error")
	assert_eq(e["message"], "nieznana komenda")


func test_parse_invalid_inputs() -> void:
	for text: String in ["", "nie json", "[1,2]", "42", "{}", '{"type":5}', '{"type":"data"}',
			'{"type":"data","power":"200"}', '{"type":"data","power":true}', '{"type":"status"}',
			'{"type":"status","state":7}', '{"type":"hello","protocol":2}']:
		var m := WebSocketPowerSource.parse_message(text)
		assert_eq(m["type"], "invalid", "dla %s" % text)
		assert_true(str(m.get("reason", "")) != "", "powód dla %s" % text)


# --- Stan połączenia --------------------------------------------------------------

func test_connecting_until_first_data() -> void:
	_setup()
	assert_eq(source.get_status(), PowerSource.Status.CONNECTING, "przed połączeniem")
	_open()
	assert_true(source.is_bridge_connected())
	assert_eq(source.get_status(), PowerSource.Status.CONNECTING, "mostek bez statusu")
	_feed(_status("searching"))
	assert_eq(source.get_status(), PowerSource.Status.CONNECTING, "mostek szuka trenażera")
	_feed(_status("connected"))
	assert_eq(source.get_status(), PowerSource.Status.CONNECTING, "połączony, ale bez danych")
	_feed(_data(180.0))
	assert_eq(source.get_status(), PowerSource.Status.ACTIVE)
	assert_eq(source.get_device_name(), "SUITO 12345")


func test_stale_data_is_lost_and_fresh_data_recovers() -> void:
	_active()
	source.update(1.9)
	assert_eq(source.get_status(), PowerSource.Status.ACTIVE, "1,9 s bez danych to jeszcze nie utrata")
	source.update(0.2)
	assert_eq(source.get_status(), PowerSource.Status.LOST, "> 2 s bez danych")
	_feed(_data(190.0))
	assert_eq(source.get_status(), PowerSource.Status.ACTIVE)


func test_bridge_disconnected_status_means_lost_immediately() -> void:
	_active()
	_feed(_status("disconnected"))
	assert_eq(source.get_status(), PowerSource.Status.LOST)
	_feed(_status("searching"))
	assert_eq(source.get_status(), PowerSource.Status.LOST, "po utracie szukanie to nadal LOST")
	_feed(_status("connecting"))
	assert_eq(source.get_status(), PowerSource.Status.LOST)
	_feed(_status("connected"))
	_feed(_data(200.0))
	assert_eq(source.get_status(), PowerSource.Status.ACTIVE)


func test_disconnected_before_any_data_is_lost() -> void:
	_setup()
	_open()
	_feed(_status("disconnected"))
	assert_eq(source.get_status(), PowerSource.Status.LOST)


func test_sim_bridge_counts_as_active() -> void:
	_setup()
	_open()
	_feed(_status("sim"))
	_feed(_data(175.0))
	assert_eq(source.get_status(), PowerSource.Status.ACTIVE)
	assert_eq(source.get_hint(), "SYMULATOR TRENAŻERA")


func test_data_without_status_is_accepted() -> void:
	_setup()
	_open()
	_feed(_data(150.0))
	assert_eq(source.get_status(), PowerSource.Status.ACTIVE, "starszy mostek bez statusu")


func test_socket_close_is_lost_and_reconnects_with_backoff() -> void:
	_active()
	assert_eq(fake.opened, 1)
	fake.state = WebSocketPeer.STATE_CLOSED
	source.update(0.0)
	assert_eq(source.get_status(), PowerSource.Status.LOST)
	assert_false(source.is_bridge_connected())
	var waits: Array[float] = [1.0, 2.0, 4.0, 5.0, 5.0]
	for i in waits.size():
		source.update(waits[i] - 0.1)
		assert_eq(fake.opened, i + 1, "przed upływem %.0f s nie ponawiamy" % waits[i])
		source.update(0.15)
		assert_eq(fake.opened, i + 2, "po %.0f s ponawiamy" % waits[i])
		fake.state = WebSocketPeer.STATE_CLOSED  # kolejna nieudana próba
		source.update(0.0)
	# Udane połączenie zeruje przerwę.
	source.update(5.1)
	fake.state = WebSocketPeer.STATE_OPEN
	source.update(0.0)
	assert_true(source.is_bridge_connected())
	assert_eq(source.get_connection_count(), 2)
	fake.state = WebSocketPeer.STATE_CLOSED
	source.update(0.0)
	var before := fake.opened
	source.update(1.05)
	assert_eq(fake.opened, before + 1, "po udanym połączeniu znów zaczynamy od 1 s")


func test_connect_timeout_and_open_error_schedule_retry() -> void:
	_setup()
	source.update(0.0)
	assert_eq(fake.opened, 1)
	source.update(4.1)  # wisi w CONNECTING
	assert_false(source.is_bridge_connected())
	source.update(1.05)
	assert_eq(fake.opened, 2, "po przekroczeniu czasu łączymy od nowa")
	fake.open_result = ERR_CANT_CONNECT
	fake.state = WebSocketPeer.STATE_CLOSED
	source.update(0.0)
	source.update(2.05)
	assert_eq(fake.opened, 3)
	source.update(4.05)
	assert_eq(fake.opened, 4, "błąd open() też liczy się jako nieudana próba")


func test_next_backoff_sequence() -> void:
	assert_near(WebSocketPowerSource.next_backoff(1.0), 2.0, 0.001)
	assert_near(WebSocketPowerSource.next_backoff(2.0), 4.0, 0.001)
	assert_near(WebSocketPowerSource.next_backoff(4.0), 5.0, 0.001)
	assert_near(WebSocketPowerSource.next_backoff(5.0), 5.0, 0.001)


func test_garbage_frames_are_ignored() -> void:
	_active()
	_feed("to nie JSON")
	_feed('{"type":"hello"}')
	_feed('{"type":"data","power":"dużo"}')
	assert_eq(source.get_status(), PowerSource.Status.ACTIVE)


# --- Moc i wygładzanie ----------------------------------------------------------------

func test_power_is_smoothed_and_converges() -> void:
	_active(200.0)
	source.update(0.05)
	assert_between(source.get_power_watts(), 1.0, 100.0, "nie skacze od razu do 200 W")
	for i in 30:
		source.update(0.05)
	assert_near(source.get_power_watts(), 200.0, 2.0, "po 1,5 s jest blisko 200 W")
	assert_between(source.get_cadence(), 75.0, 90.0)
	assert_near(source.get_speed_kmh(), 32.5, 0.01)


func test_power_decays_when_trainer_lost() -> void:
	_active(220.0)
	for i in 30:
		source.update(0.05)
	_feed(_status("disconnected"))
	for i in 40:
		source.update(0.05)
	assert_near(source.get_power_watts(), 0.0, 1.0, "bez trenażera moc spada do zera")
	assert_eq(source.get_speed_kmh(), 0.0)


# --- Komendy ERG / nachylenie ---------------------------------------------------------

func test_erg_commands_are_deduplicated() -> void:
	_active()
	source.set_erg_target(200.0)
	source.set_erg_target(200.0)
	source.set_erg_target(200.4)
	assert_eq(fake.sent.size(), 1)
	assert_eq(_sent(0)["cmd"], "erg")
	assert_near(float(_sent(0)["watts"]), 200.0, 0.001)
	source.set_erg_target(210.0)
	source.set_erg_target(0.0)
	source.set_erg_target(-5.0)
	assert_eq(fake.sent.size(), 3, "0 i -5 to ten sam stan: ERG wyłączony")
	assert_near(float(_sent(2)["watts"]), 0.0, 0.001)
	assert_eq(source.get_erg_target(), 0)


func test_grade_commands_are_snapped_clamped_and_deduplicated() -> void:
	_active()
	source.set_grade(4.54)
	source.set_grade(4.46)
	assert_eq(fake.sent.size(), 1)
	assert_eq(_sent(0)["cmd"], "slope")
	assert_near(float(_sent(0)["grade"]), 4.5, 0.001)
	source.set_grade(30.0)
	assert_near(float(_sent(1)["grade"]), 20.0, 0.001)
	source.set_grade(-0.04)
	assert_near(float(_sent(2)["grade"]), 0.0, 0.001)


func test_commands_wait_for_connection_and_are_resent_after_reconnect() -> void:
	_setup()
	source.set_erg_target(180.0)
	source.set_grade(2.0)
	assert_eq(fake.sent.size(), 0, "bez połączenia nic nie wysyłamy")
	_open()
	assert_eq(fake.sent.size(), 2, "po połączeniu wysyłamy zaległe cele")
	assert_eq(_sent(0)["cmd"], "slope")
	assert_eq(_sent(1)["cmd"], "erg")
	assert_near(float(_sent(1)["watts"]), 180.0, 0.001)
	fake.state = WebSocketPeer.STATE_CLOSED
	source.update(0.0)
	source.update(1.05)
	fake.state = WebSocketPeer.STATE_OPEN
	source.update(0.0)
	assert_eq(fake.sent.size(), 4, "po ponownym połączeniu cele idą jeszcze raz")
	assert_near(float(_sent(3)["watts"]), 180.0, 0.001)


func test_no_commands_resent_when_game_never_set_targets() -> void:
	_active()
	assert_eq(fake.sent.size(), 0)


func test_poll_connection_recovers_without_update() -> void:
	## W pauzie gra woła tylko poll_connection(): dane dalej płyną, a stan wraca do ACTIVE.
	_active()
	_feed(_status("disconnected"))
	assert_eq(source.get_status(), PowerSource.Status.LOST)
	var power_before := source.get_power_watts()
	fake.inbox.append(_status("connected"))
	fake.inbox.append(_data(240.0))
	source.poll_connection()
	assert_eq(source.get_status(), PowerSource.Status.ACTIVE)
	assert_eq(source.get_data_count(), 2)
	assert_near(source.get_power_watts(), power_before, 0.001, "bez delta nie ma wygładzania")
	fake.state = WebSocketPeer.STATE_CLOSED
	source.poll_connection()
	assert_false(source.is_bridge_connected(), "zamknięcie wykryte także w pauzie")


# --- Teksty i interfejs ---------------------------------------------------------------

func test_label_hint_and_resistance_support() -> void:
	_setup()
	assert_eq(source.get_label(), "TRENAŻER")
	assert_true(source.supports_resistance_control())
	assert_true(source is PowerSource)
	assert_eq(source.get_hint(), "ŁĄCZĘ Z TRENAŻEREM…")
	_open()
	_feed(_status("connected"))
	_feed(_data(200.0))
	assert_eq(source.get_hint(), "")
	source.set_erg_target(220.0)
	assert_eq(source.get_hint(), "ERG 220 W")
	_feed(_status("disconnected", 220))
	assert_eq(source.get_hint(), "BRAK TRENAŻERA")
	assert_near(source.get_bridge_erg(), 220.0, 0.001)


func test_describe_connection_texts() -> void:
	_setup()
	assert_true(source.describe_connection().contains("Łączę z mostkiem"), "pierwsza próba")
	source.update(0.0)
	fake.state = WebSocketPeer.STATE_CLOSED
	source.update(0.0)
	assert_true(source.describe_connection().contains("uruchom bridge"), "po nieudanej próbie")
	source.update(1.05)
	fake.state = WebSocketPeer.STATE_OPEN
	source.update(0.0)
	assert_true(source.is_bridge_connected())
	_feed(_status("searching"))
	assert_true(source.describe_connection().contains("szuka"))
	_feed(_status("connecting"))
	assert_true(source.describe_connection().contains("SUITO 12345"))
	_feed(_status("disconnected"))
	assert_true(source.describe_connection().contains("rozłączony"))
	_feed(_status("connected"))
	assert_true(source.describe_connection().contains("Czekam"))
	_feed(_data(100.0))
	assert_true(source.describe_connection().contains("połączony"))


func test_notices_on_first_connect_and_reconnect() -> void:
	_active()
	var first := source.take_notices()
	assert_eq(first.size(), 1)
	assert_true(first[0].contains("SUITO 12345"))
	_feed(_status("disconnected"))
	assert_eq(source.take_notices().size(), 0, "utrata pokazuje się w pauzie, nie jako komunikat")
	_feed(_status("connected"))
	_feed(_data(200.0))
	var again := source.take_notices()
	assert_eq(again.size(), 1)
	assert_true(again[0].contains("znów"))
