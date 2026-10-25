## Main.gd  –  baut die gesamte Szene zur Laufzeit auf.
## Kein .tscn-Layout, daher keine Anker-Bugs.
extends Node

var _main_menu:     Control
var _panorama:      PanoramaBackground = null
var _loading:       LoadingOverlay = null      # v15.8: Ladebildschirm mit laufendem Frettchen
var _intro:         IntroPlayer = null          # v15.9: Vollbild-Video-Intros (Menü + Story)
const MENU_INTRO_PATH: String = "res://assets/videos/intro_menu.ogv"
const STORY_INTRO_PATH: String = "res://assets/videos/intro_story.ogv"
var _world_creation: Control
var _game_screen:   Node3D
var _game_ctrl:     Node = null
var _game_over_screen: Control = null
var _go_cause_label:    Label   = null
# Feature (v11.4, Speicherslot-System): Welt-Auswahl-Bildschirm - listet alle
# benannten Speicherstände mit Kurzinfo (Tag/Jahreszeit/Bevölkerung/Seed) auf.
var _load_screen:    Control = null
var _load_list_vbox: VBoxContainer = null

func _ready() -> void:
	# v15.0: zentrales Theme (siehe UITheme.gd); wird zusätzlich direkt auf die obersten Controls gesetzt
	get_tree().root.theme = UITheme.get_theme()
	_panorama = PanoramaBackground.new(); _panorama.name = "Panorama"
	add_child(_panorama)
	_build_main_menu()
	_build_world_creation()
	_build_load_screen()
	_build_game_screen()
	GameState.state_changed.connect(_on_state_changed)
	# Crash-Fix (UI verschwindet + "Absturz" ins Hauptmenü): Game Over hatte
	# bisher KEINE eigene Anzeige - der Bildschirm fror für 5 Sekunden ein
	# (HUD/Bau-Menü blenden sich bei jedem Nicht-PLAYING-Zustand automatisch
	# aus) und sprang danach kommentarlos ins Hauptmenü. Das sah für
	# Spieler genau wie ein Absturz aus. Jetzt zeigt ein richtiger
	# Game-Over-Bildschirm den Grund an und der Spieler kehrt per Klick
	# bewusst ins Hauptmenü zurück.
	GameState.game_over_triggered.connect(_on_game_over_triggered)
	# v15.0: Das Window-Theme erreicht Controls unterhalb von Node/CanvasLayer NICHT
	# (Vererbung bricht an nicht-Control-Eltern ab) -> die obersten Controls bekommen es direkt.
	for top in [_main_menu, _world_creation, _load_screen]:
		if top: top.theme = UITheme.get_theme()
	# v15.8: Ladebildschirm in eigener CanvasLayer ganz oben (HUD liegt in layer 1)
	var load_layer := CanvasLayer.new(); load_layer.name = "LoadingLayer"; load_layer.layer = 100
	add_child(load_layer)
	_loading = LoadingOverlay.new(); _loading.name = "LoadingOverlay"
	load_layer.add_child(_loading)
	# v15.9: Menü-Intro (Vollbild-Video, skipbar) vor dem eigentlichen Hauptmenü.
	# Eigene Ebene über allem (Ladebildschirm liegt auf 100); danach nahtloser
	# Übergang: der letzte Video-Frame entspricht dem Menü-Hintergrund.
	var intro_layer := CanvasLayer.new(); intro_layer.name = "IntroLayer"; intro_layer.layer = 200
	add_child(intro_layer)
	_intro = IntroPlayer.new(); _intro.name = "IntroPlayer"
	intro_layer.add_child(_intro)
	_main_menu.visible = false
	_panorama.visible = false
	GameState.set_state(GameState.State.INTRO)
	await _intro.play(MENU_INTRO_PATH)
	_show_main_menu()

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

	var cc := CenterContainer.new(); _full_rect(cc); _main_menu.add_child(cc)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(380, 0)
	vbox.add_theme_constant_override("separation", 12)
	cc.add_child(vbox)

	var title_lbl := UITheme.lbl("FrettchenKolonie", "Display")
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lbl)
	var tag_lbl := UITheme.lbl("Gründe, baue und behüte deine Kolonie", "OnScene")
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(tag_lbl)
	vbox.add_child(_spacer(32))

	var nb := UITheme.btn("Neue Welt starten", "PrimaryButton", Vector2(0, 58))
	nb.pressed.connect(_show_world_creation); vbox.add_child(nb)
	var lb := UITheme.btn("Welt laden", "", Vector2(0, 50))
	lb.pressed.connect(_show_load_screen); vbox.add_child(lb)
	vbox.add_child(_spacer(4))

	# Nebenfunktionen bewusst leiser (Ghost) - Hauptaktion bleibt eindeutig
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row)
	var tb := UITheme.btn("Testwelt", "SceneButton", Vector2(0, 40))
	tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tb.pressed.connect(_on_create_test_world); row.add_child(tb)
	var touch_btn := UITheme.btn("", "SceneButton", Vector2(0, 40))
	touch_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var _update_touch_label := func() -> void:
		touch_btn.text = "Touch: %s" % ("an" if TouchControlsSettings.enabled else "aus")
	_update_touch_label.call()
	touch_btn.pressed.connect(func():
		TouchControlsSettings.toggle()
		_update_touch_label.call()
	)
	row.add_child(touch_btn)

	var gfx_btn := UITheme.btn("", "SceneButton", Vector2(0, 40))
	var _update_gfx := func() -> void:
		gfx_btn.text = "Grafik: %s" % ("Realistisch" if GraphicsSettings.realistic else "Standard")
	_update_gfx.call()
	gfx_btn.pressed.connect(func(): GraphicsSettings.set_realistic(not GraphicsSettings.realistic))
	GraphicsSettings.changed.connect(func():
		if is_instance_valid(gfx_btn): _update_gfx.call())
	vbox.add_child(gfx_btn)

	# Fußzeile
	var ver := UITheme.lbl("Version %s  ·  3D Edition" % str(ProjectSettings.get_setting("application/config/version", "")), "OnScene")
	ver.add_theme_font_size_override("font_size", 13)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	ver.offset_left = 24; ver.offset_bottom = -16; ver.offset_top = -40
	_main_menu.add_child(ver)

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

	var cc := CenterContainer.new(); _full_rect(cc); _world_creation.add_child(cc)
	var panel := UITheme.panel("Dialog"); panel.custom_minimum_size = Vector2(480, 0); cc.add_child(panel)
	var vbox := VBoxContainer.new(); vbox.add_theme_constant_override("separation", 8); panel.add_child(vbox)

	vbox.add_child(UITheme.lbl("Neue Welt erstellen", "Heading"))
	vbox.add_child(_spacer(8))

	vbox.add_child(UITheme.lbl("KOLONIENNAME", "Subheading"))
	_name_input = LineEdit.new(); _name_input.text = "Meine Kolonie"
	_name_input.custom_minimum_size = Vector2(0, 44); vbox.add_child(_name_input)
	vbox.add_child(_spacer(4))

	vbox.add_child(UITheme.lbl("SEED  (LEER = ZUFÄLLIG)", "Subheading"))
	_seed_input = LineEdit.new(); _seed_input.placeholder_text = "z. B. Wiesenhain"
	_seed_input.custom_minimum_size = Vector2(0, 44); vbox.add_child(_seed_input)
	_seed_preview = UITheme.lbl("Seed: Zufällig", "Muted"); vbox.add_child(_seed_preview)
	_seed_input.text_changed.connect(func(t: String):
		_seed_preview.text = "Seed-Hash: %d" % t.hash() if t.strip_edges()!="" else "Seed: Zufällig")
	vbox.add_child(_spacer(4))

	vbox.add_child(UITheme.lbl("WELTGRÖSSE", "Subheading"))
	_size_option = OptionButton.new(); _size_option.custom_minimum_size = Vector2(0, 44)
	for s in ["Klein (40x40)","Mittel (60x60)","Groß (80x80)","Entdecker (120x120, Nebel)"]: _size_option.add_item(s)
	_size_option.selected = 1; vbox.add_child(_size_option)
	vbox.add_child(_spacer(16))

	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 12); vbox.add_child(row)
	var bb := UITheme.btn("Zurück", "", Vector2(130, 52)); bb.pressed.connect(_show_main_menu); row.add_child(bb)
	var sb := UITheme.btn("Kolonie gründen", "PrimaryButton", Vector2(0, 52))
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.pressed.connect(_on_start_game); row.add_child(sb)

