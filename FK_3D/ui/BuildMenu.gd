## BuildMenu.gd
extends Control

var _container: VBoxContainer = null
var _epoch_btn: Button = null
var _collapsed: bool = false

# v15.7: Tooltip beim Hovern über Gebäude (Beschreibung + Produktionsdaten, siehe BuildingTooltip)
var _tip: PanelContainer = null
var _tip_label: RichTextLabel = null
var _tip_timer: Timer = null
var _tip_poll: Timer = null
var _tip_grace_until: int = 0      # msec: nach Rebind kurz nicht prüfen (Layout)
var _tip_btn: Control = null
var _tip_bid: String = ""
const TIP_WIDTH: float = 340.0
const TIP_DELAY: float = 0.25

func _ready() -> void:
	_container  = get_node_or_null("Outer/ScrollContainer/VBoxContainer")
	_epoch_btn  = get_node_or_null("Outer/Header/EpochBtn")
	if _epoch_btn: _epoch_btn.pressed.connect(_on_epoch_btn_pressed)
	var toggle: Button = get_node_or_null("Outer/Header/ToggleBtn")
	if toggle: toggle.pressed.connect(_toggle_collapse)
	GameState.build_menu_update_requested.connect(refresh)
	GameState.placement_mode_changed.connect(func(_m,_s): refresh())
	GameState.state_changed.connect(_on_state_changed)
	visibility_changed.connect(_tip_hide)
	call_deferred("_build_tip")

## Bug-Fix (fehlender Epochen-Button): Klick auf den Epochen-Button im Header
## versucht direkt, die nächste Epoche freizuschalten. Davor gab es überhaupt
## keinen dauerhaft sichtbaren Weg dafür - der alte Unlock-Button erschien nur
## ganz unten in der Liste und auch nur, wenn man sich die Epoche bereits
## leisten konnte.
func _on_epoch_btn_pressed() -> void:
	var next_id: String = TechTreeSys.get_next_epoch_id()
	if next_id == "":
		return
	# Bugfix: TechTreeSys.unlock() existiert seit dem Tech-Tree-Umbau nicht
	# mehr (aufgeteilt in unlock_node()/unlock_epoch()) - dieser Aufruf ist
	# seit v11.5 fehlgeschlagen (Aufruf einer nicht existierenden Methode).
	if not TechTreeSys.unlock_epoch(next_id):
		if not TechTreeSys.epoch_requirement_met(next_id):
			GameState.notify("Noch nicht genug Knoten der aktuellen Epoche erforscht!")
		else:
			GameState.notify("Nicht genug Wissenspunkte für die nächste Epoche!")
	refresh()

## Bug-Fix (v14.3, gemeldet: "das Baufeld lässt sich nicht einklappen"):
## _toggle_collapse() hat bisher NUR die Bauliste (ScrollContainer)
## unsichtbar gemacht - das Panel selbst (BuildMenu, dieses Control hier)
## hatte aber eine FEST codierte Breite (offset_right = 224 in
## Main.gd._build_build_menu()), die sich nie geändert hat. Eingeklappt
## stand also weiterhin ein leerer, 224px breiter, dunkler Balken über der
## Karte - sah für Spieler exakt so aus, als würde gar nichts passieren.
## Jetzt wird beim Einklappen zusätzlich die Panelbreite selbst auf einen
## schmalen Streifen (nur Kopfzeile mit dem Umschalt-Button) reduziert, und
## der Button zeigt ">>"/"<<"  passend zum aktuellen Zustand.
const EXPANDED_WIDTH: float = 216.0
const COLLAPSED_WIDTH: float = 52.0

func _toggle_collapse() -> void:
	_collapsed = !_collapsed
	var sc: Control = get_node_or_null("Outer/ScrollContainer")
	if sc: sc.visible = !_collapsed
	var epoch_btn_node: Control = get_node_or_null("Outer/Header/EpochBtn")
	if epoch_btn_node: epoch_btn_node.visible = !_collapsed
	offset_right = COLLAPSED_WIDTH if _collapsed else EXPANDED_WIDTH
	var toggle: Button = get_node_or_null("Outer/Header/ToggleBtn")
	if toggle: toggle.text = ">>" if _collapsed else "<<"

