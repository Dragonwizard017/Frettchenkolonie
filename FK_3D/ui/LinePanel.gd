## LinePanel.gd
## Feature (v16.2, Logistik-Update Phase 2): Linien-Fenster der Güterzüge.
## Eine Linie besteht aus Haltestellen (Bahnhöfen) und Frachten ("Ware von Halt A nach
## Halt B"). Züge fahren die Halte reihum an: erst entladen, dann laden (siehe
## RailSys._exchange()). Baut seine UI dynamisch in _refresh() selbst auf, analog zu
## DistrictPanel.gd/ColonyPanel.gd.
extends PanelContainer

const RES_NAMES: Dictionary = {
	"WOOD": "Holz", "STONE": "Stein", "BERRIES": "Beeren", "PLANKS": "Bretter", "TOOLS": "Werkzeuge",
	"FOOD": "Essen", "IRON": "Eisen", "IRON_BARS": "Eisenstäbe", "MACHINES": "Maschinen",
	"COAL": "Kohle", "STEEL": "Stahl", "MEAT": "Fleisch", "WHEAT": "Weizen",
	"COOKED_MEAT": "Braten", "BREAD": "Brot", "STEW": "Eintopf", "DYNAMITE": "Dynamit",
}
var _selected: int = -1

func _ready() -> void:
	hide()
	MenuManager.register(self)
	GameState.hud_update_requested.connect(func():
		if visible and not _is_busy(): _refresh())

func open() -> void:
	show(); _refresh()

## Nicht neu aufbauen, solange der Spieler tippt oder ein Auswahlmenü offen hat.
func _is_busy() -> bool:
	var fo: Control = get_viewport().gui_get_focus_owner()
	if fo is LineEdit and is_ancestor_of(fo): return true
	if fo is OptionButton and is_ancestor_of(fo) and (fo as OptionButton).get_popup().visible: return true
	return false

func _res_label(res: String) -> String:
	return "%s %s" % [BuildingData.RESOURCE_ICONS.get(res, ""), RES_NAMES.get(res, res)]

func _station_options() -> Array:
	var out: Array = []
	for b in RailSys.get_buildings_of("STATION"): out.append(b)
	return out

func _stop_name(k: int) -> String:
	var sb = RailSys.station_at_key(k)
	return RailSys.get_station_name(sb as BuildingEntity) if sb != null else "(fehlt)"

func _train_state_text(t: TrainEntity) -> String:
	match t.state:
		"MOVING": return "fährt"
		"DWELL": return "hält"
		"BLOCKED": return "wartet (keine Strecke)"
		_: return "im Depot"

func _label(text: String, size: int = 11, col: Color = Color(0.75, 0.75, 0.75), wrap: bool = true) -> Label:
	var l := Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap: l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

## Auswahlfeld, das sich an die Breite anpasst und lange Namen abschneidet (statt das Fenster zu sprengen).
func _opt() -> OptionButton:
	var o := OptionButton.new()
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.clip_text = true
	o.custom_minimum_size = Vector2(120, 0)
	return o

