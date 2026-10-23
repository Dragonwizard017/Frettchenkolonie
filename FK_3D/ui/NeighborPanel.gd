## NeighborPanel.gd
## Feature (v16.7, Logistik-Update Phase 5): Fenster "Nachbarn" - entdeckte Nachbarkolonien mit Ruf, Angebot,
## Bedarf, laufendem Auftrag und der Annexion. Baut seine UI dynamisch in _refresh() (wie ColonyPanel/LinePanel).
extends PanelContainer

const RES_NAMES: Dictionary = {
	"WOOD": "Holz", "STONE": "Stein", "BERRIES": "Beeren", "PLANKS": "Bretter", "TOOLS": "Werkzeuge",
	"FOOD": "Essen", "IRON": "Eisen", "IRON_BARS": "Eisenstäbe", "MACHINES": "Maschinen",
	"COAL": "Kohle", "STEEL": "Stahl", "MEAT": "Fleisch", "WHEAT": "Weizen",
	"COOKED_MEAT": "Braten", "BREAD": "Brot", "STEW": "Eintopf", "DYNAMITE": "Dynamit",
}

func _ready() -> void:
	hide()
	MenuManager.register(self)
	NeighborSys.neighbors_changed.connect(func():
		if visible and not _is_busy(): _refresh())
	GameState.hud_update_requested.connect(func():
		if visible and not _is_busy(): _refresh())

func open() -> void:
	show(); _refresh()

func _is_busy() -> bool:
	return false

func _gc() -> Node:
	return get_tree().root.find_child("GameScreen", true, false)

func _res(res: String) -> String:
	return "%s %s" % [BuildingData.RESOURCE_ICONS.get(res, ""), RES_NAMES.get(res, res)]

func _list_names(arr) -> String:
	var parts: PackedStringArray = []
	for r in arr: parts.append(_res(str(r)))
	return ", ".join(parts)

func _stock_of(cid: int, res: String) -> float:
	if ResourceSys.current_colony == cid: return float(ResourceSys.resources.get(res, 0.0))
	var p: Dictionary = ResourceSys.pools.get(cid, {}) as Dictionary
	return float((p.get("resources", {}) as Dictionary).get(res, 0.0))

func _label(text: String, size: int = 11, col: Color = Color(0.78, 0.78, 0.78)) -> Label:
	var l := Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _refresh() -> void:
	for c in get_children(): c.queue_free()
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 6); add_child(vb)
	var hdr := HBoxContainer.new(); vb.add_child(hdr)
	var tl := Label.new(); tl.text = "🤝 Nachbarn"
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.add_theme_font_size_override("font_size", 15)
	tl.add_theme_color_override("font_color", Color(0.78, 0.68, 0.98))
	hdr.add_child(tl)
	var cb := Button.new(); cb.text = "X"; cb.pressed.connect(hide); hdr.add_child(cb)
	vb.add_child(HSeparator.new())

	var sc := ScrollContainer.new(); sc.custom_minimum_size = Vector2(0, 400); vb.add_child(sc)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 10)
	sc.add_child(inner)

	var found := 0
	for cid_v in NeighborSys.cids():
		var cid: int = int(cid_v)
		if not NeighborSys.is_discovered(cid): continue
		found += 1
		_add_card(inner, cid)
	if found == 0:
		if not ExploreSys.enabled:
			inner.add_child(_label("Nachbarkolonien gibt es nur auf Entdeckerkarten (Weltgröße 'Entdecker', mit Nebel)."))
		else:
			inner.add_child(_label("Noch keine Nachbarn entdeckt. Im Nebel liegen fremde Kolonien - baue ab Epoche 5 eine Erkundungsstation und decke die Karte auf. Insgesamt gibt es %d Nachbarn." % NeighborSys.neighbors.size()))
	vb.add_child(_label("Handel: Waren, die du am Bahnhof eines Nachbarn ABLIEFERST, steigern den Ruf (gewünschte Waren doppelt). Waren, die du dort LÄDST, kosten etwas Ruf. Ab Ruf %d und mit Bahnanschluss kannst du den Nachbarn friedlich annektieren." % int(NeighborSys.ANNEX_REP), 10, Color(0.6, 0.6, 0.6)))

