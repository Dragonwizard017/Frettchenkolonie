## PauseMenu.gd
extends CenterContainer

var _vol_master: HSlider = null
var _vol_music: HSlider  = null
var _vol_sfx: HSlider    = null
# v16.12-Hotfix ("UI geht aus dem Bild heraus"): linker Panel-Inhalt ist seit
# v16.12 (Vollbild-Schalter + Tutorial + Dev-Zeile) hoeher als der Viewport.
# Der ScrollContainer kapsst die Panel-Hoehe auf die Fensterhoehe; siehe
# Main.gd/_build_pause_menu fuer den Layout-Umbau.
var _scroll: ScrollContainer = null

func _ready() -> void:
	hide()
	MenuManager.register(self)
	GameState.state_changed.connect(_on_state_changed)
	# Bug-Fix (v13.8, KRITISCH - gemeldet: "Pausenmenü funktioniert nicht,
	# weder Lautstärke noch Weiterspielen noch sonst etwas"):
	# Main.gd._build_pause_menu() packt seit v12.4 (Zwei-Spalten-Layout mit
	# Frettchen-Ich-Vorschau) alle Menü-Elemente in eine zusätzliche
	# HBoxContainer "Row" -> Row/Panel/Scroll/VBox/... statt Panel/VBox/...
	# Diese Datei wurde beim damaligen Umbau nie mitaktualisiert und hat
	# seitdem ALLE Buttons/Regler über die alten, falschen Pfade
	# "Panel/VBox/..." gesucht. get_node_or_null() gibt bei falschem Pfad
	# still `null` zurück (keine Fehlermeldung), _connect_btn() überspringt
	# dann einfach die Verbindung - das Menü sah normal aus, aber
	# wortwörtlich KEIN Button und KEIN Regler hatte je eine Funktion.
	# Jetzt auf die tatsächlichen Pfade "Row/Panel/Scroll/VBox/..." korrigiert.
	_vol_master = get_node_or_null("Row/Panel/Scroll/VBox/Audio/MasterSlider")
	_vol_music  = get_node_or_null("Row/Panel/Scroll/VBox/Audio/MusicSlider")
	_vol_sfx    = get_node_or_null("Row/Panel/Scroll/VBox/Audio/SfxSlider")
	_connect_btn("Row/Panel/Scroll/VBox/ResumeBtn", func(): _on_resume())
	_connect_btn("Row/Panel/Scroll/VBox/SaveBtn",   func(): _on_save())
	# Feature (v11.4, Speicherslot-System): "Speichern unter" legt einen neuen,
	# zusätzlichen benannten Speicherstand an, ohne den aktuellen Slot zu überschreiben.
	_connect_btn("Row/Panel/Scroll/VBox/SaveAsRow/SaveAsBtn", func(): _on_save_as())
	# Feature (v16.11, Welt-Export/-Import): laufende Welt als .fkw exportieren.
	_connect_btn("Row/Panel/Scroll/VBox/ExportBtn", func(): _on_export())
	_connect_btn("Row/Panel/Scroll/VBox/MenuBtn",   func(): _on_main_menu())
	_connect_btn("Row/Panel/Scroll/VBox/Speed/Btn1", func(): GameState.set_game_speed(1.0))
	_connect_btn("Row/Panel/Scroll/VBox/Speed/Btn2", func(): GameState.set_game_speed(2.0))
	_connect_btn("Row/Panel/Scroll/VBox/Speed/Btn3", func(): GameState.set_game_speed(3.0))
	# Feature (v11.10, Dev Mode):
	_connect_btn("Row/Panel/Scroll/VBox/DevModeRow/DevModeBtn", func(): _on_dev_mode_activate())
	# Feature (v16.5): Tutorial-Rundgänge
	_connect_btn("Row/Panel/Scroll/VBox/TutorialRow/TutBasicBtn", func(): _on_tutorial("basic"))
	_connect_btn("Row/Panel/Scroll/VBox/TutorialRow/TutSystemsBtn", func(): _on_tutorial("systems"))
	_connect_btn("Row/Panel/Scroll/VBox/TutorialRow/TutLogisticsBtn", func(): _on_tutorial("logistics"))
	_update_dev_mode_status()
	_scroll = get_node_or_null("Row/Panel/Scroll")
	if _scroll:
		# Hoehe nachziehen, wenn das Fenster (expand! -> Viewport height variiert),
		# die UI-Skala oder die Panel-Mindesthoehe sich aendert.
		resized.connect(_fit_height)
		get_viewport().size_changed.connect(_fit_height)
	if _vol_master: _vol_master.value_changed.connect(func(_v): _update_volumes())
	if _vol_music:  _vol_music.value_changed.connect(func(_v): _update_volumes())
	if _vol_sfx:    _vol_sfx.value_changed.connect(func(_v): _update_volumes())
	_fit_height.call_deferred()

