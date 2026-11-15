class_name VehicleModel
extends RefCounted
## Model moc -> prędkość z bezwładnością (uproszczona fizyka roweru):
##
##   m_inertia * dv/dt = F_napęd - F_powietrze - F_toczenie - F_grawitacja
##   F_napęd      = min(P_eff / max(v, v_min), F_max),  P_eff = P * engine_multiplier
##   F_powietrze  = 0.5 * rho * CdA * v^2
##   F_toczenie   = Crr * m * g * cos(atan(grade))
##   F_grawitacja = m * g * sin(atan(grade))
##
## Stan ustalony (płasko): P = (0.5*rho*CdA*v^2 + Crr*m*g) * v
##   -> 100 W ≈ 23 km/h, 200 W ≈ 31 km/h, 300 W ≈ 36 km/h, 350 W ≈ 38 km/h.
## m_inertia jest mniejsza od masy realnej, żeby gra reagowała żwawiej
## (90% nowej prędkości po ok. 5 s), a stan ustalony zostaje realistyczny.
## engine_multiplier (etap 3: ulepszenia) i grade (etapy 4–6: podjazdy) to gotowe haki.

const G := 9.81
const MAX_STEP_S := 0.05

var mass_kg := 95.0
var inertia_kg := 18.0
var cda_m2 := 0.40
var crr := 0.006
var air_density := 1.2
var min_drive_speed_mps := 2.0
var max_drive_force_n := 220.0
var engine_multiplier := 1.0
var grade := 0.0

var speed_mps := 0.0
var distance_m := 0.0


func step(delta: float, power_w: float) -> void:
	var remaining := delta
	while remaining > 1e-9:
		var h := minf(remaining, MAX_STEP_S)
		var a := acceleration(speed_mps, power_w)
		speed_mps = maxf(0.0, speed_mps + a * h)
		distance_m += speed_mps * h
		remaining -= h


func acceleration(v: float, power_w: float) -> float:
	return (drive_force(v, power_w) - resist_force(v)) / inertia_kg


func drive_force(v: float, power_w: float) -> float:
	var p := maxf(power_w, 0.0) * engine_multiplier
	if p <= 0.0:
		return 0.0
	return minf(p / maxf(v, min_drive_speed_mps), max_drive_force_n)


func resist_force(v: float) -> float:
	var theta := atan(grade)
	var aero := 0.5 * air_density * cda_m2 * v * v
	var roll := crr * mass_kg * G * cos(theta) if v > 0.0 else 0.0
	return aero + roll + mass_kg * G * sin(theta)


## Zderzenie: prędkość mnożona przez factor (np. 0.35).
func apply_impact(factor: float) -> void:
	speed_mps *= clampf(factor, 0.0, 1.0)


## Prędkość ustalona dla danej mocy (bisekcja). Do testów, HUD i przyszłego trybu ERG.
func steady_state_speed(power_w: float) -> float:
	var p := maxf(power_w, 0.0) * engine_multiplier
	if p <= 0.0:
		return 0.0
	var lo := 0.0
	var hi := 60.0
	for i in 80:
		var mid := (lo + hi) * 0.5
		if p - resist_force(mid) * mid > 0.0:
			lo = mid
		else:
			hi = mid
	return lo


func speed_kmh() -> float:
	return speed_mps * 3.6
