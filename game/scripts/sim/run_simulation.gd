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
signal near_miss(item: TrackItem)
signal crate_opened(item: TrackItem, prize: int, amount: int)
signal finished

const LOOKAHEAD_M := 260.0
const KEEP_BEHIND_M := 30.0
## Unik „o włos”: zjazd z pasa wraku najwyżej tyle sekund przed jego minięciem.
const NEAR_MISS_S := 1.3
## Nagrody ze skrzyń.
enum Prize { SCRAP_RAIN, FUEL, CHARGE, JACKPOT }

var vehicle := VehicleModel.new()
var lanes := LaneModel.new()
var generator: TrackGenerator
var expedition: Expedition
var combat: CombatModel
## Tryb wolny (etap 6): wyzwania proponowane przez grę. Domyślnie wyłączone.
var challenges := ChallengeDirector.new()
## Napady na osady (zwiad i decyzja na zjeździe). Domyślnie wyłączone.
var raids: RaidDirector
## Konwoje Tłustych: pościg, odcinanie sprzęgów, przesiadka. Domyślnie wyłączone.
var convoys: ConvoyDirector
## Układ napędowy: załoga (akcelerator) i dopalacz. Generator siedzi w VehicleModel.
var power_train := PowerTrain.new()
## Moc na kołach z ostatniego kroku [W] (moc z nóg × akceleratory × dopalacz).
var last_wheel_power_w := 0.0
## Passa (mnożnik złomu za czystą jazdę) i zlecenia (trzy cele na wyprawę).
var streak := Streak.new()
var streak_enabled := true
var contracts := ContractBoard.new()
var _left_lane_at: Dictionary = {}
var _rng := RandomNumberGenerator.new()
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
	convoys = ConvoyDirector.new(self, seed_value)
	_rng.seed = seed_value + 5501
	contracts.completed.connect(_on_contract_completed)
	contracts.all_completed.connect(func() -> void: expedition.add_fuel(ContractBoard.ALL_DONE_FUEL))
	combat.raider_destroyed.connect(func(r: RaiderModel, _dropped: int, _cause: int) -> void:
		if not r.is_convoy_part():
			_streak_add(5)
			contracts.add(ContractBoard.Kind.RAIDERS))
	combat.wreck_destroyed.connect(func(_item: TrackItem) -> void:
		_streak_add(2)
		contracts.add(ContractBoard.Kind.WRECKS))
	combat.ram_resolved.connect(func(_r: RaiderModel, outcome: int, _lost: int) -> void:
		if outcome == CombatModel.RamOutcome.HIT:
			streak.reset())
	raids.shell_landed.connect(func(_shell: Dictionary, hit: bool, blocked: bool, _lost: int) -> void:
		if hit and not blocked:
			streak.reset())
	raids.finished.connect(func(_s: Dictionary, _scrap: int, _fuel: int, repelled: bool) -> void:
		if not repelled:
			contracts.add(ContractBoard.Kind.RAID))
	convoys.mine_exploded.connect(func(_mine: Dictionary, hit: bool, blocked: bool, _lost: int) -> void:
		if hit and not blocked:
			streak.reset())
	convoys.bumped.connect(func(_squeezed: bool) -> void: streak.reset())
	convoys.finished.connect(func(_info: Dictionary, result: Dictionary) -> void:
		if int(result["outcome"]) == ConvoyDirector.Outcome.CAPTURED:
			contracts.add(ContractBoard.Kind.CONVOY))
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
	var from := lanes.target_lane
	if not lanes.request_change(direction):
		return false
	_left_lane_at[from] = expedition.elapsed_s
	return true


func step(delta: float, power_w: float) -> void:
	if expedition.finished or delta <= 0.0:
		return
	last_power_w = power_w
	# Na koła idzie moc z nóg wzmocniona przez załogę i dopalacz; trening liczy samą moc z nóg.
	power_train.step(delta)
	var drive_w := power_w * power_train.multiplier()
	last_wheel_power_w = drive_w * vehicle.engine_multiplier
	var d0 := vehicle.distance_m
	vehicle.step(delta, drive_w)
	lanes.step(delta)
	invulnerable_left_s = maxf(0.0, invulnerable_left_s - delta)
	ram_left_s = maxf(0.0, ram_left_s - delta)
	expedition.tick(delta, power_w, vehicle.speed_mps, vehicle.distance_m)
	_resolve_contacts(d0, vehicle.distance_m)
	_check_near_misses(vehicle.distance_m)
	streak.step(delta)
	expedition.best_streak = maxf(expedition.best_streak, streak.multiplier())
	_feed_contracts(delta, power_w)
	combat.step(delta, power_w)
	# Wyzwania nie nakładają się na zwiad, napad ani konwój – jedno zadanie naraz.
	if raids.state == RaidDirector.State.IDLE and not convoys.is_active():
		challenges.step(delta, expedition.elapsed_s, expedition.time_left_s(), power_w)
	raids.step(delta, power_w)
	convoys.step(delta)
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


## Łączny mnożnik mocy: generator × załoga × dopalacz.
func power_multiplier() -> float:
	return vehicle.engine_multiplier * power_train.multiplier()


