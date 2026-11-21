extends TestCase
## Kampanie treningowe: katalog z prawdziwych protokołów, postęp w zapisie, walka z bossem
## sterowana interwałami i test FTP (Rytuał Progu).

const DT := 1.0 / 60.0


# --- Opis treningu i katalog -------------------------------------------------------

func test_spec_builds_a_classic_two_by_twenty() -> void:
	var p := CampaignCatalog.parse_spec("wu10 2x(20@98 r8) cd6")
	assert_eq(p.step_count(), 6, "rozgrzewka, 2 × (próg + regeneracja), schłodzenie")
	assert_near(p.total_duration_s(), (10 + 2 * 28 + 6) * 60.0, 0.01)
	assert_eq(p.steps[0].kind, WorkoutStep.Kind.WARMUP)
	assert_eq(p.steps[1].kind, WorkoutStep.Kind.WORK)
	assert_near(p.steps[1].power_start, 0.98, 1e-6)
	assert_near(p.steps[1].duration_s, 1200.0, 0.01)
	assert_eq(p.steps[1].label, "Próg")
	assert_eq(p.steps[2].kind, WorkoutStep.Kind.RECOVERY)
	assert_eq(p.steps[5].kind, WorkoutStep.Kind.COOLDOWN)
	assert_eq(p.hard_blocks().size(), 2, "dwa ciężkie odcinki")


func test_spec_handles_nested_repeats_and_seconds() -> void:
	var p := CampaignCatalog.parse_spec("wu12 3x(13x(30s@120 15s@50) r3) cd8")
	assert_eq(p.step_count(), 1 + 3 * (13 * 2 + 1) + 1, "30/15 Rønnestada: 3 serie po 13 powtórzeń")
	assert_near(p.total_duration_s(), 12 * 60.0 + 3 * (13 * 45.0 + 180.0) + 8 * 60.0, 0.01)
	assert_near(p.steps[1].duration_s, 30.0, 0.01)
	assert_near(p.steps[1].power_start, 1.2, 1e-6)
	assert_eq(p.steps[1].label, "Zryw")
	assert_near(p.steps[2].duration_s, 15.0, 0.01)
	assert_eq(CampaignCatalog.parse_spec("").step_count(), 0, "pusty opis = pusty plan")
	assert_eq(CampaignCatalog.parse_spec("bzdura 5@").step_count(), 0, "błędny opis nie wywraca gry")


func test_every_campaign_is_four_weeks_of_real_workouts() -> void:
	assert_eq(CampaignCatalog.ORDER.size(), 3)
	for id in CampaignCatalog.ORDER:
		assert_eq(CampaignCatalog.session_count(id), 12, "%s: 12 sesji" % id)
		assert_eq(CampaignCatalog.weeks(id), 4)
		var bosses := 0
		for i in CampaignCatalog.session_count(id):
			var s := CampaignCatalog.session(id, i)
			var p := CampaignCatalog.plan(id, i)
			assert_true(p != null and not p.is_empty(), "%s #%d ma plan" % [id, i])
			assert_eq(p.name, str(s["title"]))
			assert_true(str(s["story"]).length() > 20, "%s #%d ma opis fabularny" % [id, i])
			var kind := int(s["kind"])
			if kind == CampaignCatalog.Kind.TEST:
				continue
			var minutes := p.total_duration_s() / 60.0
			assert_between(minutes, 35.0, 75.0, "%s „%s”: rozsądna długość (%.0f min)" % [id, s["title"], minutes])
			var sum := p.summary()
			assert_between(float(sum["tss"]), 20.0, 105.0, "%s „%s”: obciążenie TSS %.0f" % [id, s["title"], float(sum["tss"])])
			assert_true(float(sum["max_intensity"]) <= 1.25, "bez absurdalnych mocy")
			assert_eq(p.steps[0].kind, WorkoutStep.Kind.WARMUP, "zaczyna się rozgrzewką")
			assert_eq(p.steps[p.step_count() - 1].kind, WorkoutStep.Kind.COOLDOWN, "kończy się schłodzeniem")
			if kind == CampaignCatalog.Kind.BOSS:
				bosses += 1
				assert_true(p.hard_blocks().size() >= 2, "%s: boss ma co najmniej dwa natarcia" % s["title"])
		assert_eq(bosses, 2, "%s: dwóch bossów" % id)
		assert_eq(int(CampaignCatalog.session(id, 11)["kind"]), CampaignCatalog.Kind.TEST, "%s kończy się testem FTP" % id)
		assert_eq(int(CampaignCatalog.session(id, 11)["week"]), 4)
	assert_eq(CampaignCatalog.session(CampaignCatalog.PROG, 99), {}, "sesja spoza zakresu")
	assert_true(CampaignCatalog.plan("nie_ma", 0) == null)


