## Main.gd  –  baut die gesamte Szene zur Laufzeit auf.
## Kein .tscn-Layout, daher keine Anker-Bugs.
extends Node

var _main_menu:     Control
var _world_creation: Control
var _game_screen:   Node3D
var _game_ctrl:     Node = null
var _game_over_screen: Control = null
var _go_cause_label:    Label   = null
# Feature (v11.4, Speicherslot-System): Welt-Auswahl-Bildschirm - listet alle
# benannten Speicherstaende mit Kurzinfo (Tag/Jahreszeit/Bevoelkerung/Seed) auf.
var _load_screen:    Control = null
var _load_list_vbox: VBoxContainer = null

func _ready() -> void:
	_build_main_menu()
	_build_world_creation()
	_build_load_screen()
	_build_game_screen()
	GameState.state_changed.connect(_on_state_changed)
	# Crash-Fix (UI verschwindet + "Absturz" ins Hauptmenue): Game Over hatte
	# bisher KEINE eigene Anzeige - der Bildschirm fror fuer 5 Sekunden ein
	# (HUD/Bau-Menue blenden sich bei jedem Nicht-PLAYING-Zustand automatisch
	# aus) und sprang danach kommentarlos ins Hauptmenue. Das sah fuer
	# Spieler genau wie ein Absturz aus. Jetzt zeigt ein richtiger
	# Game-Over-Bildschirm den Grund an und der Spieler kehrt per Klick
	# bewusst ins Hauptmenue zurueck.
	GameState.game_over_triggered.connect(_on_game_over_triggered)
	GameState.set_state(GameState.State.MAIN_MENU)

func _on_game_over_triggered(cause: String) -> void:
	if _go_cause_label: _go_cause_label.text = cause

# ── Utility ───────────────────────────────────────────────────────────────────
func _full_rect(node: Control) -> Control:
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return node

func _lbl(text: String, size: int = 13, col: Color = Color.WHITE) -> Label:
	var l := Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _spacer(h: int) -> Control:
	var c := Control.new(); c.custom_minimum_size = Vector2(0, h); return c

func _btn(text: String, size: int = 14, min_h: int = 44) -> Button:
	var b := Button.new(); b.text = text
	b.custom_minimum_size = Vector2(280, min_h)
	b.add_theme_font_size_override("font_size", size)
	return b

# ══════════════════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════════════════
func _build_main_menu() -> void:
	_main_menu = Control.new(); _main_menu.name = "MainMenu"
	_full_rect(_main_menu)
	add_child(_main_menu)

	var bg := ColorRect.new(); bg.color = Color(0.05,0.07,0.12)
	_full_rect(bg); _main_menu.add_child(bg)

	var cc := CenterContainer.new()
	_full_rect(cc); _main_menu.add_child(cc)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	cc.add_child(vbox)

	var title_lbl := _lbl("FrettchenKolonie", 38, Color(0.96,0.69,0.1))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lbl)
	var sub_lbl := _lbl("v11.4 – 3D Edition", 14, Color(0.5,0.5,0.5))
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub_lbl)
	vbox.add_child(_spacer(20))

	var nb := _btn("Neue Welt starten", 18, 52); nb.pressed.connect(_show_world_creation); vbox.add_child(nb)
	# Feature (v11.4, Speicherslot-System): "Laden (Quicksave)" ersetzt durch
	# "Welt laden" - fuehrt jetzt zur Welt-Auswahl-Liste mit beliebig vielen,
	# benannten Speicherstaenden statt nur einem einzigen festen Slot.
	var lb := _btn("Welt laden", 16, 48); lb.pressed.connect(_show_load_screen); vbox.add_child(lb)
	# Feature (v11.14, Testwelt): erzeugt automatisch eine weit entwickelte
	# Test-Kolonie (viele Gebaeude, Bevoelkerung, Tech-Fortschritt) und legt
	# sie als ganz normalen Speicherstand ab - taucht danach in "Welt laden"
	# auf. Siehe GameController.bootstrap_test_colony().
	var tb := _btn("🛠️ Testwelt erstellen", 13, 40)
	tb.add_theme_color_override("font_color", Color(0.5, 0.85, 0.55))
	tb.pressed.connect(_on_create_test_world); vbox.add_child(tb)

	# Feature (v12.5, Touch-Controls): Umschalter im Hauptmenü.
	# Zeigt den aktuellen Zustand und toggelt ihn beim Klick.
	var touch_btn := _btn("", 13, 40)
	touch_btn.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	var _update_touch_label := func() -> void:
		touch_btn.text = "📱 Touch-Steuerung: %s" % ("EIN ✓" if TouchControlsSettings.enabled else "AUS")
	_update_touch_label.call()
	touch_btn.pressed.connect(func():
		TouchControlsSettings.toggle()
		_update_touch_label.call()
	)
	vbox.add_child(touch_btn)

# ══════════════════════════════════════════════════════════════════════════════
# WORLD CREATION
# ══════════════════════════════════════════════════════════════════════════════
var _name_input:    LineEdit
var _seed_input:    LineEdit
var _size_option:   OptionButton
var _seed_preview:  Label