## v15.8 (Performance-Fix): das Menü wurde jede Sekunde komplett neu gebaut (~350 ms wegen der
## RichText-Karten = Ruckler im Sekundentakt). Jetzt nur noch, wenn sich der Inhalt WIRKLICH ändert -
## erkannt an einer Signatur (freigeschaltete Gebäude, Auswahl, Bezahlbarkeit der Kosten).
var _last_sig: String = ""

func _menu_signature() -> String:
	var parts: PackedStringArray = []
	parts.append(str(TechTreeSys.get_epoch()))
	parts.append("%s:%s" % [GameState.placement_mode, str(GameState.placement_sub)])
	parts.append("1" if GameState.dev_all_buildings else "0")
	parts.append("F1" if ExploreSys.enabled else "F0")
	var all_b: Dictionary = BuildingData.BUILDINGS
	for bid in TechTreeSys.get_unlocked_buildings():
		if not all_b.has(bid): continue
		var costs: Dictionary = (all_b[bid] as Dictionary).get("costs", {}) as Dictionary
		var bits: String = "1" if BuildingSys.can_build(str(bid)) else "0"
		for res in costs: bits += "1" if ResourceSys.has(str(res), float(costs[res])) else "0"
		parts.append(str(bid) + bits)
	for ptype in BuildingData.PATH_TYPES:
		var pc: Dictionary = (BuildingData.PATH_TYPES[ptype] as Dictionary).get("costs", {}) as Dictionary
		parts.append(str(ptype) + ("1" if ResourceSys.can_afford(pc) else "0"))
	parts.append("R" + ("1" if ResourceSys.can_afford(RailSys.RAIL_COSTS) else "0"))
	parts.append("S" + ("1" if ResourceSys.has("STONE", 2) else "0"))
	parts.append("D" + str(int(float(ResourceSys.resources.get("DYNAMITE", 0.0)))))
	return "|".join(parts)

func refresh(force: bool = false) -> void:
	if not is_inside_tree() or _container == null: return
	var sig: String = _menu_signature()
	if not force and sig == _last_sig and _container.get_child_count() > 0:
		_update_epoch_btn()     # billig; Forschungspunkte ändern den Text, ohne dass sich die Einträge ändern
		return
	_last_sig = sig
	# v15.8: das Menü wird im 1-Sekunden-Takt neu aufgebaut (Kauf-Sperren aktuell halten). Der Tooltip
	# darf dabei NICHT schließen (war der Fehler: er verschwand nach <= 1 s), sondern wird danach
	# an den neuen Eintrag gebunden. Schließen tut ihn nur noch: Maus weg, Klick, Menü weg.
	var keep_tip: String = _tip_bid if (_tip != null and _tip.visible) else ""
	for c in _container.get_children(): c.queue_free()
	var unlocked: Array = TechTreeSys.get_unlocked_buildings()
	_update_epoch_btn()
	var all_b: Dictionary = BuildingData.BUILDINGS
	var type_order: Array = ["BUILDER","HOUSING","STORAGE","COLLECTOR","PROCESSOR",
		"MULTIPROCESSOR","HUNTER","FARMHOUSE","FORESTER","HAPPINESS","WATERWHEEL","DAM","DISTRICT_GATE","TOWN_HALL","EXPLORER","STATION","DEPOT","EXPEDITION","GRAVEYARD"]
	var type_labels: Dictionary = {
		"BUILDER":"Bauhöfe","HOUSING":"Wohnen","STORAGE":"Lager","COLLECTOR":"Sammler",
		"PROCESSOR":"Verarbeitung","MULTIPROCESSOR":"Küche","HUNTER":"Jagd",
		"FARMHOUSE":"Landwirtschaft","FORESTER":"Forstwirtschaft","HAPPINESS":"Glück",
		"WATERWHEEL":"Wasserrad","DAM":"Dämme","DISTRICT_GATE":"Bezirke","TOWN_HALL":"Kolonie","EXPLORER":"Erkundung","STATION":"Bahnhöfe","DEPOT":"Depots","EXPEDITION":"Expeditionen","GRAVEYARD":"Gedenkstätte"}
	for btype in type_order:
		var ids: Array = []
		for bid in unlocked:
			if not all_b.has(bid): continue
			var bd: Dictionary = all_b[bid] as Dictionary
			# v16.6: Erkundungsstation nur auf Entdeckerkarten (Nebel) sinnvoll
			if btype == "EXPLORER" and not ExploreSys.enabled and not GameState.dev_all_buildings: continue
			if str(bd.get("type","")) == btype and str(bd.get("type","")) != "DECO": ids.append(str(bid))
		if ids.is_empty(): continue
		_add_header(str(type_labels.get(btype, btype)))
		for bid in ids: _add_building_btn(str(bid))
		# Feature (v14.5, Timberborn-Feld-System): Feld-Werkzeug direkt unter
		# dem Bauernhof-Button, nur sichtbar, sobald FARMHOUSE freigeschaltet
		# ist (sonst gäbe es noch gar kein Gebäude, das Felder bewirtschaftet).
		if btype == "FARMHOUSE":
			_add_field_btn("SET", "🌾 Feld setzen", "Kostenlos  Drag=malen  nur auf Wiesen")
			_add_field_btn("CLEAR", "🚫 Feld entfernen", "Drag=malen")
	# Feature (v16.2, Schiene): Gleis-Werkzeug, sichtbar sobald Bahnhöfe freigeschaltet sind.
	if "STATION" in unlocked or GameState.dev_all_buildings:
		_add_header("Gleise")
		_add_rail_btn("PLACE", "🛤️ Gleis legen", RailSys.RAIL_COSTS, "ziehen zum Malen · nur flach, kein Wasser/Gebirge")
		_add_rail_btn("REMOVE", "🚫 Gleis entfernen", {}, "ziehen zum Entfernen")
	_add_header("Wege")
	for ptype in BuildingData.PATH_TYPES: _add_path_btn(str(ptype))
	var decos: Array = []
	for bid in unlocked:
		if not all_b.has(bid): continue
		if str((all_b[bid] as Dictionary).get("type","")) == "DECO": decos.append(str(bid))
	if not decos.is_empty():
		_add_header("Dekorationen")
		for bid in decos: _add_building_btn(str(bid))
	_add_header("Terrain")
	_add_terrain_btn("RAISE","Erde aufschütten","2 Stein/Tile  Drag=malen", ResourceSys.has("STONE",2))
	var dyn: int = int(float(ResourceSys.resources.get("DYNAMITE",0.0)))
	_add_terrain_btn("DYNAMITE","Sprengstoff (%d)" % dyn,"1 Dynamit  Klick=Legen  Nochmal=Zünden", dyn>=1)
	if keep_tip != "": _tip_rebind(keep_tip)

