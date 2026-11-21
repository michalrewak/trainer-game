extends SceneTree
## Podgląd wszystkich gadających głów naraz (kontrola wyglądu):
##   godot --path game --script tests/show_busts.gd -- wyjscie.png

var _heads: Array[TalkingHead] = []
var _t := 0.0
var _done := false


func _initialize() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.55, 0.36, 0.22)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var col := VBoxContainer.new()
	col.position = Vector2(40, 30)
	col.add_theme_constant_override("separation", 14)
	root.add_child(col)
	var chat := Chatter.new()
	var events := {Chatter.BARON: "pace_fast", Chatter.SLAVE: "cage_hit", Chatter.MECH: "convoy_hint", Chatter.PRIEST: "cadence_low", Chatter.RAIDER: "raider"}
	for who: String in events:
		var head := TalkingHead.new()
		col.add_child(head)
		var line := chat.line(str(events[who]))
		head.say(Chatter.make(who, str(line["text"])), 2)
		_heads.append(head)


func _process(delta: float) -> bool:
	_t += delta
	for h in _heads:
		h.tick(delta)
	if _t > 2.0 and not _done:
		_done = true
		var args := OS.get_cmdline_user_args()
		var path := args[0] if args.size() > 0 else "user://busts.png"
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(path)
		print("Zapisano: ", path)
		quit()
	return false