func _build_world_creation() -> void:
	_world_creation = Control.new(); _world_creation.name = "WorldCreation"
	_full_rect(_world_creation); _world_creation.visible = false
	add_child(_world_creation)

	var bg := ColorRect.new(); bg.color = Color(0.05,0.07,0.12)
	_full_rect(bg); _world_creation.add_child(bg)

	var cc := CenterContainer.new(); _full_rect(cc); _world_creation.add_child(cc)
	var panel := PanelContainer.new(); panel.custom_minimum_size = Vector2(440,0); cc.add_child(panel)
	var vbox := VBoxContainer.new(); vbox.add_theme_constant_override("separation",11); panel.add_child(vbox)

	vbox.add_child(_lbl("Neue Welt erstellen", 22, Color(0.96,0.69,0.1)))
	vbox.add_child(_lbl("Kolonienname:", 13))
	_name_input = LineEdit.new(); _name_input.text = "Meine Kolonie"
	_name_input.custom_minimum_size = Vector2(0,38); vbox.add_child(_name_input)

	vbox.add_child(_lbl("Seed (leer = zufaellig):", 13))
	_seed_input = LineEdit.new(); _seed_input.placeholder_text = "Leer = Zufaellig"
	_seed_input.custom_minimum_size = Vector2(0,38); vbox.add_child(_seed_input)
	_seed_preview = _lbl("Seed: Zufaellig", 12, Color(0.5,0.5,0.5)); vbox.add_child(_seed_preview)
	_seed_input.text_changed.connect(func(t: String):
		_seed_preview.text = "Seed-Hash: %d" % t.hash() if t.strip_edges()!="" else "Seed: Zufaellig")

	vbox.add_child(_lbl("Weltgroesse:", 13))
	_size_option = OptionButton.new(); _size_option.custom_minimum_size = Vector2(0,38)
	for s in ["Klein (40x40)","Mittel (60x60)","Gross (80x80)"]: _size_option.add_item(s)
	_size_option.selected = 1; vbox.add_child(_size_option)
	vbox.add_child(_spacer(6))

	var sb := _btn("Kolonie gruenden!", 16, 50)
	sb.add_theme_color_override("font_color", Color(0.3,1.0,0.4)); sb.pressed.connect(_on_start_game); vbox.add_child(sb)
	var bb := _btn("Zurueck", 14, 44); bb.pressed.connect(_show_main_menu); vbox.add_child(bb)

# ══════════════════════════════════════════════════════════════════════════════
# WELT-AUSWAHL / LADEN  (Feature v11.4, Speicherslot-System)
# Ersetzt den alten festen "quicksave"-Slot durch eine Liste aller benannten
# Speicherstaende inkl. Kurzinfo (Tag, Jahreszeit, Bevoelkerung, Seed,
# Weltgroesse, Speicherzeitpunkt) - anklickbar zum Laden, mit Loeschen-Option.
# ══════════════════════════════════════════════════════════════════════════════
func _build_load_screen() -> void:
	_load_screen = Control.new(); _load_screen.name = "LoadScreen"
	_full_rect(_load_screen); _load_screen.visible = false
	add_child(_load_screen)

	var bg := ColorRect.new(); bg.color = Color(0.05,0.07,0.12)
	_full_rect(bg); _load_screen.add_child(bg)

	var margin := MarginContainer.new(); _full_rect(margin)
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_" + side, 70)
	_load_screen.add_child(margin)

	var vbox := VBoxContainer.new(); vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	vbox.add_child(_lbl("Welt laden", 26, Color(0.96,0.69,0.1)))
	vbox.add_child(_spacer(4))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_load_list_vbox = VBoxContainer.new(); _load_list_vbox.name = "LoadList"
	_load_list_vbox.add_theme_constant_override("separation", 8)
	_load_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_load_list_vbox)

	vbox.add_child(_spacer(4))
	var back := _btn("Zurueck", 14, 44); back.pressed.connect(_show_main_menu); vbox.add_child(back)

## Zeigt den Welt-Auswahl-Bildschirm an und fuellt die Liste frisch.
func _show_load_screen() -> void:
	_refresh_load_list()
	GameState.set_state(GameState.State.LOAD_SCREEN)

## Baut die Liste aller Speicherstaende neu auf (neueste zuerst).
func _refresh_load_list() -> void:
	for c in _load_list_vbox.get_children(): c.queue_free()
	var names: Array = SaveSys.get_save_names()
	var infos: Array = []
	for n in names:
		var info: Dictionary = SaveSys.get_save_info(n)
		if not info.is_empty(): infos.append(info)
	infos.sort_custom(func(a, b): return str(a.get("timestamp","")) > str(b.get("timestamp","")))
	if infos.is_empty():
		_load_list_vbox.add_child(_lbl("Keine Speicherstaende vorhanden - starte zuerst eine neue Welt.", 14, Color(0.6,0.6,0.6)))
		return
	for info in infos:
		_load_list_vbox.add_child(_build_save_row(info))

## Baut eine einzelne Zeile der Welt-Auswahl-Liste (Name, Kurzinfo, Laden/Loeschen).
func _build_save_row(info: Dictionary) -> Control:
	var slot: String = str(info.get("slot",""))
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 74)
	var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 16)
	panel.add_child(hb)

	var info_vb := VBoxContainer.new(); info_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(info_vb)
	info_vb.add_child(_lbl(str(info.get("colony_name", slot)), 17, Color(0.95,0.85,0.5)))
	var details := "Tag %d   %s %s   👥 %d   Welt %dx%d   Seed %d" % [
		int(info.get("day_count",0)), str(info.get("season_icon","")), str(info.get("season_name","")),
		int(info.get("population",0)), int(info.get("world_w",0)), int(info.get("world_h",0)),
		int(info.get("seed",0))]
	info_vb.add_child(_lbl(details, 12, Color(0.7,0.7,0.7)))
	info_vb.add_child(_lbl("Gespeichert: " + str(info.get("timestamp","")), 11, Color(0.5,0.5,0.5)))

	var btn_vb := VBoxContainer.new(); btn_vb.add_theme_constant_override("separation", 4)
	hb.add_child(btn_vb)
	var load_b := Button.new(); load_b.text = "Laden"; load_b.custom_minimum_size = Vector2(130,34)
	load_b.pressed.connect(func(): _load_from_slot(slot))
	btn_vb.add_child(load_b)
	var del_b := Button.new(); del_b.text = "Loeschen"; del_b.custom_minimum_size = Vector2(130,30)
	del_b.add_theme_color_override("font_color", Color(0.85,0.35,0.3))
	del_b.pressed.connect(func(): _confirm_delete_save(slot, del_b))
	btn_vb.add_child(del_b)

	return panel

## Zwei-Klick-Sicherung: erster Klick fragt nach, zweiter Klick loescht wirklich.
func _confirm_delete_save(slot: String, btn: Button) -> void:
	if btn.get_meta("confirm", false):
		SaveSys.delete_save(slot)
		_refresh_load_list()
	else:
		btn.set_meta("confirm", true)
		btn.text = "Wirklich?!"
		btn.get_tree().create_timer(3.0).timeout.connect(func():
			if is_instance_valid(btn):
				btn.set_meta("confirm", false); btn.text = "Loeschen")

## Laedt den gewaehlten Speicherstand und wechselt ins laufende Spiel.
func _load_from_slot(slot_name: String) -> void:
	var ok: bool = SaveSys.load_game(slot_name, _game_ctrl)
	if not ok: return
	GameState.set_state(GameState.State.PLAYING)

