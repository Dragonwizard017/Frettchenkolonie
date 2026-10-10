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
func sim(steps: int, dt: float, yield_every: int = 200) -> void:
	for i in steps:
		gc.call("_process", dt)
		if i % yield_every == 0: await get_tree().process_frame
func count_type(btype: String, cid: int = -1) -> int:
	var n := 0
	for b in BuildingSys.buildings:
		var be: BuildingEntity = b
		if be.btype == btype and (cid < 0 or be.colony_id == cid): n += 1
	return n
func count_id(bid: String, cid: int = -1) -> int:
	var n := 0
	for b in BuildingSys.buildings:
		var be: BuildingEntity = b
		if be.id == bid and (cid < 0 or be.colony_id == cid): n += 1
	return n
func far_free_tile(from: Vector2i, min_d: float, max_d: float) -> Vector2i:
	var best := Vector2i(-1, -1)
	for x in gc.world_gen.w:
		for y in gc.world_gen.h:
			var t: Dictionary = (gc.world[x] as Array)[y]
			if t.get("building") != null or str(t.get("biome", "")) == "WATER": continue
			var d: float = Vector2(from).distance_to(Vector2(x, y))
			if d >= min_d and d <= max_d:
				return Vector2i(x, y)
	return best
func nan_check() -> bool:
	for cid in ColonySys.ids():
		var info: Dictionary = ResourceSys.pool_info(int(cid))
		for k in info:
			if is_nan(float(info[k])) or is_inf(float(info[k])): return true
	return false