func _refresh() -> void:
	for c in get_children(): c.queue_free()
	if not RailSys.lines.has(_selected):
		var ids: Array = RailSys.lines.keys(); ids.sort()
		_selected = int(ids[0]) if not ids.is_empty() else -1
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 6); add_child(vb)

	var hdr := HBoxContainer.new(); vb.add_child(hdr)
	var tl := Label.new(); tl.text = "🚂 Linien & Züge"
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.add_theme_font_size_override("font_size", 15)
	tl.add_theme_color_override("font_color", Color(0.95, 0.80, 0.45))
	hdr.add_child(tl)
	var cb := Button.new(); cb.text = "X"; cb.pressed.connect(hide); hdr.add_child(cb)
	vb.add_child(HSeparator.new())

	# Linienwahl
	var tabs := HFlowContainer.new(); vb.add_child(tabs)
	var ids2: Array = RailSys.lines.keys(); ids2.sort()
	for id_v in ids2:
		var lid: int = int(id_v)
		var tb := Button.new(); tb.text = str((RailSys.lines[lid] as Dictionary)["name"])
		tb.toggle_mode = true; tb.button_pressed = (lid == _selected)
		tb.add_theme_color_override("font_color", RailSys.line_color(lid))
		tb.pressed.connect(func(): _selected = lid; _refresh())
		tabs.add_child(tb)
	var nb := Button.new(); nb.text = "+ Neue Linie"
	nb.pressed.connect(func(): _selected = RailSys.create_line(); _refresh())
	tabs.add_child(nb)

	var sc := ScrollContainer.new(); sc.custom_minimum_size = Vector2(0, 380); vb.add_child(sc)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 8)
	sc.add_child(inner)

	if _selected < 0:
		inner.add_child(_label("Noch keine Linie. Baue zwei Bahnhöfe, verbinde sie mit Gleisen und erstelle hier eine Linie. 🚉 → 🛤️ → 🚉"))
		_add_depot_trains(inner)
		return
	var ln: Dictionary = RailSys.lines[_selected] as Dictionary
	var stops: Array = ln["stops"] as Array

	# Name + Löschen + Status
	var nrow := HBoxContainer.new(); inner.add_child(nrow)
	var ne := LineEdit.new(); ne.text = str(ln["name"]); ne.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sel: int = _selected
	ne.text_submitted.connect(func(t): _rename_line(sel, t); _refresh())
	ne.focus_exited.connect(func(): _rename_line(sel, ne.text))
	nrow.add_child(ne)
	var del := Button.new(); del.text = "Linie löschen"
	del.pressed.connect(func(): RailSys.delete_line(sel); _selected = -1; _refresh())
	nrow.add_child(del)
	var status: String = RailSys.line_status(_selected)
	inner.add_child(_label("✔ fahrbereit" if status == "" else "⚠ " + status, 12,
		Color(0.55, 0.85, 0.5) if status == "" else Color(0.95, 0.65, 0.25)))
	inner.add_child(_label("Geliefert: %d Einheiten · Züge auf der Linie: %d" % [int(float(ln.get("delivered", 0.0))), _trains_of(_selected).size()]))

	# Haltestellen
	inner.add_child(_label("Haltestellen (Reihenfolge = Fahrtroute, am Ende zurück zum ersten)", 12, Color(0.95, 0.80, 0.45)))
	for i in stops.size():
		var r := HBoxContainer.new(); inner.add_child(r)
		var sl := Label.new(); sl.text = "%d. %s" % [i + 1, _stop_name(int(stops[i]))]
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; r.add_child(sl)
		var idx: int = i
		var up := Button.new(); up.text = "▲"; up.disabled = i == 0
		up.pressed.connect(func(): _swap_stops(sel, idx, idx - 1)); r.add_child(up)
		var dn := Button.new(); dn.text = "▼"; dn.disabled = i == stops.size() - 1
		dn.pressed.connect(func(): _swap_stops(sel, idx, idx + 1)); r.add_child(dn)
		var rm := Button.new(); rm.text = "✕"
		rm.pressed.connect(func(): RailSys.remove_stop(sel, idx); _refresh()); r.add_child(rm)
	var stations: Array = _station_options()
	if stations.is_empty():
		inner.add_child(_label("Es gibt noch keinen fertigen Bahnhof.", 11, Color(0.95, 0.65, 0.25)))
	else:
		var arow := HBoxContainer.new(); inner.add_child(arow)
		var opt := _opt()
		for sb in stations: opt.add_item(RailSys.get_station_name(sb as BuildingEntity))
		arow.add_child(opt)
		var add := Button.new(); add.text = "+ Halt"
		add.pressed.connect(func():
			var sbb: BuildingEntity = stations[opt.selected] as BuildingEntity
			RailSys.add_stop(sel, RailSys.key(sbb.tile_x, sbb.tile_y)); _refresh())
		arow.add_child(add)

	# Frachten
	inner.add_child(_label("Frachten (was fährt von wo nach wo)", 12, Color(0.95, 0.80, 0.45)))
	var ships: Array = ln["shipments"] as Array
	for si in ships.size():
		var sd: Dictionary = ships[si]
		var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 3); inner.add_child(box)
		var row1 := HBoxContainer.new(); row1.add_theme_constant_override("separation", 4); box.add_child(row1)
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 4); box.add_child(row)
		var ro := _opt()
		var res_keys: Array = RES_NAMES.keys()
		for rk in res_keys: ro.add_item(_res_label(str(rk)))
		ro.selected = maxi(0, res_keys.find(str(sd["res"])))
		ro.item_selected.connect(func(i): sd["res"] = str(res_keys[i]))
		row1.add_child(ro)
		var fo := _opt()
		var to := _opt()
		for k in stops.size():
			fo.add_item("%d. %s" % [k + 1, _stop_name(int(stops[k]))])
			to.add_item("%d. %s" % [k + 1, _stop_name(int(stops[k]))])
		fo.selected = clampi(int(sd["from"]), 0, maxi(0, stops.size() - 1))
		to.selected = clampi(int(sd["to"]), 0, maxi(0, stops.size() - 1))
		fo.item_selected.connect(func(i): sd["from"] = i)
		to.item_selected.connect(func(i): sd["to"] = i)
		row.add_child(_label("   von", 11, Color(0.75, 0.75, 0.75), false))
		row.add_child(fo)
		row.add_child(_label("→ nach", 11, Color(0.75, 0.75, 0.75), false))
		row.add_child(to)
		var srm := Button.new(); srm.text = "✕"
		var sidx: int = si
		srm.pressed.connect(func(): RailSys.remove_shipment(sel, sidx); _refresh())
		row1.add_child(srm)
		box.add_child(HSeparator.new())
	var addship := Button.new(); addship.text = "+ Fracht"; addship.disabled = stops.size() < 2
	addship.pressed.connect(func(): RailSys.add_shipment(sel, "PLANKS", 0, 1); _refresh())
	inner.add_child(addship)

	# Züge der Linie
	inner.add_child(_label("Züge dieser Linie", 12, Color(0.95, 0.80, 0.45)))
	for t in _trains_of(_selected):
		var tr: TrainEntity = t
		var trow := HBoxContainer.new(); inner.add_child(trow)
		var tlbl := Label.new()
		tlbl.text = "Zug %d · %s · Fracht %d/%d · %s" % [tr.id, _train_state_text(tr), int(tr.cargo_total()), int(tr.capacity()), ColonySys.get_name_of(tr.colony_id)]
		tlbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; trow.add_child(tlbl)
		var home := Button.new(); home.text = "ins Depot"
		home.pressed.connect(func(): RailSys.assign_train(tr, -1); _refresh())
		trow.add_child(home)
	_add_depot_trains(inner)
	_add_buy_row(inner)

