## TouchOverlay.gd – Virtuelles Gamepad für Touch-Steuerung.
## Deckt alle Spielaktionen ab, die sonst per Tastatur/Maus ausgelöst werden:
##   - Kamera-Zoom rein/raus
##   - Frettchenmodus starten/verlassen  (= KEY_F)
##   - Interagieren im FP-Modus          (= KEY_E)
##   - Pause/Weiter                       (= Leertaste)
##   - Spielgeschwindigkeit 1x/2x/3x
##   - Laufbefehl-Modus (Tap-to-Walk)    (ersetzt Mittelklick)
##   - Baumenü öffnen/schließen
##   - Kamera-Bewegung (WASD) – 4 Pfeile
##   - Alle Panel-Buttons (Tech, Achievements, Expedition, Gräberfeld, Bezirke)
##   - Im Frettchenmodus: Sprung (Leertaste als Sprung-Button)
##
## Layout: Buttons links unten (Kamera-Steuerung) + rechts unten (Aktionen).
## Wird nur angezeigt wenn TouchControlsSettings.enabled == true UND
## GameState is_playing() (oder PAUSED für Pause-Button).
## Wichtig: alle Buttons sind in einem CanvasLayer ÜBER dem Rest der UI,
## damit sie immer klickbar sind.
extends Control

# Referenz auf GameController (wird nach dem Erzeugen von Main.gd gesetzt)
var _game_ctrl: Node = null

# Laufbefehl-Modus: nächster Tap auf die 3D-Welt wird als Walk-Ziel interpretiert
var _walk_mode: bool = false

# Buttons, die nur im FP-Modus sichtbar sind
var _fp_only_group: Array[Button] = []
# Buttons, die nur im Iso-Modus sichtbar sind
var _iso_only_group: Array[Button] = []
# Walk-Mode-Button-Referenz (für Highlight-Zustand)
var _walk_btn: Button = null
# FP-Toggle-Button für Icon-Update
var _fp_btn: Button = null
# Pause-Button für Icon-Update
var _pause_btn: Button = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	TouchControlsSettings.changed.connect(_on_setting_changed)
	GameState.state_changed.connect(_on_state_changed)
	GameState.fp_mode_changed.connect(_on_fp_mode_changed)
	_update_visibility()

# ── Hilfsfunktionen ──────────────────────────────────────────────────────────

## Erzeugt einen Touch-Button mit rundem Hintergrund.
## sz  = Größe in Pixel (quadratisch)
## col = Hintergrundfarbe
func _touch_btn(label: String, sz: int = 56, col: Color = Color(0.15, 0.18, 0.25, 0.82)) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(sz, sz)
	b.add_theme_font_size_override("font_size", 20)
	# Halbtransparenter dunkler Hintergrund
	var sty := StyleBoxFlat.new()
	sty.bg_color = col
	sty.corner_radius_top_left     = sz / 2
	sty.corner_radius_top_right    = sz / 2
	sty.corner_radius_bottom_left  = sz / 2
	sty.corner_radius_bottom_right = sz / 2
	sty.border_color = Color(0.5, 0.55, 0.65, 0.7)
	sty.border_width_top = 1; sty.border_width_bottom = 1
	sty.border_width_left = 1; sty.border_width_right = 1
	b.add_theme_stylebox_override("normal", sty)
	var sty_h := sty.duplicate() as StyleBoxFlat
	sty_h.bg_color = Color(sty.bg_color.r + 0.12, sty.bg_color.g + 0.12, sty.bg_color.b + 0.12, 0.95)
	b.add_theme_stylebox_override("hover", sty_h)
	var sty_p := sty.duplicate() as StyleBoxFlat
	sty_p.bg_color = Color(0.35, 0.50, 0.75, 0.95)
	b.add_theme_stylebox_override("pressed", sty_p)
	return b

## Erzeugt ein positioniertes Container-Panel (kein Rahmen, nur Anker).
func _panel_at(anchor_preset: int, ox: float, oy: float) -> Control:
	var c := Control.new()
	c.set_anchors_preset(anchor_preset)
	c.offset_left  = ox
	c.offset_top   = oy
	c.offset_right = 0
	c.offset_bottom = 0
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c

# ── UI-Aufbau ─────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_build_camera_dpad()
	_build_action_buttons()
	_build_fp_buttons()

