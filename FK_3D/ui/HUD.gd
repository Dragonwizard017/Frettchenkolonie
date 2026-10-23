## HUD.gd - Ressourcen, Zeit, Saison, Buttons
extends Control

# Alle Referenzen per get_node_or_null - kompatibel mit programmatischem Aufbau
var _resource_display: HBoxContainer = null
var _time_label: Label = null
var _season_label: Label = null
var _drought_label: Label = null
var _pop_label: Label = null
var _storage_bar: ProgressBar = null
var _water_bar: ProgressBar = null
var _storage_text: Label = null
var _water_text: Label = null
var _beds_text: Label = null
var _science_text: Label = null
# v12.7-Bugfix ("UI-Elemente doppeln sich, z.B. Geschwindigkeit"): diese
# beiden Reihen (Pause/1x/2x/3x sowie Tech/Achievements/Expedition/
# Gräberfeld/Bezirke) existieren inhaltsgleich nochmal - grösser und
# touch-tauglich - im TouchOverlay. Werden jetzt ausgeblendet, sobald
# Touch-Steuerung aktiv ist, damit nicht beide Versionen gleichzeitig sichtbar sind.
var _speed_buttons: BoxContainer = null
var _extra_buttons: Container = null

func _ready() -> void:
	_resource_display = find_child("ResourceDisplay", true, false)
	_time_label       = find_child("TimeLabel", true, false)
	_season_label     = find_child("SeasonLabel", true, false)
	_drought_label    = find_child("DroughtLabel", true, false)
	_pop_label        = find_child("PopLabel", true, false)
	_storage_bar      = find_child("StorageBar", true, false)
	_water_bar        = find_child("WaterBar", true, false)
	_storage_text     = find_child("StorageTextLabel", true, false)
	_water_text       = find_child("WaterTextLabel", true, false)
	_beds_text        = find_child("BedsTextLabel", true, false)
	_science_text     = find_child("ScienceTextLabel", true, false)
	_speed_buttons    = find_child("SpeedButtons", true, false)
	_extra_buttons    = find_child("ExtraButtons", true, false)
	GameState.hud_update_requested.connect(refresh)
	GameState.state_changed.connect(_on_state_changed)
	TouchControlsSettings.changed.connect(func(_e): _update_desktop_controls_visibility())
	_update_desktop_controls_visibility()
	var pb: Button = find_child("PauseBtn", true, false)
	var b1: Button = find_child("Btn1", true, false)
	var b2: Button = find_child("Btn2", true, false)
	var b3: Button = find_child("Btn3", true, false)
	if pb: pb.pressed.connect(func(): GameState.toggle_pause())
	if b1: b1.pressed.connect(func(): GameState.set_game_speed(1.0))
	if b2: b2.pressed.connect(func(): GameState.set_game_speed(2.0))
	if b3: b3.pressed.connect(func(): GameState.set_game_speed(3.0))
	# Bug-Fix (v10.14): ExpeditionPanel/GraveyardPanel existierten zwar als
	# Skripte, waren aber nirgends im UI-Baum erzeugt UND es gab keinen Weg,
	# sie zu öffnen. Beide Panels sitzen als Geschwister-Nodes direkt unter
	# UIRoot (siehe Main.gd), genau wie HUD selbst - daher "../".
	var exp_btn: Button = find_child("ExpeditionBtn", true, false)
	var grave_btn: Button = find_child("GraveyardBtn", true, false)
	var tech_btn: Button = find_child("TechTreeBtn", true, false)
	# Feature (v11.8, Achievement-System):
	var ach_btn: Button = find_child("AchievementBtn", true, false)
	# Feature (v11.11, Distrikt-System):
	var district_btn: Button = find_child("DistrictBtn", true, false)
	# Feature (v16.0, Kolonie-Fundament):
	var colony_btn: Button = find_child("ColonyBtn", true, false)
	var line_btn: Button = find_child("LineBtn", true, false)   # Feature (v16.2, Schiene)
	var map_btn: Button = find_child("WorldMapBtn", true, false)   # Feature (v16.6, Weltkarte)
	var nb_btn: Button = find_child("NeighborBtn", true, false)   # Feature (v16.7, Nachbarn)
	# Bug-Fix (v13.7, "Frettchenmodus im Nicht-Touch-Modus nicht aktivierbar"):
	# Desktop-Ersatz für die [F]-Taste, siehe scenes/Main.gd (Button-Erzeugung).
	var fp_btn: Button = find_child("FPModeBtn", true, false)
	if fp_btn:
		fp_btn.pressed.connect(func():
			var gc: Node = get_node_or_null("/root/Main/GameScreen")
			if gc == null or not GameState.is_playing(): return
			if bool(gc.call("_is_minigame_active")) or not GameState.placement_mode.is_empty(): return
			gc.call("_toggle_fp_mode")
		)
	if exp_btn:
		exp_btn.pressed.connect(func():
			var p := get_node_or_null("../ExpeditionPanel")
			if p and p.has_method("open"): p.call("open")
		)
	if grave_btn:
		grave_btn.pressed.connect(func():
			var p := get_node_or_null("../GraveyardPanel")
			if p and p.has_method("open"): p.call("open")
		)
	if tech_btn:
		tech_btn.pressed.connect(func():
			var p := get_node_or_null("../TechTreePanel")
			if p and p.has_method("open"): p.call("open")
		)
	if ach_btn:
		ach_btn.pressed.connect(func():
			var p := get_node_or_null("../AchievementPanel")
			if p and p.has_method("open"): p.call("open")
		)
	if nb_btn:
		nb_btn.pressed.connect(func():
			var np := get_node_or_null("../NeighborPanel")
			if np and np.has_method("open"): np.call("open")
		)
	if map_btn:
		map_btn.pressed.connect(func():
			var mp := get_node_or_null("../WorldMapPanel")
			if mp and mp.has_method("open"): mp.call("open")
		)
	if line_btn:
		line_btn.pressed.connect(func():
			var lp := get_node_or_null("../LinePanel")
			if lp and lp.has_method("open"): lp.call("open")
		)
	if colony_btn:
		colony_btn.pressed.connect(func():
			var p := get_node_or_null("../ColonyPanel")
			if p and p.has_method("open"): p.call("open")
		)
	if district_btn:
		district_btn.pressed.connect(func():
			var p := get_node_or_null("../DistrictPanel")
			if p and p.has_method("open"): p.call("open")
		)

