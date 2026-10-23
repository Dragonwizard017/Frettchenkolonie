## MinigameOverlay.gd
## Feature (v11.2, First-Person-Modus): generisches Overlay-Panel, das genau
## EINES der vier Minispiel-Typen (Timing-Leiste, Mash, Reaktions-Klick,
## Balance) anzeigt und steuert. Wird komplett dynamisch in _ready() gebaut
## (gleiches Muster wie BuildingInfo.gd/ExpeditionPanel.gd), Main.gd hängt
## nur einen leeren Control mit diesem Script in den UI-Baum.
##
## GameController ruft start_wood()/start_stone()/start_berries()/
## start_iron()/start_water() auf, sobald der Spieler im First-Person-Modus
## eine passende Ressourcenülle per "interact" (E) anspricht. Bei Abschluss
## (Erfolg ODER Abbruch per ESC) feuert minigame_finished(resource, reward) -
## GameController kümmert sich dort um Lagerabzug + ResourceSys.add().
extends Control

signal minigame_finished(resource_type: String, reward: float)

const STAGE_SIZE: Vector2 = Vector2(360.0, 150.0)
const BERRY_POOL_SIZE: int = 4

var _bg: ColorRect = null
var _panel: PanelContainer = null
var _stage_bg_sb: StyleBoxFlat = null
var _title_lbl: Label = null
var _instr_lbl: Label = null
var _progress_lbl: Label = null
var _stage: Control = null
var _stage_icon_lbl: Label = null

# Timing-Leiste (Holz/Erz)
var _tb_track: ColorRect = null
var _tb_zone: ColorRect = null
var _tb_marker: ColorRect = null

# Mash (Bauen)
var _mash_track: ColorRect = null
var _mash_fill: ColorRect = null

# Steinbrocken zerschlagen (Stein) - Feature (v14.0)
var _rock_labels: Array = []       # Array[Label], eines pro Brocken
var _rock_progress_track: ColorRect = null
var _rock_progress_fill: ColorRect = null

# Reaktions-Klick (Beeren)
var _berry_buttons: Array = []   # Array[Button], fester Pool

# Balance (Wasser)
var _bal_track: ColorRect = null
var _bal_knob: ColorRect = null
var _bal_center_marker: ColorRect = null

var _current = null            # TimingBarMinigame | MashMinigame | ReactionClickMinigame | BalanceMinigame
var _current_kind: String = "" # "TIMING" | "MASH" | "REACTION" | "BALANCE"
var _resource_type: String = ""