## Aktualisiert Text/Status des Epochen-Buttons im Header (zeigt aktuelle
## Epoche; falls eine nächste Epoche verfügbar ist, deren Namen + Kosten;
## der Button ist deaktiviert, solange die Kosten nicht gedeckt sind).
func _update_epoch_btn() -> void:
	if _epoch_btn == null: return
	var cur: int = TechTreeSys.get_epoch()
	var next_id: String = TechTreeSys.get_next_epoch_id()
	if next_id == "":
		_epoch_btn.text = "Epoche %d (Max)" % cur
		_epoch_btn.disabled = true
		_epoch_btn.theme_type_variation = ""
		return
	# Bugfix: TechTreeSys.nodes gab es nie (die Konstante heisst NODES und
	# enthält ohnehin nur Tech-Knoten, keine Epochen) - Epochen-Daten stehen
	# in TechTreeSys.EPOCHS, ihre Kosten sind ein einzelner Wissenspunkte-Betrag
	# ("cost"), kein Ressourcen-Dictionary ("costs"). Freischaltbar ist eine
	# Epoche zudem erst, wenn zusätzlich ~80% der Knoten der aktuellen Epoche
	# erforscht sind (siehe TechTreeSys.can_unlock_epoch()).
	var ed: Dictionary = TechTreeSys.EPOCHS.get(next_id, {}) as Dictionary
	var cost: float = float(ed.get("cost", 0.0))
	var can: bool = TechTreeSys.can_unlock_epoch(next_id)
	var req_met: bool = TechTreeSys.epoch_requirement_met(next_id)
	if not req_met:
		var cur_count: int = TechTreeSys.get_epoch_unlocked_count(cur)
		var cur_total: int = TechTreeSys.get_node_ids_for_epoch(cur).size()
		_epoch_btn.text = "Epoche %d -> %s\nForschung: %d/%d" % [cur, str(ed.get("name", next_id)), cur_count, cur_total]
	else:
		_epoch_btn.text = "Epoche %d -> %s\n🔬%d" % [cur, str(ed.get("name", next_id)), int(cost)]
	_epoch_btn.disabled = not can
	_epoch_btn.theme_type_variation = "PrimaryButton" if can else ""

