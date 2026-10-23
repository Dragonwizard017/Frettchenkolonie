## DistrictPanel.gd
## Feature (v11.11, Distrikt-System): Übersicht aller Bezirke - Farbe,
## Gebäudeanzahl, umbenennbar, sowie welche Bezirke gerade per Bezirkstor
## miteinander verknüpft sind. Baut seine UI dynamisch in _refresh() selbst
## auf, analog zu AchievementPanel.gd/GraveyardPanel.gd.
extends PanelContainer

func _ready() -> void:
	hide()
	MenuManager.register(self)
	# Bezirke ändern sich nur bei Bau/Verkauf/Tor-Verknüpfung - kein
	# _process()-Polling nötig (siehe FerretProfilePanel.gd-Bugfix-Historie
	# für WARUM das wichtig ist), stattdessen reicht ein generisches
	# HUD-Update-Signal, das ohnehin bei solchen Änderungen feuert.
	GameState.hud_update_requested.connect(func(): if visible: _refresh())

func open() -> void:
	show(); _refresh()

func _refresh() -> void:
	for c in get_children(): c.queue_free()
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 6); add_child(vb)

	var hdr := HBoxContainer.new(); vb.add_child(hdr)
	var tl := Label.new()
	tl.text = "🏘️ Bezirke – %d" % DistrictSys.districts.size()
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.add_theme_font_size_override("font_size", 15)
	tl.add_theme_color_override("font_color", Color(0.55, 0.8, 0.95))
	hdr.add_child(tl)
	var cb := Button.new(); cb.text = "X"; cb.pressed.connect(hide); hdr.add_child(cb)
	vb.add_child(HSeparator.new())

	var sc := ScrollContainer.new(); sc.custom_minimum_size = Vector2(0, 300); vb.add_child(sc)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 8)
	sc.add_child(inner)

	var ids: Array = DistrictSys.districts.keys()
	ids.sort()
	for did_v in ids:
		var did: int = int(did_v)
		if ColonySys.is_npc(DistrictSys.district_colony(did)): continue   # v16.7: Dörfer der Nachbarn nicht auflisten
		var ddata: Dictionary = DistrictSys.districts[did] as Dictionary
		var col: Array = ddata.get("color", [0.7, 0.7, 0.7]) as Array
		var district_color := Color(float(col[0]), float(col[1]), float(col[2]))

		var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8)
		inner.add_child(row)

		var swatch := ColorRect.new(); swatch.color = district_color
		swatch.custom_minimum_size = Vector2(18, 18)
		row.add_child(swatch)

		var name_input := LineEdit.new()
		name_input.text = str(ddata.get("name", "Bezirk"))
		name_input.custom_minimum_size = Vector2(120, 0)
		name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var d_id: int = did
		name_input.text_submitted.connect(func(t): DistrictSys.rename_district(d_id, t); _refresh())
		name_input.focus_exited.connect(func(): DistrictSys.rename_district(d_id, name_input.text); _refresh())
		row.add_child(name_input)

		var count_lbl := Label.new()
		count_lbl.text = "%d Gebäude" % DistrictSys.count_buildings_in_district(did)
		if ColonySys.player_count() > 1:   # v16.0: zu welcher Kolonie der Bezirk gehört
			count_lbl.text += " · " + ColonySys.get_name_of(DistrictSys.district_colony(did))
		count_lbl.add_theme_font_size_override("font_size", 11)
		count_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		row.add_child(count_lbl)

		# Feature: zeigt an, mit welchen anderen Bezirken dieser aktuell per
		# Bezirkstor verknüpft ist (siehe DistrictSys.active_links).
		var linked: Array = []
		for other_id_v in ids:
			var other_id: int = int(other_id_v)
			if other_id != did and DistrictSys.are_linked(did, other_id):
				linked.append(DistrictSys.get_district_name(other_id))
		if not linked.is_empty():
			var link_lbl := Label.new()
			link_lbl.text = "🔗 " + ", ".join(linked)
			link_lbl.add_theme_font_size_override("font_size", 10)
			link_lbl.add_theme_color_override("font_color", Color(0.5, 0.85, 0.55))
			inner.add_child(link_lbl)

	var hint := Label.new()
	hint.text = "Jedes neue Bauhof-Gebäude gründet einen eigenen Bezirk. Lagerhäuser beliefern nur Baustellen im selben oder per Bezirkstor verbundenen Bezirk. Ein besetztes Bezirkstor verbindet automatisch alle Bezirke in seiner Reichweite."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	vb.add_child(hint)