func test_ramp_plan_climbs_every_minute() -> void:
	var p := CampaignCatalog.ramp_test_plan()
	assert_eq(p.step_count(), 1 + CampaignCatalog.RAMP_STEPS)
	assert_near(p.steps[1].power_start, 0.5, 1e-6, "pierwszy stopień to 50% FTP")
	assert_near(p.steps[2].power_start - p.steps[1].power_start, 0.075, 1e-6, "co minutę 7,5% FTP więcej")
	assert_near(p.steps[1].duration_s, 60.0, 0.01)
	assert_true(p.steps[CampaignCatalog.RAMP_STEPS].power_start > 2.0, "plan sięga daleko ponad możliwości")


# --- Postęp w zapisie --------------------------------------------------------------

func test_sessions_advance_in_order_and_only_when_completed() -> void:
	var store := ProgressStore.new("user://test_saves/%d/campaign.json" % OS.get_process_id())
	var id := CampaignCatalog.PROG
	assert_eq(store.campaign_active(), "")
	assert_eq(store.campaign_next_index(id), 0)
	var run := func(index: int, completed: bool, boss: bool = false) -> void:
		store.record_run({"scrap": 5, "completed": completed, "workout_in_band_pct": 90, "tss": 60.0,
			"campaign": {"id": id, "index": index, "boss_defeated": boss}})
	run.call(0, false)
	assert_eq(store.campaign_next_index(id), 0, "przerwana sesja się nie liczy")
	run.call(0, true)
	assert_eq(store.campaign_next_index(id), 1)
	assert_eq(store.campaign_active(), id, "pierwsza zaliczona sesja ustawia aktywną kampanię")
	run.call(5, true)
	assert_eq(store.campaign_next_index(id), 1, "sesja spoza kolejności (np. z opcji testowej) nie przesuwa postępu")
	run.call(1, true, true)
	assert_eq(store.campaign_next_index(id), 2)
	assert_true(bool((store.campaign_done(id)[1] as Dictionary)["boss_defeated"]))
	assert_eq(int((store.campaign_done(id)[0] as Dictionary)["in_band_pct"]), 90)
	for i in range(2, 12):
		run.call(i, true)
	assert_true(store.campaign_finished(id))
	assert_eq(store.campaign_completions(id), 1)
	run.call(11, true)
	assert_eq(store.campaign_done(id).size(), 12, "ukończona kampania nie rośnie dalej")
	assert_true(store.save_data())
	var again := ProgressStore.new(store.path)
	assert_true(again.load_data())
	assert_true(again.campaign_finished(id), "postęp kampanii przetrwał zapis")
	again.restart_campaign(id)
	assert_eq(again.campaign_next_index(id), 0, "kampanię można zacząć od nowa")
	assert_eq(again.campaign_completions(id), 1, "licznik ukończeń zostaje")
	assert_eq(again.campaign_next_index(CampaignCatalog.BAZA), 0, "inne kampanie mają własny postęp")


# --- Boss ---------------------------------------------------------------------------

func _boss_sim() -> RunSimulation:
	var sim := RunSimulation.new(3600.0, 3)
	sim.generator.wrecks_enabled = false
	sim.generator.pickups_enabled = false
	sim.items.clear()
	sim.combat.set_first_encounter(1e9)
	var t := 0.0
	while t < 10.0:
		sim.step(DT, 200.0)
		t += DT
	return sim