## v16.12-Hotfix: Panel nie hoeher machen als das Fenster. CenterContainer
## zentriert Kinder auf deren Mindestgroesse - eine zu hohe VBox wuerde oben
## und unten aus dem Bild laufen. Die Scroll-Hoehe = min(Inhalt, Fenster - Rand).
func _fit_height() -> void:
	if _scroll == null:
		return
	var vb: Control = get_node_or_null("Row/Panel/Scroll/VBox")
	if vb == null:
		return
	var content: float = vb.get_combined_minimum_size().y
	# WICHTIG: _avail NICHT aus pm/pm.size lesen - CenterContainer kann wegen
	# der Panel-Mindesthoehe nicht unter deren Min schrumpfen (Sackgasse:
	# custom_min folgt der eingefrorenen Groesse). Die Viewport-Hoehe ist
	# immer verlaesslich (canvas_items+expand: hier in Canvas-Pixel).
	var avail: float = maxf(get_viewport_rect().size.y - 24.0, 160.0)
	var new_h: float = minf(content, avail)
	if not is_equal_approx(_scroll.custom_minimum_size.y, new_h):
		_scroll.custom_minimum_size.y = new_h
		# Nach dem neuen Layout erneut ansetzen: die Min-Groessen-Kaskade
		# (Scroll -> Panel -> Row -> CenterContainer) kann sonst einen
		# veralteten Viewport-Stand einfrieren (u.a. bei UI-Skalawechsel).
		_fit_height.call_deferred()

func _connect_btn(path: String, cb: Callable) -> void:
	var btn: Button = get_node_or_null(path)
	if btn:
		btn.pressed.connect(cb)
	else:
		# Hätte den oben behobenen Bug beim nächsten Mal sofort im
		# Godot-Output-Fenster sichtbar gemacht, statt still zu verschwinden.
		push_warning("PauseMenu: Button nicht gefunden unter Pfad '%s'" % path)

## Pause beenden und den gewählten Tutorial-Rundgang starten.
func _on_tutorial(track: String) -> void:
	_on_resume()
	var tut: Node = get_tree().root.find_child("Tutorial", true, false)
	if tut != null and tut.has_method("start"):
		tut.call_deferred("start", track)

func _on_resume() -> void:
	GameState.set_state(GameState.State.PLAYING)
	# v14.6: gewählte Geschwindigkeit (2x/3x) behalten statt immer auf 1x zu setzen
	if GameState.game_speed <= 0.0:
		GameState.game_speed = GameState._speed_before_pause if GameState._speed_before_pause > 0.0 else 1.0

## Feature (v11.4, Speicherslot-System): schreibt jetzt in den zur Kolonie
## gehörenden, benannten Slot zurück (statt in einen festen "quicksave"-Slot),
## sodass jede Welt ihren eigenen Speicherstand behält.
func _on_save() -> void:
	var gc: Node = get_node_or_null("/root/Main/GameScreen")
	if gc == null: return
	var slot: String = str(gc.current_save_slot)
	if slot.is_empty():
		slot = str(gc.current_world_name) if str(gc.current_world_name) != "" else "Kolonie"
		gc.current_save_slot = slot
	SaveSys.save(slot, gc)

