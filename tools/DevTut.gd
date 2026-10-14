extends Node
# Tutorial (v16.5) + Dev-Fenster in der echten Engine.
var main: Node
var gc: Node
var tut: Control
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
func click(pos: Vector2) -> void:
	var vp := get_viewport()
	var mm := InputEventMouseMotion.new(); mm.position = pos; mm.global_position = pos
	vp.push_input(mm)
	await get_tree().process_frame
	var d := InputEventMouseButton.new(); d.button_index = MOUSE_BUTTON_LEFT; d.pressed = true; d.position = pos; d.global_position = pos
	vp.push_input(d)
	var u := InputEventMouseButton.new(); u.button_index = MOUSE_BUTTON_LEFT; u.pressed = false; u.position = pos; u.global_position = pos
	vp.push_input(u)
	await get_tree().process_frame
func ui(path: String) -> Node:
	return main.find_child(path, true, false)
## Oberstes Control an `pos`, das Mausereignisse annimmt (mouse_filter != IGNORE) - bildet Godots Routing nach.
func topmost_at(node: Node, pos: Vector2) -> Control:
	var kids: Array = node.get_children()
	kids.reverse()
	for k in kids:
		var r: Control = topmost_at(k, pos)
		if r != null: return r
	if node is Control:
		var c := node as Control
		if c.is_visible_in_tree() and c.mouse_filter != Control.MOUSE_FILTER_IGNORE and c.get_global_rect().has_point(pos):
			return c
	return null
func overlaps(a: Control, b: Control) -> bool:
	if a == null or b == null or not a.is_visible_in_tree() or not b.is_visible_in_tree(): return false
	return a.get_global_rect().intersects(b.get_global_rect())
