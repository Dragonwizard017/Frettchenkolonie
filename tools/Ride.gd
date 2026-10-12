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
	_log("── Zugfahrt in Ich-Perspektive")
	var tr: TrainEntity = RailSys.trains[0]
	var player: PlayerController = gc.player
	gc.call("_toggle_fp_mode")
	check(gc._fp_mode, "Frettchenmodus an")
	# 1) warten bis der Zug am Bahnsteig hält
	var guard := 0
	while tr.state != "DWELL" and guard < 1500:
		await sim(1, 0.1, 50); guard += 1
	check(tr.state == "DWELL", "Zug hält (nach %d Schritten)" % guard)
	var rr: RailRenderer = gc.get_node("RailRenderer")
	await get_tree().process_frame; await get_tree().process_frame
	var parts: Array = rr.train_part_positions(tr)
	check(parts.size() == 1 + tr.wagons, "Teile des Zuges: Lok + %d Waggons" % tr.wagons)
	# weit weg: kein Einsteigen
	player.teleport_to(parts[0] + Vector3(20, 0, 20))
	gc.call("_update_fp_interaction")
	check(gc._fp_target_kind != "TRAIN", "weit entfernt: kein Einsteige-Hinweis")
	# nah dran: Hinweis
	player.teleport_to(parts[0] + Vector3(1.5, 0, 1.0))
	player.global_position.y = parts[0].y
	gc.call("_update_fp_interaction")
	check(gc._fp_target_kind == "TRAIN", "nah am haltenden Zug: Hinweis 'Einsteigen' (Ziel=%s)" % gc._fp_target_kind)
	var prompt_lbl: String = ""
	if gc._fp_hud != null and gc._fp_hud.has_method("get_prompt"): prompt_lbl = str(gc._fp_hud.call("get_prompt"))
	# 2) einsteigen
	gc.call("_try_start_fp_interaction")
	check(RailSys.riding == tr, "eingestiegen")
	check(player.is_riding(), "Spieler hängt am Zug")
	check(AchievementSys.is_unlocked("PLAYER_TRAIN_RIDE"), "Erfolg 'Fahrgast' freigeschaltet")
	await get_tree().process_frame; await get_tree().process_frame
	var loco: Node3D = rr.get_loco_node(tr)
	var off: float = Vector2(player.global_position.x - loco.global_position.x, player.global_position.z - loco.global_position.z).length()
	check(off < 0.6, "Spieler sitzt auf der Lok (Abstand %.2f)" % off)
	check(absf(player.camera.global_position.y - loco.global_position.y) > 1.0, "Kamera über dem Führerhaus (Höhe %.2f über Lok)" % (player.camera.global_position.y - loco.global_position.y))
	# WASD-Physik darf nicht bewegen
	var p_before: Vector3 = player.global_position
	player._physics_process(0.016)
	check(player.global_position.distance_to(p_before) < 0.001, "Physik bewegt den Mitfahrer nicht")
	var shot_args := OS.get_cmdline_user_args()
	if shot_args.size() > 0:
		GraphicsSettings.set_realistic(false)
		var g2 := 0
		while tr.state != "MOVING" and g2 < 600:
			await sim(1, 0.1, 50); g2 += 1
		_log("DEBUG vor Warten: riding=%s is_riding=%s fp=%s state=%s pos=%s" % [str(RailSys.riding != null), str(player.is_riding()), str(gc._fp_mode), tr.state, str(player.global_position)])
		await get_tree().create_timer(2.5).timeout
		await frames_n(5)
		_log("DEBUG nach Warten: riding=%s is_riding=%s fp=%s state=%s pos=%s loco=%s" % [str(RailSys.riding != null), str(player.is_riding()), str(gc._fp_mode), tr.state, str(player.global_position), str(rr.get_loco_node(tr).global_position)])
		get_viewport().get_texture().get_image().save_png(shot_args[0] + "_cab1.png")
		player.apply_look(Vector2(-400, 0))     # nach links schauen
		await frames_n(5)
		get_viewport().get_texture().get_image().save_png(shot_args[0] + "_cab2.png")
		player.apply_look(Vector2(900, 0))      # zurück zu den Waggons
		await frames_n(5)
		get_viewport().get_texture().get_image().save_png(shot_args[0] + "_cab3.png")
		_log("Fahrt-Screenshots gespeichert")
		get_tree().quit(); return
	# 3) mitfahren: Zug fährt los, Spieler folgt
	var start_head: Vector2 = tr.head
	var moved_checks := 0; var max_off := 0.0; var yaw_err_max := 0.0
	var steps_moving := 0
	for i in 300:
		await sim(1, 0.1, 1000)
		await get_tree().process_frame
		if tr.state == "MOVING":
			steps_moving += 1
			loco = rr.get_loco_node(tr)
			var o: float = Vector2(player.global_position.x - loco.global_position.x, player.global_position.z - loco.global_position.z).length()
			max_off = maxf(max_off, o)
		if tr.state == "DWELL" and steps_moving > 10: break
	check(tr.head.distance_to(start_head) > 3.0 or steps_moving > 10, "Zug ist gefahren (%d Schritte MOVING)" % steps_moving)
	check(max_off < 1.0, "Spieler bleibt bei der Lok (max. Abstand %.2f)" % max_off)
	# Blick: in ECHTZEIT messen (Spiel läuft selbst weiter), nur auf geraden Stücken (Richtung >= 0.7 s stabil)
	var rt_guard := 0
	while tr.state != "MOVING" and rt_guard < 600:
		await sim(1, 0.1, 50); rt_guard += 1
	var stable_t := 0.0; var last_dir: Vector2 = tr.heading; var yaw_checked := 0; var t_end: int = Time.get_ticks_msec() + 12000
	var last_ms: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() < t_end and yaw_checked < 5:
		await get_tree().process_frame
		var now_ms: int = Time.get_ticks_msec(); var dts: float = float(now_ms - last_ms) / 1000.0; last_ms = now_ms
		if tr.state != "MOVING": stable_t = 0.0; continue
		if tr.heading.distance_to(last_dir) > 0.01: stable_t = 0.0
		else: stable_t += dts
		last_dir = tr.heading
		if stable_t > 0.8:
			loco = rr.get_loco_node(tr)
			yaw_err_max = maxf(yaw_err_max, absf(angle_difference(player.rotation.y, loco.rotation.y - PI * 0.5)))
			yaw_checked += 1
	check(yaw_checked >= 3, "gerade Streckenstücke gemessen (%d Messungen)" % yaw_checked)
	check(yaw_err_max < 0.35, "Blick folgt der Fahrtrichtung auf geraden Stücken (max. Winkelfehler %.2f rad)" % yaw_err_max)
	# Blick umsehen (Maus)
	player.apply_look(Vector2(200, 0))
	await get_tree().process_frame
	check(absf(angle_difference(player.rotation.y, loco.rotation.y - PI * 0.5)) > 0.3, "freies Umsehen im Zug möglich")
	player.apply_look(Vector2(-200, 0))
	# 4) Hinweis während Fahrt vs. Halt
	guard = 0
	while tr.state != "DWELL" and guard < 800:
		await sim(1, 0.1, 50); guard += 1
	await get_tree().process_frame
	gc.call("_update_fp_interaction")
	check(gc._fp_target_kind == "TRAIN_EXIT", "am Halt: 'Aussteigen' (Ziel=%s)" % gc._fp_target_kind)
	# 5) aussteigen
	gc.call("_try_start_fp_interaction")
	check(RailSys.riding == null and not player.is_riding(), "ausgestiegen")
	await get_tree().process_frame
	var ex: Vector2i = renderer_tile(player)
	check(not RailSys.has_rail(ex.x, ex.y), "Aussteige-Kachel ist kein Gleis (%s)" % str(ex))
	var hd: Vector2i = Vector2i(roundi(tr.head.x), roundi(tr.head.y))
	check(maxi(absi(ex.x - hd.x), absi(ex.y - hd.y)) <= 1, "Aussteigen direkt am Zug (Kachel %s, Zug %s)" % [str(ex), str(hd)])
	# 6) erzwungenes Absteigen: Zug wird abgezogen
	guard = 0
	while tr.state != "DWELL" and guard < 800:
		await sim(1, 0.1, 50); guard += 1
	await get_tree().process_frame; await get_tree().process_frame
	parts = rr.train_part_positions(tr)
	player.teleport_to(parts[0] + Vector3(1.2, 0, 1.0)); player.global_position.y = parts[0].y
	gc.call("_update_fp_interaction"); gc.call("_try_start_fp_interaction")
	check(RailSys.riding == tr, "wieder eingestiegen")
	await sim(1, 0.1)
	RailSys.assign_train(tr, -1)       # Linie entzogen -> Zug fährt nicht mehr
	gc.call("_update_fp_interaction")
	check(RailSys.riding == null, "Linie entzogen: Mitfahrer wird abgesetzt")
	RailSys.assign_train(tr, line)
	# 7) Frettchenmodus verlassen während der Fahrt
	guard = 0
	while tr.state != "DWELL" and guard < 1500:
		await sim(1, 0.1, 50); guard += 1
	await get_tree().process_frame; await get_tree().process_frame
	parts = rr.train_part_positions(tr)
	player.teleport_to(parts[0] + Vector3(1.2, 0, 1.0)); player.global_position.y = parts[0].y
	gc.call("_update_fp_interaction"); gc.call("_try_start_fp_interaction")
	check(RailSys.riding == tr, "noch einmal eingestiegen")
	gc.call("_toggle_fp_mode")
	check(not gc._fp_mode and RailSys.riding == null and not player.is_riding(), "Iso-Ansicht beendet die Fahrt sauber")
	# 8) Speichern/Laden während der Fahrt
	gc.call("_toggle_fp_mode")
	guard = 0
	while tr.state != "DWELL" and guard < 1500:
		await sim(1, 0.1, 50); guard += 1
	await get_tree().process_frame; await get_tree().process_frame
	parts = rr.train_part_positions(tr)
	player.teleport_to(parts[0] + Vector3(1.2, 0, 1.0)); player.global_position.y = parts[0].y
	gc.call("_update_fp_interaction"); gc.call("_try_start_fp_interaction")
	check(RailSys.riding == tr, "für den Speichertest wieder eingestiegen")
	check(SaveSys.save("ride_test", gc), "save ok")
	check(SaveSys.load_game("ride_test", gc), "load ok")
	await get_tree().process_frame; await get_tree().process_frame; await get_tree().process_frame
	check(RailSys.riding == null and not player.is_riding(), "nach dem Laden: kein Mitfahrer")
	await sim(200, 0.1)
	check(RailSys.trains.size() == 1, "Zug existiert nach Laden weiter")
	_log("FERTIG - %d Fehler" % fails)
	get_tree().quit(1 if fails > 0 else 0)

func renderer_tile(p: PlayerController) -> Vector2i:
	return gc.renderer.world3d_to_tile(p.global_position)

func frames_n(n: int) -> void:
	for i in n: await get_tree().process_frame