func test_boss_falls_when_intervals_are_held_in_band() -> void:
	var sim := _boss_sim()
	var boss := BossFight.new()
	var events: Array = []
	boss.round_started.connect(func(i: int) -> void: events.append("start%d" % i))
	boss.round_ended.connect(func(i: int) -> void: events.append("koniec%d" % i))
	boss.destroyed.connect(func() -> void: events.append("rozbity"))
	boss.setup(sim, "Walec Smalca", 120.0, 2)
	assert_true(boss.active)
	assert_eq(sim.combat.live_raiders().size(), 1, "machina jest na drodze")
	assert_false(boss.boss.exposed, "przed natarciem działko jej nie sięga")
	var scrap0 := sim.expedition.scrap
	# Natarcie 1: 60 s w widełkach.
	var t := 0.0
	while t < 60.0:
		sim.step(DT, 200.0)
		boss.step(DT, true, true)
		t += DT
	assert_near(boss.hp, 1.0 - 60.0 / (120.0 * BossFight.KILL_RATIO), 0.01, "minuta w widełkach zdjęła prawie 59%")
	assert_true(boss.boss.exposed, "w natarciu machina jest w zasięgu działka")
	assert_true(boss.boss.d - sim.vehicle.distance_m < 35.0, "i jest blisko")
	# Regeneracja: machina odjeżdża, obrażeń nie ma.
	var hp := boss.hp
	t = 0.0
	while t < 20.0:
		sim.step(DT, 100.0)
		boss.step(DT, false, true)
		t += DT
	assert_near(boss.hp, hp, 1e-6, "w przerwie nikt nikomu nic nie robi")
	assert_true(boss.boss.d - sim.vehicle.distance_m > 60.0, "machina odjechała")
	# Natarcie 2: dobija.
	t = 0.0
	while t < 60.0 and not boss.defeated:
		sim.step(DT, 200.0)
		boss.step(DT, true, true)
		t += DT
	assert_true(boss.defeated, "85% czasu natarć w widełkach rozbija machinę")
	assert_true(t < 45.0, "przed końcem drugiego natarcia (po %.0f s)" % t)
	assert_eq(events, ["start0", "koniec0", "start1", "rozbity"])
	assert_eq(sim.expedition.scrap - scrap0, BossFight.REWARD_SCRAP)
	assert_eq(sim.expedition.fuel, BossFight.REWARD_FUEL)
	assert_eq(sim.expedition.pedalers_freed, BossFight.REWARD_CREW)
	assert_eq(boss.partial_scrap(), 0, "rozbita machina nie daje już łupu częściowego")


func test_boss_escapes_wounded_when_power_misses_the_band() -> void:
	var sim := _boss_sim()
	var boss := BossFight.new()
	boss.setup(sim, "Walec Smalca", 120.0, 2)
	var t := 0.0
	while t < 120.0:
		sim.step(DT, 200.0)
		# Tylko połowa czasu natarć w widełkach.
		boss.step(DT, true, int(t) % 2 == 0)
		t += DT
	assert_false(boss.defeated, "50% w widełkach to za mało")
	assert_near(boss.hp, 1.0 - 0.5 / BossFight.KILL_RATIO, 0.03)
	assert_between(float(boss.partial_scrap()), 100.0, 130.0, "łup za rany: połowa nagrody razy zadane obrażenia")
	assert_true(boss.boss.is_alive())


func test_turret_fires_at_the_boss_but_only_the_band_hurts_it() -> void:
	var sim := _boss_sim()
	sim.combat.auto_fire = true
	sim.combat.target_power_w = 200.0
	var boss := BossFight.new()
	boss.setup(sim, "Walec Smalca", 600.0, 1)
	var shots := [0]
	sim.combat.shot_fired.connect(func(_p: Dictionary) -> void: shots[0] += 1)
	var t := 0.0
	while t < 12.0:
		sim.step(DT, 200.0)
		boss.step(DT, true, false)
		t += DT
	assert_true(shots[0] > 5, "działko samo ostrzeliwuje machinę (%d strzałów)" % shots[0])
	assert_true(boss.boss.hits_taken > 3, "pociski trafiają")
	assert_near(boss.hp, 1.0, 1e-6, "ale liczy się tylko trzymanie widełek")


