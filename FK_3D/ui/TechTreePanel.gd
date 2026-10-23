## TechTreePanel.gd
## Feature (v11.12, Skilltree-Redesign Runde 2). Nutzer-Feedback zur ersten
## Runde (v11.10, horizontale Zeilen-pro-Epoche mit Tabs) war: zu statisch,
## soll wieder mehr wie das Referenzbild aussehen, EIN grosser Baum statt
## kleiner Epochen-Unterseiten, Epochen als räumliche GRENZEN statt Tabs,
## und alle 6 Themenbereiche in einem gemeinsamen Baum, der in verschiedene
## Richtungen abgeht.
##
## Umsetzung: RADIALES Layout. Alle 6 Themenbereiche (TechTreeSys.SECTION_ORDER)
## strahlen wie Speichen von einem gemeinsamen Mittelpunkt aus, je 60° versetzt
## (bei 6 Bereichen ergibt das einen vollen Kreis - "in verschiedene Richtungen
## abgehen"). Entlang jeder Speiche liegen die 10 Tiers dieses Bereichs vom
## Zentrum nach aussen. Epochen werden NICHT mehr als Tabs, sondern als
## konzentrische, unterschiedlich eingefärbte Ring-Zonen dargestellt (siehe
## TechTreeCanvas.gd) - Epoche 1 ist der innerste Ring, Epoche 4 der äusserste.
## Alle Epochen/Knoten sind gleichzeitig sichtbar (kein Epochen-Wechsel mehr
## nötig) - der Baum ist dafür deutlich grösser als vorher.
##
## v11.13 (Nutzer-Feedback): der Baum ist jetzt draggable (Links-Klick+Ziehen)
## und zoombar (Mausrad) statt nur über Scrollbalken verschiebbar - siehe
## _on_tree_viewport_input(). Ausserdem liegen die Knoten jetzt deutlich
## dichter beieinander (RADIUS_ORIGIN/RADIUS_PER_EPOCH verkleinert,
## Nutzerwunsch "Upgrades sollen dichter beieinander sein").
extends PanelContainer

var _selected_node_id: String = ""

# Feature (v11.13): Zoom-/Pan-Zustand bleibt über _refresh()-Aufrufe hinweg
# erhalten (Member-Variablen statt lokaler Variablen in _refresh()), damit
# der Nutzer beim Freischalten eines Knotens nicht wieder auf Start-Zoom/
# -Position zurückgesetzt wird.
var _tree_zoom: float = 1.0
var _tree_pan_offset: Vector2 = Vector2(-250, -480)
var _dragging: bool = false
var _canvas_ref: Control = null
const ZOOM_MIN := 0.4
const ZOOM_MAX := 1.8
const ZOOM_STEP := 0.12

const CELL_SIZE := 40.0
# Feature (v11.13): auf Nutzerwunsch "Upgrades sollen dichter beieinander
# sein" - Radien deutlich verkleinert (vorher ORIGIN=90/PER_EPOCH=210),
# Canvas entsprechend mitverkleinert.
const CANVAS_SIZE := Vector2(1400, 1400)
const RING_CENTER := Vector2(700, 700)
const RADIUS_ORIGIN := 55.0
const RADIUS_PER_EPOCH := 120.0
const PERP_JITTER := 9.0

const COL_LOCKED := Color(0.28, 0.28, 0.3)
const COL_LOCKED_BORDER := Color(0.42, 0.42, 0.45)
const COL_AVAILABLE := Color(0.34, 0.27, 0.08)
const COL_AVAILABLE_BORDER := Color(0.96, 0.78, 0.25)
const COL_UNLOCKED := Color(0.1, 0.28, 0.14)
const COL_UNLOCKED_BORDER := Color(0.45, 0.9, 0.5)
const COL_EDGE_ACTIVE := Color(0.85, 0.7, 0.3, 0.85)
const COL_EDGE_INACTIVE := Color(0.4, 0.4, 0.44, 0.6)

# Epoche 1 (innen) → Epoche 4 (aussen), bewusst gedeckte Farben, damit die
# Knoten-Zellen darauf gut lesbar bleiben.
const EPOCH_ZONE_COLORS := [
	Color(0.20, 0.16, 0.10, 0.55), # Epoche 1 - Steinzeit, warmer Braunton
	Color(0.11, 0.20, 0.14, 0.55), # Epoche 2 - grünlich
	Color(0.10, 0.16, 0.24, 0.55), # Epoche 3 - bläulich
	Color(0.20, 0.13, 0.24, 0.55), # Epoche 4 - violett/Moderne
]