# ══════════════════════════════════════════════════════════════════════════════
# GAME SCREEN
# ══════════════════════════════════════════════════════════════════════════════
func _build_game_screen() -> void:
	_game_screen = Node3D.new(); _game_screen.name = "GameScreen"; _game_screen.visible = false

	# Camera3D – isometrisch, orthographisch
	var cam := Camera3D.new(); cam.name = "Camera3D"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 28.0
	_game_screen.add_child(cam)

	# 3D-Renderer
	var rend := WorldRenderer3D.new(); rend.name = "WorldRenderer3D"
	_game_screen.add_child(rend)

	# Beleuchtung
	var dir_light := DirectionalLight3D.new(); dir_light.name = "Sun"
	dir_light.rotation_degrees = Vector3(-55.0, 45.0, 0.0)
	dir_light.light_energy = 1.15
	dir_light.shadow_enabled = true
	_game_screen.add_child(dir_light)

	var fill_light := DirectionalLight3D.new(); fill_light.name = "Fill"
	fill_light.rotation_degrees = Vector3(-30.0, -135.0, 0.0)
	fill_light.light_energy = 0.35
	fill_light.shadow_enabled = false
	_game_screen.add_child(fill_light)

	var world_env := WorldEnvironment.new(); world_env.name = "WorldEnv"
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color  = Color(0.30, 0.34, 0.44)
	env.ambient_light_energy = 0.55
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.52, 0.65, 0.78)
	world_env.environment = env
	_game_screen.add_child(world_env)

	# Feature (v11.2, First-Person-Modus): eigenstaendiger Spieler-Node,
	# getrennt vom Kolonie-Frettchen-Pool (siehe PlayerController.gd).
	var player := PlayerController.new(); player.name = "PlayerController"
	_game_screen.add_child(player)

	# CanvasLayer hält alle UI-Elemente
	var canvas := CanvasLayer.new(); canvas.name = "GameUI"
	_game_screen.add_child(canvas)

	# UIRoot: ein Control das den ganzen Viewport füllt, Eltern aller HUD-Nodes
	# Muss NACH add_child zu _game_screen sitzen, damit Viewport-Größe bekannt ist.
	# Wir erzwingen die Größe über _notification(NOTIFICATION_WM_SIZE_CHANGED).
	var ui_root := _make_ui_root(); canvas.add_child(ui_root)

	_build_hud(ui_root)
	_build_build_menu(ui_root)
	_build_building_info(ui_root)
	_build_placement_hint(ui_root)
	_build_pause_menu(ui_root)
	_build_notifications(ui_root)
	_build_game_over_screen(ui_root)
	_build_tutorial(ui_root)
	_build_expedition_panel(ui_root)
	_build_graveyard_panel(ui_root)
	_build_tech_tree_panel(ui_root)
	_build_achievement_panel(ui_root)
	_build_unlock_explainer(ui_root)
	_build_achievement_toast(ui_root)
	# Feature (v11.10): FerretsPanel (globales Frettchen-Roster, v11.8) auf
	# Nutzerwunsch wieder entfernt - die individuelle Klick-Interaktion
	# (FerretProfilePanel, v11.9) deckt den Anwendungsfall jetzt ab.
	_build_ferret_profile_panel(ui_root)
	_build_legendary_toast(ui_root)
	_build_dev_tools_panel(ui_root)
	_build_district_panel(ui_root)
	_build_fp_hud(ui_root)
	_build_minigame_overlay(ui_root)
	# Feature (v12.5, Touch-Controls): virtuelles Gamepad – zuletzt hinzufügen,
	# damit es ÜBER allen anderen UI-Elementen liegt.
	_build_touch_overlay(ui_root)

	# Script setzen NACHDEM alle Kinder vorhanden sind, DANN in Baum hängen
	_game_screen.set_script(load("res://game/GameController.gd") as GDScript)
	add_child(_game_screen)
	_game_ctrl = _game_screen
	# Touch-Overlay braucht Referenz auf GameController für direkte Methoden-Aufrufe.
	var touch_ov := ui_root.get_node_or_null("TouchOverlay")
	if touch_ov != null:
		touch_ov.set("_game_ctrl", _game_ctrl)