# --- Test FTP -----------------------------------------------------------------------

## Jedzie test: trzyma cel do stopnia fail_step, potem odpuszcza.
func _ride_ramp(ftp: float, hold_steps: int) -> Dictionary:
	var plan := CampaignCatalog.ramp_test_plan()
	var ramp := RampTest.new(plan, ftp)
	var metrics := TrainingMetrics.new(ftp)
	var events: Array = []
	ramp.step_reached.connect(func(n: int, w: float) -> void: events.append([n, w]))
	var t := 0.0
	var dt := 0.25
	var ended_at := -1.0
	while t < 3000.0 and ended_at < 0.0:
		var i := plan.step_index_at(t)
		var target := plan.target_watts_at(t, ftp)
		var power := target if i <= hold_steps else 40.0
		metrics.tick(dt, power)
		if ramp.step(dt, t, power, metrics):
			ended_at = t
		t += dt
	return {"ramp": ramp, "plan": plan, "events": events, "ended_at": ended_at}


func test_ramp_test_sets_ftp_from_the_best_minute() -> void:
	# FTP 200 W; zawodnik kończy 12 stopni: ostatni to 50% + 11 × 7,5% = 132,5% = 265 W.
	var r := _ride_ramp(200.0, 12)
	var ramp: RampTest = r["ramp"]
	assert_true(ramp.done)
	assert_eq(ramp.steps_done, 12)
	assert_near(ramp.result_ftp_w, roundf(265.0 * 0.75), 1.0, "FTP = 75% najlepszej minuty (265 W)")
	assert_near(float(r["ended_at"]), 5 * 60.0 + 12 * 60.0 + RampTest.FAIL_S, 1.0, "test kończy się 8 s po odpuszczeniu")
	assert_eq((r["events"] as Array).size(), 13, "ogłoszono 13 stopni (trzynasty już nieukończony)")
	assert_eq((r["events"] as Array)[0], [1, 100.0], "pierwszy stopień: 100 W")
	var plan: WorkoutPlan = r["plan"]
	assert_eq(plan.steps[plan.step_count() - 1].kind, WorkoutStep.Kind.COOLDOWN, "po teście jest schłodzenie")
	assert_near(plan.total_duration_s(), float(r["ended_at"]) + RampTest.COOLDOWN_S, 2.0, "plan obcięty w chwili końca testu")


func test_stronger_rider_gets_higher_ftp_and_too_short_test_is_void() -> void:
	var strong: RampTest = _ride_ramp(200.0, 15)["ramp"]
	var weak: RampTest = _ride_ramp(200.0, 9)["ramp"]
	assert_true(strong.result_ftp_w > weak.result_ftp_w + 30.0, "więcej stopni = wyższe FTP (%d vs %d W)" % [roundi(strong.result_ftp_w), roundi(weak.result_ftp_w)])
	var void_test: RampTest = _ride_ramp(200.0, 2)["ramp"]
	assert_true(void_test.done)
	assert_near(void_test.result_ftp_w, 0.0, 1e-6, "za krótki test nie zmienia FTP")


func test_campaign_session_in_app_follows_progress() -> void:
	# W testach autoload nie przechodzi przez _ready – dajemy mu opcje i pusty zapis.
	var had_options := App.options != null
	var old_progress: ProgressStore = App.progress
	if not had_options:
		App.options = LaunchOptions.new()
	App.progress = ProgressStore.new("user://test_saves/%d/app_campaign.json" % OS.get_process_id())
	var saved_path := App.selected_plan_path
	var saved_option := App.options.campaign
	App.options.campaign = ""
	App.selected_plan_path = ""
	assert_eq(App.campaign_session(), {}, "poza trybem kampanii nie ma sesji")
	App.selected_plan_path = App.CAMPAIGN_PLAN
	var s := App.campaign_session()
	assert_true(CampaignCatalog.has(str(s["id"])))
	assert_eq(int(s["sessions"]), 12)
	var plan := App.selected_plan()
	assert_eq(plan.name, str(s["title"]), "plan wyprawy to plan sesji kampanii")
	assert_true(App.run_duration_s() > 600.0)
	App.options.campaign = "kuznia:5"
	s = App.campaign_session()
	assert_eq(str(s["id"]), CampaignCatalog.KUZNIA)
	assert_eq(int(s["index"]), 5)
	assert_eq(int(s["kind"]), CampaignCatalog.Kind.BOSS)
	App.options.campaign = saved_option
	App.selected_plan_path = saved_path
	App.progress = old_progress
	if not had_options:
		App.options = null