func _rename_line(line_id: int, new_name: String) -> void:
	var t: String = new_name.strip_edges()
	if t == "" or not RailSys.lines.has(line_id): return
	(RailSys.lines[line_id] as Dictionary)["name"] = t

func _trains_of(line_id: int) -> Array:
	var out: Array = []
	for t in RailSys.trains:
		if (t as TrainEntity).line_id == line_id: out.append(t)
	return out

func _swap_stops(line_id: int, a: int, b: int) -> void:
	var stops: Array = (RailSys.lines[line_id] as Dictionary)["stops"] as Array
	if a < 0 or b < 0 or a >= stops.size() or b >= stops.size(): return
	# Frachten behalten ihre Haltestellen: Indizes tauschen mit
	var tmp = stops[a]; stops[a] = stops[b]; stops[b] = tmp
	for sh in ((RailSys.lines[line_id] as Dictionary)["shipments"] as Array):
		var s: Dictionary = sh
		for fld in ["from", "to"]:
			if int(s[fld]) == a: s[fld] = b
			elif int(s[fld]) == b: s[fld] = a
	_refresh()

## Geparkte Züge (ohne Linie) der gewählten Linie zuweisen.
func _add_depot_trains(inner: VBoxContainer) -> void:
	var parked: Array = []
	for t in RailSys.trains:
		if (t as TrainEntity).line_id < 0: parked.append(t)
	if parked.is_empty(): return
	inner.add_child(_label("Züge im Depot", 12, Color(0.95, 0.80, 0.45)))
	for t in parked:
		var tr: TrainEntity = t
		var r := HBoxContainer.new(); inner.add_child(r)
		var l := Label.new(); l.text = "Zug %d · %s" % [tr.id, ColonySys.get_name_of(tr.colony_id)]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL; r.add_child(l)
		var asg := Button.new(); asg.text = "Auf Linie setzen"; asg.disabled = _selected < 0
		asg.pressed.connect(func(): RailSys.assign_train(tr, _selected); _refresh())
		r.add_child(asg)
		var sell := Button.new(); sell.text = "Abbauen"
		sell.pressed.connect(func(): RailSys.remove_train(tr); _refresh())
		r.add_child(sell)

func _add_buy_row(inner: VBoxContainer) -> void:
	var depots: Array = RailSys.get_buildings_of("DEPOT")
	var cost_txt: String = ""
	for k in RailSys.TRAIN_COSTS: cost_txt += "%d %s  " % [int(RailSys.TRAIN_COSTS[k]), RES_NAMES.get(k, k)]
	inner.add_child(_label("Zug kaufen: " + cost_txt, 11))
	if depots.is_empty():
		inner.add_child(_label("Du brauchst ein fertiges Depot.", 11, Color(0.95, 0.65, 0.25)))
		return
	var row := HBoxContainer.new(); inner.add_child(row)
	var opt := _opt()
	for d in depots:
		var de: BuildingEntity = d
		opt.add_item("Depot (%s, %d/%d)" % [ColonySys.get_name_of(de.colony_id), de.tile_x, de.tile_y])
	row.add_child(opt)
	var buy := Button.new(); buy.text = "Zug kaufen"
	var line_id: int = _selected
	buy.pressed.connect(func():
		var err: String = RailSys.buy_train(depots[opt.selected] as BuildingEntity, line_id)
		if err != "": GameState.notify(err, Color(0.85, 0.55, 0.15))
		_refresh())
	row.add_child(buy)
