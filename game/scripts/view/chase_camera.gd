class_name ChaseCamera
extends Camera3D
## Kamera zza pojazdu, z góry pod kątem. Podąża za pasem z opóźnieniem, przy większej
## prędkości lekko poszerza pole widzenia; trzęsie się po uderzeniu.

var height := 5.2
var distance := 9.0
var look_ahead := 16.0
var look_height := 0.6
var follow_x := 0.6
var follow_speed := 3.5
var base_fov := 60.0
var max_fov_kick := 9.0

var _x := 0.0
var _shake := 0.0
var _time := 0.0


func _ready() -> void:
	fov = base_fov
	position = Vector3(0, height, distance)
	look_at(Vector3(0, look_height, -look_ahead))


func follow(target_x: float, speed_mps: float, delta: float) -> void:
	_time += delta
	_x = lerpf(_x, target_x * follow_x, 1.0 - exp(-delta * follow_speed))
	position = Vector3(_x, height, distance)
	look_at(Vector3(_x * 0.6 + target_x * 0.4, look_height, -look_ahead))
	var kick := clampf((speed_mps - 4.0) / 8.0, 0.0, 1.0) * max_fov_kick
	fov = lerpf(fov, base_fov + kick, 1.0 - exp(-delta * 2.0))
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.5)
		h_offset = sin(_time * 61.0) * _shake * 0.35
		v_offset = cos(_time * 47.0) * _shake * 0.25
	else:
		h_offset = 0.0
		v_offset = 0.0


func shake(amount: float = 1.0) -> void:
	_shake = maxf(_shake, amount)
