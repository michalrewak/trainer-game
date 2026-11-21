class_name Autopilot
extends RefCounted
## Prosty „kierowca” do testów dymnych i demo: omija wraki, a gdy droga wolna,
## zjeżdża po złom. Nie jest częścią rozgrywki gracza.

var look_ahead_s := 2.2
var min_look_ahead_m := 18.0
var scrap_look_ahead_m := 45.0
var cooldown_s := 0.35
## Czy autopilot zjeżdża na osady (testy napadów).
var take_raids := false

var _cooldown := 0.0


func decide(sim: RunSimulation, delta: float) -> int:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _cooldown > 0.0:
		return 0
	var lanes := sim.lanes
	var here := lanes.target_lane
	var d := sim.vehicle.distance_m
	var horizon := maxf(min_look_ahead_m, sim.vehicle.speed_mps * look_ahead_s)
	# Zjazd na osadę: przed rozwidleniem ustaw się na skrajnym pasie od jej strony.
	var raids := sim.raids
	if take_raids and raids.state == RaidDirector.State.SCOUTING and raids.distance_to_next_m() < 220.0:
		var exit := raids.exit_lane()
		if here != exit:
			var step_dir := signi(exit - here)
			if not _wreck_ahead(sim, here + step_dir, d, horizon):
				_cooldown = cooldown_s
				return step_dir
		elif raids.distance_to_next_m() < 60.0 and not _wreck_ahead(sim, here, d, horizon):
			return 0
	# Ostrzeżenie przed taranowaniem: odjedź od napastnika, jeśli pas jest wolny.
	for r in sim.combat.live_raiders():
		if r.state == RaiderModel.State.TELEGRAPH and r.timer > 0.5:
			var away := here - r.side
			if away >= 0 and away < lanes.lane_count and not _wreck_ahead(sim, away, d, horizon):
				_cooldown = cooldown_s
				return -r.side
	if _wreck_ahead(sim, here, d, horizon):
		var best := _best_free_lane(sim, here, d, horizon)
		if best != here:
			_cooldown = cooldown_s
			return signi(best - here)
		return 0
	for item in sim.items_between(d + 4.0, d + scrap_look_ahead_m):
		if item.is_scrap() and item.lane != here:
			var dir := signi(item.lane - here)
			if not _wreck_ahead(sim, here + dir, d, horizon):
				_cooldown = cooldown_s
				return dir
			break
	return 0


## Sprawdza też wraki tuż obok pojazdu (strefa kolizji to ~2,8 m w obie strony),
## żeby nie zjechać na pas, na którym właśnie mijamy wrak.
func _wreck_ahead(sim: RunSimulation, lane: int, d: float, horizon: float) -> bool:
	var behind := sim.wreck_half_length_m + sim.vehicle_half_length_m + 0.8
	# Miejsce, w które zaraz spadnie pocisk z wieży, traktujemy jak przeszkodę.
	for shell in sim.raids.shells:
		if int(shell["lane"]) == lane and absf(float(shell["d"]) - d) < horizon:
			return true
	for item in sim.items_between(d - behind, d + horizon):
		if item.is_wreck() and item.lane == lane:
			return true
	return false


func _best_free_lane(sim: RunSimulation, here: int, d: float, horizon: float) -> int:
	var best := here
	var best_cost := 1_000_000
	for lane in sim.lanes.lane_count:
		if _wreck_ahead(sim, lane, d, horizon):
			continue
		var cost := absi(lane - here)
		if cost < best_cost:
			best_cost = cost
			best = lane
	return best
