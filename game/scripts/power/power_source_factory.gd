class_name PowerSourceFactory
extends RefCounted
## Jedyne miejsce, które wie, jakie są implementacje PowerSource.
## Trenażer (etap 5) to WebSocketPowerSource łączący się z mostkiem Python (bridge/) –
## ładowany dynamicznie, więc gra działa także bez tego pliku (wtedy zostaje pad).

const KIND_GAMEPAD := "gamepad"
const KIND_AUTOPILOT := "autopilot"
const KIND_TRAINER := "trainer"
const TRAINER_SCRIPT := "res://scripts/power/websocket_power_source.gd"


static func trainer_available() -> bool:
	return ResourceLoader.exists(TRAINER_SCRIPT)


static func create(kind: String, bridge_url: String = "ws://127.0.0.1:8765") -> PowerSource:
	match kind:
		KIND_AUTOPILOT:
			return ScriptedPowerSource.new()
		KIND_TRAINER:
			if trainer_available():
				var script: GDScript = load(TRAINER_SCRIPT)
				var source: PowerSource = script.new(bridge_url)
				if source != null:
					return source
			var pad := GamepadPowerSource.new()
			pad.push_notice("Brak źródła trenażera – jedziesz na padzie")
			return pad
		_:
			return GamepadPowerSource.new()