# ══════════════════════════════════════════════════════════════════════════════
# WELT-AUSWAHL / LADEN  (Feature v11.4, Speicherslot-System)
# Ersetzt den alten festen "quicksave"-Slot durch eine Liste aller benannten
# Speicherstände inkl. Kurzinfo (Tag, Jahreszeit, Bevölkerung, Seed,
# Weltgrösse, Speicherzeitpunkt) - anklickbar zum Laden, mit Löschen-Option.
# ══════════════════════════════════════════════════════════════════════════════
func _build_load_screen() -> void:
	_load_screen = Control.new(); _load_screen.name = "LoadScreen"
	_full_rect(_load_screen); _load_screen.visible = false
	add_child(_load_screen)

	var cc := CenterContainer.new(); _full_rect(cc); _load_screen.add_child(cc)
	var panel := UITheme.panel("Dialog"); panel.custom_minimum_size = Vector2(760, 0); cc.add_child(panel)
	var vbox := VBoxContainer.new(); vbox.add_theme_constant_override("separation", 8); panel.add_child(vbox)

	vbox.add_child(UITheme.lbl("Welt laden", "Heading"))
	vbox.add_child(_spacer(8))
	# Feature (v16.11, Welt-Export/-Import): Knopf zum Importieren einer
	# .fkw-Weltdaten-Datei (bzw. Weltcode auf Geraeten ohne Datei-Dialog).
	var imp_b := UITheme.btn("Weltcode importieren (.fkw)", "", Vector2(300, 48))
	imp_b.tooltip_text = "Eine Welt-Exportdatei (.fkw) importieren. Auf Geraeten ohne Datei-Dialog den Weltcode aus der Zwischenablage einfügen."
	imp_b.pressed.connect(_on_import_button)
	vbox.add_child(imp_b)
	vbox.add_child(_spacer(8))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_load_list_vbox = VBoxContainer.new(); _load_list_vbox.name = "LoadList"
	_load_list_vbox.add_theme_constant_override("separation", 8)
	_load_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_load_list_vbox)

	vbox.add_child(_spacer(8))
	var back := UITheme.btn("Zurück", "", Vector2(160, 48)); back.pressed.connect(_show_main_menu)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vbox.add_child(back)


func _show_load_screen() -> void:
	_refresh_load_list()
	GameState.set_state(GameState.State.LOAD_SCREEN)

## Baut die Liste aller Speicherstände neu auf (neueste zuerst).
func _refresh_load_list() -> void:
	for c in _load_list_vbox.get_children(): c.queue_free()
	var names: Array = SaveSys.get_save_names()
	var infos: Array = []
	for n in names:
		var info: Dictionary = SaveSys.get_save_info(n)
		if not info.is_empty(): infos.append(info)
	infos.sort_custom(func(a, b): return str(a.get("timestamp","")) > str(b.get("timestamp","")))
	if infos.is_empty():
		_load_list_vbox.add_child(_lbl("Keine Speicherstände vorhanden - starte zuerst eine neue Welt.", 14, Color(0.6,0.6,0.6)))
		return
	for info in infos:
		_load_list_vbox.add_child(_build_save_row(info))

## Baut eine einzelne Zeile der Welt-Auswahl-Liste (Name, Kurzinfo, Laden/Löschen).
func _build_save_row(info: Dictionary) -> Control:
	var slot: String = str(info.get("slot",""))
	var panel := UITheme.panel("Card")
	var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 16)
	panel.add_child(hb)

	var info_vb := VBoxContainer.new(); info_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vb.add_theme_constant_override("separation", 2)
	hb.add_child(info_vb)
	var name_l := UITheme.lbl(str(info.get("colony_name", slot)), "Heading")
	name_l.add_theme_font_size_override("font_size", 22)
	info_vb.add_child(name_l)
	var details := "Tag %d  ·  %s %s  ·  %d Frettchen  ·  Welt %dx%d" % [
		int(info.get("day_count",0)), str(info.get("season_icon","")), str(info.get("season_name","")),
		int(info.get("population",0)), int(info.get("world_w",0)), int(info.get("world_h",0))]
	info_vb.add_child(UITheme.lbl(details, "Muted"))
	info_vb.add_child(UITheme.lbl("Seed %d  ·  gespeichert %s" % [int(info.get("seed",0)), str(info.get("timestamp","")).replace("T", " ").left(16)], "Small"))

	var btn_vb := VBoxContainer.new(); btn_vb.add_theme_constant_override("separation", 6)
	hb.add_child(btn_vb)
	var load_b := UITheme.btn("Laden", "PrimaryButton", Vector2(120, 40))
	load_b.pressed.connect(func(): _load_from_slot(slot))
	btn_vb.add_child(load_b)
	# Feature (v16.11, Welt-Export/-Import): Export als .fkw pro Spalte.
	var exp_b := UITheme.btn("Export", "GhostButton", Vector2(120, 32))
	exp_b.tooltip_text = "Diese Welt als Datei exportieren (platzsparendes .fkw-Format)."
	exp_b.pressed.connect(func(): _export_slot_dialog(slot))
	btn_vb.add_child(exp_b)
	var del_b := UITheme.btn("Löschen", "GhostButton", Vector2(120, 32))
	del_b.add_theme_color_override("font_color", UITheme.C_DANGER)
	del_b.pressed.connect(func(): _confirm_delete_save(slot, del_b))
	btn_vb.add_child(del_b)

	return panel

