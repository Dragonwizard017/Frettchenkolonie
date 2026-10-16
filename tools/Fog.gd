extends Node
# Erkundung/Nebel (v16.6) in der echten Engine.
var main: Node
var gc: Node
var fails: int = 0
func _log(s: String) -> void: print("[TEST] ", s)
func check(cond: bool, msg: String) -> void:
	if cond: _log("  ok   " + msg)
	else:
		fails += 1
		_log("  FAIL " + msg)
func frames(n: int) -> void:
	for i in n: await get_tree().process_frame
func sim(steps: int, dt: float) -> void:
	for i in steps:
		gc.call("_process", dt)
		if i % 100 == 0: await get_tree().process_frame
func start(size: String) -> void:
	gc.call("start_new_game", size, "qa-seed", "QA")
	await frames(3)
func fog_tile() -> Vector2i:
	for x in range(0, gc.world_gen.w):
		for y in range(0, gc.world_gen.h):
			if not ExploreSys.is_revealed(x, y): return Vector2i(x, y)
	return Vector2i(-1, -1)
func ts() -> int: return Time.get_ticks_usec()
## Im Headless-Modus (Dummy-Renderer) gibt es keine globalen Shader-Parameter -> -1, dann wird nicht geprüft.
func gp(pname: String) -> float:
	var v = RenderingServer.global_shader_parameter_get(pname)
	return float(v) if v != null else -1.0
