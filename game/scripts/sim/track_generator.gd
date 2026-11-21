class_name TrackGenerator
extends RefCounted
## Generator zawartości nieskończonej trasy (wraki i złom) – czysta logika, deterministyczna
## dla danego ziarna i sekwencji warunków. Gwarancje uczciwości:
## - w każdym rzędzie wraków co najmniej jeden pas jest wolny,
## - odstęp między rzędami >= max(min_row_gap_m, prędkość * min_reaction_s),
## - złom nigdy nie leży na wraku (min. odstęp scrap_clearance_m w tym samym pasie),
## - pierwsze warmup_m metrów jest bez wraków.
## Trudność 0..1 (postęp wyprawy) zagęszcza rzędy i częściej blokuje dwa pasy.

var lane_count := 3
var lane_width_m := 3.6
var warmup_m := 150.0
var min_row_gap_m := 30.0
var min_reaction_s := 2.4
var row_gap_easy_m := 75.0
var row_gap_hard_m := 34.0
var scrap_gap_easy_m := 78.0
var scrap_gap_hard_m := 56.0
var scrap_spacing_m := 3.5
var scrap_clearance_m := 6.0
var big_scrap_chance := 0.18
var wreck_variants := 4
## Wyłączenie wraków (testy, później np. „pola bezpieczne” na ciężkich interwałach).
var wrecks_enabled := true
## Wyłączenie złomu, paliwa i skrzyń (testy, które liczą łup co do sztuki).
var pickups_enabled := true
## Kanister paliwa średnio co tyle metrów (etap 3: druga waluta).
var fuel_every_m := 420.0
## Skrzynia z niespodzianką średnio co tyle metrów.
var crate_every_m := 600.0

## Warunki ustawiane przez symulację przed generowaniem kolejnych odcinków.
var difficulty := 0.0
var speed_hint_mps := 9.0

var _rng := RandomNumberGenerator.new()
var _next_id := 1
var _generated_until_m := 0.0
var _next_row_m := 0.0
var _next_scrap_m := 0.0
var _next_fuel_m := 260.0
var _next_crate_m := 380.0
## Rzędy wraków: [{d, blocked: Array[int]}] – do omijania przy rozmieszczaniu złomu.
var _rows: Array[Dictionary] = []


func _init(p_seed: int = 0, p_lane_count: int = 3) -> void:
	lane_count = p_lane_count
	_rng.seed = p_seed
	_next_row_m = warmup_m + _rng.randf_range(0.0, 20.0)
	_next_scrap_m = 25.0


func generated_until() -> float:
	return _generated_until_m


## Generuje obiekty co najmniej do podanego dystansu. Zwraca nowe obiekty posortowane po
## dystansie. Rzędy wraków powstają ROW_LOOKAHEAD_M dalej niż złom, żeby linia złomu
## nigdy nie wpadła na wrak wygenerowany później.
const ROW_LOOKAHEAD_M := 40.0

func generate_until(distance_m: float) -> Array[TrackItem]:
	var out: Array[TrackItem] = []
	if distance_m <= _generated_until_m:
		return out
	while _next_row_m < distance_m + ROW_LOOKAHEAD_M:
		_place_row(_next_row_m, out)
		_next_row_m += _row_gap()
	if not pickups_enabled:
		_next_scrap_m = maxf(_next_scrap_m, distance_m)
		_next_fuel_m = maxf(_next_fuel_m, distance_m)
		_next_crate_m = maxf(_next_crate_m, distance_m)
	while _next_scrap_m < distance_m:
		_place_scrap(_next_scrap_m, out)
		_next_scrap_m += _scrap_gap()
	while _next_fuel_m < distance_m:
		_place_fuel(_next_fuel_m, out)
		_next_fuel_m += fuel_every_m * _rng.randf_range(0.7, 1.3)
	while _next_crate_m < distance_m:
		_place_single(TrackItem.Kind.CRATE, _next_crate_m, out)
		_next_crate_m += crate_every_m * _rng.randf_range(0.7, 1.3)
	_generated_until_m = distance_m
	out.sort_custom(func(a: TrackItem, b: TrackItem) -> bool: return a.distance_m < b.distance_m)
	_forget_rows_before(distance_m - 400.0)
	return out


