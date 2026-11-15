class_name WorkoutPlan
extends RefCounted
## Plan treningowy: uporządkowana lista kroków (powtórzenia już rozwinięte) z celem mocy
## jako ułamkiem FTP. Czysta logika – gra pyta plan o cel w danej sekundzie wyprawy.
##
## Czas t liczony od początku planu w sekundach. Krok i trwa [start_i, start_i + duration_i);
## t < 0 traktujemy jak 0, po końcu planu step_index_at zwraca -1, a cel wynosi 0.

## Krok ciężki: rodzaj WORK albo średni cel od tylu FTP (patrz is_hard_step).
const HARD_THRESHOLD := WorkoutStep.HARD_THRESHOLD
## Próg mocy (FTP) do liczenia czasu „powyżej progu” w summary().
const THRESHOLD := 1.0
## Jazdę swobodną (bez celu) do szacunków w summary() liczymy jak 60% FTP.
const FREERIDE_ESTIMATE := 0.6
## Okno średniej kroczącej (s) w szacunku mocy znormalizowanej (jak w NP).
const NP_WINDOW_S := 30

var name: String = ""
var description: String = ""
## Format źródłowy: "json" | "zwo" | "fit".
var source_format: String = ""
## Ścieżka pliku, z którego wczytano plan (pusta, gdy z tekstu/bajtów).
var source_path: String = ""
## FTP (W), którym przeliczono waty z pliku na ułamki FTP; 0 = plan od początku względny.
var reference_ftp: float = 0.0
var steps: Array[WorkoutStep] = []


func add_step(step: WorkoutStep) -> void:
	steps.append(step)


func step_count() -> int:
	return steps.size()


func is_empty() -> bool:
	return steps.is_empty()


func total_duration_s() -> float:
	var total := 0.0
	for s in steps:
		total += s.duration_s
	return total


## Indeks kroku trwającego w chwili t; -1 po końcu planu (i dla pustego planu).
func step_index_at(t: float) -> int:
	var tt := maxf(t, 0.0)
	var end := 0.0
	for i in steps.size():
		end += steps[i].duration_s
		if tt < end:
			return i
	return -1


## Początek kroku (s od startu planu). Indeks spoza zakresu przycinany: <0 -> 0, >= liczby kroków -> koniec planu.
func step_start_s(index: int) -> float:
	var start := 0.0
	for i in clampi(index, 0, steps.size()):
		start += steps[i].duration_s
	return start


func step_end_s(index: int) -> float:
	if index < 0 or index >= steps.size():
		return step_start_s(index)
	return step_start_s(index) + steps[index].duration_s


## Krok trwający w chwili t albo null po końcu planu.
func step_at(t: float) -> WorkoutStep:
	var i := step_index_at(t)
	return steps[i] if i >= 0 else null


## Ile sekund minęło od początku bieżącego kroku (0 po końcu planu).
func time_in_step_s(t: float) -> float:
	var i := step_index_at(t)
	return maxf(t, 0.0) - step_start_s(i) if i >= 0 else 0.0


## Ile sekund zostało do końca bieżącego kroku (0 po końcu planu).
func time_left_in_step_s(t: float) -> float:
	var i := step_index_at(t)
	return step_end_s(i) - maxf(t, 0.0) if i >= 0 else 0.0


## Cel w chwili t jako ułamek FTP; 0 po końcu planu i w jeździe swobodnej (= ERG wyłączony).
func intensity_at(t: float) -> float:
	var tt := maxf(t, 0.0)
	var start := 0.0
	for s in steps:
		var end := start + s.duration_s
		if tt < end:
			return s.target_fraction_at(tt - start) if s.kind != WorkoutStep.Kind.FREERIDE else 0.0
		start = end
	return 0.0


## Cel w watach dla danego FTP gracza (0 = brak celu).
func target_watts_at(t: float, ftp: float) -> float:
	return intensity_at(t) * maxf(ftp, 0.0)


## Krok ciężki: rodzaj WORK albo średni cel >= HARD_THRESHOLD (0.88 FTP). Jazda swobodna nigdy.
func is_hard_step(index: int) -> bool:
	if index < 0 or index >= steps.size():
		return false
	var s := steps[index]
	if s.kind == WorkoutStep.Kind.FREERIDE:
		return false
	return s.kind == WorkoutStep.Kind.WORK or s.average_fraction() >= HARD_THRESHOLD - 1e-9


## Indeks najbliższego ciężkiego kroku od from_index włącznie; -1, gdy już nie ma.
func next_hard_step(from_index: int) -> int:
	for i in range(maxi(from_index, 0), steps.size()):
		if is_hard_step(i):
			return i
	return -1


## Ciężkie odcinki planu – ciągi sąsiednich ciężkich kroków (np. do zamiany na burzę piaskową,
## podjazd albo pościg). Każdy: {"first": indeks pierwszego kroku, "last": indeks ostatniego,
## "start_s": początek (s), "end_s": koniec (s)}.
func hard_blocks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var start := 0.0
	for i in steps.size():
		var end := start + steps[i].duration_s
		if is_hard_step(i):
			if not out.is_empty() and int(out[-1]["last"]) == i - 1:
				out[-1]["last"] = i
				out[-1]["end_s"] = end
			else:
				out.append({"first": i, "last": i, "start_s": start, "end_s": end})
		start = end
	return out