func _add_header(text: String) -> void:
	# v15.0: Abschnittskopf als Versalien in Akzentfarbe (statt "-- Text --")
	if _container.get_child_count() > 0:
		var gap := Control.new(); gap.custom_minimum_size = Vector2(0, 2); _container.add_child(gap)
	var lbl := UITheme.lbl(text.to_upper(), "Subheading")
	_container.add_child(lbl)

func _add_building_btn(bid: String) -> void:
	var all_b: Dictionary = BuildingData.BUILDINGS
	if not all_b.has(bid): return
	var data: Dictionary = all_b[bid] as Dictionary
	var can: bool = BuildingSys.can_build(bid) or GameState.dev_all_buildings
	var btn: Button = _make_btn(str(data.get("icon","?"))+"  "+str(data.get("name",bid)), _costs_rich(data.get("costs",{}) as Dictionary), can)
	if GameState.placement_mode == "BUILDING" and GameState.placement_sub == bid:
		_mark_selected(btn)
	var b: String = bid
	btn.pressed.connect(func(): GameState.set_placement("BUILDING", b); refresh())
	btn.set_meta("bid", b)
	btn.mouse_entered.connect(func(): _tip_request(btn, b))
	btn.mouse_exited.connect(func(): _tip_exit(btn))
	btn.pressed.connect(_tip_hide)     # Klick (Platzieren) schließt den Tooltip
	_container.add_child(btn)

func _add_rail_btn(sub: String, title: String, costs: Dictionary, hint: String) -> void:
	var can: bool = costs.is_empty() or ResourceSys.can_afford(costs) or GameState.dev_all_buildings
	var desc: String = (_costs_rich(costs) + "  " if not costs.is_empty() else "") + "[color=#b8a98c]· " + hint + "[/color]"
	var btn: Button = _make_btn(title, desc, can)
	if GameState.placement_mode == "RAIL" and GameState.placement_sub == sub:
		_mark_selected(btn)
	var s: String = sub
	btn.pressed.connect(func(): GameState.set_placement("RAIL", s); refresh())
	_container.add_child(btn)

func _add_path_btn(ptype: String) -> void:
	var pt: Dictionary = BuildingData.PATH_TYPES.get(ptype,{}) as Dictionary
	var costs: Dictionary = pt.get("costs",{}) as Dictionary
	var can: bool = ResourceSys.can_afford(costs) or GameState.dev_all_buildings
	var btn: Button = _make_btn(str(pt.get("name",ptype))+" (Weg)", _costs_rich(costs)+"  [color=#b8a98c]· ziehen zum Malen[/color]", can)
	var p: String = ptype
	btn.pressed.connect(func(): GameState.set_placement("PATH", p); refresh())
	_container.add_child(btn)

func _add_terrain_btn(sub: String, title: String, desc: String, enabled: bool) -> void:
	var btn: Button = _make_btn(title, desc, enabled)
	if GameState.placement_mode == "TERRAIN" and GameState.placement_sub == sub:
		_mark_selected(btn)
	var s: String = sub
	btn.pressed.connect(func(): GameState.set_placement("TERRAIN", s); refresh())
	_container.add_child(btn)

## Feature (v14.5, Timberborn-Feld-System): Feld-Werkzeug-Button, analog zu
## _add_terrain_btn() oben - setzt placement_mode "FIELD" mit sub "SET" bzw.
## "CLEAR" (siehe GameController._place_field()).
func _add_field_btn(sub: String, title: String, desc: String) -> void:
	var btn: Button = _make_btn(title, desc, true)
	if GameState.placement_mode == "FIELD" and GameState.placement_sub == sub:
		_mark_selected(btn)
	var s: String = sub
	btn.pressed.connect(func(): GameState.set_placement("FIELD", s); refresh())
	_container.add_child(btn)

