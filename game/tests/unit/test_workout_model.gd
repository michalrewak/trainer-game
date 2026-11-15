extends TestCase
## Model planu treningowego: kroki, oś czasu, cele, ciężkie kroki, podsumowanie.

const K := WorkoutStep.Kind


func _plan(steps: Array[WorkoutStep]) -> WorkoutPlan:
	var p := WorkoutPlan.new()
	for s in steps:
		p.add_step(s)
	return p


## 60 s rozgrzewki 50->70%, 30 s pracy 110%, 30 s regeneracji 50%, 60 s jazdy swobodnej.
func _sample() -> WorkoutPlan:
	return _plan([
		WorkoutStep.new(K.WARMUP, 60.0, 0.5, 0.7),
		WorkoutStep.new(K.WORK, 30.0, 1.1, -1.0, 95.0, "Pościg"),
		WorkoutStep.new(K.RECOVERY, 30.0, 0.5),
		WorkoutStep.new(K.FREERIDE, 60.0),
	])


func test_steady_and_ramp_targets() -> void:
	var steady := WorkoutStep.new(K.WORK, 240.0, 1.05)
	assert_false(steady.is_ramp(), "krok stały")
	assert_near(steady.power_end, 1.05, 1e-9, "power_end = power_start")
	assert_near(steady.target_fraction_at(0.0), 1.05, 1e-9)
	assert_near(steady.target_fraction_at(239.0), 1.05, 1e-9)
	var ramp := WorkoutStep.new(K.WARMUP, 600.0, 0.5, 0.75)
	assert_true(ramp.is_ramp(), "rampa")
	assert_near(ramp.target_fraction_at(0.0), 0.5, 1e-9, "początek rampy")
	assert_near(ramp.target_fraction_at(300.0), 0.625, 1e-9, "połowa rampy")
	assert_near(ramp.target_fraction_at(600.0), 0.75, 1e-9, "koniec rampy")
	assert_near(ramp.target_fraction_at(-10.0), 0.5, 1e-9, "czas przed krokiem przycięty")
	assert_near(ramp.target_fraction_at(900.0), 0.75, 1e-9, "czas po kroku przycięty")
	var down := WorkoutStep.new(K.COOLDOWN, 100.0, 0.65, 0.45)
	assert_near(down.target_fraction_at(25.0), 0.6, 1e-9, "rampa w dół")
	assert_near(down.average_fraction(), 0.55, 1e-9)
	assert_near(down.max_fraction(), 0.65, 1e-9)
	assert_near(WorkoutStep.new(K.WORK, 0.0, 0.8).target_fraction_at(5.0), 0.8, 1e-9, "krok zerowy nie dzieli przez zero")


func test_step_helpers() -> void:
	assert_eq(WorkoutStep.kind_from_name("WORK"), K.WORK, "nazwa bez wielkości liter")
	assert_eq(WorkoutStep.kind_from_name(" freeride "), K.FREERIDE)
	assert_eq(WorkoutStep.kind_from_name("sprint"), -1, "nieznana nazwa")
	assert_eq(WorkoutStep.kind_for_power(0.88), K.WORK, "próg ciężkiego kroku")
	assert_eq(WorkoutStep.kind_for_power(0.87), K.STEADY)
	assert_eq(WorkoutStep.kind_for_power(0.5), K.STEADY, "bez allow_recovery nie ma regeneracji")
	assert_eq(WorkoutStep.kind_for_power(0.55, true), K.RECOVERY)
	assert_eq(WorkoutStep.kind_for_power(0.56, true), K.STEADY)
	assert_eq(WorkoutStep.format_duration(0.0), "0:00")
	assert_eq(WorkoutStep.format_duration(65.4), "1:05")
	assert_eq(WorkoutStep.format_duration(5400.0), "1:30:00")
	assert_eq(WorkoutStep.format_duration(-3.0), "0:00")
	var work := WorkoutStep.new(K.WORK, 240.0, 1.05, -1.0, 95.0, "Burza")
	assert_true(work.has_target())
	assert_false(WorkoutStep.new(K.FREERIDE, 60.0).has_target(), "jazda swobodna bez celu")
	assert_false(WorkoutStep.new(K.STEADY, 60.0, 0.0).has_target(), "cel 0 = brak celu")
	assert_eq(work.display_label(), "Burza")
	assert_eq(WorkoutStep.new(K.RECOVERY, 60.0, 0.5).display_label(), "Regeneracja", "bez etykiety nazwa rodzaju")
	assert_eq(work.describe(), "work 4:00 105% @95 rpm \"Burza\"")
	assert_eq(WorkoutStep.new(K.WARMUP, 600.0, 0.5, 0.75).describe(), "warmup 10:00 50→75%")
	var copy := work.copy()
	copy.duration_s = 10.0
	copy.label = "Inny"
	assert_near(work.duration_s, 240.0, 1e-9, "kopia jest niezależna")
	assert_eq(work.label, "Burza")
	assert_near(copy.power_start, 1.05, 1e-9, "kopia ma te same cele")
	var clamped := WorkoutStep.new(K.WORK, -5.0, -1.0)
	assert_near(clamped.duration_s, 0.0, 1e-9, "ujemny czas -> 0")
	assert_near(clamped.power_start, 0.0, 1e-9, "ujemna moc -> 0")


