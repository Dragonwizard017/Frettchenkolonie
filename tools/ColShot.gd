extends Node
# Nutzung: ... res://_t/ColShot.tscn -- <modus> <ausgabe.png>   (modus: panel | ghost | menu)
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "panel"
	var out: String = args[1] if args.size() > 1 else "/home/claude/colshot.png"
	GraphicsSettings.set_realistic(false)
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for i in 30: await get_tree().process_frame
	var intro = main.get("_intro")
	if intro != null: intro.call("skip")
	for i in 5: await get_tree().process_frame
	var gc = main.get("_game_ctrl")
	gc.call("start_new_game", "SMALL", "qa-seed", "Frettchenheim")
	gc.call("bootstrap_test_colony")
	for i in 30: await get_tree().process_frame
	var hall0: Vector2i = ColonySys.get_hall_tile(0)
	# zweite Kolonie gründen
	var site := Vector2i(-1, -1)
	for x in gc.world_gen.w:
		for y in gc.world_gen.h:
			var t: Dictionary = gc.world[x][y]
			if site.x < 0 and t.get("building") == null and str(t.get("biome", "")) != "WATER" and Vector2(hall0).distance_to(Vector2(x, y)) >= 21.0:
				site = Vector2i(x, y)
	for k in ["WOOD", "STONE", "PLANKS", "TOOLS", "BERRIES"]: ResourceSys.force_add(k, 200.0)
	gc.call("_found_colony", site.x, site.y)
	for i in 80:
		gc.call("_process", 0.1)
		await get_tree().process_frame
	gc.call("focus_colony", 0)
	for i in 10: await get_tree().process_frame
	if mode == "panel":
		main.find_child("ColonyPanel", true, false).call("open")
	elif mode == "ghost":
		GameState.set_placement("BUILDING", "TOWN_HALL")
		var g: Vector2i = Vector2i(hall0.x + 4, hall0.y + 4)
		gc.renderer.update_ghost(g.x, g.y, "TOWN_HALL")
		gc.set("_cam_zoom", 60.0); gc.call("_apply_camera")
	elif mode == "far":
		gc.call("focus_colony", 1)
		main.find_child("ColonyPanel", true, false).call("open")
	for i in 20: await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("[SHOT] gespeichert ", out, " ", img.get_size())
	get_tree().quit()