func _add_card(inner: VBoxContainer, cid: int) -> void:
	var pf: Dictionary = NeighborSys.profile_of(cid)
	var nb: Dictionary = NeighborSys.neighbors[cid] as Dictionary
	var annexed: bool = bool(nb["annexed"])
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.17, 0.14, 0.22, 0.9); sb.set_corner_radius_all(8)
	sb.content_margin_left = 10; sb.content_margin_right = 10; sb.content_margin_top = 8; sb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", sb)
	inner.add_child(card)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 4); card.add_child(v)

	var head := HBoxContainer.new(); v.add_child(head)
	var nm := Label.new(); nm.text = "%s %s · %s" % [str(pf.get("icon", "🏘️")), ColonySys.get_name_of(cid), str(pf.get("title", ""))]
	nm.add_theme_font_size_override("font_size", 13); nm.add_theme_color_override("font_color", Color(0.85, 0.78, 1.0))
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(nm)
	var st := Label.new(); st.text = NeighborSys.status_of(cid)
	st.add_theme_font_size_override("font_size", 11); st.add_theme_color_override("font_color", Color(0.55, 0.85, 0.6) if NeighborSys.rep_of(cid) >= 20.0 else Color(0.9, 0.75, 0.4))
	head.add_child(st)

	if annexed:
		v.add_child(_label("Diese Kolonie gehört jetzt zu dir - du findest sie im Kolonien-Fenster (🏛️)."))
	else:
		var bar := ProgressBar.new(); bar.min_value = NeighborSys.REP_MIN; bar.max_value = NeighborSys.REP_MAX
		bar.value = NeighborSys.rep_of(cid); bar.custom_minimum_size = Vector2(0, 14)
		bar.show_percentage = false; v.add_child(bar)
		v.add_child(_label("Ruf %d  (Ziel für Annexion: %d)" % [int(NeighborSys.rep_of(cid)), int(NeighborSys.ANNEX_REP)], 10))
		var offers_txt: PackedStringArray = []
		for r in (pf.get("offers", {}) as Dictionary):
			offers_txt.append("%s (Lager %d)" % [_res(str(r)), int(_stock_of(cid, str(r)))])
		v.add_child(_label("Bietet: " + ", ".join(offers_txt)))
		v.add_child(_label("Braucht: " + _list_names(pf.get("wants", []) as Array)))
		var rq: Dictionary = nb["request"] as Dictionary
		if rq.is_empty():
			v.add_child(_label("📜 Kein Auftrag. Neue Anfragen kommen alle paar Tage.", 11, Color(0.6, 0.6, 0.6)))
		else:
			v.add_child(_label("📜 Auftrag: %d × %s (geliefert %d/%d) · bis Tag %d · Belohnung: +%d Ruf und Werkzeug" % [int(rq["amount"]), _res(str(rq["res"])), int(float(rq["delivered"])), int(rq["amount"]), int(rq["deadline"]), int(float(rq["reward_rep"]))], 11, Color(0.95, 0.85, 0.5)))
		var sk: int = -1
		for sbld in RailSys.get_buildings_of("STATION"):
			var be: BuildingEntity = sbld
			if be.colony_id == cid: sk = RailSys.key(be.tile_x, be.tile_y); v.add_child(_label("🚉 " + RailSys.get_station_name(be), 10, Color(0.6, 0.6, 0.6)))
		var row := HBoxContainer.new(); v.add_child(row)
		var show_btn := Button.new(); show_btn.text = "Auf Karte zeigen"
		var hall: Vector2i = ColonySys.get_hall_tile(cid)
		show_btn.pressed.connect(func():
			var gc: Node = _gc()
			if gc != null and gc.has_method("focus_tile"): gc.call("focus_tile", hall.x, hall.y))
		row.add_child(show_btn)
		var why: String = NeighborSys.annex_block_reason(cid)
		var annex_btn := Button.new()
		var costs_txt: PackedStringArray = []
		for r in NeighborSys.ANNEX_COSTS: costs_txt.append("%d %s" % [int(NeighborSys.ANNEX_COSTS[r]), RES_NAMES.get(r, r)])
		annex_btn.text = "Annektieren"
		annex_btn.tooltip_text = "Kosten: " + ", ".join(costs_txt)
		annex_btn.disabled = why != ""
		annex_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		annex_btn.clip_text = true
		annex_btn.pressed.connect(func():
			var gc2: Node = _gc()
			var err: String = NeighborSys.annex(cid, gc2)
			if err != "": GameState.notify(err, Color(0.85, 0.55, 0.15))
			_refresh())
		row.add_child(annex_btn)
		v.add_child(_label("Annexion kostet: " + ", ".join(costs_txt) + " (aus deiner aktiven Kolonie)", 10, Color(0.6, 0.6, 0.6)))
		if why != "": v.add_child(_label("Annexion: " + why, 10, Color(0.9, 0.7, 0.4)))