func _confirm_delete_save(slot: String, btn: Button) -> void:
	if btn.get_meta("confirm", false):
		SaveSys.delete_save(slot)
		_refresh_load_list()
	else:
		btn.set_meta("confirm", true)
		btn.text = "Wirklich?!"
		# v14.6: Child-Timer statt get_tree().create_timer() (Projekt-Konvention)
		var _t: Timer = Timer.new()
		_t.one_shot = true; _t.wait_time = 3.0
		btn.add_child(_t)
		_t.timeout.connect(func():
			if is_instance_valid(btn):
				btn.set_meta("confirm", false); btn.text = "Löschen"
			_t.queue_free())
		_t.start()

## Lädt den gewählten Speicherstand und wechselt ins laufende Spiel.
func _load_from_slot(slot_name: String) -> void:
	# v15.8: mit Ladebalken (Frettchen läuft) statt eingefrorenem Bild
	var ctx: Dictionary = {}
	var steps: Array = SaveSys.load_game_steps(slot_name, _game_ctrl, ctx)
	await _loading.run("Spielstand wird geladen", steps, ctx)
	if not bool(ctx.get("ok", false)): return
	GameState.set_state(GameState.State.PLAYING)

# ══════════════════════════════════════════════════════════════════════════════
# Feature (v16.11, WELT-EXPORT/-IMPORT): eine Welt als platzsparende .fkw-Datei
# exportieren (Welt-Auswahl: pro Spalte; Pause-Menü: laufende Welt) und
# importieren (Welt-Auswahl: Datei-Dialog bzw. Weltcode).
# ══════════════════════════════════════════════════════════════════════════════
## Nativer Datei-Dialog verfügbar? (Windows/Android: ja; Tests/Headless: nein -
## dann bleibt der Weltcode-Zwischenablage-Weg, die UI meldet das ehrlich).
func _has_native_file_dialog() -> bool:
	return DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)

func _default_export_dir() -> String:
	var d: String = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if d.is_empty(): d = OS.get_user_data_dir()
	return d

## Wortlaut für den angebotenen Dateinamen ohne verbotene Zeichen.
func _export_file_name(raw: String) -> String:
	var clean: String = raw.strip_edges()
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		clean = clean.replace(ch, "")
	return clean.substr(0, 60)

func _export_slot_dialog(slot: String) -> void:
	if not _has_native_file_dialog():
		_meldung_kein_dateidialog()
		return
	DisplayServer.file_dialog_show("Welt exportieren", _default_export_dir(), _export_file_name(slot) + ".fkw",
		false, DisplayServer.FILE_DIALOG_MODE_SAVE_FILE,
		PackedStringArray(["*.fkw;FrettchenKolonie Weltdaten"]),
		func(ok: bool, files: PackedStringArray, _fi: int):
			if not ok or files.is_empty(): return
			var msg: String = SaveSys.export_fkw_file(slot, files[0])
			if msg != "":
				GameState.notify(msg, Color(0.8, 0.2, 0.1)))

## Export aus dem Pause-Menü: exportiert den JETZT laufenden Stand (auch mit
## noch nicht gespeicherten Änderungen), nicht den letzten Speicher-Zeipunkt.
func _export_current_dialog(default_name: String) -> void:
	if not _has_native_file_dialog():
		_meldung_kein_dateidialog()
		return
	DisplayServer.file_dialog_show("Welt exportieren", _default_export_dir(), _export_file_name(default_name) + ".fkw",
		false, DisplayServer.FILE_DIALOG_MODE_SAVE_FILE,
		PackedStringArray(["*.fkw;FrettchenKolonie Weltdaten"]),
		func(ok: bool, files: PackedStringArray, _fi: int):
			if not ok or files.is_empty(): return
			var msg: String = SaveSys.export_current_fkw(_game_ctrl, files[0])
			if msg != "":
				GameState.notify(msg, Color(0.8, 0.2, 0.1)))

func _meldung_kein_dateidialog() -> void:
	GameState.notify("Auf diesem Gerät gibt es keinen Datei-Dialog - benutze den Weltcode (Zwischenablage) zum Austausch.", Color(0.8, 0.2, 0.1))

## Import-Knopf über der Welt-Liste: .fkw-Datei auswählen (oder, wenn es
## keinen Datei-Dialog gibt, den Weltcode direkt einfügen).
func _on_import_button() -> void:
	if _has_native_file_dialog():
		DisplayServer.file_dialog_show("Welt-Datei öffnen", _default_export_dir(), "",
			false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
			PackedStringArray(["*.fkw;FrettchenKolonie Weltdaten"]),
			func(ok: bool, files: PackedStringArray, _fi: int):
				if not ok or files.is_empty(): return
				var pv: Dictionary = SaveSys.read_fkw_preview(files[0])
				if pv.has("err"):
					GameState.notify(str(pv["err"]), Color(0.8, 0.2, 0.1))
					return
				_show_import_dialog(pv, files[0], ""))
	else:
		_show_import_dialog({}, "", "")

