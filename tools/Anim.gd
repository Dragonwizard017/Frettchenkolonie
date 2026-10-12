extends Node
# Prüft die Arbeits-Animationen der Gebäude (v16.3) in der echten Engine.
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
func root_of(b: BuildingEntity) -> Node:
	return gc.renderer._building_nodes.get("%d,%d" % [b.tile_x, b.tile_y]) as Node
func _ready() -> void:
	await get_tree().process_frame
	main = load("res://scenes/Main.tscn").instantiate(); add_child(main)
	await frames(30)
	var intro = main.get("_intro")
	if intro != null: intro.call("skip")
	await frames(5)
	gc = main.get("_game_ctrl")
	gc.call("start_new_game", "SMALL", "qa-seed", "QA")
	await frames(10)
	GameState.dev_all_buildings = true
	DayNight.day_length = 100000.0; DayNight.time = 20.0; DayNight.is_day = true

	# Gebäude mit eigenem Modell + Rathaus/Bahnhof/Depot auf Raster setzen
	var ids: Array = []
	for k in gc.renderer.BUILDING_MODEL_OVERRIDES.keys(): ids.append(str(k))
	for extra in ["STATION", "DEPOT"]:
		if not ids.has(extra): ids.append(extra)
	ids.sort()
	var cols := 8; var gap := 2
	var w: int = cols * gap + 1; var h: int = (ids.size() / cols + 2) * gap + 1
	var best := Vector2i(-1, -1)
	for x in range(3, gc.world_gen.w - w - 2):
		for y in range(3, gc.world_gen.h - h - 2):
			if best.x >= 0: break
			var ok := true
			for dx in range(0, w):
				for dy in range(0, h):
					var t: Dictionary = gc.world[x + dx][y + dy]
					if t.get("building") != null or str(t.get("biome", "")) == "WATER": ok = false; break
				if not ok: break
			if ok: best = Vector2i(x, y)
	if best.x < 0: best = Vector2i(4, 4)
	var placed: Array = []
	for i in ids.size():
		var tx: int = best.x + (i % cols) * gap
		var ty: int = best.y + (i / cols) * gap
		var b = BuildingSys.build_free(str(ids[i]), tx, ty, gc.world, 0)
		if b == null: continue
		b.placed_day = 0
		# erste 8 Typen: Arbeiter nötig aber keiner da -> müssen STILL stehen; Rest: ohne Arbeiterpflicht -> aktiv
		if i >= 8: b.max_workers = 0
		gc.renderer.add_building(b)
		placed.append(b)
	_log("%d Gebäude platziert, Start %s" % [placed.size(), str(best)])
	await frames(70)

	_log("── 1. Clips vorhanden, Loop, Pfade")
	var with_clip: Array = []; var without_clip: Array = []
	var bad_tracks: Dictionary = {}; var static_clips: Array = []; var not_loop: Array = []
	var clip_info: Dictionary = {}
	for bv in placed:
		var b: BuildingEntity = bv
		var root: Node = root_of(b)
		if root == null: without_clip.append(b.id + "(kein Knoten)"); continue
		if not root.has_meta("work_anim_player"): without_clip.append(b.id); continue
		with_clip.append(b.id)
		var ap: AnimationPlayer = root.get_meta("work_anim_player") as AnimationPlayer
		var clip: String = str(root.get_meta("work_anim_clip"))
		var a: Animation = ap.get_animation(clip)
		if a.loop_mode != Animation.LOOP_LINEAR: not_loop.append(b.id)
		var rn: Node = ap.get_node_or_null(ap.root_node)
		var unresolved := 0
		var moving := false
		for ti in a.get_track_count():
			var np: NodePath = a.track_get_path(ti)
			var target: Node = rn.get_node_or_null(NodePath(np.get_concatenated_names())) if rn != null else null
			if target == null: unresolved += 1
			var tt: int = a.track_get_type(ti)
			if a.track_get_key_count(ti) < 2: continue
			var t0: float = 0.0; var t1: float = a.length * 0.5
			if tt == Animation.TYPE_POSITION_3D:
				if (a.position_track_interpolate(ti, t0) as Vector3).distance_to(a.position_track_interpolate(ti, t1)) > 0.0005: moving = true
			elif tt == Animation.TYPE_ROTATION_3D:
				if (a.rotation_track_interpolate(ti, t0) as Quaternion).angle_to(a.rotation_track_interpolate(ti, t1)) > 0.0005: moving = true
			elif tt == Animation.TYPE_SCALE_3D:
				if (a.scale_track_interpolate(ti, t0) as Vector3).distance_to(a.scale_track_interpolate(ti, t1)) > 0.0005: moving = true
			else: moving = true
		if unresolved > 0: bad_tracks[b.id] = unresolved
		if not moving: static_clips.append(b.id)
		clip_info[b.id] = "%.2fs, %d Tracks" % [a.length, a.get_track_count()]
	_log("   mit Work-Clip: %d | ohne: %s" % [with_clip.size(), str(without_clip)])
	check(with_clip.size() >= 50, "mind. 50 Gebäude mit Work-Clip (%d)" % with_clip.size())
	var expected_none: Array = ["DECO_STONES", "DEPOT", "STATION", "STATUE", "STORAGE", "WATER_TOWER", "WELL"]
	var unexpected: Array = []
	for n in without_clip:
		if not (n in expected_none): unexpected.append(n)
	check(unexpected.is_empty(), "ohne Clip nur die erwarteten (DECO_STONES/STATION/DEPOT + 4 nicht aktualisierte Altmodelle); unerwartet: %s" % str(unexpected))
	check(not_loop.is_empty(), "alle Clips loopen (%s)" % str(not_loop))
	check(bad_tracks.is_empty(), "alle Track-Pfade lösen auf (kaputt: %s)" % str(bad_tracks))
	check(static_clips.is_empty(), "alle Clips bewegen etwas (statisch: %s)" % str(static_clips))
	var lens := ""
	for k in clip_info: lens += "%s[%s] " % [k, clip_info[k]]
	_log("   Clips: " + lens.substr(0, 700))

	_log("── 2. Spielt nur bei Arbeit")
	var wrong: Array = []
	var n_play := 0; var n_stop := 0
	for bv in placed:
		var b: BuildingEntity = bv
		var root: Node = root_of(b)
		if root == null or not root.has_meta("work_anim_player"): continue
		var ap: AnimationPlayer = root.get_meta("work_anim_player") as AnimationPlayer
		var want: bool = b.is_active and not b.is_under_construction
		if ap.is_playing(): n_play += 1
		else: n_stop += 1
		if ap.is_playing() != want: wrong.append("%s(aktiv=%s,spielt=%s)" % [b.id, str(b.is_active), str(ap.is_playing())])
	_log("   spielend: %d, stehend: %d" % [n_play, n_stop])
	check(wrong.is_empty(), "Animation folgt is_active (Abweichungen: %s)" % str(wrong))
	check(n_play > 20 and n_stop > 0, "sowohl laufende als auch stehende Gebäude vorhanden")

	_log("── 3. Animation bewegt wirklich Knoten")
	var sample: AnimationPlayer = null; var sample_id := ""
	for bv in placed:
		var b: BuildingEntity = bv
		var root: Node = root_of(b)
		if root != null and root.has_meta("work_anim_player") and (root.get_meta("work_anim_player") as AnimationPlayer).is_playing() and b.id in ["SAWMILL", "WATERWHEEL", "WORKSHOP", "SMELTER"]:
			sample = root.get_meta("work_anim_player") as AnimationPlayer; sample_id = b.id; break
	check(sample != null, "Beispielgebäude läuft (%s)" % sample_id)
	if sample != null:
		var p0: float = sample.current_animation_position
		await get_tree().create_timer(0.4).timeout
		var p1: float = sample.current_animation_position
		check(absf(p1 - p0) > 0.05 or p1 < p0, "Animationszeit schreitet fort (%.2f -> %.2f)" % [p0, p1])

	_log("── 4. Pause / Tempo")
	if sample != null:
		GameState.set_game_speed(0.0)
		await frames(40)
		var q0: float = sample.current_animation_position
		await get_tree().create_timer(0.5).timeout
		var q1: float = sample.current_animation_position
		check(absf(q1 - q0) < 0.02, "bei Pause (game_speed=0) steht die Animation (%.3f -> %.3f, speed_scale=%.2f)" % [q0, q1, sample.speed_scale])
		GameState.set_game_speed(3.0)
		await frames(40)
		check(absf(sample.speed_scale - 3.0) < 0.01, "bei 3x läuft sie dreifach (speed_scale=%.2f)" % sample.speed_scale)
		GameState.set_game_speed(1.0)
		await frames(40)
		check(absf(sample.speed_scale - 1.0) < 0.01 and sample.is_playing(), "bei 1x wieder normal")

	_log("── 5. Nacht")
	DayNight.time = 170.0; DayNight.day_length = 180.0
	await frames(70)
	var night_wrong: Array = []
	for bv in placed:
		var b: BuildingEntity = bv
		var root: Node = root_of(b)
		if root == null or not root.has_meta("work_anim_player"): continue
		var ap: AnimationPlayer = root.get_meta("work_anim_player") as AnimationPlayer
		var want: bool = b.is_active and not b.is_under_construction
		if ap.is_playing() != want: night_wrong.append(b.id)
	check(not DayNight.is_day, "es ist Nacht")
	check(night_wrong.is_empty(), "nachts folgen die Animationen is_active (Abweichungen: %s)" % str(night_wrong))
	DayNight.day_length = 100000.0; DayNight.time = 20.0; DayNight.is_day = true
	await frames(70)

	_log("── 6. Zweite Kolonie")
	var hall0: Vector2i = ColonySys.get_hall_tile(0)
	for k in ["WOOD", "STONE", "PLANKS", "TOOLS", "BERRIES"]: ResourceSys.force_add(k, 300.0)
	for i in 6: PopMgr.ferrets.append(FerretEntity.create_random())
	var site := Vector2i(-1, -1)
	for x in gc.world_gen.w:
		for y in gc.world_gen.h:
			var t: Dictionary = gc.world[x][y]
			if site.x < 0 and t.get("building") == null and str(t.get("biome", "")) != "WATER" and Vector2(hall0).distance_to(Vector2(x, y)) >= 21.0 and RailSys.rail_building_at(x, y) == null:
				site = Vector2i(x, y)
	gc.call("_found_colony", site.x, site.y)
	var hall1: Vector2i = ColonySys.get_hall_tile(1)
	var sp: Vector2i = gc.call("_find_free_tile_ring", hall1.x, hall1.y, gc.world, 2, 6)
	var sb: BuildingEntity = BuildingSys.build_free("SAWMILL", sp.x, sp.y, gc.world, 1)
	sb.max_workers = 0; gc.renderer.add_building(sb)
	await frames(70)
	var sroot: Node = root_of(sb)
	check(sroot != null and sroot.has_meta("work_anim_player"), "Sägewerk in Kolonie 1 hat Clip")
	if sroot != null and sroot.has_meta("work_anim_player"):
		check((sroot.get_meta("work_anim_player") as AnimationPlayer).is_playing(), "Sägewerk in Kolonie 1 läuft")
	var hb: BuildingEntity = null
	for b in BuildingSys.buildings:
		if (b as BuildingEntity).btype == "TOWN_HALL" and (b as BuildingEntity).colony_id == 1: hb = b
	var hroot: Node = root_of(hb)
	check(hroot != null and hroot.has_meta("work_anim_player"), "Rathaus mit eigenem Modell + Work-Clip")
	check(hroot != null and hroot.get_child_count() > 0, "Rathaus-Knoten hat Modell")

	_log("── 7. Verkaufen / Neu laden ohne Fehler")
	var victim: BuildingEntity = null
	for bv in placed:
		if (bv as BuildingEntity).id == "SAWMILL": victim = bv
	if victim != null:
		var vroot: Node = root_of(victim)
		BuildingSys.sell(victim, gc.world)
		gc.renderer.remove_building(victim.tile_x, victim.tile_y)
		await frames(40)
		check(not is_instance_valid(vroot) or vroot.is_queued_for_deletion(), "verkauftes Gebäude: Knoten entfernt")
	check(SaveSys.save("anim_test", gc), "save ok")
	check(SaveSys.load_game("anim_test", gc), "load ok")
	await frames(70)
	var again := 0
	for b in BuildingSys.buildings:
		var r: Node = root_of(b as BuildingEntity)
		if r != null and r.has_meta("work_anim_player"): again += 1
	check(again >= 45, "nach dem Laden bekommen die Gebäude ihre Clips wieder (%d)" % again)

	_log("── 8. Performance")
	var t0 := Time.get_ticks_usec()
	for i in 300: gc.renderer.refresh_building_anims(BuildingSys.buildings)
	var per: float = float(Time.get_ticks_usec() - t0) / 300.0 / 1000.0
	_log("   refresh_building_anims: %.3f ms pro Aufruf bei %d Gebäuden" % [per, BuildingSys.buildings.size()])
	check(per < 2.0, "Aufruf < 2 ms")
	_log("FERTIG - %d Fehler" % fails)
	get_tree().quit(1 if fails > 0 else 0)