func _ready() -> void:
	hide()
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Feature (v13.6, Minigame-Redesign): dunklerer, leicht wärmerer
	# Abdunkel-Hintergrund statt reinem Schwarz - wirkt weniger hart.
	_bg = ColorRect.new(); _bg.color = Color(0.04, 0.05, 0.07, 0.72)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)

	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(cc)

	_panel = PanelContainer.new(); _panel.custom_minimum_size = Vector2(440.0, 0.0)
	# Feature (v13.6, Minigame-Redesign): abgerundetes Panel mit sanftem
	# Rand statt Standard-Godot-Panel - passt zum restlichen UI-Stil
	# (siehe TutorialManager.gd, PauseMenu.gd).
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.09, 0.10, 0.13, 0.97)
	panel_sb.set_corner_radius_all(12)
	panel_sb.content_margin_left = 22; panel_sb.content_margin_right = 22
	panel_sb.content_margin_top = 18;  panel_sb.content_margin_bottom = 18
	panel_sb.border_width_top = 2; panel_sb.border_width_bottom = 2
	panel_sb.border_width_left = 2; panel_sb.border_width_right = 2
	panel_sb.border_color = Color(0.96, 0.69, 0.1, 0.85)
	_panel.add_theme_stylebox_override("panel", panel_sb)
	cc.add_child(_panel)
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 12)
	_panel.add_child(vb)

	_title_lbl = Label.new(); _title_lbl.add_theme_font_size_override("font_size", 24)
	_title_lbl.add_theme_color_override("font_color", Color(0.98, 0.85, 0.4))
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title_lbl)

	_instr_lbl = Label.new(); _instr_lbl.add_theme_font_size_override("font_size", 13)
	_instr_lbl.add_theme_color_override("font_color", Color(0.78, 0.78, 0.85))
	_instr_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_instr_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(_instr_lbl)

	# Feature (v13.6, Minigame-Redesign): Bühnen-Hintergrund als eigenes
	# gerundetes Panel, thematisch pro Ressource eingefärbt (siehe
	# _apply_stage_theme()) - macht jedes der 5 Minispiele optisch
	# unterscheidbar statt eines neutralen grauen Kastens.
	var stage_wrap := PanelContainer.new()
	_stage_bg_sb = StyleBoxFlat.new()
	_stage_bg_sb.bg_color = Color(0.14, 0.16, 0.19)
	_stage_bg_sb.set_corner_radius_all(8)
	_stage_bg_sb.content_margin_left = 8; _stage_bg_sb.content_margin_right = 8
	_stage_bg_sb.content_margin_top = 8;  _stage_bg_sb.content_margin_bottom = 8
	stage_wrap.add_theme_stylebox_override("panel", _stage_bg_sb)
	vb.add_child(stage_wrap)

	_stage = Control.new(); _stage.custom_minimum_size = STAGE_SIZE
	stage_wrap.add_child(_stage)
	# Feature (v13.7, "Minispiele sollen schöner sein"): grosses, dezent
	# transparentes Ressourcen-Icon im Hintergrund der Bühne - rein
	# dekorativ (mouse_filter IGNORE, liegt hinter den eigentlichen
	# Spielelementen), macht die Bühne aber weniger leer/technisch.
	_stage_icon_lbl = Label.new()
	_stage_icon_lbl.add_theme_font_size_override("font_size", 96)
	_stage_icon_lbl.modulate = Color(1.0, 1.0, 1.0, 0.16)
	_stage_icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_icon_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage_icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stage.add_child(_stage_icon_lbl)
	_build_timing_visuals()
	_build_mash_visuals()
	_build_rock_visuals()
	_build_reaction_visuals()
	_build_balance_visuals()

	_progress_lbl = Label.new(); _progress_lbl.add_theme_font_size_override("font_size", 14)
	_progress_lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	_progress_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_progress_lbl)

	var cancel_btn := Button.new(); cancel_btn.text = "Abbrechen (ESC)"
	cancel_btn.pressed.connect(_on_cancel)
	vb.add_child(cancel_btn)

## Feature (v13.6, Minigame-Redesign): färbt Panel-Rand und Bühnen-
## Hintergrund passend zur gerade gesammelten Ressource ein - kleines,
## billiges visuelles Detail (nur 2 StyleBox-Farbwerte), das die 5
## Minispiele auf den ersten Blick unterscheidbar macht.
const RESOURCE_THEME_COLOR: Dictionary = {
	"WOOD":    Color(0.55, 0.38, 0.20),
	"IRON":    Color(0.55, 0.56, 0.60),
	"STONE":   Color(0.50, 0.50, 0.52),
	"BERRIES": Color(0.55, 0.20, 0.45),
	"WATER":   Color(0.20, 0.45, 0.65),
	"BUILD":   Color(0.75, 0.55, 0.15),
}

const STAGE_ICON: Dictionary = {
	"WOOD": "🪓", "STONE": "🪨", "BERRIES": "🫐", "IRON": "⛏️", "WATER": "💧", "BUILD": "🔨",
}

func _apply_stage_theme(resource: String) -> void:
	var c: Color = RESOURCE_THEME_COLOR.get(resource, Color(0.5, 0.5, 0.5))
	if _stage_bg_sb:
		_stage_bg_sb.bg_color = Color(c.r * 0.35, c.g * 0.35, c.b * 0.35, 1.0)
	var panel_sb: StyleBoxFlat = _panel.get_theme_stylebox("panel") as StyleBoxFlat
	if panel_sb:
		panel_sb.border_color = c.lightened(0.25)
	if _stage_icon_lbl:
		_stage_icon_lbl.text = str(STAGE_ICON.get(resource, ""))



# ── Visuals: Timing-Leiste ───────────────────────────────────────────────────
func _build_timing_visuals() -> void:
	_tb_track = ColorRect.new(); _tb_track.color = Color(0.15, 0.15, 0.18)
	_tb_track.position = Vector2(0.0, 60.0); _tb_track.size = Vector2(STAGE_SIZE.x, 26.0)
	_stage.add_child(_tb_track)
	_tb_zone = ColorRect.new(); _tb_zone.color = Color(0.30, 0.85, 0.30, 0.85)
	_tb_zone.position = Vector2(0.0, 60.0); _tb_zone.size = Vector2(40.0, 26.0)
	_stage.add_child(_tb_zone)
	_tb_marker = ColorRect.new(); _tb_marker.color = Color(1.0, 0.92, 0.3)
	_tb_marker.position = Vector2(0.0, 56.0); _tb_marker.size = Vector2(4.0, 34.0)
	_stage.add_child(_tb_marker)