func _make_ui_root() -> Control:
	var r := Control.new(); r.name = "UIRoot"
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _build_hud(root: Control) -> void:
	var hud := Control.new(); hud.name = "HUD"
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.anchor_right=1.0; hud.anchor_bottom=1.0
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.set_script(load("res://ui/HUD.gd") as GDScript)
	root.add_child(hud)

	# TopBar – bleibt oben über die ganze Breite
	var topbar := HBoxContainer.new(); topbar.name = "TopBar"
	topbar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	topbar.anchor_right = 1.0; topbar.offset_bottom = 38
	topbar.add_theme_constant_override("separation", 8)
	hud.add_child(topbar)

	var bg := ColorRect.new(); bg.name = "BgRect"
	bg.color = Color(0.05,0.07,0.12,0.88); bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.anchor_right=1.0; bg.anchor_bottom=1.0
	topbar.add_child(bg)

	var rd := HBoxContainer.new(); rd.name = "ResourceDisplay"
	rd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rd.add_theme_constant_override("separation", 8); topbar.add_child(rd)

	for pair in [["TimeLabel","06:00"],["SeasonLabel","Fruehling"],
						["DroughtLabel",""],["PopLabel","F 5"]]:
		var l := Label.new(); l.name = pair[0]; l.text = pair[1]
		l.add_theme_font_size_override("font_size", 13)
		if pair[0] == "DroughtLabel":
			l.visible = false; l.add_theme_color_override("font_color",Color(0.85,0.2,0.1))
		topbar.add_child(l)

	for pair2 in [["StorageBar",60],["WaterBar",50]]:
		var pb := ProgressBar.new(); pb.name = pair2[0]
		pb.custom_minimum_size = Vector2(pair2[1], 18); topbar.add_child(pb)

	# Bug-Fix (v11.0): "Wassertand wird nicht angezeigt" - die WaterBar/
	# StorageBar oben waren bereits vorhanden und wurden von HUD.gd auch
	# aktualisiert, aber ohne jede Beschriftung/Icon waren die schmalen
	# ProgressBars in der TopBar leicht zu uebersehen bzw. nicht klar als
	# "Wasser" erkennbar. Zwei zusaetzliche, garantiert lesbare Text-Labels
	# mit Icon direkt daneben.
	for pair2b in [["StorageTextLabel","📦 0/0"],["WaterTextLabel","💧 0/0"],["BedsTextLabel","🛏️ 0/0"],["ScienceTextLabel","🔬 0"]]:
		var tl := Label.new(); tl.name = pair2b[0]; tl.text = pair2b[1]
		tl.add_theme_font_size_override("font_size", 13)
		if pair2b[0] == "WaterTextLabel":
			tl.add_theme_color_override("font_color", Color(0.55, 0.78, 1.0))
		if pair2b[0] == "BedsTextLabel":
			tl.add_theme_color_override("font_color", Color(0.85, 0.65, 1.0))
		# Feature (Tech Tree): Wissenspunkte-Anzeige in der TopBar.
		if pair2b[0] == "ScienceTextLabel":
			tl.add_theme_color_override("font_color", Color(0.55, 1.0, 0.75))
		topbar.add_child(tl)

	# Speedbuttons – rechts oben
	var srow := HBoxContainer.new(); srow.name = "SpeedButtons"
	srow.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	srow.anchor_left=1.0; srow.anchor_right=1.0
	srow.offset_left=-168; srow.offset_top=42; srow.offset_right=-4; srow.offset_bottom=70
	srow.add_theme_constant_override("separation",4); hud.add_child(srow)
	for pair3 in [["PauseBtn","||"],["Btn1","1x"],["Btn2","2x"],["Btn3","3x"]]:
		var b := Button.new(); b.name = pair3[0]; b.text = pair3[1]
		b.custom_minimum_size = Vector2(36,28); srow.add_child(b)

	# Bug-Fix (v10.14): "Expeditionen sind implementiert, aber nicht
	# erreichbar" - ExpeditionPanel.gd/GraveyardPanel.gd existierten bereits
	# vollstaendig, wurden aber nie irgendwo im UI-Baum erzeugt UND es gab
	# keinen Button, um sie zu oeffnen. Zwei zusaetzliche Buttons unterhalb
	# der Geschwindigkeits-Buttons; die eigentliche Verdrahtung (Panels
	# oeffnen) passiert in HUD.gd._ready().
	var srow2 := HBoxContainer.new(); srow2.name = "ExtraButtons"
	srow2.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	srow2.anchor_left=1.0; srow2.anchor_right=1.0
	# Feature (v11.8): Reihe fuer 5 Buttons (5*36+4*4=196 < 244) - "FerretsBtn"
	# aus v11.8 wurde in v11.10 entfernt, "DistrictBtn" in v11.11 ergaenzt.
	srow2.offset_left=-244; srow2.offset_top=74; srow2.offset_right=-4; srow2.offset_bottom=102
	srow2.add_theme_constant_override("separation",4); hud.add_child(srow2)
	# Feature (v11.8, Achievement-System): weiterer Button in derselben Reihe.
	for pair4 in [["ExpeditionBtn","🗺️"],["GraveyardBtn","🪦"],["TechTreeBtn","🔬"],["AchievementBtn","🏆"],["DistrictBtn","🏘️"]]:
		var b4 := Button.new(); b4.name = pair4[0]; b4.text = pair4[1]
		b4.custom_minimum_size = Vector2(36,28); srow2.add_child(b4)

func _build_build_menu(root: Control) -> void:
	var bm := PanelContainer.new(); bm.name = "BuildMenu"
	bm.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	bm.anchor_bottom = 1.0; bm.offset_right = 224
	# Bug-Fix (UI-Überlappung: Ressourcenanzeige lag unter dem Bau-Menü):
	# Die TopBar (HUD) ist 38px hoch und geht über die volle Breite, das
	# Bau-Menü begann aber bei y=0 (volle Höhe) und wurde NACH dem HUD
	# hinzugefügt -> es lag über der TopBar in der oberen linken Ecke und
	# verdeckte Zeit/Jahreszeit/Ressourcen-Anzeige. Jetzt beginnt es erst
	# unterhalb der TopBar.
	bm.offset_top = 38
	bm.set_script(load("res://ui/BuildMenu.gd") as GDScript)
	root.add_child(bm)

	var outer := VBoxContainer.new(); outer.name="Outer"; outer.size_flags_vertical=Control.SIZE_EXPAND_FILL; bm.add_child(outer)
	var hdr := HBoxContainer.new(); hdr.name="Header"; outer.add_child(hdr)
	# Bug-Fix (fehlender Epochen-Button): vorher nur ein Label ohne Funktion.
	# Jetzt ein klickbarer Button, der die naechste Epoche samt Kosten zeigt
	# und per Klick freischaltet, sobald genug Ressourcen vorhanden sind.
	var el := Button.new(); el.name="EpochBtn"; el.text="Epoche 1"
	el.add_theme_font_size_override("font_size", 11)
	el.size_flags_horizontal=Control.SIZE_EXPAND_FILL; hdr.add_child(el)
	var tb := Button.new(); tb.name="ToggleBtn"; tb.text="<<"; hdr.add_child(tb)
	var sc := ScrollContainer.new(); sc.name="ScrollContainer"
	sc.size_flags_vertical=Control.SIZE_EXPAND_FILL; outer.add_child(sc)
	var vb := VBoxContainer.new(); vb.name="VBoxContainer"
	vb.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation",3); sc.add_child(vb)