## Links unten: Kamera-Steuerung (D-Pad für WASD-Scroll) + Zoom
func _build_camera_dpad() -> void:
	var base := Control.new()
	base.name = "DPadBase"
	base.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	base.offset_left  =  12
	base.offset_bottom = -12
	base.offset_right  = 220
	base.offset_top    = -220
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)

	# D-Pad: Hoch, Runter, Links, Rechts – im Iso-Modus als Kamera-WASD
	var up_b := _touch_btn("▲", 52)
	up_b.set_anchors_preset(Control.PRESET_CENTER_TOP)
	up_b.offset_left = -26; up_b.offset_right = 26; up_b.offset_top = 0; up_b.offset_bottom = 52
	up_b.pressed.connect(func(): _send_key(KEY_W, true))
	base.add_child(up_b)

	var down_b := _touch_btn("▼", 52)
	down_b.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	down_b.offset_left = -26; down_b.offset_right = 26; down_b.offset_top = -52; down_b.offset_bottom = 0
	down_b.pressed.connect(func(): _send_key(KEY_S, true))
	base.add_child(down_b)

	var left_b := _touch_btn("◄", 52)
	left_b.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	left_b.offset_left = 0; left_b.offset_right = 52; left_b.offset_top = -26; left_b.offset_bottom = 26
	left_b.pressed.connect(func(): _send_key(KEY_A, true))
	base.add_child(left_b)

	var right_b := _touch_btn("►", 52)
	right_b.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	right_b.offset_left = -52; right_b.offset_right = 0; right_b.offset_top = -26; right_b.offset_bottom = 26
	right_b.pressed.connect(func(): _send_key(KEY_D, true))
	base.add_child(right_b)

	_iso_only_group.append(up_b)
	_iso_only_group.append(down_b)
	_iso_only_group.append(left_b)
	_iso_only_group.append(right_b)

	# Zoom rein/raus – rechts vom D-Pad
	var zoom_col := VBoxContainer.new()
	zoom_col.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	zoom_col.offset_left = 4; zoom_col.offset_right = 64; zoom_col.offset_top = -52; zoom_col.offset_bottom = 52
	zoom_col.add_theme_constant_override("separation", 6)
	base.add_child(zoom_col)

	var zi := _touch_btn("🔍+", 52, Color(0.10, 0.22, 0.16, 0.85))
	zi.pressed.connect(_zoom_in)
	zoom_col.add_child(zi)

	var zo := _touch_btn("🔍-", 52, Color(0.22, 0.12, 0.10, 0.85))
	zo.pressed.connect(_zoom_out)
	zoom_col.add_child(zo)

	_iso_only_group.append(zi)
	_iso_only_group.append(zo)