# ── Visuals: Mash ─────────────────────────────────────────────────────────
func _build_mash_visuals() -> void:
	_mash_track = ColorRect.new(); _mash_track.color = Color(0.15, 0.15, 0.18)
	_mash_track.position = Vector2(0.0, 60.0); _mash_track.size = Vector2(STAGE_SIZE.x, 26.0)
	_stage.add_child(_mash_track)
	_mash_fill = ColorRect.new(); _mash_fill.color = Color(0.95, 0.55, 0.2)
	_mash_fill.position = Vector2(0.0, 60.0); _mash_fill.size = Vector2(0.0, 26.0)
	_stage.add_child(_mash_fill)

## Feature (v14.0, eigenes Stein-Minispiel): drei Gesteinsbrocken-Icons
## nebeneinander (bereits zerschlagene ausgegraut, aktueller hervorgehoben,
## noch kommende schwach transparent) plus eine kleine Fortschrittsleiste
## darunter für die Schläge am aktuellen Brocken.
func _build_rock_visuals() -> void:
	var total_w: float = STAGE_SIZE.x
	var count: int = 3
	var spacing: float = total_w / float(count)
	for i in count:
		var lbl := Label.new()
		lbl.text = "🪨"
		lbl.add_theme_font_size_override("font_size", 44)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.position = Vector2(spacing * i, 10.0)
		lbl.size = Vector2(spacing, 56.0)
		_stage.add_child(lbl)
		_rock_labels.append(lbl)
	_rock_progress_track = ColorRect.new(); _rock_progress_track.color = Color(0.15, 0.15, 0.18)
	_rock_progress_track.position = Vector2(total_w * 0.15, 90.0); _rock_progress_track.size = Vector2(total_w * 0.7, 18.0)
	_stage.add_child(_rock_progress_track)
	_rock_progress_fill = ColorRect.new(); _rock_progress_fill.color = Color(0.75, 0.75, 0.78)
	_rock_progress_fill.position = Vector2(total_w * 0.15, 90.0); _rock_progress_fill.size = Vector2(0.0, 18.0)
	_stage.add_child(_rock_progress_fill)

# ── Visuals: Reaktions-Klick ─────────────────────────────────────────────────
func _build_reaction_visuals() -> void:
	for i in BERRY_POOL_SIZE:
		var btn := Button.new()
		btn.text = "🫐"
		btn.custom_minimum_size = Vector2(40.0, 40.0)
		btn.size = Vector2(40.0, 40.0)
		btn.add_theme_font_size_override("font_size", 20)
		btn.pressed.connect(_on_berry_pressed.bind(i))
		_stage.add_child(btn)
		_berry_buttons.append(btn)

# ── Visuals: Balance ──────────────────────────────────────────────────────
func _build_balance_visuals() -> void:
	_bal_track = ColorRect.new(); _bal_track.color = Color(0.15, 0.15, 0.18)
	_bal_track.position = Vector2(0.0, 65.0); _bal_track.size = Vector2(STAGE_SIZE.x, 18.0)
	_stage.add_child(_bal_track)
	_bal_center_marker = ColorRect.new(); _bal_center_marker.color = Color(0.4, 0.9, 1.0, 0.6)
	_bal_center_marker.position = Vector2(STAGE_SIZE.x * 0.5 - 2.0, 60.0); _bal_center_marker.size = Vector2(4.0, 28.0)
	_stage.add_child(_bal_center_marker)
	_bal_knob = ColorRect.new(); _bal_knob.color = Color(0.3, 0.7, 1.0)
	_bal_knob.position = Vector2(STAGE_SIZE.x * 0.5 - 7.0, 58.0); _bal_knob.size = Vector2(14.0, 34.0)
	_stage.add_child(_bal_knob)

func _hide_all_stage_visuals() -> void:
	_tb_track.visible = false; _tb_zone.visible = false; _tb_marker.visible = false
	_mash_track.visible = false; _mash_fill.visible = false
	for l in _rock_labels: (l as Label).visible = false
	_rock_progress_track.visible = false; _rock_progress_fill.visible = false
	for b in _berry_buttons: (b as Button).visible = false
	_bal_track.visible = false; _bal_knob.visible = false; _bal_center_marker.visible = false

