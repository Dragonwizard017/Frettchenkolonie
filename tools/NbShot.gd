extends Node
# Screenshots: Nachbardorf und Nachbarn-Fenster. Nutzung: ... -- /pfad/praefix
func frames(n: int) -> void:
	for i in n: await get_tree().process_frame
func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/home/claude/nbshot"
	GraphicsSettings.set_realistic(false)
	await frames(2)
	var main = load("res://scenes/Main.tscn").instantiate(); add_child(main)
	await frames(30)
	var intro = main.get("_intro")
	if intro != null: intro.call("skip")
	await frames(5)
	var gc = main.get("_game_ctrl")
	gc.call("start_new_game", "HUGE", "qa-seed", "QA")
	await frames(20)
	gc.call("dev_unlock_all_epochs", 99)
	gc.call("dev_neighbors_reveal")
	print("[SHOT] ", gc.call("dev_neighbor_line"))
	gc.call("dev_neighbors_rep", 35.0)
	gc.call("dev_neighbors_request")
	for i in 100: gc.call("_process", 0.1)
	gc.renderer.apply_fog(); ExploreSys.flush()
	Engine.time_scale = 0.001
	var cid: int = int(NeighborSys.cids()[0])
	var h: Vector2i = ColonySys.get_hall_tile(cid)
	gc.set("_cam_target", gc.renderer.tile_to_world3d(h.x, h.y)); gc.set("_cam_zoom", 16.0); gc.call("_apply_camera")
	var gui = main.find_child("GameUI", true, false)
	gui.visible = false
	await frames(25)
	get_viewport().get_texture().get_image().save_png(out + "_1_dorf.png")
	gui.visible = true
	gc.set("_cam_zoom", 28.0); gc.call("_apply_camera")
	main.find_child("NeighborPanel", true, false).call("open")
	await frames(20)
	get_viewport().get_texture().get_image().save_png(out + "_2_fenster.png")
	print("[SHOT] fertig")
	get_tree().quit()