## Bestätigungs-Fenster mit Vorschau (Name, Tag, Grösse, Bevölkerung,
## Spielversion) - inhaltlich gleich für Datei- und Weltcode-Wege.
func _show_import_dialog(preview: Dictionary, src_path: String, _pre_code: String) -> void:
	var dlg := CenterContainer.new()
	dlg.name = "ImportDialog"
	dlg.set_anchors_preset(Control.PRESET_FULL_RECT)
	dlg.theme = UITheme.get_theme()
	_load_screen.add_child(dlg)
	MenuManager.register(dlg)
	var panel := UITheme.panel("Dialog")
	panel.custom_minimum_size = Vector2(600, 0)
	dlg.add_child(panel)
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 8); panel.add_child(vb)
	vb.add_child(UITheme.lbl("Welt importieren", "Heading"))
	var code_edit: TextEdit = null
	if src_path.is_empty():
		# Ohne Datei-Dialog (z.B. Android): Weltcode aus der Zwischenablage.
		vb.add_child(UITheme.lbl("Kein Datei-Dialog verfügbar - füge hier den Weltcode ein (aus dem Export in die Zwischenablage gekommen):", "Muted"))
		code_edit = TextEdit.new()
		code_edit.custom_minimum_size = Vector2(0, 160)
		code_edit.placeholder_text = "FKW Weltcode hier einfügen ..."
		code_edit.wrap_mode = TextEdit.LINE_WRAPPING_NONE
		vb.add_child(code_edit)
	else:
		# Vorschau der Datei (aus dem Kopf, ohne Entpacken).
		vb.add_child(UITheme.lbl("Vorschau der Welt:", "Muted"))
		var info := "%s\nTag %d  ·  Welt %dx%d Kacheln  ·  %d Frettchen\nErstellt in Spielversion %s (Spielstand-Struktur v%d, Format v%d)" % [
			str(preview.get("name", "?")), int(preview.get("day", 0)), int(preview.get("w", 0)),
			int(preview.get("h", 0)), int(preview.get("pop", 0)), str(preview.get("game_version", "?")),
			int(preview.get("save_version", 0)), int(preview.get("format", 0))]
		var inf := UITheme.lbl(info, ""); inf.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(inf)
		vb.add_child(UITheme.lbl("Die Welt wird als neuer Spielstand beigelegt und dann normal geladen.", "Muted"))
	var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 8); vb.add_child(hb)
	var imp := UITheme.btn("Importieren", "PrimaryButton", Vector2(200, 48))
	imp.pressed.connect(func():
		var msg: String = ""
		if not src_path.is_empty():
			msg = SaveSys.import_fkw_file(src_path)
		else:
			if code_edit == null or code_edit.text.strip_edges().is_empty():
				GameState.notify("Bitte zuerst einen Weltcode einfügen.", Color(0.8, 0.2, 0.1))
				return
			msg = SaveSys.import_fkw_worldcode(code_edit.text)
		if msg != "":
			GameState.notify(msg, Color(0.8, 0.2, 0.1))
			return
		dlg.hide()
		_refresh_load_list())
	hb.add_child(imp)
	var cancel := UITheme.btn("Abbrechen", "GhostButton", Vector2(140, 48))
	cancel.pressed.connect(func(): dlg.hide())
	hb.add_child(cancel)

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

	# Feature (v11.2, First-Person-Modus): eigenständiger Spieler-Node,
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
	_build_colony_panel(ui_root)
	_build_line_panel(ui_root)
	_build_world_map_panel(ui_root)
	_build_neighbor_panel(ui_root)
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
	r.theme = UITheme.get_theme()   # v15.0: Theme-Vererbung endet an nicht-Control-Eltern (Node/CanvasLayer) -> hier setzen
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _build_hud(root: Control) -> void:
	var hud := Control.new(); hud.name = "HUD"
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.anchor_right = 1.0; hud.anchor_bottom = 1.0
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.set_script(load("res://ui/HUD.gd") as GDScript)
	root.add_child(hud)

	# ── Obere Leiste: Ressourcen links, Kapazitäten rechts ──
	var topbar := UITheme.panel("HudBar"); topbar.name = "TopBar"
	topbar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	topbar.anchor_right = 1.0; topbar.offset_bottom = 34
	hud.add_child(topbar)
	var row := HBoxContainer.new(); row.name = "Row"
	row.add_theme_constant_override("separation", 10); topbar.add_child(row)

	var rd := HBoxContainer.new(); rd.name = "ResourceDisplay"
	rd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rd.add_theme_constant_override("separation", 6); row.add_child(rd)

	for m in [["Storage", "📦 0/0", "StorageBar"], ["Water", "💧 0/0", "WaterBar"]]:
		var meter := VBoxContainer.new(); meter.name = m[0] + "Meter"
		meter.custom_minimum_size = Vector2(84, 0)
		meter.add_theme_constant_override("separation", 3)
		meter.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(meter)
		var tl := UITheme.lbl(m[1], "Chip"); tl.name = m[0] + "TextLabel"
		if m[0] == "Water": tl.add_theme_color_override("font_color", UITheme.C_WATER)
		meter.add_child(tl)
		var pb := ProgressBar.new(); pb.name = m[0] + "Bar"; pb.theme_type_variation = m[2]
		pb.show_percentage = false; pb.custom_minimum_size = Vector2(0, 4)
		meter.add_child(pb)

	for pair2b in [["BedsTextLabel", "🛏️ 0/0", UITheme.C_BEDS], ["ScienceTextLabel", "🔬 0", UITheme.C_SCIENCE]]:
		var tl2 := UITheme.lbl(pair2b[1], "Chip"); tl2.name = pair2b[0]
		tl2.add_theme_color_override("font_color", pair2b[2])
		row.add_child(tl2)

	# ── Rechte Spalte: Info, Geschwindigkeit, Werkzeuge ──
	var col := VBoxContainer.new(); col.name = "RightColumn"
	col.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	col.anchor_left = 1.0; col.anchor_right = 1.0
	col.offset_left = -184; col.offset_right = -8; col.offset_top = 42; col.offset_bottom = 43
	col.grow_horizontal = Control.GROW_DIRECTION_BEGIN   # wächst nach LINKS, nie über den Bildrand
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 6)
	hud.add_child(col)

	var info := UITheme.panel("FloatPanel"); info.name = "InfoPanel"; col.add_child(info)
	var ivb := VBoxContainer.new(); ivb.add_theme_constant_override("separation", 2)
	info.add_child(ivb)
	var time_l := UITheme.lbl("06:00", "Heading"); time_l.name = "TimeLabel"
	time_l.add_theme_font_size_override("font_size", 17); ivb.add_child(time_l)
	var irow := HBoxContainer.new(); irow.add_theme_constant_override("separation", 12); ivb.add_child(irow)
	var season_l := UITheme.lbl("Frühling", "Muted"); season_l.name = "SeasonLabel"; irow.add_child(season_l)
	var pop_l := UITheme.lbl("Frettchen: 5", "Muted"); pop_l.name = "PopLabel"; irow.add_child(pop_l)
	var drought_l := UITheme.lbl("", "Chip"); drought_l.name = "DroughtLabel"; drought_l.visible = false
	ivb.add_child(drought_l)

	var sp := UITheme.panel("FloatPanel"); sp.name = "SpeedPanel"; col.add_child(sp)
	var srow := HBoxContainer.new(); srow.name = "SpeedButtons"
	srow.add_theme_constant_override("separation", 4); sp.add_child(srow)
	var grp := ButtonGroup.new(); grp.allow_unpress = true
	for pair3 in [["PauseBtn", "II", "Pause"], ["Btn1", "1×", "Normale Geschwindigkeit"],
			["Btn2", "2×", "Doppelte Geschwindigkeit"], ["Btn3", "3×", "Dreifache Geschwindigkeit"]]:
		var b := UITheme.btn(pair3[1], "SegButton", Vector2(30, 26))
		b.add_theme_font_size_override("font_size", 13)
		b.name = pair3[0]; b.toggle_mode = true; b.button_group = grp
		b.tooltip_text = pair3[2]; b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		srow.add_child(b)

	var ep := UITheme.panel("FloatPanel"); ep.name = "ExtraPanel"; col.add_child(ep)
	ep.size_flags_horizontal = Control.SIZE_SHRINK_END      # schmal rechtsbündig statt volle Spaltenbreite
	var erow := GridContainer.new(); erow.name = "ExtraButtons"; erow.columns = 3   # 2 Zeilen x 3 statt 6 untereinander
	erow.add_theme_constant_override("h_separation", 4); erow.add_theme_constant_override("v_separation", 4); ep.add_child(erow)
	for pair4 in [["ExpeditionBtn", "🗺️", "Expeditionen"], ["GraveyardBtn", "🪦", "Gedenkstätte"],
			["TechTreeBtn", "🔬", "Forschung"], ["AchievementBtn", "🏆", "Erfolge"],
			["DistrictBtn", "🏘️", "Bezirke"], ["ColonyBtn", "🏛️", "Kolonien"], ["LineBtn", "🚂", "Linien & Züge"], ["WorldMapBtn", "🧭", "Weltkarte"], ["NeighborBtn", "🤝", "Nachbarn"],
			["FPModeBtn", "🦫", "Frettchen-Modus (Ich-Perspektive)"]]:
		var b4 := UITheme.btn(pair4[1], "IconButton", Vector2(34, 34))
		b4.name = pair4[0]; b4.tooltip_text = pair4[2]
		erow.add_child(b4)

