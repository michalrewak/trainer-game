class_name RunSimulation
extends RefCounted
## Cała pętla wyprawy bez węzłów i bez silnika fizyki: pojazd, pasy, trasa, kolizje,
## złom i czas. Widok (RunController + widoki 3D) tylko ją rysuje, więc całą rozgrywkę
## da się przetestować headless.
##
## Kolizje liczone są „przemiataniem” po dystansie (od pozycji z poprzedniego kroku do
## bieżącej), więc nie da się przeskoczyć wraku nawet przy dużym kroku czasu.

signal wreck_hit(item: TrackItem, scrap_lost: int)
signal scrap_collected(item: TrackItem)
signal fuel_collected(item: TrackItem)
signal wreck_rammed(item: TrackItem)
signal finished

const LOOKAHEAD_M := 260.0
const KEEP_BEHIND_M := 30.0

var vehicle := VehicleModel.new()
var lanes := LaneModel.new()
var generator: TrackGenerator
var expedition: Expedition
var combat: CombatModel
## Tryb wolny (etap 6): wyzwania proponowane przez grę. Domyślnie wyłączone.
var challenges := ChallengeDirector.new()
## Napady na osady (zwiad i decyzja na zjeździe). Domyślnie wyłączone.
var raids: RaidDirector
## Wzniesienia i doliny (CourseProfile). W grze włączone, w czystej symulacji domyślnie płasko.
var course: CourseProfile
var course_enabled := false
var items: Array[TrackItem] = []

var impact_speed_factor := 0.35
var invulnerability_s := 1.2
var vehicle_half_length_m := 1.2
var vehicle_half_width_m := 0.95
var wreck_half_length_m := 1.6
var wreck_half_width_m := 1.3
var scrap_half_length_m := 0.9
var scrap_half_width_m := 1.2

## Taran (moduł): czas ładowania [s]; 0 = brak. Naładowany rozbija wrak bez straty złomu.
var ram_cooldown_s := 0.0
var ram_keeps_speed := false
var ram_left_s := 0.0

var invulnerable_left_s := 0.0
var last_power_w := 0.0
## Teren wyprawy (TerrainCatalog) – widok dobiera do niego wygląd.
var terrain := "canyon"


func _init(duration_s: float = 900.0, seed_value: int = 0) -> void:
	expedition = Expedition.new(duration_s)
	generator = TrackGenerator.new(seed_value, lanes.lane_count)
	combat = CombatModel.new(self, seed_value)
	course = CourseProfile.new(seed_value)
	raids = RaidDirector.new(self, seed_value)
	challenges.enabled = false
	challenges.finished.connect(_on_challenge_finished)
	_refill()


## Pole bezpieczne (etap 4, ciężkie interwały): znikają wraki przed pojazdem, nowe się nie
## pojawiają, gang odpuszcza – można tylko pedałować, bez klikania. Po wyłączeniu nowe wraki
## pojawiają się dopiero na krawędzi generowania (daleko przed graczem), bez zaskoczeń.
var safe_zone := false


func set_safe_zone(enabled: bool) -> void:
	if enabled == safe_zone:
		return
	safe_zone = enabled
	generator.wrecks_enabled = not enabled
	combat.suppressed = enabled
	if enabled:
		var d := vehicle.distance_m
		var kept: Array[TrackItem] = []
		for item in items:
			if item.is_wreck() and not item.consumed and item.distance_m > d - 3.0:
				continue
			kept.append(item)
		items = kept


## Nagroda albo kara za wyzwanie trybu wolnego. Porażka ucieczki = gang dogania gracza.
func _on_challenge_finished(challenge: Dictionary, success: bool) -> void:
	if success:
		expedition.add_scrap(int(challenge.get("reward_scrap", 0)))
		expedition.add_fuel(int(challenge.get("reward_fuel", 0)))
		expedition.challenges_completed += 1
	elif int(challenge.get("kind", -1)) == ChallengeDirector.Kind.ESCAPE and combat.enabled:
		combat.spawn_raider(-1)
		combat.spawn_raider(1)


