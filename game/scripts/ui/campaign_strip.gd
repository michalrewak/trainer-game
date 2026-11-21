class_name CampaignStrip
extends Control
## Mapa kampanii: sesje jako punkty na trasie, pogrupowane w tygodnie. Zaliczone są
## turkusowe, następna pulsuje na pomarańczowo, bossowie to czerwone romby, a test FTP
## (Rytuał Progu) – złoty romb na końcu.

var campaign_id := ""
var next_index := 0

var _t := 0.0


func set_campaign(id: String, p_next_index: int) -> void:
	campaign_id = id
	next_index = p_next_index
	queue_redraw()


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_t += delta
		queue_redraw()


func _draw() -> void:
	if not CampaignCatalog.has(campaign_id):
		return
	var count := CampaignCatalog.session_count(campaign_id)
	var font := UiStyle.font()
	var per_week := CampaignCatalog.SESSIONS_PER_WEEK
	var weeks := CampaignCatalog.weeks(campaign_id)
	var week_gap := 26.0
	var step := (size.x - week_gap * (weeks - 1) - 30.0) / maxf(1.0, count - 1.0)
	var y := size.y * 0.42
	var prev := Vector2.ZERO
	for i in count:
		var week := floori(i / float(per_week))
		var p := Vector2(15.0 + i * step + week * week_gap, y)
		if i > 0:
			draw_line(prev, p, Color(1, 1, 1, 0.5 if i <= next_index else 0.18), 3.0)
		prev = p
	for i in count:
		var week := floori(i / float(per_week))
		var p := Vector2(15.0 + i * step + week * week_gap, y)
		var kind := int(CampaignCatalog.session(campaign_id, i)["kind"])
		var done := i < next_index
		var current := i == next_index
		var color := Color(1, 1, 1, 0.3)
		if kind == CampaignCatalog.Kind.BOSS:
			color = Palette.UI_BAD
		elif kind == CampaignCatalog.Kind.TEST:
			color = Color("ffd21a")
		if done:
			color = Palette.UI_SCRAP
		var r := 9.0
		if kind != CampaignCatalog.Kind.RIDE:
			r = 14.0
		if current:
			r += 3.0 * (0.5 + 0.5 * sin(_t * 6.0))
			if kind == CampaignCatalog.Kind.RIDE:
				color = Palette.UI_ACCENT
		if kind == CampaignCatalog.Kind.RIDE:
			draw_circle(p, r, color)
		else:
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]), color)
		if current:
			draw_arc(p, r + 5.0, 0.0, TAU, 24, Palette.UI_ACCENT, 3.0)
		if i % per_week == 0:
			draw_string(font, Vector2(p.x - 9.0, size.y - 2.0), "TYDZ. %d" % (week + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.55))