func _build_build_menu(root: Control) -> void:
	var bm := UITheme.panel("FloatPanel"); bm.name = "BuildMenu"
	bm.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	bm.anchor_bottom = 1.0; bm.offset_left = 8; bm.offset_right = 216
	# Bug-Fix (UI-Überlappung: Ressourcenanzeige lag unter dem Bau-Menü):
	# Die TopBar (HUD) ist 38px hoch und geht über die volle Breite, das
	# Bau-Menü begann aber bei y=0 (volle Höhe) und wurde NACH dem HUD
	# hinzugefügt -> es lag über der TopBar in der oberen linken Ecke und
	# verdeckte Zeit/Jahreszeit/Ressourcen-Anzeige. Jetzt beginnt es erst
	# unterhalb der TopBar.
	bm.offset_top = 44; bm.offset_bottom = -8
	bm.set_script(load("res://ui/BuildMenu.gd") as GDScript)
	root.add_child(bm)

	var outer := VBoxContainer.new(); outer.name="Outer"; outer.size_flags_vertical=Control.SIZE_EXPAND_FILL; bm.add_child(outer)
	var hdr := HBoxContainer.new(); hdr.name="Header"; outer.add_child(hdr)
	# Bug-Fix (fehlender Epochen-Button): vorher nur ein Label ohne Funktion.
	# Jetzt ein klickbarer Button, der die nächste Epoche samt Kosten zeigt
	# und per Klick freischaltet, sobald genug Ressourcen vorhanden sind.
	var el := Button.new(); el.name="EpochBtn"; el.text="Epoche 1"
	el.add_theme_font_size_override("font_size", 13)
	el.size_flags_horizontal=Control.SIZE_EXPAND_FILL; hdr.add_child(el)
	var tb := Button.new(); tb.name="ToggleBtn"; tb.text="<<"; tb.theme_type_variation = "GhostButton"; tb.custom_minimum_size = Vector2(44, 0); tb.focus_mode = Control.FOCUS_NONE; hdr.add_child(tb)
	var sc := ScrollContainer.new(); sc.name="ScrollContainer"
	sc.size_flags_vertical=Control.SIZE_EXPAND_FILL; outer.add_child(sc)
	var vb := VBoxContainer.new(); vb.name="VBoxContainer"
	vb.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation",3); sc.add_child(vb)

func _build_building_info(root: Control) -> void:
	var bi := UITheme.panel("FloatPanel"); bi.name="BuildingInfo"
	bi.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bi.anchor_top=1.0; bi.anchor_bottom=1.0
	bi.offset_left=224; bi.offset_top=-312; bi.offset_right=528; bi.offset_bottom=-8
	bi.visible=false
	bi.set_script(load("res://ui/BuildingInfo.gd") as GDScript)
	root.add_child(bi)

	var vb := VBoxContainer.new(); vb.name="VBox"; vb.add_theme_constant_override("separation",8); bi.add_child(vb)
	var trow := HBoxContainer.new(); trow.name="TitleRow"; vb.add_child(trow)
	var tl := Label.new(); tl.name="TitleLabel"; tl.text="Gebäude"
	tl.size_flags_horizontal=Control.SIZE_EXPAND_FILL; tl.theme_type_variation="Heading"; tl.add_theme_font_size_override("font_size",20); tl.clip_text=true; trow.add_child(tl)
	var cl := UITheme.btn("X", "IconButton", Vector2(36, 36)); cl.name="CloseBtn"; trow.add_child(cl)
	var sl:=Label.new(); sl.name="StatusLabel"; sl.text=""; sl.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; vb.add_child(sl)
	# Feature (v11.11, Distrikt-System): zeigt, zu welchem Bezirk dieses
	# Gebäude gehört (nur sichtbar wenn district_id gesetzt ist, siehe
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
	# Feature (v11.1, Logistik-Feinschliff): Lagerhäuser können auf eine
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
	var pl:=Label.new(); pl.name="PriorityLabel"; pl.text="Priorität: 3"; pr.add_child(pl)
	var ps:=HSlider.new(); ps.name="PrioritySlider"; ps.min_value=1; ps.max_value=5; ps.step=1; ps.value=3
	ps.size_flags_horizontal=Control.SIZE_EXPAND_FILL; pr.add_child(ps)
	var brow:=HBoxContainer.new(); brow.name="Buttons"; vb.add_child(brow)
	for p2 in [["UpgradeBtn","Upgrade"],["SellBtn","Verkaufen"]]:
		var b:=Button.new(); b.name=p2[0]; b.text=p2[1]; b.size_flags_horizontal=Control.SIZE_EXPAND_FILL; brow.add_child(b)
	# Feature (Tech Tree): eigene Zeile für den Umbau-Button, da dessen Text
	# (Zielname + Kosten) meist zu lang für die Upgrade/Verkaufen-Reihe ist.
	var rbrow:=HBoxContainer.new(); rbrow.name="RebuildRow"; vb.add_child(rbrow)
	var rb:=Button.new(); rb.name="RebuildBtn"; rb.text="Umbauen"
	rb.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	rb.add_theme_font_size_override("font_size", 11); rbrow.add_child(rb)

## Bug-Fix (v10.14): ExpeditionPanel.gd baut seine UI komplett selbst dynamisch
## in _refresh() (siehe dort) - hier muss nur der PanelContainer mit Skript
## existieren und zentriert auf dem Bildschirm sitzen, standardmässig
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
## hier nur der leere PanelContainer mit Skript, zentriert, deutlich grösser
## als die anderen Panels (60 Tech-Knoten + Epochen-Übersicht brauchen mehr
## Platz).
func _build_tech_tree_panel(root: Control) -> void:
	var tp := PanelContainer.new(); tp.name = "TechTreePanel"
	# Bug-Fix (v14.2, gemeldet: "Feld ist zu groß und geht aus dem
	# Spielbereich hinaus"): das Panel hatte bisher eine FESTE Pixelgröße
	# (960×760, zentriert) - auf kleineren Fenstern/Bildschirmen (z.B.
	# 1280×720 oder schmaleren Fenstern) ragte es dadurch garantiert über
	# den sichtbaren Bereich hinaus. Jetzt relativ zur tatsächlichen
	# Fenstergröße verankert (92% Breite, 88% Höhe, zentriert) - passt sich
	# automatisch an jede Auflösung an und bleibt immer komplett sichtbar.
	tp.set_anchors_preset(Control.PRESET_FULL_RECT)
	tp.anchor_left = 0.04; tp.anchor_right = 0.96
	tp.anchor_top  = 0.06; tp.anchor_bottom = 0.94
	tp.offset_left = 0; tp.offset_right = 0; tp.offset_top = 0; tp.offset_bottom = 0
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

