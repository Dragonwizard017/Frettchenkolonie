extends Node
# Nutzung: godot ... res://_t/Shot.tscn -- <modus> <ausgabe.png>
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "menu"
	var out: String = args[1] if args.size() > 1 else "/home/claude/shot.png"
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for i in 30: await get_tree().process_frame
	var gc = main.get("_game_ctrl")
	if mode == "game" or mode == "colony":
		gc.call("start_new_game", "SMALL", "qa-seed", "QA")
		if mode == "colony": gc.call("bootstrap_test_colony")
		for i in 40: await get_tree().process_frame
		for i in 60:
			gc.call("_process", 0.1)
			await get_tree().process_frame
	if mode == "pause":
		gc.call("start_new_game", "SMALL", "qa-seed", "QA")
		gc.call("bootstrap_test_colony")
		for i in 40: await get_tree().process_frame
		for i in 40:
			gc.call("_process", 0.1)
			await get_tree().process_frame
		GameState.toggle_pause()
		for i in 10: await get_tree().process_frame
	elif mode == "info":
		gc.call("start_new_game", "SMALL", "qa-seed", "QA")
		gc.call("bootstrap_test_colony")
		for i in 40: await get_tree().process_frame
		for i in 40:
			gc.call("_process", 0.1)
			await get_tree().process_frame
		for b in BuildingSys.buildings:
			if b.collects_resource == "WATER":
				GameState.building_selected.emit(b); break
		for i in 10: await get_tree().process_frame
	elif mode.begins_with("panel:"):
		gc.call("start_new_game", "SMALL", "qa-seed", "QA")
		gc.call("bootstrap_test_colony")
		for i in 40: await get_tree().process_frame
		for i in 20:
			gc.call("_process", 0.1)
			await get_tree().process_frame
		var pn = gc.get_node_or_null("GameUI/UIRoot/" + mode.substr(6))
		if pn and pn.has_method("open"): pn.call("open")
		elif pn: pn.visible = true
		for i in 10: await get_tree().process_frame
	elif mode == "world":
		GameState.set_state(GameState.State.WORLD_CREATION)
		for i in 20: await get_tree().process_frame
	elif mode == "load":
		main.call("_show_load_screen")
		for i in 20: await get_tree().process_frame
	for i in 10: await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("[SHOT] gespeichert ", out, " ", img.get_size())
	get_tree().quit()
