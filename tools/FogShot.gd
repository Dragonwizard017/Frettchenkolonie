extends Node
# Screenshots der Entdeckerkarte (Nebel). Nutzung: ... -- /pfad/praefix
func frames(n: int) -> void:
	for i in n: await get_tree().process_frame
func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/home/claude/fogshot"
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
	Engine.time_scale = 0.001
	var hall: Vector2i = ColonySys.get_hall_tile(0)
	var ct: Vector3 = gc.renderer.tile_to_world3d(hall.x, hall.y)
	gc.set("_cam_target", ct); gc.set("_cam_zoom", 60.0); gc.call("_apply_camera")
	var gui = main.find_child("GameUI", true, false)
	if gui != null: gui.visible = false
	await frames(20)
	get_viewport().get_texture().get_image().save_png(out + "_1_start.png")
	# Rand des Heimatbereichs, näher dran
	var edge: Vector3 = gc.renderer.tile_to_world3d(hall.x + 24, hall.y)
	gc.set("_cam_target", edge); gc.set("_cam_zoom", 22.0); gc.call("_apply_camera")
	await frames(10)
	get_viewport().get_texture().get_image().save_png(out + "_2_rand.png")
	# nach dem Aufdecken eines Rings
	ExploreSys.reveal_circle(hall.x + 30, hall.y, 12.0)
	await frames(60)
	ExploreSys.flush(); gc.renderer.apply_fog(); gc.renderer.refresh_water(gc.world)
	await frames(10)
	get_viewport().get_texture().get_image().save_png(out + "_3_aufgedeckt.png")
	print("[SHOT] fertig  bekannt=%.1f%%" % (ExploreSys.fraction() * 100.0))
	get_tree().quit()