## Feature (v12.3, Tutorial-Überarbeitung): läuft die gesamte Sitzung über
## im Hintergrund mit (siehe UnlockExplainer.gd) - kein manuelles
## open()/Toggle-Button nötig, reagiert selbstständig auf
## GameState.tech_unlocked.
func _build_unlock_explainer(root: Control) -> void:
	var ü := PanelContainer.new(); ü.name = "UnlockExplainer"
	ü.set_script(load("res://ui/UnlockExplainer.gd") as GDScript)
	root.add_child(ü)

## Feature (v11.9, Frettchen-Klick-Interaktion): Profil-Panel für ein
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

## Feature (v11.9, Legendäre Frettchen): eigene Full-Rect-Ebene für das
## klickbare "Frettchen wird legendär"-Popup, analog zu
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

## Feature (v11.10, Dev Mode) / v16.5: Werkzeug-Fenster, nur sichtbar wenn DevMode.enabled
## (siehe DevToolsPanel.gd/DevMode.gd). Position und Größe setzt das Skript selbst: es dockt
## rechts UNTER der HUD-Spalte an, damit nichts überlappt.
func _build_dev_tools_panel(root: Control) -> void:
	var dt := PanelContainer.new(); dt.name = "DevToolsPanel"
	dt.set_script(load("res://ui/DevToolsPanel.gd") as GDScript)
	root.add_child(dt)

## Feature (v11.11, Distrikt-System):
func _build_district_panel(root: Control) -> void:
	var dp := PanelContainer.new(); dp.name = "DistrictPanel"
	dp.set_anchors_preset(Control.PRESET_CENTER)
	dp.offset_left = -220; dp.offset_top = -220; dp.offset_right = 220; dp.offset_bottom = 220
	dp.set_script(load("res://ui/DistrictPanel.gd") as GDScript)
	root.add_child(dp)

## Feature (v16.0, Kolonie-Fundament): Übersicht aller Kolonien.
func _build_colony_panel(root: Control) -> void:
	var cp := PanelContainer.new(); cp.name = "ColonyPanel"
	cp.set_anchors_preset(Control.PRESET_CENTER)
	cp.offset_left = -250; cp.offset_top = -230; cp.offset_right = 250; cp.offset_bottom = 230
	cp.set_script(load("res://ui/ColonyPanel.gd") as GDScript)
	root.add_child(cp)

## Feature (v16.7, Nachbarn): Nachbarkolonien-Fenster.
func _build_neighbor_panel(root: Control) -> void:
	var np := PanelContainer.new(); np.name = "NeighborPanel"
	np.set_anchors_preset(Control.PRESET_CENTER)
	np.offset_left = -290; np.offset_top = -310; np.offset_right = 290; np.offset_bottom = 310
	np.set_script(load("res://ui/NeighborPanel.gd") as GDScript)
	root.add_child(np)

## Feature (v16.6, Erkundung): Weltkarte.
func _build_world_map_panel(root: Control) -> void:
	var wm := PanelContainer.new(); wm.name = "WorldMapPanel"
	wm.set_anchors_preset(Control.PRESET_CENTER)
	wm.offset_left = -270; wm.offset_top = -330; wm.offset_right = 270; wm.offset_bottom = 330
	wm.set_script(load("res://ui/WorldMapPanel.gd") as GDScript)
	root.add_child(wm)

## Feature (v16.2, Schiene): Linien- und Zug-Fenster.
func _build_line_panel(root: Control) -> void:
	var lp := PanelContainer.new(); lp.name = "LinePanel"
	lp.set_anchors_preset(Control.PRESET_CENTER)
	lp.offset_left = -340; lp.offset_top = -290; lp.offset_right = 340; lp.offset_bottom = 290
	lp.set_script(load("res://ui/LinePanel.gd") as GDScript)
	root.add_child(lp)

## Feature (v11.8, Achievement-System): eigene Full-Rect-Ebene für den
## auffälligeren Freischalt-Popup-Effekt, analog zu _build_notifications().
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