func _row_gap() -> float:
	var mean := lerpf(row_gap_easy_m, row_gap_hard_m, clampf(difficulty, 0.0, 1.0))
	var gap := mean * _rng.randf_range(0.8, 1.25)
	return maxf(gap, maxf(min_row_gap_m, speed_hint_mps * min_reaction_s))


func _scrap_gap() -> float:
	var mean := lerpf(scrap_gap_easy_m, scrap_gap_hard_m, clampf(difficulty, 0.0, 1.0))
	return mean * _rng.randf_range(0.7, 1.3)


func _place_row(d: float, out: Array[TrackItem]) -> void:
	if not wrecks_enabled:
		return
	var two_lanes_chance := lerpf(0.2, 0.6, clampf(difficulty, 0.0, 1.0))
	var blocked_count := 2 if _rng.randf() < two_lanes_chance else 1
	blocked_count = mini(blocked_count, lane_count - 1)
	var lanes: Array[int] = []
	for lane in lane_count:
		lanes.append(lane)
	_shuffle(lanes)
	var blocked: Array[int] = lanes.slice(0, blocked_count)
	for lane in blocked:
		var variant := _rng.randi_range(0, wreck_variants - 1)
		out.append(_make(TrackItem.Kind.WRECK, lane, d, 0, variant))
	_rows.append({"d": d, "blocked": blocked})
	# Ryzyko za nagrodę: duży złom tuż za wrakiem – trzeba ominąć i szybko wrócić.
	if _rng.randf() < big_scrap_chance:
		var lane: int = blocked[_rng.randi_range(0, blocked.size() - 1)]
		var big_d := d + 9.0
		if not _blocked_near(lane, big_d, scrap_clearance_m):
			out.append(_make(TrackItem.Kind.SCRAP_BIG, lane, big_d, 5, 0))


## Złom nie leży „za darmo” na środku pasa. Układy:
## - PRZESMYK: tuż obok wraku, od jego strony – trzeba przejechać o włos (cenniejszy),
## - SLALOM: wężyk między dwoma pasami – trzeba płynnie kierować,
## - KRAWĘDŹ: przy samym skraju jezdni (cenniejszy),
## - LINIA: krótki rząd na pasie (zostaje dla jazdy krzyżakiem i klawiaturą).
func _place_scrap(d: float, out: Array[TrackItem]) -> void:
	var roll := _rng.randf()
	if roll < 0.26 and _place_squeeze(d, out):
		return
	if roll < 0.6:
		_place_weave(d, out)
	elif roll < 0.82:
		_place_edge(d, out)
	else:
		_place_scrap_line(d, out)


func _center(lane: int) -> float:
	return (lane - (lane_count - 1) * 0.5) * lane_width_m


## Kawałek złomu w dowolnym miejscu w poprzek jezdni (x w metrach od środka).
func _scrap_at(x: float, d: float, value: int, out: Array[TrackItem]) -> void:
	var lane := clampi(roundi(x / lane_width_m + (lane_count - 1) * 0.5), 0, lane_count - 1)
	var offset := x - _center(lane)
	if _blocked_near(lane, d, scrap_clearance_m):
		return
	# Między pasami: obok nie może stać wrak.
	var neighbor := lane + (1 if offset > 0.0 else -1)
	if absf(offset) > 0.9 and neighbor >= 0 and neighbor < lane_count and _blocked_near(neighbor, d, scrap_clearance_m):
		return
	var item := _make(TrackItem.Kind.SCRAP, lane, d, value, 0)
	item.offset_x = offset
	out.append(item)


