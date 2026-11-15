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
var warmup_m := 150.0
var min_row_gap_m := 30.0
var min_reaction_s := 2.4
var row_gap_easy_m := 75.0
var row_gap_hard_m := 34.0
var scrap_gap_easy_m := 55.0
var scrap_gap_hard_m := 38.0
var scrap_spacing_m := 3.5
var scrap_clearance_m := 6.0
var big_scrap_chance := 0.18
var wreck_variants := 4
## Wyłączenie wraków (testy, później np. „pola bezpieczne” na ciężkich interwałach).
var wrecks_enabled := true

## Warunki ustawiane przez symulację przed generowaniem kolejnych odcinków.
var difficulty := 0.0
var speed_hint_mps := 9.0

var _rng := RandomNumberGenerator.new()
var _next_id := 1
var _generated_until_m := 0.0
var _next_row_m := 0.0
var _next_scrap_m := 0.0
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
	while _next_scrap_m < distance_m:
		_place_scrap_line(_next_scrap_m, out)
		_next_scrap_m += _scrap_gap()
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


func _place_scrap_line(d: float, out: Array[TrackItem]) -> void:
	var count := _rng.randi_range(3, 5)
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