## Feature (v11.2, First-Person-Modus): Overlay-Panel für die 5
## Ressourcen-Minispiele - mouse_filter MOUSE_FILTER_IGNORE in der Mitte des
## Baums wäre falsch (das Panel muss Klicks/Eingaben fangen können, siehe
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
	var pause_dim := ColorRect.new(); pause_dim.name = "PauseDim"
	pause_dim.color = Color(0.06, 0.04, 0.02, 0.55); pause_dim.visible = false
	pause_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(pause_dim)
	var cc := CenterContainer.new(); cc.name="PauseMenu"
	cc.visibility_changed.connect(func(): pause_dim.visible = cc.visible)
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.anchor_right=1.0; cc.anchor_bottom=1.0; cc.visible=false
	cc.set_script(load("res://ui/PauseMenu.gd") as GDScript)
	root.add_child(cc)

	# Feature (v12.4): Zwei-Spalten-Layout angelehnt an das Pause-Menü von
	# Minecraft Bedrock Edition - links die eigentlichen Menü-Optionen,
	# rechts dauerhaft die Frettchen-Ich-Vorschau samt Ausrüstung (siehe
	# ui/CharacterEditorPanel.gd, seit v12.4 kein eigenständiges Popup mehr).
	var row := HBoxContainer.new(); row.name="Row"; row.add_theme_constant_override("separation", 16)
	cc.add_child(row)

	var panel:=UITheme.panel("Dialog"); panel.name="Panel"; panel.custom_minimum_size=Vector2(360,0); row.add_child(panel)
	# v16.12-Hotfix (Nutzer-Meldung "UI geht aus dem Bild heraus"): Die VBox ist
	# durch Vollbild-Schalter + UI-Skala + Tutorial + Dev-Zeile hoeher als ein
	# 16:9-Viewport (720 vpx) - ein CenterContainer schneidet groessere Kinder
	# oben und unten schlicht ab. Scrollbereich innerhalb des Panels + Hoehen-
	# Kappe auf die Fensterhoehe im PauseMenu.gd (_fit_height).
	var psc := ScrollContainer.new(); psc.name = "Scroll"
	psc.custom_minimum_size = Vector2(360, 0)
	psc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(psc)
	var vb:=VBoxContainer.new(); vb.name="VBox"; vb.add_theme_constant_override("separation",6); psc.add_child(vb)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tl:=UITheme.lbl("Pause","Heading"); tl.horizontal_alignment=1; vb.add_child(tl)
	var rb:=Button.new(); rb.name="ResumeBtn"; rb.text="Weiterspielen"; rb.theme_type_variation="PrimaryButton"; rb.custom_minimum_size=Vector2(0,52); vb.add_child(rb)
	var ab:=VBoxContainer.new(); ab.name="Audio"; ab.add_theme_constant_override("separation",4); vb.add_child(ab)
	for p in [["MasterLabel","Master"],["MasterSlider",80.0],
					  ["MusicLabel","Musik"],["MusicSlider",60.0],
					  ["SfxLabel","Effekte"],["SfxSlider",70.0]]:
		if p[1] is String:
			ab.add_child(UITheme.lbl((p[1] as String).to_upper(), "Subheading"))
		else:
			var sl:=HSlider.new(); sl.name=p[0] as String; sl.min_value=0; sl.max_value=100; sl.value=p[1] as float; ab.add_child(sl)
	var sr:=HBoxContainer.new(); sr.name="Speed"; vb.add_child(sr)
	sr.add_child(UITheme.lbl("Geschwindigkeit", "Muted"))
	for p2 in [["Btn1","1x"],["Btn2","2x"],["Btn3","3x"]]:
		var b:=Button.new(); b.name=p2[0]; b.text=p2[1]; sr.add_child(b)
	# v15.4: schaltbarer Realismus-Modus (Himmel, Licht, Schatten, Tonemapping, Glow, SSAO ...)
	var gfx := CheckButton.new(); gfx.name = "RealismToggle"; gfx.text = "Realistische Grafik"
	gfx.tooltip_text = "Realistischer Himmel, wandernde Sonne, weiche Schatten, Bloom und Ambient Occlusion.\nKostet Leistung - bei schwächeren Geräten ausgeschaltet lassen."
	gfx.button_pressed = GraphicsSettings.realistic; gfx.focus_mode = Control.FOCUS_NONE
	gfx.toggled.connect(func(on: bool): GraphicsSettings.set_realistic(on))
	GraphicsSettings.changed.connect(func():
		if is_instance_valid(gfx): gfx.set_pressed_no_signal(GraphicsSettings.realistic))
	vb.add_child(gfx)
	# v15.7: UI-Größe (skaliert alle Oberflächen-Elemente, nicht die 3D-Welt)
	var ui_row := HBoxContainer.new(); ui_row.name = "UiScaleRow"; vb.add_child(ui_row)
	ui_row.add_child(UITheme.lbl("UI-Größe", "Muted"))
	var ui_opt := OptionButton.new(); ui_opt.name = "UiScaleOption"; ui_opt.focus_mode = Control.FOCUS_NONE
	ui_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for sc in GraphicsSettings.UI_SCALES: ui_opt.add_item("%d %%" % int(round(float(sc) * 100.0)))
	ui_opt.selected = GraphicsSettings.UI_SCALES.find(GraphicsSettings.ui_scale) if GraphicsSettings.UI_SCALES.has(GraphicsSettings.ui_scale) else 1
	ui_opt.item_selected.connect(func(i: int): GraphicsSettings.set_ui_scale(float(GraphicsSettings.UI_SCALES[i])))
	ui_row.add_child(ui_opt)
	# Feature (v16.12, Fenstermodus): Vollbild-Schalter im Pause-Menü, synchron
	# mit den Hotkeys F11 / Alt+Enter (GraphicsSettings._unhandled_key_input).
	var fs := CheckButton.new(); fs.name = "FullscreenToggle"; fs.text = "Vollbild (F11 / Alt+Enter)"
	fs.tooltip_text = "Fenster füllt den ganzen Bildschirm. Zurück mit erneutem F11,\nAlt+Enter oder dem Schalter hier. Die gemerkte Fenstergröße/Position\nbleibt für den normalen Fenstermodus erhalten."
	fs.focus_mode = Control.FOCUS_NONE
	fs.button_pressed = GraphicsSettings.window_fullscreen
	fs.toggled.connect(func(on: bool): GraphicsSettings.set_fullscreen(on))
	GraphicsSettings.changed.connect(func():
		if is_instance_valid(fs): fs.set_pressed_no_signal(GraphicsSettings.window_fullscreen)
		# UI-Groesse im Dropdown nachziehen (z. B. wenn set_ui_scale programmatisch laeuft)
		if is_instance_valid(ui_opt) and GraphicsSettings.UI_SCALES.has(GraphicsSettings.ui_scale):
			ui_opt.selected = GraphicsSettings.UI_SCALES.find(GraphicsSettings.ui_scale))
	vb.add_child(fs)
	var svb:=Button.new(); svb.name="SaveBtn"; svb.text="Speichern"; svb.custom_minimum_size=Vector2(0,44); vb.add_child(svb)
	# Feature (v11.4, Speicherslot-System): "Speichern unter" erlaubt es, den
	# aktuellen Stand zusätzlich unter einem neuen Namen als eigenen,
	# separaten Speicherstand abzulegen (statt nur den aktuellen Slot zu
	# überschreiben) - so lassen sich beliebig viele Welten/Zwischenstände
	# parallel behalten.
	var sa_row := HBoxContainer.new(); sa_row.name="SaveAsRow"; sa_row.add_theme_constant_override("separation",6); vb.add_child(sa_row)
	var sa_input := LineEdit.new(); sa_input.name="SaveAsInput"; sa_input.placeholder_text="Neuer Name..."
	sa_input.custom_minimum_size = Vector2(180,36); sa_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sa_row.add_child(sa_input)
	var sa_btn := Button.new(); sa_btn.name="SaveAsBtn"; sa_btn.text="Speichern unter"; sa_btn.custom_minimum_size=Vector2(0,36)
	sa_row.add_child(sa_btn)
	# Feature (v16.11, Welt-Export/-Import): die JETZT laufende Welt (auch mit
	# noch nicht gespeicherten Aenderungen) als .fkw-Datei nach Draussen geben.
	var xb:=Button.new(); xb.name="ExportBtn"; xb.text="Welt exportieren (.fkw)"; xb.custom_minimum_size=Vector2(0,36)
	vb.add_child(xb)
	var mb:=Button.new(); mb.name="MenuBtn"; mb.text="Hauptmenü"; mb.theme_type_variation="GhostButton"; mb.custom_minimum_size=Vector2(0,44); vb.add_child(mb)

	# Feature (v12.4): dauerhaft angedockte Frettchen-Ich-Vorschau.
	var cep := PanelContainer.new(); cep.name = "CharacterEditorPanel"
	cep.set_script(load("res://ui/CharacterEditorPanel.gd") as GDScript)
	row.add_child(cep)

	# Feature (v11.10, Dev Mode): Passwort-Eingabefeld in den Einstellungen -
	# bei korrektem Passwort ("frettchendev") wird DevMode.enabled aktiviert,
	# was an mehreren Stellen zusätzliche Test-Funktionen einblendet (siehe
	# DevMode.gd für Details/Konvention). Rein clientseitig, kein
	# Sicherheitsfeature - nur ein Schutz vor versehentlichem Aktivieren.
	# Feature (v16.5): Tutorial-Rundgänge jederzeit (wieder) starten
	vb.add_child(HSeparator.new())
	vb.add_child(UITheme.lbl("TUTORIAL", "Subheading"))
	var tut_row := HBoxContainer.new(); tut_row.name = "TutorialRow"; tut_row.add_theme_constant_override("separation", 4); vb.add_child(tut_row)
	for tp in [["TutBasicBtn", "Basis", "Tutorial: Grundlagen (Kamera, Bauen, Versorgung, Forschung)"], ["TutSystemsBtn", "Systeme", "Tutorial: Systeme (Bezirke, Wasser, Dürre, Jahreszeiten, Expeditionen)"], ["TutLogisticsBtn", "Logistik", "Tutorial: Kolonien & Schiene (Rathaus, Gleise, Linien, Mitfahren)"]]:
		var tbtn := Button.new(); tbtn.name = tp[0]; tbtn.text = tp[1]; tbtn.tooltip_text = tp[2]
		tbtn.custom_minimum_size = Vector2(0, 32); tbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tbtn.clip_text = true
		tut_row.add_child(tbtn)
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
	dev_status.theme_type_variation = "Small"
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

	var bg := ColorRect.new(); bg.color = Color(0.07, 0.05, 0.03, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.anchor_right = 1.0; bg.anchor_bottom = 1.0
	_game_over_screen.add_child(bg)

	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.anchor_right = 1.0; cc.anchor_bottom = 1.0
	_game_over_screen.add_child(cc)

	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 14)
	cc.add_child(vb)

	var title := UITheme.lbl("Deine Kolonie ist ausgestorben …", "Heading")
	title.add_theme_color_override("font_color", UITheme.C_DANGER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	_go_cause_label = UITheme.lbl("", "Muted")
	_go_cause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_go_cause_label)

	vb.add_child(_spacer(10))
	var btn := UITheme.btn("Zum Hauptmenü", "PrimaryButton", Vector2(280, 52))
	btn.pressed.connect(func(): GameState.set_state(GameState.State.MAIN_MENU))
	vb.add_child(btn)

