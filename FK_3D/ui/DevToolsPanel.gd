## DevToolsPanel.gd
## Feature (v11.10, Dev Mode) / überarbeitet v16.5: Werkzeug-Fenster, das NUR sichtbar ist,
## wenn DevMode.enabled true ist (Aktivierung per Passwort in den Einstellungen, siehe
## DevMode.gd). Macht alle großen Systeme testbar: Ressourcen, Epochen/Forschung, Frettchen,
## Baustellen, Zeit/Jahreszeit/Dürre, Kolonien, Schiene (ein Klick baut eine komplette
## Test-Linie) und Tutorials.
##
## Layout: dockt am RECHTEN Rand UNTER der HUD-Spalte (Uhr/Tempo/Knöpfe) an, ist
## einklappbar (▾/▸) und scrollt innen - so verdeckt es weder Bau-Menü noch Ressourcenleiste,
## noch die Fenster in der Bildschirmmitte. Die Position wird laufend an die tatsächliche
## Höhe der HUD-Spalte angepasst. Die eigentliche Logik steckt als dev_*()-Funktionen im
## GameController (hat Zugriff auf Welt/Renderer/Spieler); hier sind nur Knöpfe.
extends PanelContainer

const WIDTH: float = 292.0
const MARGIN: float = 8.0

var _collapsed: bool = false
var _tabs: TabContainer = null
var _relayout_timer: float = 0.0
var _last_top: float = -1.0

func _ready() -> void:
	DevMode.dev_mode_changed.connect(func(_e): _refresh())
	get_viewport().size_changed.connect(_relayout)
	_refresh()

func _process(delta: float) -> void:
	if not visible: return
	_relayout_timer += delta
	if _relayout_timer >= 0.4:
		_relayout_timer = 0.0
		_relayout()

func _gc() -> Node:
	return get_tree().root.find_child("GameScreen", true, false)

## Panel unter die rechte HUD-Spalte setzen (Höhe schwankt: Dürre-Zeile, Fensterbreite ...).
func _relayout() -> void:
	if not visible: return
	var top: float = 340.0
	var rc := get_node_or_null("../HUD/RightColumn") as Control
	if rc != null and rc.is_visible_in_tree():
		top = rc.get_global_rect().end.y + 8.0 - get_parent_control().global_position.y
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	anchor_left = 1.0; anchor_right = 1.0; anchor_top = 0.0; anchor_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_left = -(WIDTH + MARGIN); offset_right = -MARGIN
	var avail: float = get_viewport_rect().size.y - top - 12.0
	offset_top = top
	if _collapsed:
		offset_bottom = top + 36.0
	else:
		offset_bottom = top + maxf(160.0, minf(avail, 520.0))
	_last_top = top

func _refresh() -> void:
	visible = DevMode.enabled
	if not visible: return
	for c in get_children(): c.queue_free()
	mouse_filter = Control.MOUSE_FILTER_STOP

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.14, 0.08, 0.95)
	sb.border_color = Color(0.35, 0.85, 0.4)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 8; sb.content_margin_right = 8
	sb.content_margin_top = 6;  sb.content_margin_bottom = 6
	add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 4); add_child(vb)
	var hdr := HBoxContainer.new(); vb.add_child(hdr)
	var tl := Label.new(); tl.text = "🛠️ Dev Tools"
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.add_theme_font_size_override("font_size", 13)
	tl.add_theme_color_override("font_color", Color(0.5, 0.95, 0.55))
	hdr.add_child(tl)
	var tg := Button.new(); tg.text = "▸" if _collapsed else "▾"
	tg.tooltip_text = "Ein-/Ausklappen"
	tg.pressed.connect(func(): _collapsed = not _collapsed; _refresh())
	hdr.add_child(tg)
	if _collapsed:
		call_deferred("_relayout"); return

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 10)
	vb.add_child(_tabs)
	_build_basis(_tab("Basis"))
	_build_welt(_tab("Welt"))
	_build_kolonien(_tab("Kolonien"))
	_build_schiene(_tab("Schiene"))
	_build_hilfe(_tab("Hilfe"))
	call_deferred("_relayout")

# ── Aufbau-Helfer ────────────────────────────────────────────────────────────
func _tab(title: String) -> VBoxContainer:
	var sc := ScrollContainer.new(); sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 3)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	_tabs.add_child(sc)
	return vb

func _btn(vb: VBoxContainer, text: String, cb: Callable) -> void:
	var b := Button.new(); b.text = text
	b.add_theme_font_size_override("font_size", 10)
	b.clip_text = true
	b.pressed.connect(cb)
	vb.add_child(b)