func _process(_dt: float) -> void:
	_sync_speed_buttons()
	if not GameState.is_playing(): return
	if _time_label:
		_time_label.text = "%s %s  ·  Tag %d" % [DayNight.icon, DayNight.display_time, DayNight.day_count + 1]
	if _drought_label:
		if DroughtSys.phase != "WET":
			_drought_label.text = DroughtSys.display_text
			_drought_label.modulate = DroughtSys.hud_color
			_drought_label.show()
		else:
			_drought_label.hide()
	if _season_label:
		_season_label.text = SeasonSys.get_season_icon() + " " + SeasonSys.get_season_name()

func refresh() -> void:
	if not is_inside_tree(): return
	_update_resources()
	_update_bars()
	if _pop_label:
		var pop_active: int = PopMgr.get_count(ColonySys.active_id)
		_pop_label.text = ("👥 %d" % pop_active) if ColonySys.player_count() <= 1 \
			else "🏛️ %s  👥 %d" % [ColonySys.get_name_of(ColonySys.active_id), pop_active]

## v15.8 (Performance-Fix): die Ressourcen-Pillen wurden jede Sekunde neu erzeugt (~30 ms). Jetzt bleiben
## sie bestehen; aktualisiert werden nur Text, Farbe und Sichtbarkeit.
var _chips: Dictionary = {}      # res -> {"chip": PanelContainer, "val": Label}