## Dodatkowe obiekty na trasie (np. złom wypadający z rozbitego wroga).
func add_items(new_items: Array[TrackItem]) -> void:
	items.append_array(new_items)


func request_lane_change(direction: int) -> bool:
	if expedition.finished:
		return false
	return lanes.request_change(direction)


func step(delta: float, power_w: float) -> void:
	if expedition.finished or delta <= 0.0:
		return
	last_power_w = power_w
	var d0 := vehicle.distance_m
	vehicle.step(delta, power_w)
	lanes.step(delta)
	invulnerable_left_s = maxf(0.0, invulnerable_left_s - delta)
	ram_left_s = maxf(0.0, ram_left_s - delta)
	expedition.tick(delta, power_w, vehicle.speed_mps, vehicle.distance_m)
	_resolve_contacts(d0, vehicle.distance_m)
	combat.step(delta, power_w)
	# Wyzwania nie nakładają się na zwiad i napad – jedno zadanie naraz.
	if raids.state == RaidDirector.State.IDLE:
		challenges.step(delta, expedition.elapsed_s, expedition.time_left_s(), power_w)
	raids.step(delta, power_w)
	vehicle.grade = current_grade()
	generator.difficulty = expedition.progress()
	generator.speed_hint_mps = maxf(vehicle.speed_mps, 8.0)
	_refill()
	_prune()
	if expedition.finished:
		finished.emit()


## Nachylenie w tej chwili: podjazd z wyzwania ma pierwszeństwo, potem ukształtowanie trasy.
func current_grade() -> float:
	if challenges.enabled and challenges.grade_percent() > 0.0:
		return challenges.grade_percent() / 100.0
	if course_enabled:
		return course.grade_at(vehicle.distance_m)
	return 0.0


func ram_ready() -> bool:
	return ram_cooldown_s > 0.0 and ram_left_s <= 0.0


func is_invulnerable() -> bool:
	return invulnerable_left_s > 0.0


func lane_x(lane: int) -> float:
	return lanes.lane_center(lane)


## Obiekty w zasięgu [from_d, to_d] (nie skonsumowane), np. dla autopilota.
func items_between(from_d: float, to_d: float) -> Array[TrackItem]:
	var out: Array[TrackItem] = []
	for item in items:
		if not item.consumed and item.distance_m >= from_d and item.distance_m <= to_d:
			out.append(item)
	return out


func _resolve_contacts(d0: float, d1: float) -> void:
	var x := lanes.x_m
	for item in items:
		if item.consumed:
			continue
		var half_len := wreck_half_length_m if item.is_wreck() else scrap_half_length_m
		var half_w := wreck_half_width_m if item.is_wreck() else scrap_half_width_m
		if item.distance_m + half_len < d0 - vehicle_half_length_m:
			continue
		if item.distance_m - half_len > d1 + vehicle_half_length_m:
			continue
		if absf(lane_x(item.lane) - x) > half_w + vehicle_half_width_m:
			continue
		if item.is_wreck():
			if is_invulnerable():
				continue
			if ram_ready():
				item.consumed = true
				ram_left_s = ram_cooldown_s
				if not ram_keeps_speed:
					vehicle.apply_impact(0.75)
				wreck_rammed.emit(item)
				continue
			item.consumed = true
			vehicle.apply_impact(impact_speed_factor)
			invulnerable_left_s = invulnerability_s
			var lost := expedition.lose_scrap_on_hit()
			wreck_hit.emit(item, lost)
		elif item.is_fuel():
			item.consumed = true
			expedition.add_fuel(item.value)
			fuel_collected.emit(item)
		else:
			item.consumed = true
			expedition.add_scrap(item.value)
			scrap_collected.emit(item)


func _refill() -> void:
	var target := vehicle.distance_m + LOOKAHEAD_M
	if target > generator.generated_until():
		items.append_array(generator.generate_until(target))


func _prune() -> void:
	var limit := vehicle.distance_m - KEEP_BEHIND_M
	var kept: Array[TrackItem] = []
	for item in items:
		if item.distance_m >= limit:
			kept.append(item)
	if kept.size() != items.size():
		items = kept
