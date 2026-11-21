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
	# Konwój: z bliska trzymamy się lewego pasa (środkowy zajmuje kolumna), a przed miną
	# zrzuconą na nasz pas uciekamy na środek, póki jest na to miejsce.
	var convoy := sim.convoys
	if convoy.is_active() and convoy.galley != null and convoy.gap_m() < 34.0:
		var gap := convoy.gap_m()
		var mine_here := _mine_on(sim, here, d)
		if here != 0:
			if not _mine_on(sim, here - 1, d):
				_cooldown = cooldown_s
				return -1
		elif mine_here and gap > 14.0:
			_cooldown = cooldown_s
			return 1
		return 0
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
		if (item.is_scrap() or item.is_crate()) and item.lane != here:
			var dir := signi(item.lane - here)
			if not _wreck_ahead(sim, here + dir, d, horizon):
				_cooldown = cooldown_s
				return dir
			break
	return 0


func _mine_on(sim: RunSimulation, lane: int, d: float) -> bool:
	for mine in sim.convoys.mines:
		if int(mine["lane"]) == lane and absf(float(mine["d"]) - d) < 30.0:
			return true
	return false


## Moc, jaką autopilot chce kręcić podczas konwoju: goni, potem trzyma się okna sprzęgu
## (przyspiesza i zwalnia razem z konwojem), a na przesiadkę odpuszcza.
func convoy_power_w(sim: RunSimulation, ftp_w: float) -> float:
	var c := sim.convoys
	var hold := c.hold_power_w()
	match c.state:
		ConvoyDirector.State.CHASE:
			return ftp_w * 1.1
		ConvoyDirector.State.ENGAGED:
			var want := ConvoyDirector.window_center_m(not c.guard_attached)
			return clampf(hold + (want - c.rel_m()) * 9.0, 30.0, ftp_w * 1.6)
		ConvoyDirector.State.CAPTURE:
			if sim.vehicle.speed_mps > ConvoyDirector.BOARD_MAX_SPEED - 0.5 and c.rel_m() > -12.0:
				return 1.0
			return clampf(hold - c.rel_m() * 6.0, 1.0, ftp_w)
	return 0.0


## Dopalacz w pościgu, gdy konwój odjeżdża.
func wants_boost(sim: RunSimulation) -> bool:
	var c := sim.convoys
	var t := sim.power_train
	if t.charges <= 0 or t.is_boosting() or not c.is_active():
		return false
	return (c.state == ConvoyDirector.State.CHASE and c.gap_m() > 70.0) or (c.state == ConvoyDirector.State.ENGAGED and c.gap_m() > 55.0)


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