## Tutorial wieder hinzugefügt: Freddy Frettchen führt neue Spieler durch
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
	const SIZES: Array = ["SMALL","MEDIUM","LARGE","HUGE"]
	var sz: String = str(SIZES[_size_option.selected])
	# v15.9: Story-Intro (25 s, skipbar) VOR dem Ladebalken; die Menü-Musik
	# pausiert solange, damit sie sich nicht mit der Video-Musik überlagert.
	SoundSys.pause_music()
	await _intro.play(STORY_INTRO_PATH)
	SoundSys.resume_music()
	# v15.8: mit Ladebalken (Frettchen läuft); der Spielstart besteht aus Schritten (siehe new_game_steps)
	var steps: Array = _game_ctrl.call("new_game_steps", sz, seed_str, wname)
	await _loading.run("Welt wird erstellt", steps)
	# Feature (v13.1, Bugfix): Tutorial nur beim allerersten Spielstart,
	# nicht bei jeder neuen Welt. Spieler würde sonst bei jedem "Neue Welt"
	# wieder im Tutorial stecken.
	# TODO: Dies könnnte später durch ein "Anfänger-Modus" Flag ersetzt werden
	# v16.5: jetzt aktiv - die Grundlagen starten beim allerersten Spielstart von selbst
	# (Fortschritt in user://tutorial.cfg; überspringen zählt als erledigt). Die übrigen
	# Rundgänge gibt es im Pause-Menü.
	var tut: Node = find_child("Tutorial", true, false)
	if tut != null and tut.has_method("maybe_autostart"): tut.call_deferred("maybe_autostart")

## Feature (v11.14, Testwelt): läuft automatisch ab - neue Welt mit festem
## Namen/Seed erzeugen, per bootstrap_test_colony() eine entwickelte Kolonie
## aufbauen, speichern, zurück ins Hauptmenü (die Testwelt taucht danach
## ganz normal in "Welt laden" auf). _make_unique_save_slot() hängt bei
## einem Namenskonflikt automatisch "(2)"/"(3)"/... an - ein erneuter Klick
## überschreibt die vorherige Testwelt also NICHT, sondern legt eine
## weitere an (gleiches Verhalten wie bei zwei normalen Welten mit
## demselben eingegebenen Namen).
##
## Bug-Fix (v11.15): vorher liefen start_new_game() → bootstrap_test_colony()
## → save_now() → _show_main_menu() alle SYNCHRON in einem einzigen Frame
## (PLAYING- und MAIN_MENU-Zustand wechselten sich ab, bevor die Engine auch
## nur einen Frame Zeit hatte, irgendetwas davon fertig zu verarbeiten) -
## das führte zu "Lambda capture at index 0 was freed"-Fehlern, vermutlich
## weil Renderer-/UI-Aufbauschritte (die intern u.a. Tweens/verzögerte
## Callables nutzen) durch den sofortigen Rücksprung ins Hauptmenü
## unterbrochen wurden, bevor sie fertig waren. Fix: zwischen den Phasen
## jeweils einen Frame abwarten (await get_tree().process_frame), damit die
## Engine jeden Schritt vollständig verarbeiten kann, bevor der nächste
## beginnt.
func _on_create_test_world() -> void:
	# v15.8: alle Phasen als Ladeschritte (zwischen den Schritten werden Bilder gezeichnet - das ersetzt
	# die früheren Einzel-Frame-Pausen aus dem v11.15-Fix und zeigt den Fortschritt als laufendes Frettchen)
	var steps: Array = _game_ctrl.call("new_game_steps", "MEDIUM", "testwelt-fix-seed", "Testwelt")
	steps.append({"label": "Testkolonie wird bevölkert …", "weight": 30.0, "fn": func(): _game_ctrl.call("bootstrap_test_colony")})
	steps.append({"label": "Spielstand wird gespeichert …", "weight": 8.0, "fn": func(): _game_ctrl.call("save_now")})
	await _loading.run("Testwelt wird erstellt", steps)
	GameState.notify("Testwelt erstellt und gespeichert – unter „Welt laden“ zu finden.")
	_show_main_menu()

func _on_state_changed(state: GameState.State) -> void:
	_main_menu.visible     = (state == GameState.State.MAIN_MENU)
	# Panorama nur in den Menüs; Dialog-Seiten dunkeln es leicht ab (Lesbarkeit)
	if _panorama:
		_panorama.visible = state in [GameState.State.MAIN_MENU, GameState.State.WORLD_CREATION, GameState.State.LOAD_SCREEN]
		_panorama.set_dim(0.0 if state == GameState.State.MAIN_MENU else 0.38)
	_world_creation.visible = (state == GameState.State.WORLD_CREATION)
	# Feature (v11.4, Speicherslot-System): eigener Welt-Auswahl-Bildschirm.
	_load_screen.visible   = (state == GameState.State.LOAD_SCREEN)
	_game_screen.visible   = state in [GameState.State.PLAYING, GameState.State.PAUSED, GameState.State.GAME_OVER]
	if _game_over_screen: _game_over_screen.visible = (state == GameState.State.GAME_OVER)