## Feature (v11.4, Speicherslot-System): speichert den aktuellen Stand
## zusätzlich unter einem neuen Namen als eigenen Speicherstand.
func _on_save_as() -> void:
	var gc: Node = get_node_or_null("/root/Main/GameScreen")
	var input: LineEdit = get_node_or_null("Row/Panel/Scroll/VBox/SaveAsRow/SaveAsInput")
	if gc == null or input == null: return
	var raw_name: String = input.text.strip_edges()
	if raw_name.is_empty():
		GameState.notify("Bitte zuerst einen Namen eingeben.", Color(0.8,0.2,0.1)); return
	var new_slot: String = str(gc.call("_make_unique_save_slot", raw_name))
	gc.current_save_slot = new_slot
	gc.current_world_name = raw_name
	SaveSys.save(new_slot, gc)
	input.text = ""

## Feature (v16.11, Welt-Export/-Import): die laufende Welt als .fkw nach
## Draussen geben. Delegiert an Main.gd (dort liegen der Datei-Dialog und die
## Vorschau/Konventionen), ohne laufende Simulationen zu unterbrechen.
func _on_export() -> void:
	var gc: Node = get_node_or_null("/root/Main/GameScreen")
	var main: Node = get_node_or_null("/root/Main")
	if gc == null or main == null: return
	var name_base: String = str(gc.current_save_slot)
	if name_base.is_empty(): name_base = str(gc.current_world_name)
	main.call("_export_current_dialog", name_base)

func _on_main_menu() -> void:
	SoundSys.stop_music()
	GameState.set_state(GameState.State.MAIN_MENU)

func _update_volumes() -> void:
	SoundSys.set_volumes(
		_vol_master.value if _vol_master else 80.0,
		_vol_music.value  if _vol_music  else 60.0,
		_vol_sfx.value    if _vol_sfx    else 70.0
	)

## Feature (v11.10, Dev Mode): Passwort-Eingabefeld in den Einstellungen -
## siehe DevMode.gd für die eigentliche Freischalt-Logik/Konvention.
func _on_dev_mode_activate() -> void:
	var input: LineEdit = get_node_or_null("Row/Panel/Scroll/VBox/DevModeRow/DevPasswordInput")
	if input == null: return
	if DevMode.try_enable(input.text):
		GameState.notify("🛠️ Dev Mode aktiviert!", Color(0.3, 0.85, 0.4))
	else:
		GameState.notify("Falsches Passwort.", Color(0.8, 0.2, 0.1))
	input.text = ""
	_update_dev_mode_status()

func _update_dev_mode_status() -> void:
	var status: Label = get_node_or_null("Row/Panel/Scroll/VBox/DevModeStatus")
	if status == null: return
	if DevMode.enabled:
		status.text = "🛠️ Dev Mode: AN"
		status.add_theme_color_override("font_color", Color(0.3, 0.85, 0.4))
	else:
		status.text = "🛠️ Dev Mode: AUS"
		status.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

func _on_state_changed(state: GameState.State) -> void:
	visible = (state == GameState.State.PAUSED)
	# Feature (v11.4, Speicherslot-System): Save-Button zeigt den Namen der
	# aktuellen Kolonie, damit klar ist, in welchen Slot "Speichern" schreibt.
	if visible:
		var gc: Node = get_node_or_null("/root/Main/GameScreen")
		var save_btn: Button = get_node_or_null("Row/Panel/Scroll/VBox/SaveBtn")
		if gc and save_btn:
			save_btn.text = "Speichern: " + str(gc.current_world_name)
		_update_dev_mode_status()
		# Fensterhoehen-Kappe erst nach dem Layout-Lauf ansetzen
		_fit_height.call_deferred()