# Undurchsichtige Varianten der Zonen-Farben, für gut lesbaren Text in der
# Epochen-Fortschrittszeile (die EPOCH_ZONE_COLORS oben sind bewusst
# halbtransparent, da sie als Flächenfüllung hinter den Knoten dienen).
const EPOCH_LABEL_COLORS := [
	Color(0.85, 0.65, 0.4),
	Color(0.5, 0.85, 0.6),
	Color(0.5, 0.7, 0.95),
	Color(0.8, 0.55, 0.95),
]

func _ready() -> void:
	hide()
	MenuManager.register(self)
	GameState.hud_update_requested.connect(func(): if visible: _refresh())

func open() -> void:
	show(); _refresh()

func _refresh() -> void:
	for c in get_children(): c.queue_free()

	var header_sb := StyleBoxFlat.new()
	header_sb.bg_color = Color(0.08, 0.08, 0.1, 0.97)
	header_sb.border_color = Color(0.7, 0.58, 0.22)
	header_sb.set_border_width_all(2)
	header_sb.set_corner_radius_all(8)
	header_sb.content_margin_left = 12; header_sb.content_margin_right = 12
	header_sb.content_margin_top = 8;   header_sb.content_margin_bottom = 8
	add_theme_stylebox_override("panel", header_sb)

	var outer := VBoxContainer.new(); outer.add_theme_constant_override("separation", 6); add_child(outer)

	# ── Kopfleiste ───────────────────────────────────────────────────────
	var hdr := HBoxContainer.new(); outer.add_child(hdr)
	var tl := Label.new()
	tl.text = "🔬 TECH TREE"
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.add_theme_font_size_override("font_size", 17)
	tl.add_theme_color_override("font_color", Color(0.93, 0.8, 0.4))
	hdr.add_child(tl)
	var pts_lbl := Label.new()
	pts_lbl.text = "🔬 %d Wissenspunkte" % int(ResourceSys.science)
	pts_lbl.add_theme_font_size_override("font_size", 13)
	pts_lbl.add_theme_color_override("font_color", Color(0.55, 1.0, 0.75))
	hdr.add_child(pts_lbl)
	var reset_btn := Button.new(); reset_btn.text = "🎯"; reset_btn.tooltip_text = "Ansicht zurücksetzen"
	reset_btn.custom_minimum_size = Vector2(28, 0)
	reset_btn.pressed.connect(func():
		_tree_zoom = 1.0; _tree_pan_offset = Vector2(-250, -480); _refresh()
	)
	hdr.add_child(reset_btn)
	var cb := Button.new(); cb.text = "X"; cb.custom_minimum_size = Vector2(28, 0)
	cb.pressed.connect(hide)
	hdr.add_child(cb)

	# ── Kompakte Epochen-Fortschrittsleiste (ersetzt die alten Tabs - die
	# Epochen selbst werden jetzt räumlich im Baum als Ringe dargestellt,
	# hier nur noch eine kurze Fortschritts-/Freischalt-Zeile) ────────────
	outer.add_child(_build_epoch_summary_row())
	var ctrl_hint := Label.new()
	ctrl_hint.text = "🖱️ Ziehen zum Verschieben · Mausrad zum Zoomen · 🎯 setzt die Ansicht zurück"
	ctrl_hint.add_theme_font_size_override("font_size", 9)
	ctrl_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	outer.add_child(ctrl_hint)
	outer.add_child(HSeparator.new())

	# ── Der eigentliche, grosse radiale Baum - draggable + zoombar (v11.13,
	# Nutzerwunsch: "im Menü rein/raus zoomen" + "Baum ist draggable") statt
	# eines simplen ScrollContainers mit Scrollbalken. Ein aussenliegendes
	# "Viewport"-Control schneidet den Inhalt ab (clip_contents) und fängt
	# per _gui_input() Mausrad (Zoom) + Links-Drag (Pan) ab; die eigentliche
	# TechTreeCanvas wird per position/scale bewegt statt gescrollt.
	var viewport := Control.new(); viewport.name = "TreeViewport"
	viewport.custom_minimum_size = Vector2(0, 420)
	viewport.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport.clip_contents = true
	viewport.mouse_filter = Control.MOUSE_FILTER_STOP
	outer.add_child(viewport)

	var canvas := TechTreeCanvas.new()
	canvas.custom_minimum_size = CANVAS_SIZE
	canvas.size = CANVAS_SIZE
	canvas.position = _tree_pan_offset
	canvas.scale = Vector2.ONE * _tree_zoom
	canvas.ring_center = RING_CENTER
	# Bug-Fix (v11.14): TechTreeCanvas ist ein Control mit dem Standard-
	# mouse_filter STOP - das hat bisher JEDEN Klick/Drag auf den (riesigen,
	# praktisch den ganzen sichtbaren Bereich abdeckenden) Canvas-Hintergrund
	# komplett verschluckt, BEVOR er den Viewport-Container erreichen konnte,
	# an dem der Drag-Handler hängt (siehe _on_tree_viewport_input() unten).
	# Ergebnis: Dragging tat scheinbar gar nichts. IGNORE macht den Canvas
	# selbst "durchlässig" für Maus-Events - seine Kind-Nodes (die Knoten-
	# Buttons) sind davon NICHT betroffen und bleiben für sich klickbar,
	# da jeder Button unabhängig an seiner eigenen Bildschirmposition
	# getroffen wird.
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(canvas)
	viewport.gui_input.connect(_on_tree_viewport_input.bind(canvas))
	_canvas_ref = canvas

	var epoch_rings: Array = []
	for k in range(4, 0, -1):
		epoch_rings.append({"radius": RADIUS_ORIGIN + float(k) * RADIUS_PER_EPOCH, "fill": EPOCH_ZONE_COLORS[k - 1]})
	canvas.epoch_rings = epoch_rings

	var edges: Array = []
	var section_count: int = TechTreeSys.SECTION_ORDER.size()
	for si in section_count:
		var sid: String = TechTreeSys.SECTION_ORDER[si]
		var sdata: Dictionary = TechTreeSys.SECTIONS.get(sid, {})
		var angle: float = -PI / 2.0 + float(si) * TAU / float(section_count)
		var dir: Vector2 = Vector2(cos(angle), sin(angle))
		var perp: Vector2 = Vector2(-dir.y, dir.x)

		# Knoten dieses Bereichs in Tier-Reihenfolge sammeln.
		var section_nodes: Array = []
		for tier in range(1, 11):
			var tid: String = "%s_%d" % [sid, tier]
			if TechTreeSys.NODES.has(tid): section_nodes.append(tid)
		if section_nodes.is_empty(): continue

		# Für gleichmässige Epochen-Ringe: Knoten nach Epoche gruppieren,
		# Position innerhalb der Epoche normiert (0..1) statt nach rohem
		# Tier-Index - siehe Klassenkommentar oben.
		var by_epoch: Dictionary = {}
		for tid2 in section_nodes:
			var e: int = int((TechTreeSys.NODES[tid2] as Dictionary).get("epoch", 1))
			if not by_epoch.has(e): by_epoch[e] = []
			(by_epoch[e] as Array).append(tid2)

		var prev_pos: Vector2 = RING_CENTER
		var prev_unlocked: bool = true
		for ni in section_nodes.size():
			var tid: String = section_nodes[ni]
			var e2: int = int((TechTreeSys.NODES[tid] as Dictionary).get("epoch", 1))
			var group: Array = by_epoch[e2]
			var idx_in_epoch: int = group.find(tid)
			var radius_units: float = float(e2 - 1) + (float(idx_in_epoch) + 0.5) / float(group.size())
			var radius_px: float = RADIUS_ORIGIN + radius_units * RADIUS_PER_EPOCH
			var jitter: float = PERP_JITTER if idx_in_epoch % 2 == 0 else -PERP_JITTER
			var pos: Vector2 = RING_CENTER + dir * radius_px + perp * jitter

			var is_unlocked: bool = TechTreeSys.is_node_unlocked(tid)
			edges.append({"from": prev_pos, "to": pos, "color": (COL_EDGE_ACTIVE if prev_unlocked else COL_EDGE_INACTIVE), "width": 2.5})
			canvas.add_child(_build_node_cell(tid, pos))
			prev_pos = pos; prev_unlocked = is_unlocked

		canvas.add_child(_build_section_label(sdata, dir))

	canvas.edges = edges
	canvas.queue_redraw()

	# ── Detail-Panel des zuletzt angeklickten Knotens (fest unten, nicht
	# Teil des scrollbaren Baums) ────────────────────────────────────────
	outer.add_child(HSeparator.new())
	if _selected_node_id != "" and TechTreeSys.NODES.has(_selected_node_id):
		outer.add_child(_build_detail_panel(_selected_node_id))
	else:
		var hint := Label.new()
		hint.text = "Klicke auf einen Knoten im Baum für Details."
		hint.add_theme_font_size_override("font_size", 11)
		hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		outer.add_child(hint)

