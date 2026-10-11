extends Node
var main: Node
var gc: Node
var fails: int = 0
func _log(s: String) -> void: print("[TEST] ", s)
func check(cond: bool, msg: String) -> void:
	if cond: _log("  ok   " + msg)
	else:
		fails += 1
		_log("  FAIL " + msg)
func sim(steps: int, dt: float, yield_every: int = 100) -> void:
	for i in steps:
		gc.call("_process", dt)
		if i % yield_every == 0: await get_tree().process_frame
func pool(cid: int, res: String) -> float:
	ResourceSys.use_colony(cid)
	var v: float = float(ResourceSys.resources.get(res, 0.0))
	ResourceSys.use_colony(ColonySys.active_id)
	return v
func far_free_tile(from: Vector2i, min_d: float, max_d: float) -> Vector2i:
	for x in gc.world_gen.w:
		for y in gc.world_gen.h:
			var t: Dictionary = (gc.world[x] as Array)[y]
			if t.get("building") != null or str(t.get("biome", "")) == "WATER": continue
			var d: float = Vector2(from).distance_to(Vector2(x, y))
			if d >= min_d and d <= max_d: return Vector2i(x, y)
	return Vector2i(-1, -1)
func bfs(a: Vector2i, b: Vector2i) -> Array:
	var prev: Dictionary = {}; var q: Array = [a]; prev[a] = a
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if c == b: break
		for d in RailSys.DIRS:
			var n: Vector2i = c + (d as Vector2i)
			if n.x < 0 or n.y < 0 or n.x >= gc.world_gen.w or n.y >= gc.world_gen.h or prev.has(n): continue
			var t: Dictionary = (gc.world[n.x] as Array)[n.y]
			var bi: String = str(t.get("biome", ""))
			if bi == "WATER" or bi == "MOUNTAIN": continue
			if t.get("building") != null and n != b: continue
			if FarmSys.has_field(n.x, n.y): continue
			prev[n] = c; q.append(n)
	if not prev.has(b): return []
	var path: Array = []; var cur: Vector2i = b
	while cur != a: path.push_front(cur); cur = prev[cur]
	path.push_front(a)
	return path
