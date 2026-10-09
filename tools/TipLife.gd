extends Node
func _ready() -> void:
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate(); add_child(main)
	for i in 5: await get_tree().process_frame
	GraphicsSettings.set_realistic(false)
	var gc = main.get("_game_ctrl")
	gc.call("start_new_game", "SMALL", "qa-seed", "QA")
	gc.call("bootstrap_test_colony")
	for i in 20: await get_tree().process_frame
	var bm = gc.get_node("GameUI/UIRoot/BuildMenu")
	bm.call("refresh"); await get_tree().process_frame; await get_tree().process_frame
	# einen echten Gebäude-Eintrag wählen
	var btn: Control = null
	for c in bm._container.get_children():
		if c.has_meta("bid"): btn = c; break
	var bid: String = str(btn.get_meta("bid"))
	bm.debug_mouse = btn.get_global_rect().get_center()       # Maus liegt auf dem Eintrag
	bm.call("_tip_request", btn, bid)
	await get_tree().create_timer(0.5).timeout
	print("[TIPLIFE] nach Hover: sichtbar=", bm._tip.visible, " (Eintrag ", bid, ")")
	for k in 40:
		bm.call("refresh", true)                               # erzwungener Neuaufbau
		for i in 3: await get_tree().process_frame
		await get_tree().create_timer(0.25).timeout           # Wächter-Timer läuft dazwischen
		if not bm._tip.visible: print("[TIPLIFE] FEHLER: nach Neuaufbau ", k + 1, " unsichtbar")
	print("[TIPLIFE] 40 Neuaufbauten überstanden: sichtbar=", bm._tip.visible)
	bm.debug_mouse = Vector2(900, 600)                         # Maus weg
	await get_tree().create_timer(0.35).timeout
	print("[TIPLIFE] Maus weg: sichtbar=", bm._tip.visible)
	get_tree().quit()