func _build_building_info(root: Control) -> void:
	var bi := PanelContainer.new(); bi.name="BuildingInfo"
	bi.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bi.anchor_top=1.0; bi.anchor_bottom=1.0
	bi.offset_left=230; bi.offset_top=-312; bi.offset_right=534; bi.offset_bottom=-4
	bi.visible=false
	bi.set_script(load("res://ui/BuildingInfo.gd") as GDScript)
	root.add_child(bi)

	var vb := VBoxContainer.new(); vb.name="VBox"; vb.add_theme_constant_override("separation",8); bi.add_child(vb)
	var trow := HBoxContainer.new(); trow.name="TitleRow"; vb.add_child(trow)
	var tl := Label.new(); tl.name="TitleLabel"; tl.text="Gebaeude"
	tl.size_flags_horizontal=Control.SIZE_EXPAND_FILL; tl.add_theme_font_size_override("font_size",14); trow.add_child(tl)
	var cl := Button.new(); cl.name="CloseBtn"; cl.text="X"; trow.add_child(cl)
	var sl:=Label.new(); sl.name="StatusLabel"; sl.text=""; vb.add_child(sl)
	# Feature (v11.11, Distrikt-System): zeigt, zu welchem Bezirk dieses
	# Gebaeude gehoert (nur sichtbar wenn district_id gesetzt ist, siehe
	# BuildingInfo._refresh()) - Farbe entspricht der Bezirksfarbe aus
	# DistrictSystem.gd.
	var distl:=Label.new(); distl.name="DistrictLabel"; distl.text=""; distl.visible=false
	distl.add_theme_font_size_override("font_size",11); vb.add_child(distl)
	# Bug-Fix/Feature (Arbeiter-Zuweisung manuell steuern): vorher nur ein
	# reines Anzeige-Label ("Arbeiter: 2/3") ohne Funktion. Jetzt mit "-"/"+"
	# Buttons, um direkt zu steuern, wie viele Frettchen hier arbeiten.
	var wrow:=HBoxContainer.new(); wrow.name="WorkerRow"; wrow.add_theme_constant_override("separation",6); vb.add_child(wrow)
	var wl:=Label.new(); wl.name="WorkersLabel"; wl.text=""; wl.size_flags_horizontal=Control.SIZE_EXPAND_FILL; wrow.add_child(wl)
	var wm:=Button.new(); wm.name="WorkerMinusBtn"; wm.text="-"; wm.custom_minimum_size=Vector2(30,0); wrow.add_child(wm)
	var wp:=Button.new(); wp.name="WorkerPlusBtn";  wp.text="+"; wp.custom_minimum_size=Vector2(30,0); wrow.add_child(wp)
	var dl:=Label.new(); dl.name="DescLabel"; dl.text=""
	dl.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; dl.add_theme_font_size_override("font_size",12)
	vb.add_child(dl)
	var pb:=ProgressBar.new(); pb.name="ProgressBar"; pb.custom_minimum_size=Vector2(0,14); vb.add_child(pb)
	# Feature (v11.1, Logistik-Feinschliff): Lagerhaeuser koennen auf eine
	# einzelne Ressource spezialisiert werden - nur diese wird dann von
	# Lagerarbeitern/Haulern dort eingelagert (siehe BuildingEntity.
	# storage_filter, accepts_resource()). "Alles" (Index 0) = unspezialisiert.
	var fr:=HBoxContainer.new(); fr.name="FilterRow"; fr.add_theme_constant_override("separation",6); vb.add_child(fr)
	var fl:=Label.new(); fl.name="FilterLabel"; fl.text="Filter:"; fr.add_child(fl)
	var fo:=OptionButton.new(); fo.name="FilterOption"; fo.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	fo.add_item("Alles", 0)
	for i in BuildingData.STORAGE_FILTER_OPTIONS.size():
		var rname: String = str(BuildingData.STORAGE_FILTER_OPTIONS[i])
		fo.add_item(str(BuildingData.RESOURCE_ICONS.get(rname,"?"))+" "+rname, i+1)
	fr.add_child(fo)
	var pr:=HBoxContainer.new(); pr.name="PriorityRow"; vb.add_child(pr)
	var pl:=Label.new(); pl.name="PriorityLabel"; pl.text="Prioritaet: 3"; pr.add_child(pl)
	var ps:=HSlider.new(); ps.name="PrioritySlider"; ps.min_value=1; ps.max_value=5; ps.step=1; ps.value=3
	ps.size_flags_horizontal=Control.SIZE_EXPAND_FILL; pr.add_child(ps)
	var brow:=HBoxContainer.new(); brow.name="Buttons"; vb.add_child(brow)
	for p2 in [["UpgradeBtn","Upgrade"],["SellBtn","Verkaufen"]]:
		var b:=Button.new(); b.name=p2[0]; b.text=p2[1]; b.size_flags_horizontal=Control.SIZE_EXPAND_FILL; brow.add_child(b)
	# Feature (Tech Tree): eigene Zeile fuer den Umbau-Button, da dessen Text
	# (Zielname + Kosten) meist zu lang fuer die Upgrade/Verkaufen-Reihe ist.
	var rbrow:=HBoxContainer.new(); rbrow.name="RebuildRow"; vb.add_child(rbrow)
	var rb:=Button.new(); rb.name="RebuildBtn"; rb.text="Umbauen"
	rb.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	rb.add_theme_font_size_override("font_size", 11); rbrow.add_child(rb)

## Bug-Fix (v10.14): ExpeditionPanel.gd baut seine UI komplett selbst dynamisch
## in _refresh() (siehe dort) - hier muss nur der PanelContainer mit Skript
## existieren und zentriert auf dem Bildschirm sitzen, standardmaessig
## versteckt (das macht das Panel selbst in _ready() via hide()).
func _build_expedition_panel(root: Control) -> void:
	var ep := PanelContainer.new(); ep.name = "ExpeditionPanel"
	ep.set_anchors_preset(Control.PRESET_CENTER)
	ep.offset_left = -170; ep.offset_top = -150; ep.offset_right = 170; ep.offset_bottom = 150
	ep.set_script(load("res://ui/ExpeditionPanel.gd") as GDScript)
	root.add_child(ep)

func _build_graveyard_panel(root: Control) -> void:
	var gp := PanelContainer.new(); gp.name = "GraveyardPanel"
	gp.set_anchors_preset(Control.PRESET_CENTER)
	gp.offset_left = -180; gp.offset_top = -160; gp.offset_right = 180; gp.offset_bottom = 160
	gp.set_script(load("res://ui/GraveyardPanel.gd") as GDScript)
	root.add_child(gp)