func _place_weave(d: float, out: Array[TrackItem]) -> void:
	var a := _rng.randi_range(0, lane_count - 2)
	var mid := (_center(a) + _center(a + 1)) * 0.5
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	for i in 7:
		_scrap_at(mid + side * lane_width_m * 0.5 * cos(PI * i / 3.0), d + i * 4.5, 1, out)


func _place_edge(d: float, out: Array[TrackItem]) -> void:
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	# Na samej linii krawędzi: ze środka skrajnego pasa się nie sięgnie.
	var x := _center(0 if side < 0.0 else lane_count - 1) + side * 2.0
	for i in 4:
		_scrap_at(x, d + i * 3.5, 2, out)


## Złom w przesmyku: na wolnym pasie, dociśnięty do wraku stojącego obok. False, gdy
## w pobliżu nie ma pasującego rzędu wraków.
func _place_squeeze(d: float, out: Array[TrackItem]) -> bool:
	for row in _rows:
		var rd: float = row["d"]
		if rd < d or rd > d + 30.0:
			continue
		var blocked: Array = row["blocked"]
		for lane in lane_count:
			if blocked.has(lane):
				continue
			for dir: int in [-1, 1]:
				if blocked.has(lane + dir):
					for k in 3:
						var item := _make(TrackItem.Kind.SCRAP, lane, rd + (k - 1) * 3.5, 2, 0)
						item.offset_x = dir * 1.6
						out.append(item)
					return true
	return false


func _place_scrap_line(d: float, out: Array[TrackItem]) -> void:
	var count := _rng.randi_range(3, 4)
	var length := (count - 1) * scrap_spacing_m
	var candidates: Array[int] = []
	for lane in lane_count:
		if not _blocked_between(lane, d - scrap_clearance_m, d + length + scrap_clearance_m):
			candidates.append(lane)
	if candidates.is_empty():
		return
	var lane: int = candidates[_rng.randi_range(0, candidates.size() - 1)]
	for i in count:
		out.append(_make(TrackItem.Kind.SCRAP, lane, d + i * scrap_spacing_m, 1, 0))


func _place_fuel(d: float, out: Array[TrackItem]) -> void:
	var candidates: Array[int] = []
	for lane in lane_count:
		if not _blocked_near(lane, d, scrap_clearance_m):
			candidates.append(lane)
	if candidates.is_empty():
		return
	out.append(_make(TrackItem.Kind.FUEL, candidates[_rng.randi_range(0, candidates.size() - 1)], d, 1, 0))


## Pojedynczy obiekt (np. skrzynia) na pasie bez wraku w pobliżu.
func _place_single(kind: TrackItem.Kind, d: float, out: Array[TrackItem]) -> void:
	var candidates: Array[int] = []
	for lane in lane_count:
		if not _blocked_near(lane, d, scrap_clearance_m):
			candidates.append(lane)
	if candidates.is_empty():
		return
	out.append(_make(kind, candidates[_rng.randi_range(0, candidates.size() - 1)], d, 1, 0))


func _make(kind: TrackItem.Kind, lane: int, d: float, value: int, variant: int) -> TrackItem:
	var item := TrackItem.new(_next_id, kind, lane, d, value, variant)
	_next_id += 1
	return item


func _blocked_near(lane: int, d: float, clearance: float) -> bool:
	return _blocked_between(lane, d - clearance, d + clearance)


## Czy w danym pasie stoi wrak w przedziale [from_d, to_d].
func _blocked_between(lane: int, from_d: float, to_d: float) -> bool:
	for row in _rows:
		var rd: float = row["d"]
		if rd >= from_d and rd <= to_d and (row["blocked"] as Array).has(lane):
			return true
	return false


func _forget_rows_before(d: float) -> void:
	while not _rows.is_empty() and float(_rows[0]["d"]) < d:
		_rows.pop_front()


func _shuffle(arr: Array[int]) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
