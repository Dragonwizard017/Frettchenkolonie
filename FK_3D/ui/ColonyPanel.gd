## ColonyPanel.gd
## Feature (v16.0, Kolonie-Fundament / Phase 1): Übersicht aller Kolonien - Farbe,
## umbenennbar, Bevölkerung, Lager, Wasser; per Knopf zur Kolonie wechseln
## (Kamera springt zu ihrem Rathaus). Baut seine UI dynamisch in _refresh() selbst
## auf, analog zu DistrictPanel.gd.
extends PanelContainer

func _ready() -> void:
	hide()
	MenuManager.register(self)
	# Zahlen ändern sich ständig - das generische HUD-Update (1x/Sek.) reicht.
	# Nicht neu aufbauen, solange der Spieler gerade einen Namen tippt.
	GameState.hud_update_requested.connect(func():
		if visible and not _is_editing(): _refresh())

func open() -> void:
	show(); _refresh()

func _is_editing() -> bool:
	var fo: Control = get_viewport().gui_get_focus_owner()
	return fo is LineEdit and is_ancestor_of(fo)

func _game_controller() -> Node:
	return get_tree().root.find_child("GameScreen", true, false)

func _refresh() -> void:
	for c in get_children(): c.queue_free()
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 6); add_child(vb)

	var hdr := HBoxContainer.new(); vb.add_child(hdr)
	var tl := Label.new()
	tl.text = "🏛️ Kolonien – %d" % ColonySys.player_count()
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.add_theme_font_size_override("font_size", 15)
	tl.add_theme_color_override("font_color", Color(0.95, 0.80, 0.45))
	hdr.add_child(tl)
	var cb := Button.new(); cb.text = "X"; cb.pressed.connect(hide); hdr.add_child(cb)
	vb.add_child(HSeparator.new())

	var sc := ScrollContainer.new(); sc.custom_minimum_size = Vector2(0, 300); vb.add_child(sc)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 10)
	sc.add_child(inner)

	for cid_v in ColonySys.player_ids():
		var cid: int = int(cid_v)
		var is_active: bool = cid == ColonySys.active_id

		var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8)
		inner.add_child(row)

		var swatch := ColorRect.new(); swatch.color = ColonySys.get_color_of(cid)
		swatch.custom_minimum_size = Vector2(18, 18)
		row.add_child(swatch)

		var name_input := LineEdit.new()
		name_input.text = ColonySys.get_name_of(cid)
		name_input.custom_minimum_size = Vector2(140, 0)
		name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var c_id: int = cid
		name_input.text_submitted.connect(func(t): ColonySys.rename(c_id, t); _refresh())
		name_input.focus_exited.connect(func(): ColonySys.rename(c_id, name_input.text); _refresh())
		row.add_child(name_input)

		var go := Button.new()
		go.text = "● aktiv" if is_active else "Anzeigen"
		go.disabled = is_active
		go.pressed.connect(func():
			var gc: Node = _game_controller()
			if gc != null and gc.has_method("focus_colony"): gc.call("focus_colony", c_id)
			else: ColonySys.set_active(c_id)
			_refresh())
		row.add_child(go)

		var info: Dictionary = ResourceSys.pool_info(cid)
		var lbl := Label.new()
		lbl.text = "👥 %d   🛏️ %d/%d   📦 %d/%d   💧 %d/%d   🏠 %d Gebäude" % [
			PopMgr.get_count(cid),
			BuildingSys.get_occupied_beds(cid), BuildingSys.get_total_beds(cid),
			int(float(info["stored"])), int(float(info["capacity"])),
			int(float(info["water"])), int(float(info["water_capacity"])),
			BuildingSys.get_colony_buildings(cid).size() if ColonySys.player_count() > 1 else BuildingSys.get_colony_buildings(cid).size()]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
		inner.add_child(lbl)

	var hint := Label.new()
	hint.text = "Neue Kolonie gründen: Baumenü → Kolonie → Rathaus (ab Epoche 2). Es braucht mindestens %d Kacheln Abstand zu jedem Rathaus, die Gründerkolonie mind. %d Frettchen; %d ziehen als Siedler mit. Das Gründungspaket (Baukosten) wird zum Startbestand der neuen Kolonie, dazu gibt es Bauhof und Lager gratis. Jede Kolonie hat eigene Lager, eigenes Wasser und eigene Bevölkerung - gebaut wird nur im Gebiet der aktiven Kolonie. Forschung gilt für alle." % [int(ColonySys.MIN_HALL_DISTANCE), ColonySys.MIN_FERRETS_TO_FOUND, ColonySys.SETTLERS]
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	vb.add_child(hint)