func test_timeline_and_boundaries() -> void:
	var p := _sample()
	assert_eq(p.step_count(), 4)
	assert_near(p.total_duration_s(), 180.0, 1e-9)
	assert_eq(p.step_index_at(0.0), 0)
	assert_eq(p.step_index_at(59.999), 0)
	assert_eq(p.step_index_at(60.0), 1, "granica należy do następnego kroku")
	assert_eq(p.step_index_at(119.0), 2)
	assert_eq(p.step_index_at(179.9), 3)
	assert_eq(p.step_index_at(180.0), -1, "po końcu planu")
	assert_eq(p.step_index_at(1e9), -1)
	assert_eq(p.step_index_at(-5.0), 0, "przed startem jak t = 0")
	assert_near(p.step_start_s(0), 0.0, 1e-9)
	assert_near(p.step_start_s(2), 90.0, 1e-9)
	assert_near(p.step_start_s(-3), 0.0, 1e-9, "indeks ujemny przycięty")
	assert_near(p.step_start_s(99), 180.0, 1e-9, "indeks za końcem = koniec planu")
	assert_near(p.step_end_s(1), 90.0, 1e-9)
	assert_near(p.time_in_step_s(75.0), 15.0, 1e-9)
	assert_near(p.time_left_in_step_s(75.0), 15.0, 1e-9)
	assert_near(p.time_in_step_s(500.0), 0.0, 1e-9)
	assert_true(p.step_at(70.0) == p.steps[1], "step_at")
	assert_true(p.step_at(200.0) == null, "po końcu brak kroku")
	var empty := WorkoutPlan.new()
	assert_true(empty.is_empty())
	assert_eq(empty.step_index_at(0.0), -1, "pusty plan")
	assert_near(empty.intensity_at(0.0), 0.0, 1e-9)
	assert_near(empty.total_duration_s(), 0.0, 1e-9)


func test_targets_in_watts() -> void:
	var p := _sample()
	assert_near(p.intensity_at(30.0), 0.6, 1e-9, "środek rampy rozgrzewki")
	assert_near(p.target_watts_at(30.0, 250.0), 150.0, 1e-6)
	assert_near(p.intensity_at(70.0), 1.1, 1e-9)
	assert_near(p.target_watts_at(70.0, 300.0), 330.0, 1e-6)
	assert_near(p.intensity_at(100.0), 0.5, 1e-9)
	assert_near(p.intensity_at(150.0), 0.0, 1e-9, "jazda swobodna: brak celu (ERG wyłączony)")
	assert_near(p.target_watts_at(150.0, 250.0), 0.0, 1e-9)
	assert_near(p.intensity_at(180.0), 0.0, 1e-9, "po końcu brak celu")
	assert_near(p.target_watts_at(70.0, -100.0), 0.0, 1e-9, "ujemne FTP -> 0")
	assert_near(p.intensity_at(-1.0), 0.5, 1e-9, "przed startem jak t = 0")


func test_hard_steps() -> void:
	var p := _plan([
		WorkoutStep.new(K.WORK, 60.0, 0.6),
		WorkoutStep.new(K.STEADY, 60.0, 0.9),
		WorkoutStep.new(K.STEADY, 60.0, 0.85),
		WorkoutStep.new(K.RECOVERY, 60.0, 0.5),
		WorkoutStep.new(K.FREERIDE, 60.0),
		WorkoutStep.new(K.WARMUP, 60.0, 0.6, 1.2),
		WorkoutStep.new(K.STEADY, 60.0, 0.75, 1.0),
	])
	assert_true(p.is_hard_step(0), "WORK zawsze ciężki")
	assert_true(p.is_hard_step(1), "0.9 FTP ciężki")
	assert_false(p.is_hard_step(2), "0.85 FTP nie")
	assert_false(p.is_hard_step(3))
	assert_false(p.is_hard_step(4), "jazda swobodna nigdy")
	assert_true(p.is_hard_step(5), "rampa o średniej 0.9")
	assert_false(p.is_hard_step(6), "rampa o średniej 0.875")
	assert_false(p.is_hard_step(-1))
	assert_false(p.is_hard_step(7))
	assert_eq(p.next_hard_step(2), 5)
	assert_eq(p.next_hard_step(6), -1)
	assert_eq(p.next_hard_step(-4), 0)