func _note(vb: VBoxContainer, text: String) -> void:
	var l := Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_color", Color(0.6, 0.75, 0.6))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(l)

func _toggle(vb: VBoxContainer, text: String, on: bool, cb: Callable) -> void:
	var c := CheckButton.new(); c.text = text; c.button_pressed = on
	c.add_theme_font_size_override("font_size", 10)
	c.toggled.connect(cb)
	vb.add_child(c)

func _say(msg: String) -> void:
	if msg != "": GameState.notify(msg, Color(0.5, 0.95, 0.55))

## ruft eine dev_*()-Funktion des GameControllers auf; Rückgabe (String) wird als Meldung gezeigt
func _call(fn: String, args: Array = []) -> void:
	var gc: Node = _gc()
	if gc == null or not gc.has_method(fn):
		GameState.notify("🛠️ Nicht verfügbar (kein laufendes Spiel)"); return
	var r = gc.callv(fn, args)
	if r is String: _say(str(r))

# ── Reiter ───────────────────────────────────────────────────────────────────
func _build_basis(vb: VBoxContainer) -> void:
	_toggle(vb, "Alles gratis bauen", GameState.dev_all_buildings, func(on):
		GameState.dev_all_buildings = on
		GameState.build_menu_update_requested.emit()
		_say("Alles gratis bauen: " + ("AN" if on else "AUS")))
	_toggle(vb, "Lager-Limit aus (nichts geht verloren)", GameState.dev_unlimited_storage, func(on):
		GameState.dev_unlimited_storage = on
		_say("Lager-Limit: " + ("AUS (unbegrenzt)" if on else "wieder aktiv")))
	_btn(vb, "+500 aller Ressourcen (aktive Kolonie)", func(): _call("dev_add_all_resources", [500.0]))
	_btn(vb, "+5000 aller Ressourcen", func(): _call("dev_add_all_resources", [5000.0]))
	_btn(vb, "+1000 Wissenspunkte", func():
		ResourceSys.science += 1000.0
		_say("+1000 Wissenspunkte"))
	_btn(vb, "Nächste Epoche freischalten", func():
		var next_id: String = TechTreeSys.get_next_epoch_id()
		if next_id == "":
			_say("Höchste Epoche bereits erreicht."); return
		_call("dev_unlock_all_epochs", [1]))
	_btn(vb, "ALLE Epochen freischalten", func(): _call("dev_unlock_all_epochs", [99]))
	_btn(vb, "ALLE Tech-Knoten freischalten", func(): _call("dev_unlock_all_tech"))
	_btn(vb, "+5 Frettchen (aktive Kolonie)", func(): _call("dev_spawn_ferrets", [5]))
	_btn(vb, "Frettchen & Wasser auffüllen", func(): _call("dev_fill_needs"))
	_btn(vb, "Alle Baustellen sofort fertig", func(): _call("dev_finish_construction"))
	_btn(vb, "Alle Achievements freischalten", func():
		for aid in AchievementSys.ACHIEVEMENTS:
			if not AchievementSys.is_unlocked(aid):
				AchievementSys.debug_force_unlock(aid)
		_say("Alle Achievements freigeschaltet"))

func _build_welt(vb: VBoxContainer) -> void:
	_note(vb, "Tageszeit")
	_btn(vb, "→ Morgen (06:00)", func(): _call("dev_set_time", [0.0]))
	_btn(vb, "→ Mittag (12:00)", func(): _call("dev_set_time", [0.25]))
	_btn(vb, "→ Abend (18:00)", func(): _call("dev_set_time", [0.5]))
	_btn(vb, "→ Nacht (02:00)", func(): _call("dev_set_time", [0.84]))
	_note(vb, "Jahreszeit & Wetter")
	_btn(vb, "Nächste Jahreszeit", func(): _call("dev_next_season"))
	_btn(vb, "Dürre starten", func(): _call("dev_start_drought"))
	_btn(vb, "Dürre beenden", func(): _call("dev_end_drought"))
	_note(vb, "Erkundung (nur Entdeckerkarten mit Nebel)")
	_btn(vb, "Radius 20 um das Rathaus aufdecken", func(): _call("dev_reveal_ring", [20.0]))
	_btn(vb, "Radius 40 um das Rathaus aufdecken", func(): _call("dev_reveal_ring", [40.0]))
	_btn(vb, "Ganze Karte aufdecken", func(): _call("dev_reveal_all"))
	_btn(vb, "Weltkarte öffnen", func():
		var p := get_node_or_null("../WorldMapPanel")
		if p and p.has_method("open"): p.call("open"))
	_note(vb, "Spielgeschwindigkeit (zum Durchtesten)")
	var row := HBoxContainer.new(); vb.add_child(row)
	for sp in [1.0, 3.0, 6.0, 12.0]:
		var b := Button.new(); b.text = "%d×" % int(sp)
		b.add_theme_font_size_override("font_size", 10)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var spd: float = sp
		b.pressed.connect(func(): GameState.set_game_speed(spd))
		row.add_child(b)

