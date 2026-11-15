class_name PowerSourceFactory
extends RefCounted
## Jedyne miejsce, które wie, jakie są implementacje PowerSource.
## Etap 5 doda tu źródło trenażera (WebSocket) – reszta gry się nie zmieni.

const KIND_GAMEPAD := "gamepad"
const KIND_AUTOPILOT := "autopilot"


static func create(kind: String) -> PowerSource:
	match kind:
		KIND_AUTOPILOT:
			return ScriptedPowerSource.new()
		_:
			return GamepadPowerSource.new()