## Feature (Tech Tree): analog zu ExpeditionPanel/GraveyardPanel baut
## TechTreePanel.gd seine komplette UI dynamisch in _refresh() selbst auf -
## hier nur der leere PanelContainer mit Skript, zentriert, deutlich groesser
## als die anderen Panels (60 Tech-Knoten + Epochen-Uebersicht brauchen mehr
## Platz).
func _build_tech_tree_panel(root: Control) -> void:
	var tp := PanelContainer.new(); tp.name = "TechTreePanel"
	tp.set_anchors_preset(Control.PRESET_CENTER)
	# Feature (v11.12, Skilltree-Redesign): deutlich vergroessert - EIN
	# grosser, scrollbarer Baum statt kleiner Epochen-Unterseiten.
	tp.offset_left = -480; tp.offset_top = -380; tp.offset_right = 480; tp.offset_bottom = 380
	tp.set_script(load("res://ui/TechTreePanel.gd") as GDScript)
	root.add_child(tp)

## Feature (v11.8, Achievement-System): analog zu ExpeditionPanel/
## GraveyardPanel/TechTreePanel baut AchievementPanel.gd seine komplette UI
## dynamisch in _refresh() selbst auf - hier nur der leere PanelContainer.
func _build_achievement_panel(root: Control) -> void:
	var ap := PanelContainer.new(); ap.name = "AchievementPanel"
	ap.set_anchors_preset(Control.PRESET_CENTER)
	ap.offset_left = -260; ap.offset_top = -220; ap.offset_right = 260; ap.offset_bottom = 220
	ap.set_script(load("res://ui/AchievementPanel.gd") as GDScript)
	root.add_child(ap)

## Feature (v12.3, Tutorial-Ueberarbeitung): laeuft die gesamte Sitzung ueber
## im Hintergrund mit (siehe UnlockExplainer.gd) - kein manuelles
## open()/Toggle-Button noetig, reagiert selbststaendig auf
## GameState.tech_unlocked.
func _build_unlock_explainer(root: Control) -> void:
	var ue := PanelContainer.new(); ue.name = "UnlockExplainer"
	ue.set_script(load("res://ui/UnlockExplainer.gd") as GDScript)
	root.add_child(ue)

## Feature (v11.9, Frettchen-Klick-Interaktion): Profil-Panel fuer ein
## einzelnes angeklicktes Frettchen (siehe GameController._on_ferret_selected()).
## (v11.10: das vormalige Roster-Panel FerretsPanel.gd wurde auf Nutzerwunsch
## wieder entfernt, dieses Profil-Panel bleibt der einzige Weg, Frettchen-
## Details einzusehen - per Klick auf ein Frettchen in der 3D-Welt.)
func _build_ferret_profile_panel(root: Control) -> void:
	var fpp := PanelContainer.new(); fpp.name = "FerretProfilePanel"
	fpp.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	fpp.offset_left = 20; fpp.offset_top = -160; fpp.offset_right = 260; fpp.offset_bottom = 160
	fpp.set_script(load("res://ui/FerretProfilePanel.gd") as GDScript)
	root.add_child(fpp)

## Feature (v11.9, Legendäre Frettchen): eigene Full-Rect-Ebene fuer das
## klickbare "Frettchen wird legendaer"-Popup, analog zu
## _build_achievement_toast(). Wird von GameController per find_child() über
## den gesamten Baum gesucht (siehe _on_ferret_became_legendary()), daher ist
## der genaue Elternpfad hier nicht kritisch - nur der eindeutige Name.
func _build_legendary_toast(root: Control) -> void:
	var lt := Control.new(); lt.name = "LegendaryToast"
	lt.set_anchors_preset(Control.PRESET_FULL_RECT)
	lt.anchor_right = 1.0; lt.anchor_bottom = 1.0
	lt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lt.set_script(load("res://ui/LegendaryToast.gd") as GDScript)
	root.add_child(lt)

## Feature (v11.10, Dev Mode): kleines Werkzeug-Panel oben links, nur
## sichtbar wenn DevMode.enabled (siehe DevToolsPanel.gd/DevMode.gd).
func _build_dev_tools_panel(root: Control) -> void:
	var dt := PanelContainer.new(); dt.name = "DevToolsPanel"
	dt.set_anchors_preset(Control.PRESET_TOP_LEFT)
	dt.offset_left = 8; dt.offset_top = 8; dt.offset_right = 200; dt.offset_bottom = 8
	dt.set_script(load("res://ui/DevToolsPanel.gd") as GDScript)
	root.add_child(dt)

## Feature (v11.11, Distrikt-System):
func _build_district_panel(root: Control) -> void:
	var dp := PanelContainer.new(); dp.name = "DistrictPanel"
	dp.set_anchors_preset(Control.PRESET_CENTER)
	dp.offset_left = -220; dp.offset_top = -220; dp.offset_right = 220; dp.offset_bottom = 220
	dp.set_script(load("res://ui/DistrictPanel.gd") as GDScript)
	root.add_child(dp)

## Feature (v11.8, Achievement-System): eigene Full-Rect-Ebene fuer den
## auffaelligeren Freischalt-Popup-Effekt, analog zu _build_notifications().
func _build_achievement_toast(root: Control) -> void:
	var at := Control.new(); at.name = "AchievementToast"
	at.set_anchors_preset(Control.PRESET_FULL_RECT)
	at.anchor_right = 1.0; at.anchor_bottom = 1.0
	at.mouse_filter = Control.MOUSE_FILTER_IGNORE
	at.set_script(load("res://ui/AchievementToast.gd") as GDScript)
	root.add_child(at)

## Feature (v11.2, First-Person-Modus): eigene HUD-Ebene (Fadenkreuz,
## Interaktions-Prompt), getrennt von der normalen Kolonie-HUD.
func _build_fp_hud(root: Control) -> void:
	var fh := Control.new(); fh.name = "FPHud"
	fh.set_script(load("res://ui/FPHud.gd") as GDScript)
	root.add_child(fh)

## Feature (v11.2, First-Person-Modus): Overlay-Panel fuer die 5
## Ressourcen-Minispiele - mouse_filter MOUSE_FILTER_IGNORE in der Mitte des
## Baums waere falsch (das Panel muss Klicks/Eingaben fangen koennen, siehe
## MinigameOverlay.gd selbst), daher hier bewusst KEIN root.mouse_filter-
## Override gesetzt.
func _build_minigame_overlay(root: Control) -> void:
	var mo := Control.new(); mo.name = "MinigameOverlay"
	mo.set_script(load("res://ui/MinigameOverlay.gd") as GDScript)
	root.add_child(mo)