# ── Start-Funktionen pro Ressourcentyp ───────────────────────────────────────
# Feature (v12.2, Phase 4): Bandana- ("leichter") und Augenklappe-
# ("kürzere Dauer nötig") Boost gelten für alle 5 Minispiele, jeweils auf
# den für den jeweiligen Minispiel-Typ passendsten Parameter angewendet:
# Bandana -> Präzisions-/Toleranz-Parameter (breitere Zone/Fenster, langsamerer
# Verfall), Augenklappe -> Mengen-/Dauer-Parameter (weniger nötige Treffer,
# schnelleres Füllen). Werte < 1.0 (Bandana) vergrössern die jeweilige
# Toleranz-Grösse, da sie divisorisch angewendet werden; Werte < 1.0
# (Augenklappe) verkleinern direkt die nötige Menge/Dauer.

## Holzfällen: gemäßigte Timing-Leiste, breite Zone, 5 Treffer.
## Feature (v13.6, Einfacher-für-Anfänger): Zone von 0.24 auf 0.32 verbreitert
## und Treffer-Anzahl von 5 auf 4 reduziert - schneller zu schaffen, weniger
## frustrierend beim "Farmen" von Ressourcen.
func start_wood(max_reward: float) -> void:
	_resource_type = "WOOD"
	_current_kind = "TIMING"
	var zone_w: float = 0.40 / PlayerAccessories.get_boost_mult("minigame_ease_mult")
	var hits: int = max(1, roundi(3 * PlayerAccessories.get_boost_mult("minigame_duration_mult")))
	_current = TimingBarMinigame.new("WOOD", max_reward, zone_w, 0.5, hits, 18.0)
	_title_lbl.text = "🪓 Holz fällen"
	_instr_lbl.text = "Drücke [E], wenn der Marker im grünen Bereich ist - %d gute Treffer!" % hits
	_show_kind()

## Erzabbau: gleiche Mechanik wie Holz, aber schmalere Zone, höhere
## Geschwindigkeit und mehr nötige Treffer - spürbar präziser/schwerer.
## Feature (v13.6, Einfacher-für-Anfänger): Zone von 0.11 auf 0.17 verbreitert,
## Treffer von 7 auf 6 reduziert - bleibt anspruchsvoller als Holz, aber
## nicht mehr unfair schwer.
func start_iron(max_reward: float) -> void:
	_resource_type = "IRON"
	_current_kind = "TIMING"
	var zone_w: float = 0.23 / PlayerAccessories.get_boost_mult("minigame_ease_mult")
	var hits: int = max(1, roundi(5 * PlayerAccessories.get_boost_mult("minigame_duration_mult")))
	_current = TimingBarMinigame.new("IRON", max_reward, zone_w, 0.75, hits, 22.0)
	_title_lbl.text = "⛏️ Erz abbauen"
	_instr_lbl.text = "Triff die Ader! Drücke [E] im grünen Bereich - %d Treffer." % hits
	_show_kind()

## Steinbrechen: eigenes Minispiel (v14.0) - 3 Gesteinsbrocken nacheinander,
## jeweils mit fester Schlagzahl in einem kleinen Zeitfenster zertrümmern.
## Vorher lief hier dieselbe Mash-Mechanik wie beim Bauen ("Mitbauen") -
## fühlte sich identisch an. Jetzt klar unterscheidbar: mehrstufig statt
## eine einzelne Leiste, mit sichtbarem Fortschritt pro Brocken.
func start_stone(max_reward: float) -> void:
	_resource_type = "STONE"
	_current_kind = "ROCKS"
	var hits: int = max(2, roundi(5 * PlayerAccessories.get_boost_mult("minigame_duration_mult")))
	var time_per_chunk: float = 4.0 / PlayerAccessories.get_boost_mult("minigame_ease_mult")
	_current = RockSmashMinigame.new(max_reward, 3, hits, time_per_chunk)
	_title_lbl.text = "🪨 Stein brechen"
	_instr_lbl.text = "Zertrümmere nacheinander 3 Brocken - drücke [E] jeweils %d mal, bevor die Zeit um ist!" % hits
	_show_kind()