## Rechts unten: Aktions-Buttons (Hauptspielfunktionen)
func _build_action_buttons() -> void:
	var base := Control.new()
	base.name = "ActionBase"
	base.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	base.offset_right  = -12
	base.offset_bottom = -12
	base.offset_left   = -290
	base.offset_top    = -230
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)

	# Obere Reihe: Panel-Buttons
	var top_row := HBoxContainer.new()
	top_row.name = "TopRow"
	top_row.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top_row.offset_right = 0; top_row.offset_top = 0
	top_row.offset_left = -290; top_row.offset_bottom = 52
	top_row.add_theme_constant_override("separation", 6)
	base.add_child(top_row)

	var panel_buttons: Array = [
		["🔬", "TechTree",       func(): _open_panel("TechTreePanel")],
		["🏆", "Achievements",   func(): _open_panel("AchievementPanel")],
		["🗺️", "Expeditionen",   func(): _open_panel("ExpeditionPanel")],
		["🪦", "Gräberfeld",     func(): _open_panel("GraveyardPanel")],
		["🏘️", "Bezirke",        func(): _open_panel("DistrictPanel")],
	]
	for pd in panel_buttons:
		var b := _touch_btn(pd[0], 48, Color(0.14, 0.16, 0.24, 0.82))
		b.tooltip_text = pd[1] as String
		b.pressed.connect(pd[2])
		top_row.add_child(b)
		_iso_only_group.append(b)

	# Mittlere Reihe: Spielsteuerung
	var mid_row := HBoxContainer.new()
	mid_row.name = "MidRow"
	mid_row.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	mid_row.offset_right = 0; mid_row.offset_left = -290
	mid_row.offset_top = -26; mid_row.offset_bottom = 26
	mid_row.add_theme_constant_override("separation", 6)
	base.add_child(mid_row)

	# Pause-Button
	_pause_btn = _touch_btn("⏸", 52, Color(0.20, 0.20, 0.12, 0.85))
	_pause_btn.pressed.connect(func(): GameState.toggle_pause())
	mid_row.add_child(_pause_btn)

	# Geschwindigkeit 1x/2x/3x
	for spd: Array in [[" 1×", 1.0], [" 2×", 2.0], [" 3×", 3.0]]:
		var sb := _touch_btn(spd[0] as String, 52, Color(0.10, 0.15, 0.25, 0.82))
		var speed: float = spd[1] as float
		sb.pressed.connect(func(): GameState.set_game_speed(speed))
		mid_row.add_child(sb)

	# FP-Toggle: Frettchenmodus starten/verlassen
	_fp_btn = _touch_btn("🐾", 52, Color(0.18, 0.24, 0.14, 0.85))
	_fp_btn.tooltip_text = "Frettchenmodus (F)"
	_fp_btn.pressed.connect(func(): _send_key(KEY_F, true))
	mid_row.add_child(_fp_btn)

	# Untere Reihe: Laufbefehl + Baumenü
	var bot_row := HBoxContainer.new()
	bot_row.name = "BotRow"
	bot_row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bot_row.offset_right = 0; bot_row.offset_bottom = 0
	bot_row.offset_left = -290; bot_row.offset_top = -52
	bot_row.add_theme_constant_override("separation", 6)
	base.add_child(bot_row)

	# Laufbefehl-Modus Toggle (ersetzt Mittelklick)
	_walk_btn = _touch_btn("🚶", 52, Color(0.16, 0.22, 0.16, 0.85))
	_walk_btn.tooltip_text = "Laufbefehl-Modus"
	_walk_btn.pressed.connect(_toggle_walk_mode)
	bot_row.add_child(_walk_btn)
	_iso_only_group.append(_walk_btn)

	# Baumenü öffnen/schließen
	var build_btn := _touch_btn("🏗️", 52, Color(0.22, 0.16, 0.10, 0.85))
	build_btn.tooltip_text = "Baumenü"
	build_btn.pressed.connect(_toggle_build_menu)
	bot_row.add_child(build_btn)
	_iso_only_group.append(build_btn)

	# Abbruch/ESC
	var esc_btn := _touch_btn("✖", 52, Color(0.25, 0.12, 0.10, 0.85))
	esc_btn.tooltip_text = "Abbrechen / ESC"
	esc_btn.pressed.connect(func(): _send_key(KEY_ESCAPE, true))
	bot_row.add_child(esc_btn)

## Rechts unten (andere Reihe): Buttons NUR für den First-Person-Modus
func _build_fp_buttons() -> void:
	var base := Control.new()
	base.name = "FPActionBase"
	base.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	base.offset_right  = -12
	base.offset_bottom = -290  # über den normalen Aktions-Buttons
	base.offset_left   = -132
	base.offset_top    = -132
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base.visible = false
	add_child(base)

	# Interagieren (E)
	var e_btn := _touch_btn("⚡\nE", 56, Color(0.22, 0.20, 0.08, 0.85))
	e_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	e_btn.offset_left = 0; e_btn.offset_right = 56; e_btn.offset_top = 0; e_btn.offset_bottom = 56
	e_btn.tooltip_text = "Interagieren (E)"
	e_btn.pressed.connect(func(): _send_key(KEY_E, true))
	base.add_child(e_btn)
	_fp_only_group.append(e_btn)

	# Sprung (Leertaste)
	var jump_btn := _touch_btn("⬆\nSPR", 56, Color(0.10, 0.18, 0.28, 0.85))
	jump_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	jump_btn.offset_left = -56; jump_btn.offset_right = 0; jump_btn.offset_top = 0; jump_btn.offset_bottom = 56
	jump_btn.tooltip_text = "Springen"
	jump_btn.pressed.connect(func(): _send_key(KEY_SPACE, true))
	base.add_child(jump_btn)
	_fp_only_group.append(jump_btn)

	# FP-Modus verlassen (ESC)
	var leave_btn := _touch_btn("🔙\nISO", 56, Color(0.20, 0.10, 0.14, 0.85))
	leave_btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	leave_btn.offset_left = 0; leave_btn.offset_right = 56; leave_btn.offset_top = -56; leave_btn.offset_bottom = 0
	leave_btn.tooltip_text = "Zurück zur Kolonie-Ansicht"
	leave_btn.pressed.connect(func(): _send_key(KEY_ESCAPE, true))
	base.add_child(leave_btn)
	_fp_only_group.append(leave_btn)

	# Kein Minispiel abbrechen – der ESC-Button oben deckt das ab.
	# Aber: im FP-Modus braucht man die FP-Buttons-Base sichtbar.
	for btn in _fp_only_group:
		btn.visible = true
	# Die Base selbst steuert die Sichtbarkeit der FP-Gruppe.
	# Verstecke nochmal komplett; _on_fp_mode_changed schaltet sie.
	base.visible = false