## Podsumowanie planu (do listy planów i ekranu startowego):
##   duration_s              – łączny czas (s)
##   step_count              – liczba kroków po rozwinięciu powtórzeń
##   hard_intervals          – liczba ciężkich interwałów (ciągi sąsiednich ciężkich kroków liczone raz)
##   hard_time_s             – czas w ciężkich krokach (s)
##   time_above_threshold_s  – czas z celem >= 100% FTP (s), dla ramp liczony dokładnie
##   freeride_s              – czas jazdy swobodnej (s)
##   max_intensity           – najwyższy cel (ułamek FTP)
##   avg_intensity           – średni cel ważony czasem (jazda swobodna jako FREERIDE_ESTIMATE)
##   intensity_factor        – szacunek IF: moc znormalizowana planu / FTP (średnia krocząca 30 s,
##                             średnia potęg czwartych, pierwiastek czwartego stopnia – jak NP)
##   tss                     – szacunek TSS = godziny * IF^2 * 100
func summary() -> Dictionary:
	var total := total_duration_s()
	var hard_time := 0.0
	var above := 0.0
	var freeride := 0.0
	var max_intensity := 0.0
	var weighted := 0.0
	for i in steps.size():
		var s := steps[i]
		if is_hard_step(i):
			hard_time += s.duration_s
		if s.kind == WorkoutStep.Kind.FREERIDE:
			freeride += s.duration_s
			weighted += FREERIDE_ESTIMATE * s.duration_s
			continue
		weighted += s.average_fraction() * s.duration_s
		above += _time_at_or_above(s, THRESHOLD)
		max_intensity = maxf(max_intensity, s.max_fraction())
	var intensity_factor := _normalized_fraction()
	return {
		"duration_s": total,
		"step_count": steps.size(),
		"hard_intervals": hard_blocks().size(),
		"hard_time_s": hard_time,
		"time_above_threshold_s": above,
		"freeride_s": freeride,
		"max_intensity": max_intensity,
		"avg_intensity": weighted / total if total > 0.0 else 0.0,
		"intensity_factor": intensity_factor,
		"tss": total / 3600.0 * intensity_factor * intensity_factor * 100.0,
	}


## Plan w naszym formacie JSON (powtórzenia zapisane jako rozwinięte kroki). Do zapisu
## zaimportowanych planów (np. z Garmina) i testów; parse_json(JSON.stringify(...)) daje ten sam plan.
func to_json_dict() -> Dictionary:
	var out_steps: Array = []
	for s in steps:
		out_steps.append(s.to_dict())
	var d := {"name": name, "steps": out_steps}
	if description != "":
		d["description"] = description
	return d


## Wielowierszowy opis planu do logów i testów.
func describe() -> String:
	var lines: Array[String] = ["%s (%s, %s)" % [name, source_format, WorkoutStep.format_duration(total_duration_s())]]
	for i in steps.size():
		lines.append("  %2d. %s" % [i + 1, steps[i].describe()])
	return "\n".join(lines)


## Czas kroku z celem >= level; rampa przecina próg liniowo.
static func _time_at_or_above(s: WorkoutStep, level: float) -> float:
	var a := s.power_start
	var b := s.power_end
	if a >= level and b >= level:
		return s.duration_s
	if a < level and b < level:
		return 0.0
	return s.duration_s * (maxf(a, b) - level) / absf(b - a)


## Moc znormalizowana planu jako ułamek FTP: próbki co 1 s, średnia krocząca NP_WINDOW_S,
## średnia czwartych potęg i pierwiastek czwartego stopnia. Krótszy plan: bez średniej kroczącej.
func _normalized_fraction() -> float:
	var total := total_duration_s()
	if total <= 0.0 or steps.is_empty():
		return 0.0
	var n := maxi(1, int(total))
	var samples := PackedFloat64Array()
	samples.resize(n)
	var step_i := 0
	var step_start := 0.0
	for k in n:
		var t := minf(k + 0.5, total - 1e-6)
		while step_i < steps.size() - 1 and t >= step_start + steps[step_i].duration_s:
			step_start += steps[step_i].duration_s
			step_i += 1
		var s := steps[step_i]
		samples[k] = FREERIDE_ESTIMATE if s.kind == WorkoutStep.Kind.FREERIDE else s.target_fraction_at(t - step_start)
	var acc := 0.0
	var count := 0
	if n < NP_WINDOW_S:
		for v in samples:
			acc += pow(v, 4.0)
		return pow(acc / n, 0.25)
	var window := 0.0
	for k in n:
		window += samples[k]
		if k >= NP_WINDOW_S:
			window -= samples[k - NP_WINDOW_S]
		if k >= NP_WINDOW_S - 1:
			acc += pow(window / NP_WINDOW_S, 4.0)
			count += 1
	return pow(acc / count, 0.25)