## Alte, seit Einführung von TechTreePanel.gd nicht mehr aufgerufene
## Hilfsfunktion für einen einzelnen Tech-Knoten-Button. Referenzierte bisher
## TechTreeSys.nodes/can_unlock()/unlock(), die es seit dem Tech-Tree-Umbau
## nicht mehr gibt (Bugfix, obwohl aktuell unbenutzt - falls diese Funktion
## später wieder verdrahtet wird, soll sie nicht sofort abstürzen).
func _add_tech_btn(tid: String) -> void:
	var nd: Dictionary = TechTreeSys.NODES.get(tid,{}) as Dictionary
	var btn: Button = _make_btn("Erforschen: "+str(nd.get("name",tid)), "🔬"+str(int(nd.get("cost",0.0))), TechTreeSys.can_unlock_node(tid))
	var t: String = tid
	btn.pressed.connect(func(): TechTreeSys.unlock_node(t); refresh())
	_container.add_child(btn)

## v15.0: Eintrag als Karte - Titel fett, darunter die Kostenzeile (BBCode erlaubt).
func _make_btn(title: String, sub: String, enabled: bool) -> Button:
	var btn := Button.new()
	btn.theme_type_variation = "BuildItem"
	btn.disabled = not enabled
	btn.toggle_mode = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 44)
	btn.clip_contents = true
	var mc := MarginContainer.new(); mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mc.add_theme_constant_override("margin_left", 10); mc.add_theme_constant_override("margin_right", 6)
	mc.add_theme_constant_override("margin_top", 3);  mc.add_theme_constant_override("margin_bottom", 3)
	btn.add_child(mc)
	var vb := VBoxContainer.new(); vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 1); vb.alignment = BoxContainer.ALIGNMENT_CENTER
	mc.add_child(vb)
	var tl := Label.new(); tl.text = title; tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.add_theme_font_size_override("font_size", 14)
	tl.clip_text = true
	vb.add_child(tl)
	var rt := RichTextLabel.new(); rt.bbcode_enabled = true; rt.fit_content = true
	rt.scroll_active = false; rt.autowrap_mode = TextServer.AUTOWRAP_OFF
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rt.add_theme_font_size_override("normal_font_size", 11)
	rt.add_theme_color_override("default_color", UITheme.C_TEXT_MUTED)
	rt.text = sub
	vb.add_child(rt)
	if not enabled: btn.modulate = Color(1, 1, 1, 0.6)
	return btn

func _mark_selected(btn: Button) -> void:
	btn.set_pressed_no_signal(true)

## Kostenzeile mit BBCode: getönte Icons, nicht bezahlbare Beträge in Rot.
func _costs_rich(costs: Dictionary) -> String:
	var parts: Array = []
	var icons: Dictionary = BuildingData.RESOURCE_ICONS
	for res in costs:
		var r: String = str(res)
		var need: float = float(costs[res])
		var col: Color = UITheme.RES_COLORS.get(r, UITheme.C_TEXT_MUTED)
		var amount_col: Color = UITheme.C_TEXT_MUTED if ResourceSys.has(r, need) else UITheme.C_DANGER
		parts.append("[color=%s]%s[/color] [color=%s]%s[/color]" % [UITheme.hex(col), str(icons.get(r, "?")), UITheme.hex(amount_col), str(costs[res])])
	return "   ".join(parts) if not parts.is_empty() else "[color=#b8a98c]kostenlos[/color]"

func _costs_str(costs: Dictionary) -> String:
	var parts: Array = []
	var icons: Dictionary = BuildingData.RESOURCE_ICONS
	for res in costs: parts.append(str(icons.get(str(res),"?"))+str(costs[res]))
	return " ".join(parts)

func _on_state_changed(state: GameState.State) -> void:
	visible = (state == GameState.State.PLAYING)


# ── Tooltip (v15.7) ──────────────────────────────────────────────────────────────────────────
func _build_tip() -> void:
	var host: Node = get_parent()
	if host == null or _tip != null: return
	_tip_timer = Timer.new(); _tip_timer.one_shot = true; _tip_timer.wait_time = TIP_DELAY
	_tip_timer.timeout.connect(_tip_show)
	add_child(_tip_timer)
	# Wächter: solange der Tooltip offen ist, prüft er alle 0.1 s, ob die Maus noch über dem Eintrag ist
	_tip_poll = Timer.new(); _tip_poll.wait_time = 0.1; _tip_poll.one_shot = false
	_tip_poll.timeout.connect(_tip_check)
	add_child(_tip_poll)
	_tip = UITheme.panel("FloatPanel")
	_tip.name = "BuildingTooltip"
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.z_index = 80
	_tip.visible = false
	_tip.custom_minimum_size = Vector2(TIP_WIDTH, 0)
	_tip.size = Vector2(TIP_WIDTH, 10)
	var mg := MarginContainer.new(); mg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]: mg.add_theme_constant_override("margin_" + side, 8)
	for side2 in ["top", "bottom"]: mg.add_theme_constant_override("margin_" + side2, 6)
	_tip.add_child(mg)
	_tip_label = RichTextLabel.new()
	_tip_label.bbcode_enabled = true; _tip_label.fit_content = true; _tip_label.scroll_active = false
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_label.custom_minimum_size = Vector2(TIP_WIDTH - 32.0, 0)
	_tip_label.add_theme_font_size_override("normal_font_size", 13)
	mg.add_child(_tip_label)
	host.add_child(_tip)

