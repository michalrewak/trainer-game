extends TestCase


func test_three_lanes_centered() -> void:
	var l := LaneModel.new()
	assert_eq(l.target_lane, 1, "start na środkowym pasie")
	assert_near(l.lane_center(0), -3.6, 0.001)
	assert_near(l.lane_center(1), 0.0, 0.001)
	assert_near(l.lane_center(2), 3.6, 0.001)


func test_change_lane_and_clamp_at_edges() -> void:
	var l := LaneModel.new()
	assert_true(l.request_change(-1))
	assert_false(l.request_change(-1), "nie ma pasa za lewą krawędzią")
	assert_eq(l.target_lane, 0)
	assert_true(l.request_change(1))
	assert_true(l.request_change(1))
	assert_false(l.request_change(1), "nie ma pasa za prawą krawędzią")
	assert_eq(l.target_lane, 2)


func test_lateral_move_takes_about_a_third_of_a_second() -> void:
	var l := LaneModel.new()
	l.request_change(1)
	var t := 0.0
	while l.is_changing() and t < 2.0:
		l.step(1.0 / 60.0)
		t += 1.0 / 60.0
	assert_between(t, 0.15, 0.6, "czas zmiany pasa [s]")
	assert_near(l.x_m, 3.6, 0.01)
	assert_eq(l.current_lane(), 2)


func test_lane_input_single_press_and_repeat() -> void:
	var li := LaneInput.new()
	assert_eq(li.update(0.016, 0.0, 1.0), 1, "wciśnięcie w prawo")
	assert_eq(li.update(0.016, 0.0, 1.0), 0, "trzymanie nie powtarza od razu")
	var fired := 0
	for i in 60:
		fired += absi(li.update(0.016, 0.0, 1.0))
	assert_between(float(fired), 1.0, 3.0, "powtarzanie przy przytrzymaniu przez ~1 s")
	assert_eq(li.update(0.016, 0.0, 0.0), 0, "puszczenie")
	assert_eq(li.update(0.016, 1.0, 0.0), -1, "wciśnięcie w lewo")


func test_lane_input_hysteresis_ignores_stick_jitter() -> void:
	var li := LaneInput.new()
	assert_eq(li.update(0.016, 0.6, 0.0), -1, "gałka mocno w lewo")
	# Gałka drga między 0.4 a 0.6 – nadal „trzymana”, brak nowych poleceń.
	var extra := 0
	for i in 10:
		extra += absi(li.update(0.016, 0.4 if i % 2 == 0 else 0.6, 0.0))
	assert_eq(extra, 0, "drgania gałki nie zmieniają pasa")
	assert_eq(li.update(0.016, 0.1, 0.0), 0, "puszczenie poniżej progu")
	assert_eq(li.update(0.016, 0.6, 0.0), -1, "ponowne wychylenie")