## Beerenpflücken: Reaktions-Klick.
## Feature (v13.6, Einfacher-für-Anfänger): längere Lebenszeit (1.3 -> 1.7s),
## weniger nötige Klicks (10 -> 8).
func start_berries(max_reward: float) -> void:
	_resource_type = "BERRIES"
	_current_kind = "REACTION"
	var lifetime: float = 2.1 / PlayerAccessories.get_boost_mult("minigame_ease_mult")
	var count: int = max(1, roundi(6 * PlayerAccessories.get_boost_mult("minigame_duration_mult")))
	_current = ReactionClickMinigame.new("BERRIES", max_reward, count, BERRY_POOL_SIZE, lifetime, 0.55, 14.0, STAGE_SIZE)
	_title_lbl.text = "🫐 Beeren pflücken"
	_instr_lbl.text = "Klicke die Beeren an, bevor sie verschwinden!"
	_show_kind()

## Wasserschöpfen: Balance-Minispiel.
## Feature (v13.6, Einfacher-für-Anfänger): mehr Toleranz beim Ausbalancieren
## (spill_limit 1.0 -> 1.4) - Strömung darf stärker abweichen, bevor sie
## als "verschüttet" zählt.
func start_water(max_reward: float) -> void:
	_resource_type = "WATER"
	_current_kind = "BALANCE"
	var correct_speed: float = 0.9 * PlayerAccessories.get_boost_mult("minigame_ease_mult")
	var duration: float = 9.0 * PlayerAccessories.get_boost_mult("minigame_duration_mult")
	_current = BalanceMinigame.new("WATER", max_reward, correct_speed, duration, 1.8)
	_title_lbl.text = "💧 Wasser schöpfen"
	_instr_lbl.text = "Halte den Eimer mit [A]/[D] im Gleichgewicht - die Strömung zieht!"
	_show_kind()

## Feature (v13.6, Bauen als Minispiel): "Mitbauen" nutzt dieselbe Mash-
## Mechanik wie Steinbrechen (Hämmern passt thematisch zum Bauen) - bewusst
## noch etwas grosszügiger eingestellt, damit es sich eher nach hilfreichem
## Anpacken als nach einer Prüfung anfühlt. max_reward ist hier KEIN
## Rohstoff-Betrag, sondern der maximale Baufortschritt, den GameController
## direkt auf die anvisierte Baustelle anwendet (siehe
## GameController._on_minigame_finished()).
func start_build(max_reward: float) -> void:
	_resource_type = "BUILD"
	_current_kind = "MASH"
	var decay: float = 0.10 * PlayerAccessories.get_boost_mult("minigame_ease_mult")
	var fill: float = 0.18 / PlayerAccessories.get_boost_mult("minigame_duration_mult")
	_current = MashMinigame.new("BUILD", max_reward, fill, decay, 7.0)
	_title_lbl.text = "🔨 Mitbauen"
	_instr_lbl.text = "Hämmere [E] im Rhythmus - hilf der Baustelle voranzukommen!"
	_show_kind()

func _show_kind() -> void:
	_hide_all_stage_visuals()
	_apply_stage_theme(_resource_type)
	match _current_kind:
		"TIMING":
			_tb_track.visible = true; _tb_zone.visible = true; _tb_marker.visible = true
		"MASH":
			_mash_track.visible = true; _mash_fill.visible = true
		"ROCKS":
			for l in _rock_labels: (l as Label).visible = true
			_rock_progress_track.visible = true; _rock_progress_fill.visible = true
		"REACTION":
			for b in _berry_buttons: (b as Button).visible = false
		"BALANCE":
			_bal_track.visible = true; _bal_knob.visible = true; _bal_center_marker.visible = true
	show()
	# Mauszeiger wird gebraucht, um Beeren anzuklicken und den Abbrechen-Button
	# zu treffen - während des Minispiels immer sichtbar/frei, unabhängig
	# davon, ob gerade im First-Person-Umsehen die Maus gefangen war.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func is_active() -> bool:
	return _current != null

## Öffentlicher Abbruch-Einstieg, genutzt von GameController bei ESC während
## eines laufenden Minispiels.
func cancel() -> void:
	_on_cancel()

