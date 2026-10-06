extends Node
# Nahaufnahme eines Frettchens im echten Spiel: -- <ausgabe.png> <modus: sleep|work|carry>
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "/home/claude/sleepcam.png"
	var mode: String = a[1] if a.size() > 1 else "sleep"
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate(); add_child(main)
	for i in 5: await get_tree().process_frame
	GraphicsSettings.set_realistic(false)   # Realismus-Modus ist auf Software-Vulkan extrem langsam
	var gc = main.get("_game_ctrl")
	gc.call("start_new_game", "MEDIUM", "qa-seed", "QA")
	gc.call("bootstrap_test_colony")
	for i in 10: await get_tree().process_frame
	var rend = gc.renderer
	# Zeit: Nacht für Schlaf (Frettchen schlafen nachts), sonst Tag
	var want_clip: Dictionary = {"sleep": "Sleep", "work": "Work", "carry": "Carry"}
	var found: Node3D = null
	var t := 0
	while found == null and t < 3000:
		if mode == "sleep" and t == 0: DayNight.time = DayNight.day_length * 0.80
		gc.call("_process", 0.2)
		for n in rend._ferret_nodes:
			if (n as Node3D).visible and str(n.get_meta("cur_clip", "")) == want_clip[mode]:
				if mode != "sleep" or float(Time.get_ticks_msec()) / 1000.0 - float(n.get_meta("clip_t0", 0.0)) > 1.4:
					found = n; break
		t += 1
		if t % 5 == 0: await get_tree().process_frame
	print("[SLEEPCAM] gefunden nach ", t, " Schritten: ", found)
	if found == null: get_tree().quit(); return
	gc.set_process(false)
	var ui = gc.get_node_or_null("GameUI"); if ui: ui.visible = false
	var svp := SubViewport.new(); svp.size = Vector2i(1000, 650); svp.msaa_3d = Viewport.MSAA_4X
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(svp)
	var cam := Camera3D.new(); svp.add_child(cam); cam.current = true; cam.fov = 40
	var p: Vector3 = found.global_position
	cam.look_at_from_position(p + Vector3(1.7, 0.9, 1.9), p + Vector3(0, 0.15, 0), Vector3.UP)
	for i in 10: await get_tree().process_frame
	svp.get_texture().get_image().save_png(out)
	print("[SLEEPCAM] gespeichert; Position ", p, " Rotation ", found.rotation_degrees)
	get_tree().quit()