func _update_resources() -> void:
	if _resource_display == null: return
	var icons: Dictionary = BuildingData.RESOURCE_ICONS
	var order: Array = ["WOOD","STONE","BERRIES","PLANKS","TOOLS","FOOD",
		"MEAT","WHEAT","COOKED_MEAT","BREAD","STEW","IRON","IRON_BARS","MACHINES","COAL","STEEL","DYNAMITE"]
	var hide_zero: Array = ["MEAT","DYNAMITE","WHEAT","COOKED_MEAT","BREAD","STEW","IRON","IRON_BARS","MACHINES","COAL","STEEL"]
	for res in order:
		var val: float = float(ResourceSys.resources.get(res, 0.0))
		var shown: bool = not (res in hide_zero and val < 1.0)
		if not _chips.has(res) or not is_instance_valid((_chips[res] as Dictionary)["chip"]):
			# einmalig anlegen (v15.0: jede Ressource als "Pille" mit getöntem Icon + Wert)
			var chip := UITheme.panel("ChipPanel")
			chip.tooltip_text = str(res).capitalize().replace("_", " ")
			var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 4)
			chip.add_child(hb)
			var ic := Label.new(); ic.text = str(icons.get(res, "?"))
			ic.add_theme_font_size_override("font_size", 14)
			ic.add_theme_color_override("font_color", UITheme.RES_COLORS.get(res, UITheme.C_TEXT))
			hb.add_child(ic)
			var vl := UITheme.lbl("0", "Chip")
			hb.add_child(vl)
			_resource_display.add_child(chip)
			_chips[res] = {"chip": chip, "val": vl}
		var e: Dictionary = _chips[res]
		(e["chip"] as Control).visible = shown
		if shown:
			var vl2: Label = e["val"] as Label
			vl2.text = str(int(val))
			if val < 1.0: vl2.add_theme_color_override("font_color", UITheme.C_TEXT_DIM)
			else: vl2.remove_theme_color_override("font_color")

## v15.0: zeigt die aktive Geschwindigkeit (bzw. Pause) in den Segment-Knöpfen an.
func _sync_speed_buttons() -> void:
	if _speed_buttons == null or not _speed_buttons.is_visible_in_tree(): return
	var paused: bool = GameState.game_speed <= 0.0 or GameState.current_state == GameState.State.PAUSED
	var want: String = "PauseBtn" if paused else ("Btn3" if GameState.game_speed >= 2.5 else ("Btn2" if GameState.game_speed >= 1.5 else "Btn1"))
	for c in _speed_buttons.get_children():
		var bb: Button = c as Button
		if bb: bb.set_pressed_no_signal(bb.name == want)

func _update_bars() -> void:
	if _storage_bar:
		var stored: float = ResourceSys.get_total_stored()
		var cap: float = maxf(1.0, ResourceSys.storage_capacity)
		_storage_bar.value = stored / cap * 100.0
		_storage_bar.tooltip_text = "Lager: %d/%d" % [int(stored), int(cap)]
	if _storage_text:
		_storage_text.text = "📦 %d/%d" % [int(ResourceSys.get_total_stored()), int(ResourceSys.storage_capacity)]
	if _water_bar:
		var wc: float = maxf(1.0, ResourceSys.water_capacity)
		_water_bar.value = ResourceSys.water / wc * 100.0
		_water_bar.tooltip_text = "Wasser: %d/%d" % [int(ResourceSys.water), int(wc)]
	# Bug-Fix (v11.0): "Wassertand wird nicht angezeigt" - garantiert
	# sichtbares Text-Label statt sich ausschliesslich auf die schmale,
	# beschriftungslose ProgressBar zu verlassen.
	if _water_text:
		_water_text.text = "💧 %d/%d" % [int(ResourceSys.water), int(ResourceSys.water_capacity)]
	# Feature (v11.1, Betten): zeigt belegte/gesamte Schlafplätze der Kolonie.
	# Färbung warnt, sobald mehr Frettchen als Betten da sind (Obdachlose).
	if _beds_text:
		var total_beds: int = BuildingSys.get_total_beds(ColonySys.active_id)
		var occ_beds: int = BuildingSys.get_occupied_beds(ColonySys.active_id)
		_beds_text.text = "🛏️ %d/%d" % [occ_beds, total_beds]
		var homeless: int = PopMgr.get_count(ColonySys.active_id) - total_beds
		_beds_text.add_theme_color_override("font_color",
			Color(0.95, 0.35, 0.25) if homeless > 0 else Color(0.85, 0.65, 1.0))
	# Feature (Tech Tree): zeigt den aktuellen Wissenspunkte-Bestand.
	if _science_text:
		_science_text.text = "🔬 %d" % int(ResourceSys.science)

func _on_state_changed(state: GameState.State) -> void:
	visible = (state == GameState.State.PLAYING or state == GameState.State.PAUSED)

func _update_desktop_controls_visibility() -> void:
	var hide_them: bool = TouchControlsSettings.enabled
	if _speed_buttons: _speed_buttons.get_parent().visible = not hide_them
	if _extra_buttons: _extra_buttons.get_parent().visible = not hide_them