func _tip_request(btn: Control, bid: String) -> void:
	if _tip == null or TouchControlsSettings.enabled: return   # Touch: kein Hover
	_tip_btn = btn; _tip_bid = bid
	_tip_timer.start()

func _tip_hide() -> void:
	if _tip_timer != null: _tip_timer.stop()
	if _tip_poll != null: _tip_poll.stop()
	_tip_btn = null
	if _tip != null: _tip.visible = false

## Nur für Tests: feste Mausposition statt der echten (headless gibt es keinen Mauszeiger).
var debug_mouse: Vector2 = Vector2(-1, -1)

func _mouse_pos() -> Vector2:
	return debug_mouse if debug_mouse.x >= 0.0 else get_global_mouse_position()

func _mouse_over(c: Control) -> bool:
	return c != null and is_instance_valid(c) and c.is_inside_tree() and c.get_global_rect().has_point(_mouse_pos())

## mouse_exited kann auch feuern, wenn der Eintrag nur neu gebaut wird (Maus noch drüber) -> dann ignorieren.
func _tip_exit(btn: Control) -> void:
	if btn == _tip_btn and (_mouse_over(btn) or Time.get_ticks_msec() < _tip_grace_until): return
	_tip_hide()

func _tip_check() -> void:
	if _tip == null or not _tip.visible: return
	# Ein gerade neu gebauter Eintrag ist erst nach dem nächsten Layout-Durchlauf positioniert (Größe 0):
	# bis dahin nicht urteilen, sonst schließt der Wächter den Tooltip zufällig direkt nach dem Neuaufbau.
	if _tip_btn != null and is_instance_valid(_tip_btn) and (_tip_btn.size.x < 1.0 or Time.get_ticks_msec() < _tip_grace_until):
		return
	if _tip_btn == null or not _mouse_over(_tip_btn):
		_tip_hide()
	else:
		_tip_place()

## Nach dem Menü-Neuaufbau: Tooltip an den neuen Eintrag derselben Gebäude-ID hängen (Kosten-Farben aktuell).
func _tip_rebind(bid: String) -> void:
	for c in _container.get_children():
		if c.is_queued_for_deletion(): continue
		if c.has_meta("bid") and str(c.get_meta("bid")) == bid:
			_tip_btn = c as Control
			_tip_bid = bid
			_tip_grace_until = Time.get_ticks_msec() + 250
			_tip_label.text = BuildingTooltip.build(bid)
			_tip.reset_size()
			call_deferred("_tip_place")
			return
	_tip_hide()

func _tip_show() -> void:
	if _tip == null or _tip_btn == null or not is_instance_valid(_tip_btn) or _tip_bid == "": return
	_tip_label.text = BuildingTooltip.build(_tip_bid)
	_tip.visible = true
	_tip.reset_size()
	if _tip_poll != null: _tip_poll.start()
	call_deferred("_tip_place")

## Rechts neben dem Menü, auf Höhe des Eintrags, nie aus dem Bildschirm heraus.
func _tip_place() -> void:
	if _tip == null or _tip_btn == null or not is_instance_valid(_tip_btn): return
	var vp: Vector2 = get_viewport_rect().size
	var br: Rect2 = _tip_btn.get_global_rect()
	var mr: Rect2 = get_global_rect()
	var sz: Vector2 = _tip.size
	var x: float = mr.end.x + 8.0
	if x + sz.x > vp.x - 8.0: x = maxf(8.0, vp.x - sz.x - 8.0)
	var y: float = clampf(br.position.y, 44.0, maxf(44.0, vp.y - sz.y - 8.0))
	_tip.global_position = Vector2(x, y)