## Feature (v12.5, Touch-Controls): virtuelles Gamepad-Overlay.
## Wird als letztes Kind in den UI-Root gehängt, damit es über allen anderen
## UI-Panels liegt und immer klickbar bleibt.
func _build_touch_overlay(root: Control) -> void:
	var ov := Control.new(); ov.name = "TouchOverlay"
	ov.set_script(load("res://ui/TouchOverlay.gd") as GDScript)
	root.add_child(ov)

func _build_placement_hint(root: Control) -> void:
	var h := Label.new(); h.name="PlacementHint"
	h.set_anchors_preset(Control.PRESET_CENTER_TOP)
	h.anchor_left=0.5; h.anchor_right=0.5
	h.offset_left=-240; h.offset_top=44; h.offset_right=240; h.offset_bottom=70
	h.text="Klicken zum Platzieren  |  ESC = Abbrechen"
	h.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; h.visible=false
	h.add_theme_font_size_override("font_size",13)
	h.add_theme_color_override("font_color",Color(0.96,0.69,0.1))
	root.add_child(h)

func _build_pause_menu(root: Control) -> void:
	var cc := CenterContainer.new(); cc.name="PauseMenu"
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.anchor_right=1.0; cc.anchor_bottom=1.0; cc.visible=false
	cc.set_script(load("res://ui/PauseMenu.gd") as GDScript)
	root.add_child(cc)

	# Feature (v12.4): Zwei-Spalten-Layout angelehnt an das Pause-Menue von
	# Minecraft Bedrock Edition - links die eigentlichen Menue-Optionen,
	# rechts dauerhaft die Frettchen-Ich-Vorschau samt Ausruestung (siehe
	# ui/CharacterEditorPanel.gd, seit v12.4 kein eigenstaendiges Popup mehr).
	var row := HBoxContainer.new(); row.name="Row"; row.add_theme_constant_override("separation", 16)
	cc.add_child(row)

	var panel:=PanelContainer.new(); panel.name="Panel"; panel.custom_minimum_size=Vector2(320,0); row.add_child(panel)
	var vb:=VBoxContainer.new(); vb.name="VBox"; vb.add_theme_constant_override("separation",10); panel.add_child(vb)
	var tl:=Label.new(); tl.text="Pause"; tl.horizontal_alignment=1
	tl.add_theme_font_size_override("font_size",20); tl.add_theme_color_override("font_color",Color(0.96,0.69,0.1)); vb.add_child(tl)
	var rb:=Button.new(); rb.name="ResumeBtn"; rb.text="Weiterspielen"; rb.custom_minimum_size=Vector2(0,44); vb.add_child(rb)
	var ab:=VBoxContainer.new(); ab.name="Audio"; ab.add_theme_constant_override("separation",4); vb.add_child(ab)
	for p in [["MasterLabel","Master"],["MasterSlider",80.0],
					  ["MusicLabel","Musik"],["MusicSlider",60.0],
					  ["SfxLabel","Effekte"],["SfxSlider",70.0]]:
		if p[1] is String:
			ab.add_child(_lbl(p[1] as String, 12))
		else:
			var sl:=HSlider.new(); sl.name=p[0] as String; sl.min_value=0; sl.max_value=100; sl.value=p[1] as float; ab.add_child(sl)
	var sr:=HBoxContainer.new(); sr.name="Speed"; vb.add_child(sr)
	sr.add_child(_lbl("Geschwindigkeit:  ",13))
	for p2 in [["Btn1","1x"],["Btn2","2x"],["Btn3","3x"]]:
		var b:=Button.new(); b.name=p2[0]; b.text=p2[1]; sr.add_child(b)
	var svb:=Button.new(); svb.name="SaveBtn"; svb.text="Speichern"; svb.custom_minimum_size=Vector2(0,44); vb.add_child(svb)
	# Feature (v11.4, Speicherslot-System): "Speichern unter" erlaubt es, den
	# aktuellen Stand zusaetzlich unter einem neuen Namen als eigenen,
	# separaten Speicherstand abzulegen (statt nur den aktuellen Slot zu
	# ueberschreiben) - so lassen sich beliebig viele Welten/Zwischenstaende
	# parallel behalten.
	var sa_row := HBoxContainer.new(); sa_row.name="SaveAsRow"; sa_row.add_theme_constant_override("separation",6); vb.add_child(sa_row)
	var sa_input := LineEdit.new(); sa_input.name="SaveAsInput"; sa_input.placeholder_text="Neuer Name..."
	sa_input.custom_minimum_size = Vector2(180,36); sa_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sa_row.add_child(sa_input)
	var sa_btn := Button.new(); sa_btn.name="SaveAsBtn"; sa_btn.text="Speichern unter"; sa_btn.custom_minimum_size=Vector2(0,36)
	sa_row.add_child(sa_btn)
	var mb:=Button.new(); mb.name="MenuBtn"; mb.text="Hauptmenue"; mb.custom_minimum_size=Vector2(0,44); vb.add_child(mb)

	# Feature (v12.4): dauerhaft angedockte Frettchen-Ich-Vorschau.
	var cep := PanelContainer.new(); cep.name = "CharacterEditorPanel"
	cep.set_script(load("res://ui/CharacterEditorPanel.gd") as GDScript)
	row.add_child(cep)

	# Feature (v11.10, Dev Mode): Passwort-Eingabefeld in den Einstellungen -
	# bei korrektem Passwort ("frettchendev") wird DevMode.enabled aktiviert,
	# was an mehreren Stellen zusaetzliche Test-Funktionen einblendet (siehe
	# DevMode.gd fuer Details/Konvention). Rein clientseitig, kein
	# Sicherheitsfeature - nur ein Schutz vor versehentlichem Aktivieren.
	vb.add_child(HSeparator.new())
	var dev_row := HBoxContainer.new(); dev_row.name="DevModeRow"; dev_row.add_theme_constant_override("separation",6); vb.add_child(dev_row)
	var dev_input := LineEdit.new(); dev_input.name="DevPasswordInput"
	dev_input.placeholder_text = "Dev-Passwort..."; dev_input.secret = true
	dev_input.custom_minimum_size = Vector2(140,32); dev_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dev_row.add_child(dev_input)
	var dev_btn := Button.new(); dev_btn.name="DevModeBtn"; dev_btn.text="Aktivieren"; dev_btn.custom_minimum_size=Vector2(0,32)
	dev_row.add_child(dev_btn)
	var dev_status := Label.new(); dev_status.name="DevModeStatus"
	dev_status.text = "🛠️ Dev Mode: AUS"
	dev_status.add_theme_font_size_override("font_size", 10)
	dev_status.add_theme_color_override("font_color", Color(0.5,0.5,0.5))
	vb.add_child(dev_status)