func _ready() -> void:
	await get_tree().process_frame
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for i in 5: await get_tree().process_frame
	gc = main.get("_game_ctrl")
	_log("gc=%s" % str(gc))
	gc.call("start_new_game", "SMALL", "qa-seed", "QA-Kolonie")
	await sim(100, 0.1)

	_log("── 1. Startkolonie")
	check(ColonySys.count() == 1, "genau 1 Kolonie")
	check(ColonySys.get_name_of(0) == "QA-Kolonie", "Kolonie 0 heißt wie die Welt (%s)" % ColonySys.get_name_of(0))
	check(count_type("TOWN_HALL", 0) == 1, "Rathaus der Startkolonie gebaut")
	var hall0: Vector2i = ColonySys.get_hall_tile(0)
	check(hall0.x >= 0, "Rathaus-Kachel gesetzt %s" % str(hall0))
	check(ColonySys.colony_of_tile(hall0.x, hall0.y) == 0, "Rathaus-Kachel gehört zu Kolonie 0")

	gc.call("bootstrap_test_colony")
	await sim(100, 0.1)
	_log("   Frettchen=%d Gebäude=%d" % [PopMgr.ferrets.size(), BuildingSys.buildings.size()])
	var w0_before: float = float(ResourceSys.resources.get("WOOD", 0.0))

	_log("── 2. Rathaus nicht verkaufbar")
	var hall_b: BuildingEntity = null
	for b in BuildingSys.buildings:
		if (b as BuildingEntity).btype == "TOWN_HALL": hall_b = b
	BuildingSys.sell(hall_b, gc.world)
	check(count_type("TOWN_HALL", 0) == 1, "Rathaus steht nach Verkaufsversuch noch")

	_log("── 3. Gründung zu nah dran wird abgelehnt")
	var near: Vector2i = far_free_tile(hall0, 6.0, 12.0)
	var cnt_before: int = ColonySys.count()
	gc.call("_found_colony", near.x, near.y)
	check(ColonySys.count() == cnt_before, "zu nahe Gründung abgelehnt (%s)" % str(near))

	_log("── 4. Neue Kolonie gründen")
	var site: Vector2i = far_free_tile(hall0, 21.0, 30.0)
	check(site.x >= 0, "Gründungsplatz gefunden %s" % str(site))
	var pop0_before: int = PopMgr.get_count(0)
	ResourceSys.force_add("WOOD", 200.0); ResourceSys.force_add("STONE", 200.0)
	ResourceSys.force_add("PLANKS", 100.0); ResourceSys.force_add("TOOLS", 50.0); ResourceSys.force_add("BERRIES", 100.0)
	var wood_before: float = float(ResourceSys.resources.get("WOOD", 0.0))
	gc.call("_found_colony", site.x, site.y)
	check(ColonySys.count() == 2, "2 Kolonien")
	check(ColonySys.active_id == 1, "neue Kolonie ist aktiv")
	check(ResourceSys.current_colony == 1, "Ressourcen-Kontext = Kolonie 1")
	check(count_type("TOWN_HALL", 1) == 1, "Rathaus der neuen Kolonie")
	check(count_type("BUILDER", 1) == 1, "Bauhof der neuen Kolonie")
	check(count_type("STORAGE", 1) == 1, "Lager der neuen Kolonie")
	check(PopMgr.get_count(1) == ColonySys.SETTLERS, "%d Siedler in Kolonie 1 (ist %d)" % [ColonySys.SETTLERS, PopMgr.get_count(1)])
	check(PopMgr.get_count(0) == pop0_before - ColonySys.SETTLERS, "Kolonie 0 hat %d Frettchen weniger" % ColonySys.SETTLERS)
	check(absf(float(ResourceSys.resources.get("WOOD", 0.0)) - 80.0) < 0.01, "Startbestand Holz = Gründungspaket (80), ist %.1f" % float(ResourceSys.resources.get("WOOD", 0.0)))
	ResourceSys.use_colony(0)
	check(absf(float(ResourceSys.resources.get("WOOD", 0.0)) - (wood_before - 80.0)) < 0.5, "Kolonie 0 hat 80 Holz bezahlt")
	ResourceSys.use_colony(1)
	var d1: int = DistrictSys.district_colony(0)
	var yard1: BuildingEntity = null
	for b in BuildingSys.buildings:
		if (b as BuildingEntity).btype == "BUILDER" and (b as BuildingEntity).colony_id == 1: yard1 = b
	check(yard1 != null and yard1.district_id != 0 and DistrictSys.district_colony(yard1.district_id) == 1, "Bauhof 1 gründet eigenen Bezirk der Kolonie 1 (Bezirk %d)" % yard1.district_id)
	check(not DistrictSys.are_linked(0, yard1.district_id), "Bezirke verschiedener Kolonien nicht verbunden")

	_log("── 5. Bauen nur im eigenen Gebiet")
	var hall1: Vector2i = ColonySys.get_hall_tile(1)
	var house_site: Vector2i = gc.call("_find_free_tile_ring", hall1.x, hall1.y, gc.world, 3, 8)
	var houses_before: int = count_id("HOUSE")
	gc.call("_place_building", house_site.x, house_site.y, "HOUSE")
	check(count_id("HOUSE", 1) == 1 and count_id("HOUSE") == houses_before + 1, "Haus in Kolonie 1 gebaut und Kolonie 1 zugeordnet")
	var foreign: Vector2i = gc.call("_find_free_tile_ring", hall0.x, hall0.y, gc.world, 3, 8)
	var all_before: int = BuildingSys.buildings.size()
	gc.call("_place_building", foreign.x, foreign.y, "HOUSE")
	check(BuildingSys.buildings.size() == all_before, "Bauen im Gebiet von Kolonie 0 bei aktiver Kolonie 1 abgelehnt")
	var nowhere: Vector2i = far_free_tile(hall0, 40.0, 60.0)
	if nowhere.x >= 0 and ColonySys.colony_of_tile(nowhere.x, nowhere.y) < 0:
		gc.call("_place_building", nowhere.x, nowhere.y, "HOUSE")
		check(BuildingSys.buildings.size() == all_before, "Bauen im Niemandsland abgelehnt")

	_log("── 6. Simulation beider Kolonien")
	await sim(1200, 0.25)
	check(not nan_check(), "keine NaN/Inf in den Pools")
	var cross := 0
	for f in PopMgr.ferrets:
		var fe: FerretEntity = f
		if fe.assigned_building != null and (fe.assigned_building as BuildingEntity).colony_id != fe.colony_id: cross += 1
		if fe.home != null and (fe.home as BuildingEntity).colony_id != fe.colony_id: cross += 1
	check(cross == 0, "keine kolonieübergreifende Arbeit/Wohnung (%d)" % cross)
	check(ResourceSys.current_colony == ColonySys.active_id, "Kontext nach Simulation wieder = aktive Kolonie")
	_log("   Kolonie0: Frettchen=%d %s | Kolonie1: Frettchen=%d %s" % [PopMgr.get_count(0), str(ResourceSys.pool_info(0)), PopMgr.get_count(1), str(ResourceSys.pool_info(1))])

	_log("── 7. Pools sind getrennt")
	ResourceSys.use_colony(1)
	var w1: float = float(ResourceSys.resources.get("WOOD", 0.0))
	ResourceSys.force_add("WOOD", 50.0)
	ResourceSys.use_colony(0)
	check(absf(float(ResourceSys.resources.get("WOOD", 0.0)) - float(ResourceSys.pool_info(0)["stored"])) >= 0.0, "Pool 0 lesbar")
	var w0_a: float = float(ResourceSys.resources.get("WOOD", 0.0))
	ResourceSys.use_colony(1)
	check(absf(float(ResourceSys.resources.get("WOOD", 0.0)) - (w1 + 50.0)) < 0.01, "50 Holz nur in Kolonie 1 angekommen")
	ResourceSys.use_colony(0)
	check(absf(float(ResourceSys.resources.get("WOOD", 0.0)) - w0_a) < 0.01, "Kolonie 0 unverändert")
	ResourceSys.use_colony(ColonySys.active_id)

	_log("── 8. Auswahl wechselt die aktive Kolonie")
	gc.call("focus_colony", 0)
	check(ColonySys.active_id == 0, "focus_colony(0)")
	var yard_tile: Vector2i = Vector2i(yard1.tile_x, yard1.tile_y)
	gc.call("_select_tile", yard_tile.x, yard_tile.y)
	check(ColonySys.active_id == 1, "Klick auf Gebäude von Kolonie 1 schaltet auf Kolonie 1")

	_log("── 8b. Dürre mit zwei Kolonien (getrennte Wassertanks, Felder)")
	for cid in [0, 1]:
		ResourceSys.use_colony(cid); ResourceSys.water = 30.0
	ResourceSys.use_colony(ColonySys.active_id)
	gc.call("_place_field", ColonySys.get_hall_tile(1).x + 3, ColonySys.get_hall_tile(1).y + 3, "SET", true)
	DroughtSys.force_drought()
	await sim(200, 0.25)
	var wa: float = float(ResourceSys.pool_info(0)["water"]); var wb: float = float(ResourceSys.pool_info(1)["water"])
	check(wa < 30.0 and wb < 30.0, "Dürre zieht Wasser aus BEIDEN Tanks (%.1f / %.1f)" % [wa, wb])
	check(not nan_check() and ResourceSys.current_colony == ColonySys.active_id, "Dürre: keine NaN, Kontext = aktive Kolonie")

	_log("── 9. UI: HUD, Kolonien-Panel")
	var hud: Node = main.find_child("HUD", true, false)
	hud.call("refresh")
	var pop_lbl: Label = main.find_child("PopLabel", true, false)
	check(pop_lbl != null and pop_lbl.text.contains(ColonySys.get_name_of(1)), "HUD zeigt Kolonie-Namen: '%s'" % (pop_lbl.text if pop_lbl else "-"))
	var panel: Node = main.find_child("ColonyPanel", true, false)
	check(panel != null, "ColonyPanel existiert")
	if panel != null:
		panel.call("open")
		await get_tree().process_frame
		check(panel.get_child_count() > 0, "ColonyPanel baut Inhalt auf")
		panel.call("hide")
	var bm: Node = main.find_child("BuildMenu", true, false)
	bm.call("refresh")
	await get_tree().process_frame

	_log("── 10. Speichern / Laden")
	var sum0_before: Dictionary = ResourceSys.pool_info(0)
	var sum1_before: Dictionary = ResourceSys.pool_info(1)
	var n_before: int = BuildingSys.buildings.size()
	var pop1_before: int = PopMgr.get_count(1)
	check(SaveSys.save("colony_test", gc), "save ok")
	check(SaveSys.load_game("colony_test", gc), "load ok")
	check(ColonySys.count() == 2, "nach Laden: 2 Kolonien")
	check(ColonySys.active_id == 1, "nach Laden: aktive Kolonie 1")
	check(ResourceSys.current_colony == 1, "nach Laden: Kontext = 1")
	check(BuildingSys.buildings.size() == n_before, "Gebäudezahl gleich")
	check(count_type("TOWN_HALL", 1) == 1 and count_type("TOWN_HALL", 0) == 1, "beide Rathäuser vorhanden")
	check(PopMgr.get_count(1) == pop1_before, "Frettchen von Kolonie 1 gleich (%d)" % PopMgr.get_count(1))
	var s0a: Dictionary = ResourceSys.pool_info(0); var s1a: Dictionary = ResourceSys.pool_info(1)
	check(absf(float(s0a["stored"]) - float(sum0_before["stored"])) < 1.0, "Pool 0 gleich (%.1f vs %.1f)" % [float(s0a["stored"]), float(sum0_before["stored"])])
	check(absf(float(s1a["stored"]) - float(sum1_before["stored"])) < 1.0, "Pool 1 gleich (%.1f vs %.1f)" % [float(s1a["stored"]), float(sum1_before["stored"])])
	check(DistrictSys.district_colony(yard1.district_id) == 1, "Bezirk-Kolonie gespeichert")
	await sim(400, 0.25)
	check(not nan_check(), "nach Laden+Simulation: keine NaN")

	_log("── 11. Alt-Save (vor v16.0) migrieren")
	var path: String = "user://saves/colony_test.json"
	var txt: String = FileAccess.get_file_as_string(path)
	var data: Dictionary = JSON.parse_string(txt) as Dictionary
	data.erase("colonies")
	(data["resources"] as Dictionary).erase("pools")
	var olds: Array = []
	for bd in data["buildings"]:
		var bdd: Dictionary = bd
		if str(bdd.get("id")) == "TOWN_HALL": continue
		bdd.erase("colony_id"); olds.append(bdd)
	data["buildings"] = olds
	for fd in (data["population"] as Dictionary)["ferrets"]: (fd as Dictionary).erase("colony_id")
	var f2: FileAccess = FileAccess.open("user://saves/colony_old.json", FileAccess.WRITE)
	f2.store_string(JSON.stringify(data)); f2.close()
	check(SaveSys.load_game("colony_old", gc), "Alt-Save lädt")
	check(ColonySys.count() == 1, "Alt-Save: 1 Kolonie")
	check(count_type("TOWN_HALL", 0) == 1, "Alt-Save: Rathaus nachgerüstet")
	var hall_old: Vector2i = ColonySys.get_hall_tile(0)
	var outside := 0
	for b in BuildingSys.buildings:
		var be: BuildingEntity = b
		if ColonySys.colony_of_tile(be.tile_x, be.tile_y) != 0: outside += 1
	check(outside == 0, "Alt-Save: alle %d Gebäude liegen im Gebiet von Kolonie 0 (Radius %.1f, Rathaus %s)" % [BuildingSys.buildings.size(), ColonySys.get_radius(0), str(hall_old)])
	await sim(600, 0.25)
	check(not nan_check(), "Alt-Save: nach Simulation keine NaN")
	check(PopMgr.get_count(0) == PopMgr.ferrets.size(), "Alt-Save: alle Frettchen in Kolonie 0")

	_log("FERTIG - %d Fehler" % fails)
	get_tree().quit(1 if fails > 0 else 0)
