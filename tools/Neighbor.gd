extends Node
# Nachbarkolonien (v16.7) in der echten Engine.
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
func pool_res(cid: int, res: String) -> float:
	var p: Dictionary = ResourceSys.pools.get(cid, {}) as Dictionary
	if ResourceSys.current_colony == cid: return float(ResourceSys.resources.get(res, 0.0))
	return float((p.get("resources", {}) as Dictionary).get(res, 0.0))
func _ready() -> void:
	await get_tree().process_frame
	main = load("res://scenes/Main.tscn").instantiate(); add_child(main)
	await frames(30)
	var intro = main.get("_intro")
	if intro != null: intro.call("skip")
	await frames(5)
	gc = main.get("_game_ctrl")
	gc.call("start_new_game", "HUGE", "qa-seed", "QA")
	await frames(10)
	DayNight.day_length = 100000.0; DayNight.time = 20.0; DayNight.is_day = true

	_log("── 1. Nachbarn werden erzeugt")
	var cids: Array = NeighborSys.cids()
	check(cids.size() >= 3, "%d Nachbarn erzeugt" % cids.size())
	check(ColonySys.player_count() == 1 and ColonySys.count() == 1 + cids.size(), "1 eigene Kolonie + %d fremde" % cids.size())
	var profiles: Array = []
	var all_far := true; var all_built := true; var all_pool := true
	for cid in cids:
		var c: int = int(cid)
		profiles.append(str((NeighborSys.neighbors[c] as Dictionary)["profile"]))
		check(ColonySys.is_npc(c), "%s ist eine fremde Kolonie" % ColonySys.get_name_of(c))
		var hall: Vector2i = ColonySys.get_hall_tile(c)
		if Vector2(hall).distance_to(Vector2(60, 60)) < GameController_start_r() + 6.0: all_far = false
		var kinds := {}
		for b in BuildingSys.buildings:
			if (b as BuildingEntity).colony_id == c: kinds[(b as BuildingEntity).btype] = int(kinds.get((b as BuildingEntity).btype, 0)) + 1
		if not (kinds.has("TOWN_HALL") and kinds.has("STATION") and kinds.has("STORAGE") and int(kinds.get("HOUSING", 0)) >= 2): all_built = false
		if not ResourceSys.pools.has(c): all_pool = false
		check(not ExploreSys.is_revealed(hall.x, hall.y), "%s liegt im Nebel" % ColonySys.get_name_of(c))
		check(not NeighborSys.is_discovered(c), "%s ist noch unentdeckt" % ColonySys.get_name_of(c))
	check(all_far, "alle Nachbarn liegen weit außerhalb des Heimatbereichs")
	check(all_built, "jedes Dorf: Rathaus, Bahnhof, Lager, 2 Häuser")
	check(all_pool, "jedes Dorf hat einen eigenen Ressourcen-Pool")
	check("MINE" in profiles, "Bergbaudorf (Eisen) ist dabei: %s" % str(profiles))
	var first: int = int(cids[0])
	var bn: Node3D = gc.renderer._building_nodes.get("%d,%d" % [ColonySys.get_hall_tile(first).x, ColonySys.get_hall_tile(first).y]) as Node3D
	await frames(3)
	check(bn != null and not bn.visible, "Rathaus im Nebel ist unsichtbar (kein Schweben)")
	var pf: Dictionary = NeighborSys.profile_of(first)
	check(pool_res(first, str((pf["offers"] as Dictionary).keys()[0])) > 0.0, "Startlager gefüllt")

	_log("── 2. Der Spieler wird nicht gestört")
	check(ColonySys.active_id == 0, "aktive Kolonie bleibt 0")
	ColonySys.set_active(first)
	check(ColonySys.active_id == 0, "fremde Kolonie lässt sich nicht aktivieren")
	var hp: BuildingEntity = null
	for b in BuildingSys.buildings:
		if (b as BuildingEntity).colony_id == first and (b as BuildingEntity).btype == "HOUSING": hp = b
	var n_before: int = BuildingSys.buildings.size()
	BuildingSys.sell(hp, gc.world)
	check(BuildingSys.buildings.size() == n_before, "fremdes Gebäude lässt sich nicht verkaufen")
	await sim(300, 0.1)
	check(PopMgr.get_count(first) == 0, "im Dorf entstehen keine Frettchen")
	check(float(pool_res(first, str((pf["offers"] as Dictionary).keys()[0]))) >= 0.0, "Dorf-Lager intakt")

	_log("── 3. Entdecken")
	var hall1: Vector2i = ColonySys.get_hall_tile(first)
	ExploreSys.reveal_circle(hall1.x, hall1.y, 3.0)
	NeighborSys.check_discovery(2.0)
	check(NeighborSys.is_discovered(first), "Nachbar entdeckt, sobald sein Rathaus-Feld aufgedeckt ist")
	check(AchievementSys.is_unlocked("NEIGHBOR_FOUND"), "Erfolg 'Entdecker'")
	check(ExploreSys.is_revealed(hall1.x + 6, hall1.y), "Dorf-Umgebung wird mit aufgedeckt")
	await get_tree().create_timer(0.7).timeout
	await sim(10, 0.1)
	check(bn.visible, "Dorf nach dem Aufdecken sichtbar")
	var other: int = int(cids[1])
	check(not NeighborSys.is_discovered(other), "anderer Nachbar weiter unentdeckt")

	_log("── 4. Tägliche Produktion")
	var res0: String = str((pf["offers"] as Dictionary).keys()[0])
	var amt0: float = pool_res(first, res0)
	ResourceSys.pools[first]["resources"][res0] = 5.0 if ResourceSys.current_colony != first else 5.0
	GameState.day_changed.emit(DayNight.day_count + 1)
	check(pool_res(first, res0) > 5.0, "Dorf produziert täglich %s (5 -> %.0f)" % [res0, pool_res(first, res0)])

	_log("── 5. Handelslinie (Dev: 1 Klick) und Ruf")
	GameState.dev_all_buildings = false
	var msg: String = gc.call("dev_neighbor_line")
	_log("   " + msg)
	check(msg.begins_with("🛠️ Handelslinie zu"), "Handelslinie gebaut")
	var line: int = int(RailSys.lines.keys()[0])
	check(RailSys.line_status(line) == "", "Linie fahrbereit ('%s')" % RailSys.line_status(line))
	var target: int = -1
	for s in RailSys.get_buildings_of("STATION"):
		if ColonySys.is_npc((s as BuildingEntity).colony_id): target = (s as BuildingEntity).colony_id
	# ersten verbundenen Nachbarn bestimmen
	var stops: Array = (RailSys.lines[line] as Dictionary)["stops"] as Array
	var sb = RailSys.station_at_key(int(stops[1]))
	target = (sb as BuildingEntity).colony_id
	var rep0: float = NeighborSys.rep_of(target)
	var wants: Array = NeighborSys.profile_of(target).get("wants", []) as Array
	var give: String = str(wants[0])
	var offer: String = str((NeighborSys.profile_of(target)["offers"] as Dictionary).keys()[0])
	var mine0: float = pool_res(0, offer)
	await sim(1500, 0.1)
	_log("   Ruf %.1f -> %.1f | %s im Besitz: %.0f -> %.0f" % [rep0, NeighborSys.rep_of(target), offer, mine0, pool_res(0, offer)])
	check(NeighborSys.rep_of(target) > rep0 + 3.0, "Lieferungen erhöhen den Ruf (%.1f -> %.1f)" % [rep0, NeighborSys.rep_of(target)])
	check(float((NeighborSys.neighbors[target] as Dictionary)["delivered_total"]) > 0.0, "gelieferte Menge wird gezählt")
	check(pool_res(0, offer) > mine0, "Zug bringt %s vom Nachbarn zu dir" % offer)
	check(ResourceSys.current_colony == ColonySys.active_id, "Pool-Kontext nach der Fahrt = aktive Kolonie")

	_log("── 6. Ruf-Kredit beim Laden")
	var nb_t: Dictionary = NeighborSys.neighbors[target] as Dictionary
	nb_t["rep"] = NeighborSys.REP_MIN
	check(NeighborSys.limit_take(target, offer, 100.0) == 0.0, "bei Ruf %d darf nichts mehr geladen werden" % int(NeighborSys.REP_MIN))
	nb_t["rep"] = 50.0
	check(NeighborSys.limit_take(target, offer, 10.0) == 10.0, "bei gutem Ruf darf geladen werden")
	var r_before: float = NeighborSys.rep_of(target)
	NeighborSys.on_take(target, offer, 100.0)
	check(NeighborSys.rep_of(target) < r_before, "Laden kostet Ruf (%.1f -> %.1f)" % [r_before, NeighborSys.rep_of(target)])
	NeighborSys.on_delivery(target, give, 100.0)
	check(NeighborSys.rep_of(target) > r_before - 5.0, "gewünschte Ware bringt wieder Ruf")

	_log("── 7. Aufträge")
	nb_t["request"] = {}
	NeighborSys._new_request(target, DayNight.day_count)
	var rq: Dictionary = nb_t["request"] as Dictionary
	check(not rq.is_empty() and str(rq["res"]) in wants, "Auftrag erzeugt: %d x %s" % [int(rq["amount"]), str(rq["res"])])
	var rep_a: float = NeighborSys.rep_of(target)
	var tools_a: float = pool_res(0, "TOOLS")
	NeighborSys.on_delivery(target, str(rq["res"]), float(rq["amount"]))
	check((nb_t["request"] as Dictionary).is_empty(), "Auftrag erfüllt -> abgeschlossen")
	check(NeighborSys.rep_of(target) >= rep_a + 12.0, "Bonus-Ruf (%.1f -> %.1f)" % [rep_a, NeighborSys.rep_of(target)])
	check(pool_res(0, "TOOLS") > tools_a, "Belohnung: Werkzeug")
	nb_t["next_request_day"] = 0
	GameState.day_changed.emit(DayNight.day_count + 1)
	var rq2: Dictionary = nb_t["request"] as Dictionary
	check(not rq2.is_empty(), "nächster Auftrag kommt von selbst")
	rq2["deadline"] = DayNight.day_count - 1
	var rep_b: float = NeighborSys.rep_of(target)
	GameState.day_changed.emit(DayNight.day_count + 1)
	check(NeighborSys.rep_of(target) < rep_b and (nb_t["request"] as Dictionary).is_empty(), "abgelaufener Auftrag kostet Ruf")

	_log("── 8. Bauen im Nachbargebiet")
	var th: Vector2i = ColonySys.get_hall_tile(target)
	GameState.dev_all_buildings = false
	for k in ["WOOD", "STONE", "PLANKS"]: ResourceSys.force_add(k, 300.0)
	var tile_near := Vector2i(th.x + 6, th.y + 6)
	var n_b: int = BuildingSys.buildings.size()
	gc.call("_place_building", tile_near.x, tile_near.y, "HOUSE")
	check(BuildingSys.buildings.size() == n_b, "im Gebiet des Nachbarn kann man nicht bauen")

	_log("── 9. Annexion")
	nb_t["rep"] = 20.0
	check(NeighborSys.annex_block_reason(target).begins_with("Ruf"), "zu wenig Ruf: '%s'" % NeighborSys.annex_block_reason(target))
	nb_t["rep"] = 90.0
	ResourceSys.use_colony(0)
	for k in NeighborSys.ANNEX_COSTS: ResourceSys.force_add(str(k), 500.0)
	var why: String = NeighborSys.annex_block_reason(target)
	check(why == "", "alle Bedingungen erfüllt (Ruf, Bahnanschluss, Kosten): '%s'" % why)
	var pop_before: int = PopMgr.get_count(target)
	var cnt_before: int = ColonySys.player_count()
	var err: String = NeighborSys.annex(target, gc)
	check(err == "", "Annexion ohne Fehler")
	check(not ColonySys.is_npc(target) and ColonySys.player_count() == cnt_before + 1, "Nachbar ist jetzt eigene Kolonie (%d eigene)" % ColonySys.player_count())
	check(PopMgr.get_count(target) == pop_before + 4, "4 Frettchen ziehen ein")
	var has_yard := false
	for b in BuildingSys.buildings:
		if (b as BuildingEntity).colony_id == target and (b as BuildingEntity).btype == "BUILDER": has_yard = true
	check(has_yard, "Bauhof gebaut")
	check(AchievementSys.is_unlocked("NEIGHBOR_ANNEXED"), "Erfolg 'Gute Nachbarschaft'")
	ColonySys.set_active(target)
	check(ColonySys.active_id == target, "annektierte Kolonie ist umschaltbar")
	ColonySys.set_active(0)
	await sim(300, 0.1)
	check(PopMgr.get_count(target) >= 4, "Kolonie läuft weiter (%d Frettchen)" % PopMgr.get_count(target))
	check(NeighborSys.annex_block_reason(target) == "Bereits Teil deiner Kolonie.", "zweite Annexion unmöglich")

	_log("── 10. UI")
	var np: Control = main.find_child("NeighborPanel", true, false) as Control
	check(np != null, "NeighborPanel existiert")
	np.call("open"); await frames(3)
	check(np.get_child_count() > 0, "Fenster baut Inhalt auf")
	var cards := 0
	for l in np.find_children("*", "Label", true, false):
		if (l as Label).text.contains("Bietet:") or (l as Label).text.contains("gehört jetzt zu dir"): cards += 1
	check(cards >= 1, "Karte(n) der entdeckten Nachbarn (%d)" % cards)
	np.hide()
	var cp: Control = main.find_child("ColonyPanel", true, false) as Control
	cp.call("open"); await frames(3)
	var rows := 0
	for l in cp.find_children("*", "LineEdit", true, false): rows += 1
	check(rows == ColonySys.player_count(), "Kolonien-Fenster listet nur eigene Kolonien (%d == %d)" % [rows, ColonySys.player_count()])
	cp.hide()
	var wm: Control = main.find_child("WorldMapPanel", true, false) as Control
	wm.call("open"); await frames(3)
	check(wm._rect.texture != null, "Weltkarte zeichnet mit Nachbarn")
	wm.hide()

	_log("── 11. Speichern / Laden")
	var snap_rep: float = NeighborSys.rep_of(int(cids[0]))
	var disc: Array = []
	for c in cids: disc.append(NeighborSys.is_discovered(int(c)))
	var annexed_t: bool = bool((NeighborSys.neighbors[target] as Dictionary)["annexed"])
	check(SaveSys.save("nb_test", gc), "save ok")
	NeighborSys.reset()
	check(SaveSys.load_game("nb_test", gc), "load ok")
	await frames(5)
	check(NeighborSys.neighbors.size() == cids.size(), "Nachbarn geladen (%d)" % NeighborSys.neighbors.size())
	var same := true
	for i in cids.size():
		if NeighborSys.is_discovered(int(cids[i])) != bool(disc[i]): same = false
	check(same, "Entdeckt-Zustände gleich")
	check(bool((NeighborSys.neighbors[target] as Dictionary)["annexed"]) == annexed_t and not ColonySys.is_npc(target), "Annexion bleibt erhalten")
	check(ColonySys.is_npc(int(cids[1])) and ColonySys.is_npc(int(cids[2])), "übrige Nachbarn weiter fremd")
	check(absf(NeighborSys.rep_of(int(cids[0])) - snap_rep) < 0.01, "Ruf gespeichert")
	await sim(300, 0.1)

	_log("── 12. Klassische Welt hat keine Nachbarn")
	gc.call("start_new_game", "SMALL", "qa-seed", "QA")
	await frames(5)
	check(NeighborSys.neighbors.is_empty() and ColonySys.count() == 1, "SMALL: keine Nachbarn")
	np.call("open"); await frames(3)
	var hint := false
	for l in np.find_children("*", "Label", true, false):
		if (l as Label).text.contains("nur auf Entdeckerkarten"): hint = true
	check(hint, "Hinweis im Fenster, dass Nachbarn Entdeckerkarten brauchen")
	np.hide()
	_log("FERTIG - %d Fehler" % fails)
	get_tree().quit(1 if fails > 0 else 0)

func GameController_start_r() -> float:
	return gc.START_REVEAL_RADIUS
