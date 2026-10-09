extends Node
# Nutzung: godot ... res://_t/Shot.tscn -- <modus> <ausgabe.png>
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "menu"
	var out: String = args[1] if args.size() > 1 else "/home/claude/shot.png"
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for i in 30: await get_tree().process_frame
	var gc = main.get("_game_ctrl")
	if mode == "game" or mode == "colony":
		gc.call("start_new_game", "SMALL", "qa-seed", "QA")
		if mode == "colony": gc.call("bootstrap_test_colony")
		for i in 40: await get_tree().process_frame
		for i in 60:
			gc.call("_process", 0.1)
			await get_tree().process_frame
	if mode.begins_with("season:"):
		# season:<0-3>:<0|1 realistisch>[:fp]
		var parts: PackedStringArray = mode.split(":")
		var S: int = int(parts[1]); var R: int = int(parts[2])
		gc.call("start_new_game", "MEDIUM", "qa-seed", "QA")
		gc.call("bootstrap_test_colony")
		for i in 20: await get_tree().process_frame
		var day: int = S * 15 + 7
		DayNight.day_count = day; gc.set("_day_prev", day); SeasonSys.update(day)
		var pct: float = float(parts[4]) if parts.size() > 4 else 0.30
		DayNight.time = DayNight.day_length * pct
		GraphicsSettings.set_realistic(R == 1)
		if parts.size() > 3 and parts[3] == "fp":
			gc.call("_toggle_fp_mode")
			# offene Stelle mit Fernsicht suchen: höchste Wiesen-/Waldkachel 7-16 Kacheln vom Zentrum
			var cx: int = gc.world_gen.w / 2; var cy: int = gc.world_gen.h / 2
			var best := Vector2i(cx + 9, cy); var bh := -1.0
			for x in range(cx - 16, cx + 17):
				for y in range(cy - 16, cy + 17):
					var dd: float = Vector2(x - cx, y - cy).length()
					if dd < 7.0 or dd > 16.0 or x < 2 or y < 2 or x >= gc.world_gen.w - 2 or y >= gc.world_gen.h - 2: continue
					var tl: Dictionary = gc.world[x][y]
					if str(tl.get("biome", "")) in ["PLAINS", "FOREST"] and float(tl.get("height", 0.0)) > bh:
						bh = float(tl.get("height", 0.0)); best = Vector2i(x, y)
			var sun = gc.get("_sun_light")
			var sv: Vector3 = -(sun.global_transform.basis * Vector3.FORWARD)
			var yaw_off: float = deg_to_rad(float(parts[5])) if parts.size() > 5 else 0.0
			var yaw: float = atan2(-sv.x, -sv.z) + yaw_off
			var wp: Vector3 = gc.renderer.tile_to_world3d(best.x, best.y) + Vector3(0, 7.0, 0)
			gc.player.teleport_to(wp, yaw)
			gc.player.set("_pitch", 0.10); gc.player.camera.rotation.x = 0.10
		for i in (60 if R == 0 else 10):
			DayNight.time = DayNight.day_length * pct
			gc.call("_process", 0.05)
			await get_tree().process_frame
	elif mode.begins_with("tip:"):
		# tip:<ID>:<Index des Menü-Eintrags für die Position>
		var tp: PackedStringArray = mode.split(":")
		GraphicsSettings.set_realistic(false)
		gc.call("start_new_game", "SMALL", "qa-seed", "QA")
		gc.call("bootstrap_test_colony")
		for i in 30: await get_tree().process_frame
		for i in 20:
			gc.call("_process", 0.1)
			await get_tree().process_frame
		var bm = gc.get_node("GameUI/UIRoot/BuildMenu")
		bm.call("refresh")
		for i in 3: await get_tree().process_frame
		bm.set("_tip_btn", bm._container.get_child(int(tp[2])))
		bm.set("_tip_bid", tp[1])
		bm.call("_tip_show")
		for i in 6: await get_tree().process_frame
	elif mode.begins_with("loading:"):
		# loading:<Schritt-Nr 1-5>  - Ladebildschirm an diesem Punkt fotografieren
		var which: int = int(mode.split(":")[1])
		GraphicsSettings.set_realistic(false)
		var steps: Array = []
		for k in 5:
			var kk: int = k + 1
			steps.append({"label": ["Welt wird erzeugt …", "Gelände wird aufgeschüttet …", "Kollisionen werden berechnet …", "Bäume werden gepflanzt …", "Letzte Handgriffe …"][k], "weight": 1.0, "fn": func():
				OS.delay_msec(650)
				if kk == which:
					get_viewport().get_texture().get_image().save_png(out)
					print("[SHOT] gespeichert ", out)})
		main._loading.run("Welt wird erstellt", steps)
		for i in 400: await get_tree().process_frame
		get_tree().quit(); return
	elif mode == "pause":
		gc.call("start_new_game", "SMALL", "qa-seed", "QA")
		gc.call("bootstrap_test_colony")
		for i in 40: await get_tree().process_frame
		for i in 40:
			gc.call("_process", 0.1)
			await get_tree().process_frame
		GameState.toggle_pause()
		for i in 10: await get_tree().process_frame
	elif mode == "equip":
		gc.call("start_new_game", "SMALL", "qa-seed", "QA")
		for i in 20: await get_tree().process_frame
		for aid in AchievementSys.ACHIEVEMENTS: AchievementSys.debug_force_unlock(aid)
		GameState.toggle_pause()
		for i in 5: await get_tree().process_frame
		var cep = gc.get_node("GameUI/UIRoot/PauseMenu/Row/CharacterEditorPanel")
		cep.call("_on_toggle_equip")
		for k in ["HEAD", "NECK", "FACE", "BACK"]:
			PlayerAccessories.call("equip", {"HEAD":"CROWN","NECK":"SCARF","FACE":"MONOCLE","BACK":"CAPE"}[k])
		for i in 25: await get_tree().process_frame
	elif mode == "info":
		gc.call("start_new_game", "SMALL", "qa-seed", "QA")
		gc.call("bootstrap_test_colony")
		for i in 40: await get_tree().process_frame
		for i in 40:
			gc.call("_process", 0.1)
			await get_tree().process_frame
		for b in BuildingSys.buildings:
			if b.collects_resource == "WATER":
				GameState.building_selected.emit(b); break
		for i in 10: await get_tree().process_frame
	elif mode.begins_with("panel:"):
		gc.call("start_new_game", "SMALL", "qa-seed", "QA")
		gc.call("bootstrap_test_colony")
		for i in 40: await get_tree().process_frame
		for i in 20:
			gc.call("_process", 0.1)
			await get_tree().process_frame
		var pn = gc.get_node_or_null("GameUI/UIRoot/" + mode.substr(6))
		if pn and pn.has_method("open"): pn.call("open")
		elif pn: pn.visible = true
		for i in 10: await get_tree().process_frame
	elif mode == "world":
		GameState.set_state(GameState.State.WORLD_CREATION)
		for i in 20: await get_tree().process_frame
	elif mode == "load":
		main.call("_show_load_screen")
		for i in 20: await get_tree().process_frame
	for i in 10: await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("[SHOT] gespeichert ", out, " ", img.get_size())
	get_tree().quit()