func test_summary_counts_and_threshold() -> void:
	var p := _plan([
		WorkoutStep.new(K.WARMUP, 600.0, 0.5, 0.75),
		WorkoutStep.new(K.WORK, 240.0, 1.05),
		WorkoutStep.new(K.RECOVERY, 180.0, 0.55),
		WorkoutStep.new(K.WORK, 240.0, 1.05),
		WorkoutStep.new(K.WORK, 60.0, 1.2),
		WorkoutStep.new(K.RECOVERY, 120.0, 0.5),
		WorkoutStep.new(K.STEADY, 100.0, 0.9, 1.1),
		WorkoutStep.new(K.FREERIDE, 60.0),
		WorkoutStep.new(K.COOLDOWN, 300.0, 0.6, 0.4),
	])
	var s := p.summary()
	assert_near(s["duration_s"], 1900.0, 1e-6)
	assert_eq(s["step_count"], 9)
	assert_eq(s["hard_intervals"], 3, "sąsiednie ciężkie kroki to jeden interwał")
	assert_near(s["hard_time_s"], 640.0, 1e-6)
	assert_near(s["time_above_threshold_s"], 590.0, 1e-6, "rampa 90->110% jest nad progiem przez połowę")
	assert_near(s["freeride_s"], 60.0, 1e-6)
	assert_near(s["max_intensity"], 1.2, 1e-9)
	assert_near(s["avg_intensity"], 1396.0 / 1900.0, 1e-6, "średnia ważona czasem, jazda swobodna 60%")
	assert_between(s["intensity_factor"], s["avg_intensity"], s["max_intensity"], "IF między średnią a maksimum")
	var blocks := p.hard_blocks()
	assert_eq(blocks.size(), 3)
	if blocks.size() == 3:
		assert_eq([blocks[0]["first"], blocks[0]["last"]], [1, 1], "pierwszy interwał")
		assert_near(blocks[0]["start_s"], 600.0, 1e-9)
		assert_near(blocks[0]["end_s"], 840.0, 1e-9)
		assert_eq([blocks[1]["first"], blocks[1]["last"]], [3, 4], "dwa sąsiednie ciężkie kroki = jeden odcinek")
		assert_near(blocks[1]["start_s"], 1020.0, 1e-9)
		assert_near(blocks[1]["end_s"], 1320.0, 1e-9)
		assert_eq([blocks[2]["first"], blocks[2]["last"]], [6, 6], "rampa o średniej 100%")
	assert_true(WorkoutPlan.new().hard_blocks().is_empty())


func test_intensity_factor_and_tss() -> void:
	var hour := _plan([WorkoutStep.new(K.STEADY, 3600.0, 1.0)])
	assert_near(hour.summary()["intensity_factor"], 1.0, 1e-9, "godzina na FTP: IF 1.0")
	assert_near(hour.summary()["tss"], 100.0, 1e-6, "godzina na FTP: TSS 100")
	var steady := _plan([WorkoutStep.new(K.STEADY, 1200.0, 0.8)])
	assert_near(steady.summary()["intensity_factor"], 0.8, 1e-9)
	assert_near(steady.summary()["tss"], 1200.0 / 3600.0 * 0.64 * 100.0, 1e-6)
	var short := _plan([WorkoutStep.new(K.WORK, 10.0, 1.2)])
	assert_near(short.summary()["intensity_factor"], 1.2, 1e-9, "plan krótszy niż okno 30 s")
	var steps: Array[WorkoutStep] = []
	for i in 15:
		steps.append(WorkoutStep.new(K.WORK, 60.0, 1.2))
		steps.append(WorkoutStep.new(K.RECOVERY, 60.0, 0.5))
	var intervals := _plan(steps).summary()
	assert_near(intervals["avg_intensity"], 0.85, 1e-6)
	assert_true(intervals["intensity_factor"] > 0.88, "interwały ważą więcej niż średnia (NP > AP): %.3f" % intervals["intensity_factor"])
	assert_eq(intervals["hard_intervals"], 15)
	var empty := WorkoutPlan.new().summary()
	assert_near(empty["intensity_factor"], 0.0, 1e-9, "pusty plan")
	assert_near(empty["avg_intensity"], 0.0, 1e-9)


func test_to_json_roundtrip() -> void:
	var p := _sample()
	p.name = "Próbka"
	p.description = "Opis"
	var text := JSON.stringify(p.to_json_dict())
	var r := WorkoutLoader.parse_json(text)
	assert_eq(r["error"], "", "plan z to_json_dict wczytuje się bez błędów")
	var back: WorkoutPlan = r["plan"]
	if back == null:
		return
	assert_eq(back.name, "Próbka")
	assert_eq(back.description, "Opis")
	assert_eq(back.step_count(), p.step_count())
	for i in p.step_count():
		var a := p.steps[i]
		var b := back.steps[i]
		assert_eq(b.kind, a.kind, "rodzaj %d" % i)
		assert_near(b.duration_s, a.duration_s, 1e-6, "czas %d" % i)
		assert_near(b.power_start, a.power_start, 1e-4, "start %d" % i)
		assert_near(b.power_end, a.power_end, 1e-4, "koniec %d" % i)
		assert_near(b.cadence_rpm, a.cadence_rpm, 1e-6, "kadencja %d" % i)
		assert_eq(b.label, a.label, "etykieta %d" % i)
	assert_true((r["warnings"] as Array).is_empty(), "bez ostrzeżeń")