func _ready() -> void:
	await get_tree().process_frame
	main = load("res://scenes/Main.tscn").instantiate(); add_child(main)
	await frames(30)
	var intro = main.get("_intro")
	if intro != null: intro.call("skip")
	await frames(5)
	gc = main.get("_game_ctrl")
	gc.call("start_new_game", "SMALL", "qa-seed", "QA")
	check(RailSys.world.size() == gc.world.size() and gc.world.size() > 0, "RailSys kennt die Welt direkt nach dem Neustart (%d von %d)" % [RailSys.world.size(), gc.world.size()])
	await sim(60, 0.1)
	tut = ui("Tutorial") as Control
	check(tut != null, "Tutorial-Knoten existiert")
	check(tut._game_ctrl != null and tut._game_ctrl.has_method("set_simulation_paused"), "Tutorial findet den GameController")

	_log("── 1. Alle Schritte aller Rundgänge")
	TutorialManager.reset_progress()
	for track in ["basic", "systems", "logistics"]:
		tut.call("start", track)
		await frames(2)
		var steps: Array = tut._steps
		var bad_hl: Array = []; var empty_txt: Array = []; var n := 0
		var guard := 0
		while tut.visible and guard < 100:
			guard += 1
			var s: Dictionary = steps[tut._step]
			if str(s.get("title", "")) == "" or str(s.get("text", "")) == "": empty_txt.append(tut._step)
			var hp: String = str(s.get("highlight_path", ""))
			if hp != "":
				var tgt := tut.get_node_or_null(hp) as Control
				if tgt == null: bad_hl.append("%d:%s" % [tut._step, hp])
				elif not tgt.is_visible_in_tree(): bad_hl.append("%d:unsichtbar %s" % [tut._step, hp])
			if tut._waiting_for != "" and tut._next_btn.text != "Schritt überspringen": bad_hl.append("%d:kein Überspringen" % tut._step)
			n += 1
			tut.call("_on_next")
			await frames(2)
		check(not tut.visible, "%s: Rundgang läuft bis zum Ende (%d Schritte)" % [track, n])
		check(n == steps.size(), "%s: alle %d Schritte besucht" % [track, steps.size()])
		check(bad_hl.is_empty(), "%s: Markierungen stimmen (Fehler: %s)" % [track, str(bad_hl)])
		check(empty_txt.is_empty(), "%s: keine leeren Texte (%s)" % [track, str(empty_txt)])
		check(TutorialManager.is_done(track), "%s: Fortschritt gespeichert" % track)

	_log("── 2. Pause während des Tutorials, Klicks gehen durch")
	TutorialManager.reset_progress()
	var bm0: Control = ui("BuildMenu") as Control
	var base_btn: Button = null
	for c in bm0.find_children("*", "Button", true, false):
		var b0 := c as Button
		if b0.is_visible_in_tree() and not b0.disabled and b0.get_global_rect().size.y > 10 and b0.get_global_rect().end.y < get_viewport().get_visible_rect().size.y - 40 and b0.name != "ToggleBtn" and b0.name != "EpochBtn":
			base_btn = b0; break
	check(base_btn != null, "Bau-Menü-Knopf gefunden")
	var pos: Vector2 = base_btn.get_global_rect().get_center()
	var root_ui: Node = main.find_child("UIRoot", true, false)
	var hov0: Control = topmost_at(root_ui, pos)
	check(hov0 != null and bm0.is_ancestor_of(hov0) or hov0 == bm0, "Kontrolle: ohne Tutorial nimmt das Bau-Menü die Maus an (%s)" % str(hov0))
	tut.call("start", "basic")
	await frames(3)
	check(GameState.game_speed == 0.0, "Spiel pausiert im Tutorial")
	check(tut.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Vollbild-Overlay schluckt keine Klicks")
	var hov1: Control = topmost_at(root_ui, pos)
	check(hov1 != null and (bm0.is_ancestor_of(hov1) or hov1 == bm0), "im Tutorial: Klick auf das Bau-Menü erreicht das Menü (%s)" % str(hov1))
	# Welt: eine Stelle mitten im Bild, die in keinem Fenster liegt
	var wp := Vector2(get_viewport().get_visible_rect().size.x * 0.5, 80.0)
	var hov2: Control = topmost_at(root_ui, wp)
	check(hov2 == null or (hov2 != tut and not tut.is_ancestor_of(hov2)), "im Tutorial: Klick auf die Welt wird nicht vom Overlay gefangen (%s)" % str(hov2))
	# Klick in die Tutorial-Box selbst: wird abgefangen (richtig so)
	var hov4: Control = topmost_at(root_ui, tut._box.get_global_rect().get_center())
	check(hov4 != null and (hov4 == tut._box or tut._box.is_ancestor_of(hov4)), "Klick auf die Tutorial-Box bleibt in der Box (%s)" % str(hov4))
	# Gegenprobe: mit STOP würde das Overlay alles fangen
	tut.mouse_filter = Control.MOUSE_FILTER_STOP
	var hov3: Control = topmost_at(root_ui, wp)
	check(hov3 == tut, "Gegenprobe: mit STOP fängt das Overlay die Welt-Klicks (%s)" % str(hov3))
	tut.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameState.set_state(GameState.State.PLAYING)

	_log("── 3. Interaktive Schritte")
	tut.call("start", "basic"); await frames(2)
	for i in 4: tut.call("_on_next")
	await frames(2)
	check(tut._waiting_for == "building_placed_at_marker", "Schritt 5 wartet auf Platzieren")
	check(tut._marker_tile.x >= 0, "grüne Markierung gesetzt %s" % str(tut._marker_tile))
	var prev_dev: bool = GameState.dev_all_buildings
	GameState.dev_all_buildings = true
	gc.call("_place_building", tut._marker_tile.x, tut._marker_tile.y, "LUMBERJACK")
	await frames(2)
	GameState.dev_all_buildings = prev_dev
	check(tut._step == 5 and tut._waiting_for == "", "Holzfäller auf Markierung -> nächster Schritt")
	for i in 8: tut.call("_on_next")   # bis zum Frettchenmodus-Schritt
	await frames(2)
	check(tut._waiting_for == "fp_mode_entered", "Frettchenmodus-Schritt wartet (Schritt %d)" % (tut._step + 1))
	GameState.fp_mode_changed.emit(true)
	await frames(2)
	check(tut._waiting_for == "", "FP-Modus erkannt -> weiter")
	tut.call("_on_skip"); await frames(2)
	check(not tut.visible and GameState.game_speed > 0.0, "Überspringen beendet Tutorial und gibt das Spiel frei")
	tut.call("start", "logistics"); await frames(2)
	tut.call("_on_next"); tut.call("_on_next"); await frames(2)
	check(tut._waiting_for == "panel:ColonyPanel", "Logistik: wartet auf Kolonien-Fenster")
	var cp: Control = ui("ColonyPanel") as Control
	var step_before: int = tut._step
	cp.call("open")
	await frames(3)
	check(tut._step == step_before + 1, "Kolonien-Fenster geöffnet -> nächster Schritt")
	cp.hide()
	for i in 5: tut.call("_on_next")
	await frames(2)
	check(tut._waiting_for == "panel:LinePanel", "Logistik: wartet auf Linien-Fenster (Schritt %d)" % (tut._step + 1))
	var lp: Control = ui("LinePanel") as Control
	step_before = tut._step
	lp.call("open"); await frames(3)
	check(tut._step == step_before + 1, "Linien-Fenster geöffnet -> nächster Schritt")
	lp.hide()
	tut.call("_on_skip"); await frames(2)

	_log("── 4. Fortschritt / Autostart")
	TutorialManager.reset_progress()
	check(not TutorialManager.is_done("basic"), "Fortschritt zurückgesetzt")
	tut.call("maybe_autostart"); await frames(2)
	check(tut.visible, "frischer Fortschritt: Autostart der Grundlagen")
	tut.call("_on_skip"); await frames(2)
	check(TutorialManager.is_done("basic"), "Überspringen zählt als erledigt")
	tut.call("maybe_autostart"); await frames(2)
	check(not tut.visible, "danach kein erneuter Autostart")

	_log("── 5. Dev-Fenster: Aufbau und Überlappung")
	var dt: PanelContainer = ui("DevToolsPanel") as PanelContainer
	check(dt != null and not dt.visible, "Dev-Fenster ohne Dev-Modus unsichtbar")
	DevMode.try_enable("frettchendev")
	await frames(5)
	check(dt.visible, "Dev-Modus an -> sichtbar")
	check(dt._tabs != null and dt._tabs.get_tab_count() == 5, "5 Reiter (%d)" % (dt._tabs.get_tab_count() if dt._tabs else -1))
	var sizes := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(1024, 600)]
	for sz in sizes:
		get_window().size = sz
		await frames(8)
		dt._relayout()
		await frames(3)
		var vp: Vector2 = get_viewport().get_visible_rect().size
		var rects_ok := true; var details := ""
		for other in ["BuildMenu", "TopBar", "RightColumn"]:
			var o := ui(other) as Control
			if o != null and overlaps(dt, o): rects_ok = false; details += " " + other
		var inside: bool = dt.get_global_rect().position.x >= 0.0 and dt.get_global_rect().end.x <= vp.x + 0.5 and dt.get_global_rect().end.y <= vp.y + 0.5
		check(rects_ok, "%s: keine Überlappung mit Bau-Menü/Leiste/HUD-Spalte%s (Viewport %s, Panel %s)" % [str(sz), details, str(vp), str(dt.get_global_rect())])
		check(inside, "%s: Dev-Fenster liegt komplett im Bild" % str(sz))
		# Tutorial-Box + Fenster in der Mitte
		tut.call("start", "basic"); await frames(3)
		var box: Control = tut._box
		check(not overlaps(dt, box), "%s: Tutorial-Box überlappt das Dev-Fenster nicht" % str(sz))
		check(not overlaps(ui("BuildMenu") as Control, box), "%s: Tutorial-Box überlappt das Bau-Menü nicht" % str(sz))
		tut.call("_on_skip"); await frames(2)
		cp.call("open"); lp.call("open"); await frames(3)
		check(not overlaps(dt, cp) and not overlaps(dt, lp), "%s: Kolonien-/Linien-Fenster überlappen das Dev-Fenster nicht" % str(sz))
		cp.hide(); lp.hide()
	get_window().size = Vector2i(1600, 900); await frames(8)
	# Einklappen
	var h_open: float = dt.get_global_rect().size.y
	dt._collapsed = true; dt._refresh(); await frames(4)
	check(dt.get_global_rect().size.y < 60.0 and dt.get_global_rect().size.y < h_open, "eingeklappt: nur die Titelzeile (%.0f px, vorher %.0f)" % [dt.get_global_rect().size.y, h_open])
	dt._collapsed = false; dt._refresh(); await frames(4)

	_log("── 6. Dev-Aktionen einzeln")
	var wood0: float = float(ResourceSys.resources.get("WOOD", 0.0))
	check(str(gc.call("dev_add_all_resources", 500.0)).begins_with("🛠️"), "+500 Ressourcen: Meldung")
	check(float(ResourceSys.resources.get("WOOD", 0.0)) >= wood0 + 499.0, "Holz +500")
	gc.call("dev_unlock_all_epochs", 99)
	var ub: Array = TechTreeSys.get_unlocked_buildings()
	check(TechTreeSys.get_epoch() == 4 and "STATION" in ub and "DEPOT" in ub and "TOWN_HALL" in ub, "alle Epochen: Bahnhof/Depot/Rathaus freigeschaltet")
	gc.call("dev_unlock_all_tech")
	check(TechTreeSys.unlocked.size() == TechTreeSys.NODES.size(), "alle %d Tech-Knoten" % TechTreeSys.NODES.size())
	var pop0: int = PopMgr.get_count(ColonySys.active_id)
	gc.call("dev_spawn_ferrets", 5)
	check(PopMgr.get_count(ColonySys.active_id) == pop0 + 5, "+5 Frettchen")
	gc.call("dev_fill_needs")
	check(absf(ResourceSys.water - ResourceSys.water_capacity) < 0.01, "Wassertank gefüllt")
	var site := Vector2i(-1, -1)
	var hall0: Vector2i = ColonySys.get_hall_tile(0)
	site = gc.call("_find_free_tile_ring", hall0.x, hall0.y, gc.world, 3, 9)
	GameState.dev_all_buildings = false
	for k in ["WOOD", "STONE", "PLANKS"]: ResourceSys.force_add(k, 500.0)
	gc.call("_place_building", site.x, site.y, "HOUSE")
	var sites: int = BuildingSys.get_construction_sites().size()
	check(sites >= 1, "Baustelle vorhanden (%d)" % sites)
	gc.call("dev_finish_construction")
	await sim(40, 0.25)
	check(BuildingSys.get_construction_sites().size() == 0, "alle Baustellen fertig")
	gc.call("dev_set_time", 0.5)
	check(DayNight.display_time == "18:00", "Abend: %s" % DayNight.display_time)
	gc.call("dev_set_time", 0.84)
	check(not DayNight.is_day, "Nacht: is_day=false")
	gc.call("dev_set_time", 0.0)
	var s0: int = SeasonSys.current_season
	gc.call("dev_next_season")
	check(SeasonSys.current_season == (s0 + 1) % 4, "Jahreszeit %d -> %d" % [s0, SeasonSys.current_season])
	gc.call("dev_start_drought"); check(DroughtSys.is_drought, "Dürre an")
	gc.call("dev_end_drought"); check(not DroughtSys.is_drought, "Dürre aus")
	var msg: String = gc.call("dev_rail_test_line")
	_log("   Test-Linie: " + msg)
	check(msg.begins_with("🛠️ Test-Linie gebaut"), "Test-Linie in einem Klick")
	check(ColonySys.count() >= 2, "2. Kolonie wurde mitgegründet (%d)" % ColonySys.count())
	check(RailSys.trains.size() == 1 and RailSys.lines.size() == 1, "1 Zug, 1 Linie")
	var lid: int = int(RailSys.lines.keys()[0])
	check(RailSys.line_status(lid) == "", "Linie fahrbereit ('%s')" % RailSys.line_status(lid))
	await sim(900, 0.1)
	check(float((RailSys.lines[lid] as Dictionary)["delivered"]) > 0.0, "Zug liefert (%.0f)" % float((RailSys.lines[lid] as Dictionary)["delivered"]))
	gc.call("dev_buy_train")
	check(RailSys.trains.size() == 2, "Zug gekauft")
	gc.call("dev_halt_trains", 30.0)
	var halted := 0
	for t in RailSys.trains:
		if (t as TrainEntity).state == "DWELL": halted += 1
	check(halted >= 1, "Züge angehalten (%d)" % halted)
	gc.call("dev_teleport_to_train")
	await frames(3)
	check(gc._fp_mode, "Frettchenmodus nach Teleport an")
	gc.call("_toggle_fp_mode")
	var cs: int = ColonySys.active_id
	gc.call("dev_cycle_colony")
	check(ColonySys.active_id != cs, "Kolonie wechseln")
	var n_col: int = ColonySys.count()
	gc.call("dev_found_colony")
	check(ColonySys.count() == n_col + 1 or ColonySys.count() == n_col, "weitere Kolonie (%d -> %d, Platz begrenzt)" % [n_col, ColonySys.count()])
	gc.call("dev_remove_trains"); check(RailSys.trains.is_empty(), "Züge entfernt")
	gc.call("dev_remove_rails"); check(RailSys.rails.is_empty(), "Gleise entfernt")

	_log("── 7. Jeder Knopf im Dev-Fenster (außer Ausschalten/Tutorial) löst ohne Fehler aus")
	dt._refresh(); await frames(4)
	var pressed_n := 0
	var all_btns: Array = []
	for tab in dt._tabs.get_children():
		for btn in tab.find_children("*", "Button", true, false):
			var bb0 := btn as Button
			if bb0 is CheckButton or bb0.text.begins_with("Dev Mode") or bb0.text.begins_with("Tutorial"): continue
			all_btns.append(bb0)
	for bb in all_btns:
		if not is_instance_valid(bb): continue   # das Panel baut sich nach manchen Aktionen neu auf
		(bb as Button).pressed.emit(); pressed_n += 1
		await frames(1)
	check(pressed_n >= 20, "%d Knöpfe ausgelöst" % pressed_n)
	await sim(60, 0.1)
	GameState.set_game_speed(1.0)
	check(not DevMode.enabled == false, "Dev-Modus noch an")
	_log("FERTIG - %d Fehler" % fails)
	get_tree().quit(1 if fails > 0 else 0)
