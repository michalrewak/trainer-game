extends TestCase
## Gadające głowy (obsada, kwestie, okienko) i widoki części konwoju – testy w trybie headless.


func test_every_line_has_a_known_speaker_and_fits_the_screen() -> void:
	for event: String in Chatter.LINES:
		var pool: Array = Chatter.LINES[event]
		assert_true(pool.size() > 0, "%s ma kwestie" % event)
		for entry: Array in pool:
			assert_true(Chatter.CAST.has(entry[0]), "%s: znany mówca %s" % [event, entry[0]])
			var text := str(entry[1])
			assert_true(text.length() >= 8 and text.length() <= 80, "%s: kwestia do przeczytania z 3 m (%d znaków): %s" % [event, text.length(), text])


func test_lines_rotate_instead_of_repeating() -> void:
	var chat := Chatter.new()
	var first := chat.line("lore")
	var second := chat.line("lore")
	assert_true(first["text"] != second["text"], "kolejna kwestia jest inna")
	assert_true(str(first["name"]).length() > 0 and first.has("color"))
	assert_eq(chat.line("nie_ma_takiego_zdarzenia"), {}, "nieznane zdarzenie = cisza")
	for i in Chatter.LINES["lore"].size():
		chat.line("lore")
	assert_true(str(chat.line("lore")["text"]).length() > 0, "po wyczerpaniu puli kwestie się zawijają")


func test_story_cast_is_complete() -> void:
	for who: String in [Chatter.BARON, Chatter.SLAVE, Chatter.MECH, Chatter.PRIEST, Chatter.RAIDER]:
		var bust := BustFactory.build(who)
		assert_true(bust.get_child_count() > 8, "%s ma popiersie" % who)
		assert_true(bust.get_node_or_null("Jaw") != null, "%s rusza szczęką" % who)
		bust.free()
	var spoken := {}
	for event: String in Chatter.LINES:
		for entry: Array in Chatter.LINES[event]:
			spoken[entry[0]] = true
	assert_eq(spoken.size(), Chatter.CAST.size(), "każda postać coś mówi")


func test_talking_head_queue_and_priorities() -> void:
	var head := TalkingHead.new()
	assert_false(head.is_busy())
	head.say(Chatter.make(Chatter.MECH, "Pierwsza kwestia, zwykła."), 1)
	assert_eq(head.speaker(), Chatter.MECH)
	assert_true(head.visible)
	head.say(Chatter.make(Chatter.PRIEST, "Tło nie przerywa i nie czeka."), 0)
	head.say(Chatter.make(Chatter.SLAVE, "Zwykła czeka w kolejce."), 1)
	assert_eq(head.speaker(), Chatter.MECH, "zwykła kwestia nie przerywa zwykłej")
	head.say(Chatter.make(Chatter.BARON, "WAŻNE! Przerywam!"), 2)
	assert_eq(head.speaker(), Chatter.BARON, "ważna kwestia przerywa")
	var t := 0.0
	while t < 4.0:
		head.tick(0.1)
		t += 0.1
	assert_eq(head.speaker(), Chatter.SLAVE, "po ważnej wchodzi kwestia z kolejki")
	while t < 20.0:
		head.tick(0.1)
		t += 0.1
	assert_false(head.is_busy(), "po wszystkim okienko znika")
	assert_false(head.visible)
	head.say({}, 2)
	assert_false(head.is_busy(), "pusta kwestia nic nie robi")
	head.free()


func test_convoy_parts_build_and_animate() -> void:
	var sim := RunSimulation.new(600.0, 4)
	for part: int in [RaiderModel.Part.TRACTOR, RaiderModel.Part.GALLEY, RaiderModel.Part.GUARD, RaiderModel.Part.HITCH_REAR]:
		var r := sim.combat.add_convoy_part(part, 20, 1)
		var view := ConvoyPartView.new()
		view.build(r)
		# W drzewie sceny – dym i światła potrzebują transformacji globalnej.
		(Engine.get_main_loop() as SceneTree).root.add_child(view)
		r.speed = 8.0
		r.exposed = true
		r.braking = true
		view.sync(r, 0.0, 0.1)
		r.hit_flash = 0.2
		view.sync(r, 0.0, 0.1)
		r.hit_flash = 0.0
		r.detached = true
		view.sync(r, 0.0, 0.1)
		r.set_state(RaiderModel.State.DESTROYED)
		r.timer = 2.5
		view.sync(r, 0.0, 0.1)
		assert_true(view.get_child_count() > 0, "część %d ma bryłę" % part)
		view.free()


func test_boost_action_is_on_pad_and_keyboard() -> void:
	var pad := false
	var key := false
	for e in InputMap.action_get_events(&"boost"):
		if e is InputEventJoypadButton and e.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			pad = true
		if e is InputEventKey:
			key = true
	assert_true(pad, "dopalacz na RB")
	assert_true(key, "dopalacz na klawiaturze (B)")


func test_convoy_diagram_and_mine_view_run_headless() -> void:
	var diagram := ConvoyDiagram.new()
	diagram.size = Vector2(760, 190)
	diagram.rel_m = -80.0
	diagram.window = 1
	diagram.board = 0.5
	diagram.free()
	var sim := RunSimulation.new(600.0, 4)
	sim.convoys.mines.append({"id": 1, "lane": 1, "d": 30.0, "t_left": 1.0})
	var view := ConvoyView.new()
	view.sync(sim, 0.1)
	assert_eq(view.get_child_count(), 1, "mina ma znacznik")
	sim.convoys.mines.clear()
	view.sync(sim, 0.1)
	view.free()
