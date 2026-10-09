extends Node
func _ready() -> void:
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate(); add_child(main)
	for i in 5: await get_tree().process_frame
	GraphicsSettings.set_realistic(false)
	var gc = main.get("_game_ctrl")
	gc.call("start_new_game", "SMALL", "qa-seed", "QA")
	for i in 25: await get_tree().process_frame
	UISounds.suppress_windows = false
	UISounds.play_log.clear()
	var root = gc.get_node("GameUI/UIRoot")
	print("[SND] Streams geladen: ", UISounds._streams.size(), " von ", UISounds.NAMES.size())
	# 1) normaler Button -> click
	var sp = root.find_child("Btn2", true, false) as Button
	sp.emit_signal("pressed"); await get_tree().process_frame; await get_tree().process_frame
	print("[SND] Button Btn2 pressed -> ", UISounds.play_log)
	UISounds.play_log.clear(); await get_tree().create_timer(0.1).timeout
	# 2) Hover
	sp.emit_signal("mouse_entered"); print("[SND] Hover -> ", UISounds.play_log)
	UISounds.play_log.clear(); await get_tree().create_timer(0.1).timeout
	# 3) Schalter (CheckButton RealismToggle) an/aus
	var cb = root.find_child("RealismToggle", true, false) as CheckButton
	cb.set_pressed_no_signal(false)
	cb.button_pressed = true; await get_tree().process_frame
	cb.button_pressed = false; await get_tree().process_frame
	print("[SND] Schalter an/aus -> ", UISounds.play_log)
	UISounds.play_log.clear()
	GraphicsSettings.set_realistic(false)
	# 4) Fenster: TechTree öffnen und schließen
	var tp = root.find_child("TechTreePanel", true, false)
	tp.call("open"); await get_tree().process_frame
	tp.visible = false; await get_tree().process_frame
	print("[SND] Fenster öffnen/schließen -> ", UISounds.play_log)
	UISounds.play_log.clear()
	# 5) Klick, der ein Fenster öffnet: nur Fenster-Ton, kein Klick davor
	var tb = root.find_child("TechTreeBtn", true, false) as Button
	for c in tb.pressed.get_connections(): pass
	tb.emit_signal("pressed"); await get_tree().process_frame; await get_tree().process_frame
	print("[SND] Knopf der ein Fenster öffnet -> ", UISounds.play_log, " (Fenster sichtbar: ", tp.visible, ")")
	UISounds.play_log.clear()
	tp.visible = false; await get_tree().process_frame; UISounds.play_log.clear()
	# 6) Slider-Tick nur beim Ziehen
	var sl = root.find_child("Master", true, false)
	var hs: HSlider = null
	for n in root.find_children("*", "HSlider", true, false): hs = n; break
	hs.value = hs.min_value; await get_tree().process_frame
	UISounds.play_log.clear()
	hs.value = hs.max_value; await get_tree().process_frame
	print("[SND] Slider (", hs.min_value, "-", hs.max_value, ") ohne Ziehen -> ", UISounds.play_log)
	hs.emit_signal("drag_started"); hs.value = hs.min_value; await get_tree().process_frame
	print("[SND] Slider beim Ziehen -> ", UISounds.play_log)
	UISounds.play_log.clear()
	# 7) rote Meldung -> Fehler; grüne nicht
	GameState.notify("Test", Color(0.8, 0.2, 0.1)); GameState.notify("ok", Color(0.18, 0.38, 0.18, 0.92))
	print("[SND] Meldungen rot/grün -> ", UISounds.play_log)
	UISounds.play_log.clear()
	# 8) Lautstärke 0 -> still
	var old = SoundSys.sfx_vol; SoundSys.sfx_vol = 0.0; UISounds.play("click"); print("[SND] sfx_vol=0 -> ", UISounds.play_log); SoundSys.sfx_vol = old
	get_tree().quit()