## Odpala dopalacz (wtrysk czystego paliwa). False, gdy brak ładunków.
func trigger_boost() -> bool:
	if expedition.finished or not power_train.trigger():
		return false
	expedition.boosts_used += 1
	return true


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
				_streak_add(2)
				contracts.add(ContractBoard.Kind.WRECKS)
				ram_left_s = ram_cooldown_s
				if not ram_keeps_speed:
					vehicle.apply_impact(0.75)
				wreck_rammed.emit(item)
				continue
			item.consumed = true
			vehicle.apply_impact(impact_speed_factor)
			invulnerable_left_s = invulnerability_s
			streak.reset()
			var lost := expedition.lose_scrap_on_hit()
			wreck_hit.emit(item, lost)
		elif item.is_crate():
			item.consumed = true
			_open_crate(item)
		elif item.is_fuel():
			item.consumed = true
			expedition.add_fuel(item.value)
			power_train.refill(item.value)
			_streak_add(2)
			fuel_collected.emit(item)
		else:
			item.consumed = true
			expedition.add_scrap(item.value, streak.multiplier() if streak_enabled else 1.0)
			_streak_add(2 if item.value > 1 else 1)
			contracts.add(ContractBoard.Kind.SCRAP, item.value)
			scrap_collected.emit(item)


func _streak_add(amount: int) -> void:
	if streak_enabled:
		streak.add(amount)


## Unik „o włos”: wrak minięty tuż po zjechaniu z jego pasa.
func _check_near_misses(d: float) -> void:
	var behind := d - vehicle_half_length_m - wreck_half_length_m
	for item in items:
		if item.passed or item.consumed or not item.is_wreck() or item.distance_m >= behind:
			continue
		item.passed = true
		if expedition.elapsed_s - float(_left_lane_at.get(item.lane, -99.0)) <= NEAR_MISS_S and lanes.target_lane != item.lane:
			expedition.near_misses += 1
			_streak_add(3)
			contracts.add(ContractBoard.Kind.NEAR_MISS)
			near_miss.emit(item)


## Zlecenia treningowe i „osiągnij wartość” karmione co krok.
func _feed_contracts(delta: float, power_w: float) -> void:
	if contracts.contracts.is_empty():
		return
	if power_w > 20.0 and combat.band_status(power_w) == TargetBand.Status.IN_BAND:
		contracts.add(ContractBoard.Kind.IN_BAND, delta)
	if TrainingMetrics.zone_index(power_w, expedition.metrics.ftp_w) >= 2:
		contracts.add(ContractBoard.Kind.ZONE, delta)
	contracts.add(ContractBoard.Kind.KJ, maxf(power_w, 0.0) * delta / 1000.0)
	contracts.raise(ContractBoard.Kind.SPEED, vehicle.speed_kmh())
	contracts.raise(ContractBoard.Kind.STREAK, float(streak.tier()))


func _on_contract_completed(c: Dictionary) -> void:
	expedition.add_scrap(int(c["reward_scrap"]))
	expedition.add_fuel(int(c["reward_fuel"]))
	expedition.contracts_done += 1


## Skrzynia: losowa nagroda – deszcz zębatek, kanister, pełny dopalacz z tarczą albo
## złota zębatka. Niewiadoma, co wypadnie, to połowa frajdy.
func _open_crate(item: TrackItem) -> void:
	var roll := _rng.randf()
	var prize := Prize.JACKPOT
	var amount := 25
	if roll < 0.45:
		var lane := _free_lane_ahead(vehicle.distance_m + 8.0, vehicle.distance_m + 50.0)
		if lane >= 0:
			prize = Prize.SCRAP_RAIN
			amount = 10
			var rain: Array[TrackItem] = []
			for i in amount:
				rain.append(TrackItem.new(3_000_000 + item.id * 16 + i, TrackItem.Kind.SCRAP, lane, vehicle.distance_m + 12.0 + i * 3.2, 1, 0))
			add_items(rain)
	elif roll < 0.65:
		prize = Prize.FUEL
		amount = 1
		expedition.add_fuel(1)
		power_train.refill(1)
	elif roll < 0.85:
		prize = Prize.CHARGE
		amount = power_train.max_charges
		power_train.charges = power_train.max_charges
		combat.shield = 1.0
	if prize == Prize.JACKPOT:
		expedition.add_scrap(amount, streak.multiplier() if streak_enabled else 1.0)
	expedition.crates_opened += 1
	_streak_add(2)
	crate_opened.emit(item, prize, amount)


## Pas bez wraków na odcinku [from_d, to_d]; najchętniej ten, którym jedzie gracz. -1 = brak.
func _free_lane_ahead(from_d: float, to_d: float) -> int:
	var order: Array[int] = [lanes.target_lane]
	for lane in lanes.lane_count:
		if lane != lanes.target_lane:
			order.append(lane)
	for lane in order:
		var free := true
		for item in items:
			if item.is_wreck() and not item.consumed and item.lane == lane and item.distance_m >= from_d and item.distance_m <= to_d:
				free = false
				break
		if free:
			return lane
	return -1


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