# --- Krótkie warianty sesji ---------------------------------------------------------

func test_short_variants_keep_intensity_and_cut_volume() -> void:
	for id in CampaignCatalog.ORDER:
		for i in CampaignCatalog.session_count(id):
			var full := CampaignCatalog.session(id, i)
			var short := CampaignCatalog.session(id, i, true)
			assert_eq(short["kind"], full["kind"], "%s #%d: ten sam rodzaj sesji" % [id, i])
			assert_true(bool(short["short"]) and not bool(full["short"]))
			assert_eq(short["story"], full["story"], "to ta sama sesja fabularnie")
			if int(full["kind"]) == CampaignCatalog.Kind.TEST:
				assert_near(CampaignCatalog.plan(id, i, true).total_duration_s(), CampaignCatalog.plan(id, i).total_duration_s(), 0.01, "test FTP jest jeden")
				continue
			var fp := CampaignCatalog.plan(id, i)
			var sp := CampaignCatalog.plan(id, i, true)
			var minutes := sp.total_duration_s() / 60.0
			assert_between(minutes, 24.0, 42.0, "%s „%s”: krótka sesja ma %.0f min" % [id, short["title"], minutes])
			assert_true(sp.total_duration_s() < fp.total_duration_s() * 0.85, "%s „%s” jest wyraźnie krótsza od pełnej" % [id, short["title"]])
			assert_near(float(sp.summary()["max_intensity"]), float(fp.summary()["max_intensity"]), 1e-6, "%s „%s”: ta sama najwyższa intensywność" % [id, short["title"]])
			assert_true(float(sp.summary()["tss"]) >= 12.0, "krótka sesja to nadal trening")
			assert_eq(sp.name, str(short["title"]))
			if int(full["kind"]) == CampaignCatalog.Kind.BOSS:
				assert_true(sp.hard_blocks().size() >= 2, "%s: krótki boss też ma co najmniej dwa natarcia" % short["title"])
				assert_true(str(short["title"]).contains(":") and str(short["title"]) != str(full["title"]), "krótki boss ma własny tytuł z protokołem")


func test_short_setting_changes_the_campaign_plan() -> void:
	var had_options := App.options != null
	var old_progress: ProgressStore = App.progress
	if not had_options:
		App.options = LaunchOptions.new()
	App.progress = ProgressStore.new("user://test_saves/%d/app_short.json" % OS.get_process_id())
	var saved_path := App.selected_plan_path
	var saved_campaign := App.options.campaign
	var saved_short := App.options.campaign_short
	App.selected_plan_path = App.CAMPAIGN_PLAN
	App.options.campaign = "prog:9"
	App.options.campaign_short = false
	var was_setting: Variant = App.settings.get("campaign_short")
	App.settings["campaign_short"] = false
	var full_s := App.selected_plan().total_duration_s()
	assert_eq(App.selected_plan().name, "Twierdza Barona: 2×20 na progu")
	App.options.campaign_short = true
	assert_true(bool(App.campaign_session()["short"]))
	assert_eq(App.selected_plan().name, "Twierdza Barona: 2×10 na progu")
	assert_true(App.selected_plan().total_duration_s() < full_s * 0.6, "krótki wariant skraca wyprawę")
	assert_near(App.run_duration_s(), App.selected_plan().total_duration_s(), 0.01, "wyprawa trwa tyle, co plan")
	App.options.campaign_short = saved_short
	App.options.campaign = saved_campaign
	App.selected_plan_path = saved_path
	if was_setting == null:
		App.settings.erase("campaign_short")
	else:
		App.settings["campaign_short"] = was_setting
	App.progress = old_progress
	if not had_options:
		App.options = null