func _ready() -> void:
	await get_tree().process_frame
	main = load("res://scenes/Main.tscn").instantiate(); add_child(main)
	for i in 30: await get_tree().process_frame
	var intro = main.get("_intro")
	if intro != null: intro.call("skip")
	for i in 5: await get_tree().process_frame
	gc = main.get("_game_ctrl")
	gc.call("start_new_game", "SMALL", "qa-seed", "QA")
	await sim(100, 0.1)
	gc.call("bootstrap_test_colony")
	await sim(50, 0.1)
	GameState.dev_all_buildings = true
	for k in ["WOOD", "STONE", "PLANKS", "TOOLS", "BERRIES", "IRON_BARS"]: ResourceSys.force_add(k, 300.0)

	_log("── 1. Zwei Kolonien und Bahnhöfe")
	var hall0: Vector2i = ColonySys.get_hall_tile(0)
	var site: Vector2i = far_free_tile(hall0, 21.0, 30.0)
	gc.call("_found_colony", site.x, site.y)
	check(ColonySys.count() == 2, "2 Kolonien")
	gc.call("focus_colony", 0)
	var hall1: Vector2i = ColonySys.get_hall_tile(1)
	var pa: Vector2i = gc.call("_find_free_tile_ring", hall0.x, hall0.y, gc.world, 3, 7)
	var pb: Vector2i = gc.call("_find_free_tile_ring", hall1.x, hall1.y, gc.world, 3, 7)
	var A: BuildingEntity = BuildingSys.build_free("STATION", pa.x, pa.y, gc.world, 0)
	var B: BuildingEntity = BuildingSys.build_free("STATION", pb.x, pb.y, gc.world, 1)
	for b in [A, B]:
		(b as BuildingEntity).placed_day = 0; gc.renderer.add_building(b)
	check(A != null and B != null, "Bahnhöfe gebaut %s %s" % [str(pa), str(pb)])
	check(RailSys.get_station_name(A) != RailSys.get_station_name(B), "Bahnhöfe haben eindeutige Namen (%s / %s)" % [RailSys.get_station_name(A), RailSys.get_station_name(B)])

	_log("── 2. Gleisregeln")
	var route: Array = bfs(pa, pb)
	check(route.size() > 5, "Route gefunden (%d Kacheln)" % route.size())
	# Gelände entlang der Route flach machen, Vorkommen räumen (Testaufbau)
	var h0: float = float(((gc.world[pa.x] as Array)[pa.y] as Dictionary)["height"])
	for v in route:
		var t: Dictionary = (gc.world[(v as Vector2i).x] as Array)[(v as Vector2i).y]
		t["height"] = h0; t["resource_node"] = null
	# Depot DIREKT neben Bahnhof A (4er-Nachbar, nicht auf der Route), ebenfalls auf gleicher Höhe
	var pd := Vector2i(-1, -1)
	for d in RailSys.DIRS:
		var c: Vector2i = pa + (d as Vector2i)
		var tt: Dictionary = (gc.world[c.x] as Array)[c.y]
		if c in route or tt.get("building") != null or str(tt.get("biome", "")) in ["WATER", "MOUNTAIN"] or FarmSys.has_field(c.x, c.y): continue
		pd = c; break
	check(pd.x >= 0, "Platz für Depot neben Bahnhof A %s" % str(pd))
	var tdp: Dictionary = (gc.world[pd.x] as Array)[pd.y]
	tdp["height"] = h0; tdp["resource_node"] = null
	var D: BuildingEntity = BuildingSys.build_free("DEPOT", pd.x, pd.y, gc.world, 0)
	gc.renderer.add_building(D)
	check(D != null and D.colony_id == 0, "Depot in Kolonie 0 %s" % str(pd))
	gc.renderer.refresh_terrain()
	# Steilheit prüfen: eine Kachel neben der Route künstlich erhöhen
	var probe: Vector2i = (route[2] as Vector2i) + Vector2i(0, 1)
	if probe in route: probe = (route[2] as Vector2i) + Vector2i(1, 0)
	var tp: Dictionary = (gc.world[probe.x] as Array)[probe.y]
	var old_h: float = float(tp["height"]); var old_node = tp.get("resource_node")
	var old_biome: String = str(tp["biome"])
	RailSys.place_rail((route[2] as Vector2i).x, (route[2] as Vector2i).y)
	tp["height"] = h0 + 3.0; tp["resource_node"] = null
	if old_biome != "WATER" and old_biome != "MOUNTAIN" and tp.get("building") == null:
		check(RailSys.can_place_rail(probe.x, probe.y).begins_with("Zu steil"), "Steiler Hang wird abgelehnt: '%s'" % RailSys.can_place_rail(probe.x, probe.y))
	tp["height"] = old_h; tp["resource_node"] = old_node
	RailSys.remove_rail((route[2] as Vector2i).x, (route[2] as Vector2i).y)
	var water_tile := Vector2i(-1, -1)
	for x in gc.world_gen.w:
		for y in gc.world_gen.h:
			if str(((gc.world[x] as Array)[y] as Dictionary).get("biome", "")) == "WATER" and water_tile.x < 0: water_tile = Vector2i(x, y)
	if water_tile.x >= 0: check(RailSys.can_place_rail(water_tile.x, water_tile.y).begins_with("Auf Wasser"), "Wasser wird abgelehnt")
	check(RailSys.can_place_rail(pa.x, pa.y).begins_with("Hier steht ein Gebäude"), "Gleis auf Gebäude abgelehnt")

	_log("── 3. Linie ohne Gleise ist nicht fahrbereit")
	var line: int = RailSys.create_line()
	RailSys.add_stop(line, RailSys.key(pa.x, pa.y))
	RailSys.add_stop(line, RailSys.key(pb.x, pb.y))
	check(RailSys.line_status(line).begins_with("Kein Gleispfad"), "ohne Gleise: '%s'" % RailSys.line_status(line))

	_log("── 4. Gleise legen (über das Spiel-Werkzeug)")
	GameState.dev_all_buildings = false
	var rails_before: float = pool(0, "PLANKS")
	var iron_before: float = pool(0, "IRON")
	var placed := 0
	for i in range(1, route.size() - 1):
		var v: Vector2i = route[i]
		gc.call("_place_rail", v.x, v.y, "PLACE", true)
		if RailSys.has_rail(v.x, v.y): placed += 1
	check(placed == route.size() - 2, "%d von %d Gleisen gelegt" % [placed, route.size() - 2])
	check(absf((rails_before - pool(0, "PLANKS")) - float(placed)) < 0.01, "Kosten: %d Bretter bezahlt" % placed)
	GameState.dev_all_buildings = true
	check(RailSys.line_status(line) == "", "Linie fahrbereit: '%s'" % RailSys.line_status(line))
	var gp: Array = RailSys.find_path(RailSys.key(pa.x, pa.y), RailSys.key(pb.x, pb.y))
	check(gp.size() == route.size(), "A* findet Weg (%d Knoten)" % gp.size())
	check(RailSys.find_path(RailSys.key(pd.x, pd.y), RailSys.key(pb.x, pb.y)).size() == route.size() + 1, "Depot ist über den Bahnhof angebunden")

	# Bootstrap-Kolonie ist über Kapazität gefüllt (force_add) -> Lagerbestand realistisch machen
	ResourceSys.use_colony(0)
	for k in ResourceSys.resources.keys(): ResourceSys.resources[k] = 30.0
	ResourceSys.resources["PLANKS"] = 400.0
	ResourceSys.use_colony(ColonySys.active_id)
	_log("── 5. Fracht: Bretter 0 -> 1, Holz 1 -> 0")
	RailSys.add_shipment(line, "PLANKS", 0, 1)
	RailSys.add_shipment(line, "WOOD", 1, 0)
	var err: String = RailSys.buy_train(D, line)
	check(err == "", "Zug gekauft")
	check(RailSys.trains.size() == 1, "1 Zug")
	var pl0: float = pool(0, "PLANKS"); var pl1: float = pool(1, "PLANKS")
	var wd0: float = pool(0, "WOOD"); var wd1: float = pool(1, "WOOD")
	for chunk in 9:
		await sim(100, 0.1)
		var tq: TrainEntity = RailSys.trains[0]
		_log("   t=%ds state=%s next=%d trips=%d cargo=%s PL0=%.0f PL1=%.0f WD0=%.0f WD1=%.0f deliv=%.0f" % [(chunk + 1) * 10, tq.state, tq.next_stop, tq.trips, str(tq.cargo), pool(0, "PLANKS"), pool(1, "PLANKS"), pool(0, "WOOD"), pool(1, "WOOD"), float((RailSys.lines[line] as Dictionary)["delivered"])])
	var shot_args := OS.get_cmdline_user_args()
	if shot_args.size() > 0:
		GraphicsSettings.set_realistic(false)
		Engine.time_scale = 0.0005    # Software-Rendering ist langsam - Zug soll fürs Foto stillhalten
		var tq2: TrainEntity = RailSys.trains[0]
		var mid_t: Vector2i = route[route.size() / 2]
		var ct: Vector3 = gc.renderer.tile_to_world3d(mid_t.x, mid_t.y); gc.set("_cam_target", ct); gc.set("_cam_zoom", 22.0); gc.call("_apply_camera")
		for i in 15: await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(shot_args[0] + "_route.png")
		var ct2: Vector3 = gc.renderer.tile_to_world3d(roundi(tq2.head.x), roundi(tq2.head.y)); gc.set("_cam_target", ct2); gc.set("_cam_zoom", 9.0); gc.call("_apply_camera")
		for i in 15: await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(shot_args[0] + "_train.png")
		gc.set("_cam_zoom", 20.0); gc.call("_apply_camera")
		var lpn: Node = main.find_child("LinePanel", true, false)
		lpn.call("open")
		for i in 15: await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(shot_args[0] + "_panel.png")
		_log("Screenshots gespeichert")
		get_tree().quit(); return
	var tr: TrainEntity = RailSys.trains[0]
	_log("   Zug: Zustand=%s Halte=%d Fracht=%s head=%s" % [tr.state, tr.trips, str(tr.cargo), str(tr.head)])
	check(tr.trips >= 2, "Zug hat Halte angefahren (%d)" % tr.trips)
	check(pool(1, "PLANKS") > pl1 + 1.0, "Bretter in Kolonie 1 angekommen (%.0f -> %.0f)" % [pl1, pool(1, "PLANKS")])
	check(pool(0, "PLANKS") < pl0, "Bretter aus Kolonie 0 weg (%.0f -> %.0f)" % [pl0, pool(0, "PLANKS")])
	check(pool(0, "WOOD") > wd0 - 1.0 or pool(1, "WOOD") < wd1, "Holz fährt von Kolonie 1 ab")
	check(float((RailSys.lines[line] as Dictionary)["delivered"]) >= 100.0, "Statistik 'geliefert' = %.0f" % float((RailSys.lines[line] as Dictionary)["delivered"]))
	check(ResourceSys.current_colony == ColonySys.active_id, "Kontext nach Bahnsimulation = aktive Kolonie")

	_log("── 6. Gleis wird unterbrochen")
	var mid: Vector2i = route[route.size() / 2]
	RailSys.remove_rail(mid.x, mid.y)
	await sim(400, 0.1)
	check(tr.state == "BLOCKED" or tr.state == "DWELL" or tr.state == "MOVING", "Zug reagiert (Zustand %s)" % tr.state)
	check(RailSys.line_status(line).begins_with("Kein Gleispfad"), "Linie meldet Unterbrechung")
	var trips_blocked: int = tr.trips
	await sim(300, 0.1)
	check(tr.trips <= trips_blocked + 1, "Zug fährt nicht durch die Lücke")
	gc.call("_place_rail", mid.x, mid.y, "PLACE", true)
	await sim(900, 0.1)
	check(tr.trips > trips_blocked + 1, "Nach Reparatur fährt der Zug weiter (Halte %d -> %d)" % [trips_blocked, tr.trips])

	_log("── 7. Speichern / Laden mitten im Betrieb")
	var trips_save: int = tr.trips
	var rails_n: int = RailSys.rails.size()
	var delivered_save: float = float((RailSys.lines[line] as Dictionary)["delivered"])
	check(SaveSys.save("rail_test", gc), "save ok")
	check(SaveSys.load_game("rail_test", gc), "load ok")
	check(RailSys.rails.size() == rails_n, "Gleise gleich (%d)" % RailSys.rails.size())
	check(RailSys.lines.has(line) and RailSys.trains.size() == 1, "Linie und Zug geladen")
	check(absf(float((RailSys.lines[line] as Dictionary)["delivered"]) - delivered_save) < 0.01, "Statistik gespeichert")
	await sim(900, 0.1)
	var tr2: TrainEntity = RailSys.trains[0]
	check(tr2.trips >= 1, "Zug fährt nach dem Laden weiter (Halte %d)" % tr2.trips)
	check(float((RailSys.lines[line] as Dictionary)["delivered"]) > delivered_save, "weiter geliefert nach Laden (%.0f -> %.0f)" % [delivered_save, float((RailSys.lines[line] as Dictionary)["delivered"])])

	_log("── 8. Darstellung")
	var rr: Node = gc.get_node_or_null("RailRenderer")
	check(rr != null, "RailRenderer existiert")
	await get_tree().process_frame
	await get_tree().process_frame
	var mesh_n := 0
	for c in rr.get_children():
		if c is MeshInstance3D: mesh_n += 1
	check(mesh_n >= RailSys.rails.size(), "Gleis-Meshes (%d) für %d Gleise" % [mesh_n, RailSys.rails.size()])
	check(rr.get_child_count() >= mesh_n + 1, "Zug-Knoten vorhanden")

	_log("── 9. UI")
	var lp: Node = main.find_child("LinePanel", true, false)
	check(lp != null, "LinePanel existiert")
	if lp != null:
		lp.call("open"); await get_tree().process_frame
		check(lp.get_child_count() > 0, "LinePanel baut Inhalt auf")
		lp.call("hide")
	var bm: Node = main.find_child("BuildMenu", true, false)
	bm.call("refresh", true); await get_tree().process_frame

	_log("── 10. Alte Saves (ohne rail-Block) laden")
	var txt: String = FileAccess.get_file_as_string("user://saves/rail_test.json")
	var data: Dictionary = JSON.parse_string(txt) as Dictionary
	data.erase("rail")
	var f2: FileAccess = FileAccess.open("user://saves/rail_old.json", FileAccess.WRITE)
	f2.store_string(JSON.stringify(data)); f2.close()
	check(SaveSys.load_game("rail_old", gc), "Save ohne Gleisblock lädt")
	check(RailSys.rails.is_empty() and RailSys.trains.is_empty(), "leeres Gleisnetz")
	await sim(100, 0.1)
	_log("FERTIG - %d Fehler" % fails)
	get_tree().quit(1 if fails > 0 else 0)