func _build_notifications(root: Control) -> void:
	var nl:=Control.new(); nl.name="Notifications"
	nl.set_anchors_preset(Control.PRESET_FULL_RECT)
	nl.anchor_right=1.0; nl.anchor_bottom=1.0
	nl.mouse_filter=Control.MOUSE_FILTER_IGNORE
	nl.set_script(load("res://ui/NotificationLayer.gd") as GDScript)
	root.add_child(nl)

## Crash-Fix: richtiger Game-Over-Bildschirm statt stillem 5-Sekunden-Einfrieren.
func _build_game_over_screen(root: Control) -> void:
	_game_over_screen = Control.new(); _game_over_screen.name = "GameOverScreen"
	_game_over_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_over_screen.anchor_right = 1.0; _game_over_screen.anchor_bottom = 1.0
	_game_over_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	_game_over_screen.visible = false
	root.add_child(_game_over_screen)

	var bg := ColorRect.new(); bg.color = Color(0.04, 0.04, 0.06, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.anchor_right = 1.0; bg.anchor_bottom = 1.0
	_game_over_screen.add_child(bg)

	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.anchor_right = 1.0; cc.anchor_bottom = 1.0
	_game_over_screen.add_child(cc)

	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 14)
	cc.add_child(vb)

	var title := _lbl("Deine Kolonie ist ausgestorben...", 22, Color(0.95, 0.35, 0.30))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	_go_cause_label = _lbl("", 14, Color(0.85, 0.85, 0.85))
	_go_cause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_go_cause_label)

	vb.add_child(_spacer(10))
	var btn := _btn("Zum Hauptmenue")
	btn.pressed.connect(func(): GameState.set_state(GameState.State.MAIN_MENU))
	vb.add_child(btn)

## Tutorial wieder hinzugefuegt: Freddy Frettchen fuehrt neue Spieler durch
## die Grundlagen. Gestartet wird es in _on_start_game() (nur bei neuer
## Kolonie, nicht beim Laden eines Spielstands).
func _build_tutorial(root: Control) -> void:
	var tut := Control.new(); tut.name = "Tutorial"
	tut.set_script(load("res://ui/TutorialManager.gd") as GDScript)
	root.add_child(tut)


# ══════════════════════════════════════════════════════════════════════════════
# NAVIGATION
# ══════════════════════════════════════════════════════════════════════════════
func _show_main_menu() -> void:   GameState.set_state(GameState.State.MAIN_MENU)
func _show_world_creation() -> void: GameState.set_state(GameState.State.WORLD_CREATION)

func _on_start_game() -> void:
	var wname: String = _name_input.text.strip_edges()
	if wname == "": wname = "Meine Kolonie"
	var seed_str: String = _seed_input.text.strip_edges()
	const SIZES: Array = ["SMALL","MEDIUM","LARGE"]
	var sz: String = str(SIZES[_size_option.selected])
	_game_ctrl.call("start_new_game", sz, seed_str, wname)
	var tut := get_node_or_null("GameScreen/GameUI/UIRoot/Tutorial")
	if tut and tut.has_method("start"): tut.call("start")

## Feature (v11.14, Testwelt): laeuft automatisch ab - neue Welt mit festem
## Namen/Seed erzeugen, per bootstrap_test_colony() eine entwickelte Kolonie
## aufbauen, speichern, zurueck ins Hauptmenue (die Testwelt taucht danach
## ganz normal in "Welt laden" auf). _make_unique_save_slot() haengt bei
## einem Namenskonflikt automatisch "(2)"/"(3)"/... an - ein erneuter Klick
## ueberschreibt die vorherige Testwelt also NICHT, sondern legt eine
## weitere an (gleiches Verhalten wie bei zwei normalen Welten mit
## demselben eingegebenen Namen).
##
## Bug-Fix (v11.15): vorher liefen start_new_game() → bootstrap_test_colony()
## → save_now() → _show_main_menu() alle SYNCHRON in einem einzigen Frame
## (PLAYING- und MAIN_MENU-Zustand wechselten sich ab, bevor die Engine auch
## nur einen Frame Zeit hatte, irgendetwas davon fertig zu verarbeiten) -
## das fuehrte zu "Lambda capture at index 0 was freed"-Fehlern, vermutlich
## weil Renderer-/UI-Aufbauschritte (die intern u.a. Tweens/verzoegerte
## Callables nutzen) durch den sofortigen Ruecksprung ins Hauptmenue
## unterbrochen wurden, bevor sie fertig waren. Fix: zwischen den Phasen
## jeweils einen Frame abwarten (await get_tree().process_frame), damit die
## Engine jeden Schritt vollstaendig verarbeiten kann, bevor der naechste
## beginnt.
func _on_create_test_world() -> void:
	_game_ctrl.call("start_new_game", "MEDIUM", "testwelt-fix-seed", "Testwelt")
	await get_tree().process_frame
	await get_tree().process_frame
	_game_ctrl.call("bootstrap_test_colony")
	await get_tree().process_frame
	await get_tree().process_frame
	_game_ctrl.call("save_now")
	await get_tree().process_frame
	GameState.notify("Testwelt erstellt und gespeichert – unter „Welt laden“ zu finden.")
	_show_main_menu()

func _on_state_changed(state: GameState.State) -> void:
	_main_menu.visible     = (state == GameState.State.MAIN_MENU)
	_world_creation.visible = (state == GameState.State.WORLD_CREATION)
	# Feature (v11.4, Speicherslot-System): eigener Welt-Auswahl-Bildschirm.
	_load_screen.visible   = (state == GameState.State.LOAD_SCREEN)
	_game_screen.visible   = state in [GameState.State.PLAYING, GameState.State.PAUSED, GameState.State.GAME_OVER]
	if _game_over_screen: _game_over_screen.visible = (state == GameState.State.GAME_OVER)