func _build_kolonien(vb: VBoxContainer) -> void:
	_note(vb, "Aktive Kolonie: %s (%d von %d)" % [ColonySys.get_name_of(ColonySys.active_id), ColonySys.player_ids().find(ColonySys.active_id) + 1, ColonySys.player_count()])
	_btn(vb, "Neue Kolonie gründen (gratis, Siedler automatisch)", func():
		_call("dev_found_colony"); call_deferred("_refresh"))
	_btn(vb, "Zur nächsten Kolonie wechseln", func():
		_call("dev_cycle_colony"); call_deferred("_refresh"))
	_btn(vb, "Kolonien-Fenster öffnen", func():
		var p := get_node_or_null("../ColonyPanel")
		if p and p.has_method("open"): p.call("open"))
	_note(vb, "Nachbarn (Entdeckerkarten)")
	_btn(vb, "Alle Nachbarn aufdecken", func(): _call("dev_neighbors_reveal"))
	_btn(vb, "Ruf +30 bei entdeckten Nachbarn", func(): _call("dev_neighbors_rep", [30.0]))
	_btn(vb, "Neue Aufträge erzeugen", func(): _call("dev_neighbors_request"))
	_btn(vb, "HANDELSLINIE zum ersten Nachbarn bauen (1 Klick)", func(): _call("dev_neighbor_line"))
	_btn(vb, "Ersten Nachbarn annektieren (gratis)", func(): _call("dev_annex_first"); call_deferred("_refresh"))
	_btn(vb, "Nachbarn-Fenster öffnen", func():
		var p := get_node_or_null("../NeighborPanel")
		if p and p.has_method("open"): p.call("open"))
	_note(vb, "Das Rathaus-Gebiet begrenzt das Bauen; 'Alles gratis bauen' hebt nur die Kosten, nicht den Abstand zu anderen Rathäusern (20 Kacheln) auf.")

func _build_schiene(vb: VBoxContainer) -> void:
	_btn(vb, "TEST-LINIE bauen (komplett, 1 Klick)", func(): _call("dev_rail_test_line"))
	_note(vb, "Gründet bei Bedarf eine 2. Kolonie, baut zwei Bahnhöfe + Depot, ebnet eine Strecke ein, legt Gleise, erstellt eine Linie (Bretter ↔ Holz) und kauft einen Zug.")
	_btn(vb, "Zug kaufen (erstes Depot, erste Linie)", func(): _call("dev_buy_train"))
	_btn(vb, "Alle Züge 30 s anhalten", func(): _call("dev_halt_trains", [30.0]))
	_btn(vb, "Zum Zug teleportieren (Frettchenmodus)", func(): _call("dev_teleport_to_train"))
	_btn(vb, "In den Zug setzen (Lokführer, 1 Klick)", func(): _call("dev_ride_train"))
	_btn(vb, "Linien-Fenster öffnen", func():
		var p := get_node_or_null("../LinePanel")
		if p and p.has_method("open"): p.call("open"))
	_btn(vb, "Alle Züge entfernen", func(): _call("dev_remove_trains"))
	_btn(vb, "Alle Gleise entfernen", func(): _call("dev_remove_rails"))

func _build_hilfe(vb: VBoxContainer) -> void:
	for t in [["basic", "Tutorial: Grundlagen"], ["systems", "Tutorial: Systeme"], ["logistics", "Tutorial: Kolonien & Schiene"]]:
		var track: String = t[0]
		_btn(vb, str(t[1]), func():
			var tut := get_node_or_null("../Tutorial")
			if tut != null and tut.has_method("start"): tut.call("start", track))
	_btn(vb, "Tutorial-Fortschritt zurücksetzen", func():
		TutorialManager.reset_progress()
		_say("Tutorial-Fortschritt gelöscht (Grundlagen starten beim nächsten neuen Spiel wieder)"))
	vb.add_child(HSeparator.new())
	_btn(vb, "Dev Mode ausschalten", func(): DevMode.disable())