func _process(dt: float) -> void:
	if _current == null: return
	match _current_kind:
		"TIMING":
			var tb: TimingBarMinigame = _current
			if Input.is_action_just_pressed("interact"): tb.try_hit()
			tb.update(dt)
			var marker: float = tb.get_marker_pos()
			var zr: Vector2 = tb.get_zone_range()
			_tb_marker.position.x = marker * STAGE_SIZE.x - _tb_marker.size.x * 0.5
			_tb_zone.position.x = zr.x * STAGE_SIZE.x
			_tb_zone.size.x = (zr.y - zr.x) * STAGE_SIZE.x
			_progress_lbl.text = "Treffer: %d/%d   Zeit: %.0fs" % [tb.hits_done, tb.hits_required, maxf(0.0, tb.max_time - tb.elapsed)]
			if tb.is_finished(): _finish_current()
		"MASH":
			var mg: MashMinigame = _current
			if Input.is_action_just_pressed("interact"): mg.press()
			mg.update(dt)
			_mash_fill.size.x = mg.fill * STAGE_SIZE.x
			_progress_lbl.text = "Füllstand: %d%%   Zeit: %.0fs" % [int(mg.fill * 100.0), maxf(0.0, mg.max_time - mg.elapsed)]
			if mg.is_finished(): _finish_current()
		"ROCKS":
			var rs: RockSmashMinigame = _current
			if Input.is_action_just_pressed("interact"): rs.try_hit()
			rs.update(dt)
			for i in _rock_labels.size():
				var lbl: Label = _rock_labels[i]
				if i < rs.current_chunk:
					lbl.modulate = Color(0.4, 0.4, 0.4, 0.5)   # bereits zerschlagen
				elif i == rs.current_chunk:
					lbl.modulate = Color(1.0, 1.0, 1.0, 1.0)   # aktueller Brocken
				else:
					lbl.modulate = Color(1.0, 1.0, 1.0, 0.35)  # noch nicht dran
			_rock_progress_fill.size.x = rs.get_progress() * _rock_progress_track.size.x
			_progress_lbl.text = "Brocken %d/%d   Schläge: %d/%d   Zeit: %.0fs" % [
				mini(rs.current_chunk + 1, rs.chunk_count), rs.chunk_count,
				rs.hits_in_chunk, rs.hits_per_chunk, maxf(0.0, rs.time_per_chunk - rs.chunk_timer)]
			if rs.is_finished(): _finish_current()
		"REACTION":
			var rc: ReactionClickMinigame = _current
			rc.update(dt)
			var active: Array = rc.get_active_targets()
			for i in BERRY_POOL_SIZE:
				var btn: Button = _berry_buttons[i]
				if i < active.size():
					var ad: Dictionary = active[i]
					btn.visible = true
					btn.position = (ad["pos"] as Vector2) - btn.size * 0.5
					var lf: float = float(ad["life_frac"])
					btn.modulate = Color(1.0, 1.0, 1.0, 0.4 + 0.6 * lf)
				else:
					btn.visible = false
			_progress_lbl.text = "Gepflückt: %d/%d   Zeit: %.0fs" % [rc.total_clicked, rc.total_targets, maxf(0.0, rc.max_time - rc.elapsed)]
			if rc.is_finished(): _finish_current()
		"BALANCE":
			var bm: BalanceMinigame = _current
			var left: bool = Input.is_action_pressed("move_left")
			var right: bool = Input.is_action_pressed("move_right")
			bm.update(dt, left, right)
			var t: float = clampf((bm.value + 1.5) / 3.0, 0.0, 1.0)
			_bal_knob.position.x = t * STAGE_SIZE.x - _bal_knob.size.x * 0.5
			_bal_knob.color = Color(0.95, 0.3, 0.25) if absf(bm.value) >= bm.spill_limit else Color(0.3, 0.7, 1.0)
			_progress_lbl.text = "Balance halten...   Zeit: %.0fs" % maxf(0.0, bm.max_time - bm.elapsed)
			if bm.is_finished(): _finish_current()

func _on_berry_pressed(idx: int) -> void:
	if _current_kind != "REACTION" or _current == null: return
	var rc: ReactionClickMinigame = _current
	var btn: Button = _berry_buttons[idx]
	rc.try_click(btn.position + btn.size * 0.5)

func _finish_current() -> void:
	if _current == null: return
	# Feature (v14.2, Tech Tree "Kür"-Knoten): +15% Ertrag pro freigeschaltetem
	# Minispiel-Knoten (max. 6 = +90%), siehe TechTree.gd FORESTRY_11 usw.
	var reward: float = _current.get_reward() * (1.0 + TechTreeSys.get_global_bonus("minigame_reward_mult"))
	var res: String = _resource_type
	_current = null; _current_kind = ""; _resource_type = ""
	hide()
	minigame_finished.emit(res, reward)

func _on_cancel() -> void:
	if _current == null: return
	_current = null; _current_kind = ""
	var res: String = _resource_type
	_resource_type = ""
	hide()
	minigame_finished.emit(res, 0.0)