# ── Aktionen ─────────────────────────────────────────────────────────────────

func _zoom_in() -> void:
	if _game_ctrl == null or not _game_ctrl.has_method("_touch_zoom_in"):
		# Fallback: simuliere Mausrad-rein
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_WHEEL_UP
		ev.pressed = true
		Input.parse_input_event(ev)
		return
	_game_ctrl.call("_touch_zoom_in")

func _zoom_out() -> void:
	if _game_ctrl == null or not _game_ctrl.has_method("_touch_zoom_out"):
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_WHEEL_DOWN
		ev.pressed = true
		Input.parse_input_event(ev)
		return
	_game_ctrl.call("_touch_zoom_out")

func _toggle_walk_mode() -> void:
	_walk_mode = not _walk_mode
	_update_walk_btn()

func _update_walk_btn() -> void:
	if _walk_btn == null:
		return
	if _walk_mode:
		var sty := StyleBoxFlat.new()
		sty.bg_color = Color(0.20, 0.55, 0.25, 0.92)
		sty.corner_radius_top_left = 28; sty.corner_radius_top_right = 28
		sty.corner_radius_bottom_left = 28; sty.corner_radius_bottom_right = 28
		sty.border_color = Color(0.4, 0.9, 0.45, 0.9)
		sty.border_width_top = 2; sty.border_width_bottom = 2
		sty.border_width_left = 2; sty.border_width_right = 2
		_walk_btn.add_theme_stylebox_override("normal", sty)
		_walk_btn.text = "🚶✓"
	else:
		# Zurücksetzen auf Standard-Stil
		var b_tmp := _touch_btn("🚶", 52, Color(0.16, 0.22, 0.16, 0.85))
		_walk_btn.add_theme_stylebox_override("normal", b_tmp.get_theme_stylebox("normal"))
		b_tmp.queue_free()
		_walk_btn.text = "🚶"

## Verarbeitet einen Tap auf die 3D-Welt: wenn _walk_mode aktiv, wird der
## Tap als Laufbefehl-Ziel interpretiert (anstelle von Mittelklick).
## Wird von GameController._handle_touch_walk() aufgerufen.
func consume_walk_tap(screen_pos: Vector2) -> bool:
	if not _walk_mode:
		return false
	if _game_ctrl != null and _game_ctrl.has_method("_start_player_walk_to_screen"):
		_game_ctrl.call("_start_player_walk_to_screen", screen_pos)
	# Modus nach einem Tap automatisch beenden (einmaliger Befehl)
	_walk_mode = false
	_update_walk_btn()
	return true

func _open_panel(panel_name: String) -> void:
	var ui_root := get_parent()
	if ui_root == null:
		return
	var p := ui_root.get_node_or_null(panel_name)
	if p != null and p.has_method("open"):
		p.open()

func _toggle_build_menu() -> void:
	var ui_root := get_parent()
	if ui_root == null:
		return
	var bm := ui_root.get_node_or_null("BuildMenu")
	if bm != null:
		bm.visible = not bm.visible

## Simuliert einen Tastendruck über Godots Input-System.
func _send_key(keycode: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = pressed
	Input.parse_input_event(ev)

# ── Sichtbarkeits-Steuerung ──────────────────────────────────────────────────

func _update_visibility() -> void:
	var playing: bool = GameState.is_playing() or GameState.state == GameState.State.PAUSED
	visible = TouchControlsSettings.enabled and playing

func _on_setting_changed(_enabled: bool) -> void:
	_update_visibility()

func _on_state_changed(_state: GameState.State) -> void:
	_update_visibility()
	# Pause-Button-Icon anpassen
	if _pause_btn != null:
		if GameState.state == GameState.State.PAUSED:
			_pause_btn.text = "▶"
		else:
			_pause_btn.text = "⏸"

func _on_fp_mode_changed(is_fp: bool) -> void:
	# ISO-Buttons verstecken im FP-Modus
	for b in _iso_only_group:
		b.visible = not is_fp
	# FP-Base sichtbar/unsichtbar
	var fp_base := get_node_or_null("FPActionBase")
	if fp_base != null:
		fp_base.visible = is_fp
	# Walk-Modus zurücksetzen wenn man in FP wechselt
	if is_fp and _walk_mode:
		_walk_mode = false
		_update_walk_btn()
	# FP-Buttons innerhalb der Base sichtbar lassen
	for b in _fp_only_group:
		b.visible = true
	# FP-Button-Icon
	if _fp_btn != null:
		_fp_btn.text = "🐾" if not is_fp else "🔙"