## Feature (v11.13, robuster gemacht in v11.14): globaler Fallback für
## Drag-Bewegung und -Ende. viewport.gui_input() (siehe unten) liefert
## Maus-Events NUR, solange der Cursor über dem Viewport-Rechteck steht -
## bei einer schnellen Ziehbewegung verlässt der Cursor dieses Rechteck
## leicht (z.B. nach oben über die Kopfzeile), wodurch die Bewegung
## "hängen" blieb und ein Loslassen ausserhalb nie registriert wurde
## (️_dragging blieb auf true stehen). _input() bekommt dagegen JEDES
## Maus-Event, unabhängig von der Position, und übernimmt Bewegung/Ende.
func _input(event: InputEvent) -> void:
	if not visible or _canvas_ref == null: return
	if event is InputEventMouseMotion and _dragging:
		_tree_pan_offset += (event as InputEventMouseMotion).relative
		_canvas_ref.position = _tree_pan_offset
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_dragging = false

## Feature (v11.13): Mausrad = Zoom (rein/raus), Links-Klick = Drag-Start
## (die eigentliche Bewegung/das Loslassen übernimmt _input() oben, damit
## ein schnelles Ziehen über den Viewport-Rand hinaus nicht hängen bleibt).
## Wird NUR aufgerufen, wenn kein Knoten-Button das Event zuerst konsumiert
## hat (Buttons "schlucken" Klicks auf sich selbst, siehe Godot GUI-Input-
## Bubbling) - Klicks auf einen Knoten und Draggen im Leerraum stören sich
## dadurch nicht gegenseitig.
func _on_tree_viewport_input(event: InputEvent, canvas: Control) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_tree_zoom = clampf(_tree_zoom + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			canvas.scale = Vector2.ONE * _tree_zoom
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_tree_zoom = clampf(_tree_zoom - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			canvas.scale = Vector2.ONE * _tree_zoom
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_dragging = true

func _build_section_label(sdata: Dictionary, dir: Vector2) -> Control:
	var lbl := Label.new()
	lbl.text = "%s %s" % [str(sdata.get("icon", "")), str(sdata.get("name", "")).to_upper()]
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	# Label knapp ausserhalb des äussersten Knotens dieser Speiche platzieren.
	var label_radius: float = RADIUS_ORIGIN + 4.0 * RADIUS_PER_EPOCH + 26.0
	var pos: Vector2 = RING_CENTER + dir * label_radius
	lbl.position = pos - Vector2(60, 8)
	lbl.custom_minimum_size = Vector2(120, 16)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return lbl

func _build_node_cell(tid: String, pos: Vector2) -> Control:
	var nd: Dictionary = TechTreeSys.NODES.get(tid, {})
	var is_unlocked: bool = TechTreeSys.is_node_unlocked(tid)
	var node_epoch: int = int(nd.get("epoch", 1))
	var epoch_ok: bool = node_epoch <= TechTreeSys.get_epoch()
	var req: String = str(nd.get("requires_node", ""))
	var req_ok: bool = req == "" or TechTreeSys.is_node_unlocked(req)
	var can_unlock: bool = TechTreeSys.can_unlock_node(tid)

	var btn := Button.new()
	btn.position = pos - Vector2(CELL_SIZE, CELL_SIZE) * 0.5
	btn.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
	btn.size = Vector2(CELL_SIZE, CELL_SIZE)
	btn.flat = true
	btn.tooltip_text = "%s\n%s\nKosten: 🔬%d" % [str(nd.get("name", tid)), str(nd.get("desc", "")), int(nd.get("cost", 0.0))]

	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(23)
	sb.set_border_width_all(2 if not is_unlocked else 3)
	if is_unlocked:
		sb.bg_color = COL_UNLOCKED; sb.border_color = COL_UNLOCKED_BORDER
	elif can_unlock:
		sb.bg_color = COL_AVAILABLE; sb.border_color = COL_AVAILABLE_BORDER
	else:
		sb.bg_color = COL_LOCKED; sb.border_color = COL_LOCKED_BORDER
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("disabled", sb)

	var content := CenterContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Feature (v11.14, Nutzerwunsch "jeder Skillpunkt soll ein eigenes Icon
	# haben"): das themen-passende Icon aus TechTreeSys.NODES[tid]["icon"]
	# (60 individuelle Icons, siehe TechTree.gd) wird jetzt IMMER gezeigt,
	# statt bei freigeschalteten/gesperrten Knoten durch ✅/🔒 ersetzt zu
	# werden. Status wird stattdessen durch Abdunkeln (gesperrt) bzw. volle
	# Deckkraft (verfügbar/freigeschaltet) signalisiert - der Rahmen
	# (COL_LOCKED/COL_AVAILABLE/COL_UNLOCKED, siehe oben) bleibt zusätzlich
	# die Haupt-Statusfarbe.
	var lbl := Label.new()
	lbl.text = str(nd.get("icon", "❔"))
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not is_unlocked and not can_unlock:
		lbl.modulate = Color(1.0, 1.0, 1.0, 0.35)
	content.add_child(lbl)
	btn.add_child(content)

	# Kleines Status-Badge oben rechts in der Zelle - ergänzt das Icon,
	# statt es zu ersetzen (✅ freigeschaltet / 🔒 gesperrt, nichts wenn
	# gerade erforschbar, da die goldene Rahmenfarbe das schon anzeigt).
	if is_unlocked or (not can_unlock and not epoch_ok) or (not can_unlock and not req_ok):
		var badge := Label.new()
		badge.text = "✅" if is_unlocked else "🔒"
		badge.add_theme_font_size_override("font_size", 11)
		badge.position = Vector2(CELL_SIZE - 15, -4)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(badge)

	var t: String = tid
	btn.pressed.connect(func():
		_selected_node_id = t
		if is_unlocked:
			_refresh(); return
		if can_unlock:
			TechTreeSys.unlock_node(t)
		else:
			# Bug-Fix (v14.2, Nutzerwunsch "einfach auf den Knoten tippen, und
			# wenn die Punkte nicht reichen eine Info"): ein Tap auf einen
			# nicht erforschbaren Knoten hat bisher NUR das Detailpanel unten
			# aktualisiert (musste man extra runterschauen) - jetzt gibt es
			# zusätzlich sofort eine klare Info-Meldung mit dem konkreten Grund.
			if node_epoch > TechTreeSys.get_epoch():
				GameState.notify("🔒 '%s' braucht erst Epoche %d." % [str(nd.get("name", tid)), node_epoch], Color(0.75, 0.35, 0.3))
			elif req != "" and not TechTreeSys.is_node_unlocked(req):
				var req_nd: Dictionary = TechTreeSys.NODES.get(req, {})
				GameState.notify("🔒 '%s' braucht zuerst: %s." % [str(nd.get("name", tid)), str(req_nd.get("name", req))], Color(0.75, 0.35, 0.3))
			else:
				var cost: int = int(nd.get("cost", 0.0))
				GameState.notify("🔬 Nicht genug Wissenspunkte für '%s' (brauchst %d, hast %d)." % [str(nd.get("name", tid)), cost, int(ResourceSys.science)], Color(0.75, 0.5, 0.2))
		_refresh()
	)
	return btn

func _build_detail_panel(tid: String) -> Control:
	var nd: Dictionary = TechTreeSys.NODES.get(tid, {})
	var is_unlocked: bool = TechTreeSys.is_node_unlocked(tid)
	var can_unlock: bool = TechTreeSys.can_unlock_node(tid)
	var node_epoch: int = int(nd.get("epoch", 1))
	var epoch_ok: bool = node_epoch <= TechTreeSys.get_epoch()
	var req: String = str(nd.get("requires_node", ""))
	var req_ok: bool = req == "" or TechTreeSys.is_node_unlocked(req)

	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 3)
	var name_lbl := Label.new()
	name_lbl.text = "Epoche %d, Stufe %d: %s" % [node_epoch, int(nd.get("tier", 0)), str(nd.get("name", tid))]
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", COL_UNLOCKED_BORDER if is_unlocked else COL_AVAILABLE_BORDER)
	vb.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = str(nd.get("desc", ""))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	vb.add_child(desc_lbl)

	if is_unlocked:
		var ok_lbl := Label.new(); ok_lbl.text = "✅ Bereits erforscht."
		ok_lbl.add_theme_font_size_override("font_size", 10)
		ok_lbl.add_theme_color_override("font_color", COL_UNLOCKED_BORDER)
		vb.add_child(ok_lbl)
	elif not epoch_ok:
		var lock_lbl := Label.new(); lock_lbl.text = "🔒 Benötigt Epoche %d." % node_epoch
		lock_lbl.add_theme_font_size_override("font_size", 10)
		lock_lbl.add_theme_color_override("font_color", Color(0.7, 0.35, 0.3))
		vb.add_child(lock_lbl)
	elif not req_ok:
		var req_nd: Dictionary = TechTreeSys.NODES.get(req, {})
		var lock_lbl2 := Label.new(); lock_lbl2.text = "🔒 Benötigt zuerst: %s" % str(req_nd.get("name", req))
		lock_lbl2.add_theme_font_size_override("font_size", 10)
		lock_lbl2.add_theme_color_override("font_color", Color(0.7, 0.35, 0.3))
		vb.add_child(lock_lbl2)
	else:
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8)
		var btn := Button.new()
		btn.text = "Erforschen (🔬%d)" % int(nd.get("cost", 0.0))
		btn.disabled = not can_unlock
		var t: String = tid
		btn.pressed.connect(func(): TechTreeSys.unlock_node(t); _refresh())
		row.add_child(btn)
		vb.add_child(row)
	return vb

func _build_epoch_summary_row() -> Control:
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 14)
	var cur: int = TechTreeSys.get_epoch()

	for e_num in range(1, 5):
		var eid: String = "EPOCH_%d" % e_num
		var ed: Dictionary = TechTreeSys.EPOCHS.get(eid, {})
		var is_unlocked_epoch: bool = eid in TechTreeSys.unlocked_epochs
		var done: int = TechTreeSys.get_epoch_unlocked_count(e_num)
		var total: int = TechTreeSys.get_node_ids_for_epoch(e_num).size()
		var lbl := Label.new()
		var icon: String = "✅" if is_unlocked_epoch else "🔒"
		lbl.text = "%s E%d %s (%d/%d)" % [icon, e_num, str(ed.get("name", eid)), done, total]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", EPOCH_LABEL_COLORS[e_num - 1] if is_unlocked_epoch else Color(0.5, 0.5, 0.5))
		row.add_child(lbl)

	var next_id: String = TechTreeSys.get_next_epoch_id()
	if next_id != "":
		var ed2: Dictionary = TechTreeSys.EPOCHS.get(next_id, {})
		var req_met: bool = TechTreeSys.epoch_requirement_met(next_id)
		var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		if req_met:
			var btn := Button.new()
			btn.text = "Epoche freischalten: %s (🔬%d)" % [str(ed2.get("name", next_id)), int(ed2.get("cost", 0.0))]
			btn.disabled = not TechTreeSys.can_unlock_epoch(next_id)
			btn.pressed.connect(func(): TechTreeSys.unlock_epoch(next_id); _refresh())
			row.add_child(btn)
		else:
			var req_lbl := Label.new()
			var cur_done: int = TechTreeSys.get_epoch_unlocked_count(cur)
			var required: int = TechTreeSys.get_epoch_unlock_requirement(cur)
			req_lbl.text = "Noch %d Knoten in Epoche %d für Aufstieg" % [maxi(0, required - cur_done), cur]
			req_lbl.add_theme_font_size_override("font_size", 10)
			req_lbl.add_theme_color_override("font_color", Color(0.85, 0.5, 0.3))
			row.add_child(req_lbl)
	return row