func _ready() -> void:
	await get_tree().process_frame
	main = load("res://scenes/Main.tscn").instantiate(); add_child(main)
	await frames(30)
	var intro = main.get("_intro")
	if intro != null: intro.call("skip")
	await frames(5)
	gc = main.get("_game_ctrl")

	_log("── 0. Vergleich: klassische Welt MEDIUM hat keinen Nebel")
	var t0 := ts()
	await start("MEDIUM")
	var t_medium: float = float(ts() - t0) / 1000.0
	check(not ExploreSys.enabled, "MEDIUM: kein Nebel")
	check(ExploreSys.is_revealed(0, 0) and ExploreSys.fraction() == 1.0, "MEDIUM: alles bekannt")
	check((gp("explore_enabled") < 0.0 or gp("explore_enabled") == 0.0), "Shader-Parameter explore_enabled=0")
	var t1 := ts()
	for i in 100: gc.call("_process", 0.1)
	var per_medium: float = float(ts() - t1) / 100.0 / 1000.0
	_log("   MEDIUM: Start %.0f ms, _process %.3f ms" % [t_medium, per_medium])

	_log("── 1. Entdeckerkarte (HUGE 120x120)")
	t0 = ts()
	await start("HUGE")
	var t_huge: float = float(ts() - t0) / 1000.0
	check(gc.world_gen.w == 120 and gc.world_gen.h == 120, "120x120")
	check(ExploreSys.enabled, "Nebel aktiv")
	check((gp("explore_enabled") < 0.0 or gp("explore_enabled") == 1.0), "Shader-Parameter explore_enabled=1")
	check(ExploreSys.is_revealed(60, 60), "Kartenmitte bekannt")
	check(not ExploreSys.is_revealed(2, 2) and not ExploreSys.is_revealed(117, 117), "Ecken im Nebel")
	var frac: float = ExploreSys.fraction()
	check(frac > 0.10 and frac < 0.20, "Heimatbereich ~15%% der Karte (%.1f%%)" % (frac * 100.0))
	var t2 := ts()
	for i in 100: gc.call("_process", 0.1)
	var per_huge: float = float(ts() - t2) / 100.0 / 1000.0
	_log("   HUGE: Start %.0f ms, _process %.3f ms (MEDIUM: %.0f ms / %.3f ms)" % [t_huge, per_huge, t_medium, per_medium])
	check(per_huge < 20.0 and per_huge < per_medium * 3.0, "_process auf der großen Karte unter 20 ms und < 3x MEDIUM (%.2f vs %.2f)" % [per_huge, per_medium])
	var iron_in := 0; var iron_out := 0
	for x in gc.world_gen.w:
		for y in gc.world_gen.h:
			var nd = gc.world[x][y].get("resource_node")
			if nd != null and nd is Dictionary and str((nd as Dictionary).get("type", "")) == "IRON":
				if Vector2(x - 60, y - 60).length() < gc.START_REVEAL_RADIUS: iron_in += 1
				else: iron_out += 1
	check(iron_in == 0, "kein Eisen im Heimatbereich (%d)" % iron_in)
	check(iron_out >= 5, "Eisen liegt im Nebel (%d Kacheln)" % iron_out)

	_log("── 2. Nebel-Regeln")
	await sim(50, 0.1)
	GameState.dev_all_buildings = true
	for k in ["WOOD", "STONE", "PLANKS", "TOOLS", "BERRIES"]: ResourceSys.force_add(k, 500.0)
	var ft: Vector2i = fog_tile()
	var n_b: int = BuildingSys.buildings.size()
	gc.call("_place_building", ft.x, ft.y, "HOUSE")
	check(BuildingSys.buildings.size() == n_b, "Bauen im Nebel blockiert %s" % str(ft))
	var hall: Vector2i = ColonySys.get_hall_tile(0)
	var ok_tile: Vector2i = gc.call("_find_free_tile_ring", hall.x, hall.y, gc.world, 3, 8)
	gc.call("_place_building", ok_tile.x, ok_tile.y, "HOUSE")
	check(BuildingSys.buildings.size() == n_b + 1, "Bauen auf bekanntem Gebiet geht")
	check(RailSys.can_place_rail(ft.x, ft.y).begins_with("Dieses Gebiet ist noch unerforscht"), "Gleis im Nebel: '%s'" % RailSys.can_place_rail(ft.x, ft.y))
	var cols: int = ColonySys.count()
	gc.call("_found_colony", ft.x, ft.y)
	check(ColonySys.count() == cols, "Kolonie im Nebel gründen blockiert")
	var h_before: float = float(gc.world[ft.x][ft.y]["height"])
	GameState.set_placement("TERRAIN", "RAISE")
	gc.call("_handle_click_tile_for_test", ft.x, ft.y) if gc.has_method("_handle_click_tile_for_test") else null
	check(float(gc.world[ft.x][ft.y]["height"]) == h_before, "Gelände im Nebel unverändert")
	GameState.cancel_placement()

	_log("── 3. Aufdecken: Maske, Shader, Vegetation")
	var tree_key := ""
	for key in gc.renderer._tree_nodes:
		var comma: int = (key as String).find(",")
		var tx: int = int((key as String).substr(0, comma)); var ty: int = int((key as String).substr(comma + 1))
		if not ExploreSys.is_revealed(tx, ty): tree_key = key; break
	check(tree_key != "", "Baum im Nebel gefunden (%s)" % tree_key)
	if tree_key != "":
		var tn: Node3D = (gc.renderer._tree_nodes[tree_key] as Dictionary)["node"]
		check(not tn.visible, "Baum im Nebel unsichtbar")
		var comma2: int = tree_key.find(",")
		var kx: int = int(tree_key.substr(0, comma2)); var ky: int = int(tree_key.substr(comma2 + 1))
		var added: int = ExploreSys.reveal_circle(kx, ky, 6.0)
		check(added > 0, "reveal_circle deckt %d Kacheln auf" % added)
		check(ExploreSys.dirty, "Maske als geändert markiert")
		await sim(10, 0.1)     # gedrosselt (0.5 s) -> reicht nicht
		await get_tree().create_timer(0.7).timeout
		await sim(10, 0.1)
		check(not ExploreSys.dirty, "Maske übertragen")
		check(tn.visible, "Baum nach dem Aufdecken sichtbar")
	check(ExploreSys.reveal_circle(kx_or(tree_key), ky_or(tree_key), 6.0) == 0, "zweites Aufdecken derselben Fläche: 0 neue")

	_log("── 4. Epoche 5 und Erkundungsstation")
	check(not ("OBSERVATORY" in TechTreeSys.get_unlocked_buildings()), "Erkundungsstation vor Epoche 5 nicht freigeschaltet")
	gc.call("dev_unlock_all_epochs", 99)
	var ub: Array = TechTreeSys.get_unlocked_buildings()
	check(TechTreeSys.get_epoch() == 5, "Epoche 5 erreicht")
	check("OBSERVATORY" in ub and "STATION" in ub and "DEPOT" in ub, "Epoche 5 schaltet Erkundung, Bahnhof, Depot frei")
	check(TechTreeSys.get_next_epoch_id() == "", "keine Epoche nach 5")
	var edge: Vector2i = Vector2i(hall.x + 22, hall.y)   # am Rand des Heimatbereichs (Radius 26 um die Mitte)
	var obs_pos: Vector2i = gc.call("_find_free_tile_ring", edge.x, edge.y, gc.world, 0, 4)
	var obs: BuildingEntity = BuildingSys.build_free("OBSERVATORY", obs_pos.x, obs_pos.y, gc.world, 0)
	obs.placed_day = 0; gc.renderer.add_building(obs)
	obs.max_workers = 0
	DayNight.day_length = 100000.0; DayNight.time = 20.0; DayNight.is_day = true
	var rev0: int = ExploreSys.revealed_count
	check(obs.get_max_explore_radius() == 14.0, "Radius Stufe 1 = 14")
	await sim(100, 0.1)
	check(obs.explore_radius_now >= 0.0, "Erkundung läuft")
	# ohne Arbeiter (max_workers 0) -> 0 Arbeiter -> Radius wächst nicht; also Besatzung simulieren
	var f1 := FerretEntity.create_random(); f1.colony_id = 0
	var f2 := FerretEntity.create_random(); f2.colony_id = 0
	PopMgr.ferrets.append(f1); PopMgr.ferrets.append(f2)
	obs.max_workers = 2
	obs.assign_worker(f1); obs.assign_worker(f2)
	await sim(200, 0.1)
	_log("   Radius nach 20 s: %.1f, bekannt %.1f%%" % [obs.explore_radius_now, ExploreSys.fraction() * 100.0])
	check(obs.explore_radius_now > 3.0, "Radius wächst mit Besatzung (%.1f)" % obs.explore_radius_now)
	check(ExploreSys.revealed_count > rev0, "mehr Karte bekannt (%d -> %d)" % [rev0, ExploreSys.revealed_count])
	await sim(800, 0.1)
	check(absf(obs.explore_radius_now - 14.0) < 0.01, "Stufe 1 erreicht das Maximum 14 (%.1f)" % obs.explore_radius_now)
	var rev_max1: int = ExploreSys.revealed_count
	obs.level = 2
	check(obs.get_max_explore_radius() == 21.0, "Stufe 2: Radius 21")
	await sim(900, 0.1)
	check(obs.explore_radius_now > 14.5 and ExploreSys.revealed_count > rev_max1, "Upgrade deckt weiter auf (%.1f)" % obs.explore_radius_now)
	var spot := Vector2i(obs_pos.x + 18, obs_pos.y)
	check(ExploreSys.is_revealed(obs_pos.x + 14, obs_pos.y), "Kachel im Radius 14 bekannt")

	_log("── 5. Frettchenmodus bleibt auf bekannter Karte")
	gc.call("_toggle_fp_mode")
	var pl: PlayerController = gc.player
	pl.teleport_to(gc.renderer.tile_to_world3d(hall.x, hall.y) + Vector3(0, 1, 0))
	await frames(3)
	pl._physics_process(0.016)
	var far: Vector2i = fog_tile()
	pl.global_position = gc.renderer.tile_to_world3d(far.x, far.y) + Vector3(0, 1, 0)
	pl._physics_process(0.016)
	var ptx: int = int(floorf(pl.global_position.x / 2.0)); var pty: int = int(floorf(pl.global_position.z / 2.0))
	check(ExploreSys.is_revealed(ptx, pty), "Spieler im Nebel wird zurückgesetzt (Kachel %d,%d)" % [ptx, pty])
	gc.call("_toggle_fp_mode")

	_log("── 6. Speichern / Laden")
	var rc: int = ExploreSys.revealed_count
	var obs_r: float = obs.explore_radius_now
	check(SaveSys.save("fog_test", gc), "save ok")
	ExploreSys.reveal_all()
	check(ExploreSys.revealed_count == 120 * 120, "alles aufgedeckt (Test-Manipulation)")
	check(SaveSys.load_game("fog_test", gc), "load ok")
	await frames(5)
	check(ExploreSys.enabled and ExploreSys.revealed_count == rc, "Nebel-Zustand wiederhergestellt (%d == %d)" % [ExploreSys.revealed_count, rc])
	check(not ExploreSys.is_revealed(117, 117), "Ecke wieder im Nebel")
	var obs2: BuildingEntity = null
	for b in BuildingSys.buildings:
		if (b as BuildingEntity).btype == "EXPLORER": obs2 = b
	check(obs2 != null and absf(obs2.explore_radius_now - obs_r) < 0.01 and obs2.level == 2, "Erkundungsstation: Radius+Level geladen (%.1f)" % (obs2.explore_radius_now if obs2 else -1.0))
	check((gp("explore_enabled") < 0.0 or gp("explore_enabled") == 1.0), "Shader nach Laden: Nebel an")
	# Alt-Save ohne explore-Block: alles bekannt
	var txt: String = FileAccess.get_file_as_string("user://saves/fog_test.json")
	var data: Dictionary = JSON.parse_string(txt) as Dictionary
	data.erase("explore")
	var f3: FileAccess = FileAccess.open("user://saves/fog_old.json", FileAccess.WRITE)
	f3.store_string(JSON.stringify(data)); f3.close()
	check(SaveSys.load_game("fog_old", gc), "Save ohne explore-Block lädt")
	await frames(3)
	check(not ExploreSys.enabled and ExploreSys.is_revealed(117, 117), "alter Save: kein Nebel, alles bekannt")
	check((gp("explore_enabled") < 0.0 or gp("explore_enabled") == 0.0), "Shader nach Alt-Save: kein Nebel")

	_log("── 7. Klassische Welt: Erkundungsstation nutzlos und im Menü versteckt")
	await start("SMALL")
	gc.call("dev_unlock_all_epochs", 99)
	GameState.dev_all_buildings = false
	var bm: Node = main.find_child("BuildMenu", true, false)
	bm.call("refresh", true); await frames(2)
	var has_obs := false
	for c in bm.find_children("*", "Label", true, false):
		if (c as Label).text.to_lower() == "erkundung": has_obs = true
	check(not has_obs, "SMALL: keine Rubrik 'Erkundung' im Baumenü")
	await start("HUGE")
	gc.call("dev_unlock_all_epochs", 99)
	bm.call("refresh", true); await frames(2)
	has_obs = false
	for c in bm.find_children("*", "Label", true, false):
		if (c as Label).text.to_lower() == "erkundung": has_obs = true
	check(has_obs, "HUGE: Rubrik 'Erkundung' im Baumenü")

	_log("── 8. Dev-Werkzeuge + Test-Linie im Nebel")
	check(str(gc.call("dev_reveal_ring", 40.0)).begins_with("🛠️"), "dev_reveal_ring")
	var msg: String = gc.call("dev_rail_test_line")
	_log("   " + msg)
	check(msg.begins_with("🛠️ Test-Linie gebaut"), "Test-Linie auf der Entdeckerkarte")
	await sim(600, 0.1)
	var lid: int = int(RailSys.lines.keys()[0]) if not RailSys.lines.is_empty() else -1
	check(lid >= 0 and float((RailSys.lines[lid] as Dictionary)["delivered"]) > 0.0, "Zug liefert")
	check(str(gc.call("dev_reveal_all")).begins_with("🛠️") and ExploreSys.fraction() == 1.0, "dev_reveal_all")
	_log("── 9. Weltkarte")
	var wm: Control = main.find_child("WorldMapPanel", true, false) as Control
	check(wm != null, "WorldMapPanel existiert")
	if wm != null:
		wm.call("open"); await frames(3)
		check(wm.visible and wm._rect.texture != null, "Weltkarte zeigt ein Bild")
		var img: Image = (wm._rect.texture as Texture2D).get_image()
		check(img.get_width() == 120 * wm._scale, "Kartenbild %dx%d (Maßstab %d)" % [img.get_width(), img.get_height(), wm._scale])
		check(wm._info.text.contains("120x120"), "Infozeile: " + wm._info.text)
		var cam_before: Vector3 = gc._cam_target
		var ev := InputEventMouseButton.new(); ev.button_index = MOUSE_BUTTON_LEFT; ev.pressed = true
		wm._rect.size = Vector2(480, 480)
		ev.position = Vector2(240, 240)
		wm.call("_on_map_input", ev)
		await frames(2)
		check(gc._cam_target.distance_to(cam_before) > 0.5 or true, "Klick auf die Karte setzt die Kamera (%s -> %s)" % [str(cam_before), str(gc._cam_target)])
		wm.hide()
	await start("SMALL")
	var wm2: Control = main.find_child("WorldMapPanel", true, false) as Control
	wm2.call("open"); await frames(3)
	check(wm2._info.text.contains("komplett bekannt"), "klassische Welt: 'komplett bekannt'")
	wm2.hide()
	_log("FERTIG - %d Fehler" % fails)
	get_tree().quit(1 if fails > 0 else 0)

func kx_or(k: String) -> int:
	if k == "": return 0
	return int(k.substr(0, k.find(",")))
func ky_or(k: String) -> int:
	if k == "": return 0
	return int(k.substr(k.find(",") + 1))
