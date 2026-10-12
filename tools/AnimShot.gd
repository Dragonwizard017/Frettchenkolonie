extends Node
# Screenshot-Variante: alle Gebäude aktiv, zwei Aufnahmen nacheinander.
var main: Node
var gc: Node
var fails: int = 0
func _log(s: String) -> void: print("[TEST] ", s)
func check(cond: bool, msg: String) -> void:
	if cond: _log("  ok   " + msg)
	else:
		fails += 1
		_log("  FAIL " + msg)
func frames(n: int) -> void:
	for i in n: await get_tree().process_frame
func root_of(b: BuildingEntity) -> Node:
	return gc.renderer._building_nodes.get("%d,%d" % [b.tile_x, b.tile_y]) as Node
func _ready() -> void:
	await get_tree().process_frame
	main = load("res://scenes/Main.tscn").instantiate(); add_child(main)
	await frames(30)
	var intro = main.get("_intro")
	if intro != null: intro.call("skip")
	await frames(5)
	gc = main.get("_game_ctrl")
	gc.call("start_new_game", "SMALL", "qa-seed", "QA")
	await frames(10)
	GameState.dev_all_buildings = true
	DayNight.day_length = 100000.0; DayNight.time = 20.0; DayNight.is_day = true

	# Gebäude mit eigenem Modell + Rathaus/Bahnhof/Depot auf Raster setzen
	var ids: Array = []
	for k in gc.renderer.BUILDING_MODEL_OVERRIDES.keys(): ids.append(str(k))
	for extra in ["STATION", "DEPOT"]:
		if not ids.has(extra): ids.append(extra)
	ids.sort()
	var cols := 8; var gap := 2
	var w: int = cols * gap + 1; var h: int = (ids.size() / cols + 2) * gap + 1
	var best := Vector2i(-1, -1)
	for x in range(3, gc.world_gen.w - w - 2):
		for y in range(3, gc.world_gen.h - h - 2):
			if best.x >= 0: break
			var ok := true
			for dx in range(0, w):
				for dy in range(0, h):
					var t: Dictionary = gc.world[x + dx][y + dy]
					if t.get("building") != null or str(t.get("biome", "")) == "WATER": ok = false; break
				if not ok: break
			if ok: best = Vector2i(x, y)
	if best.x < 0: best = Vector2i(4, 4)
	var placed: Array = []
	for i in ids.size():
		var tx: int = best.x + (i % cols) * gap
		var ty: int = best.y + (i / cols) * gap
		var b = BuildingSys.build_free(str(ids[i]), tx, ty, gc.world, 0)
		if b == null: continue
		b.placed_day = 0
		# erste 8 Typen: Arbeiter nötig aber keiner da -> müssen STILL stehen; Rest: ohne Arbeiterpflicht -> aktiv
		b.max_workers = 0
		gc.renderer.add_building(b)
		placed.append(b)
	GraphicsSettings.set_realistic(false)
	await frames(70)
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "/home/claude/animshot"
	var row0: int = int(a[1]) if a.size() > 1 else 0
	var rows: int = int(a[2]) if a.size() > 2 else 3
	var zoom: float = float(a[3]) if a.size() > 3 else 20.0
	var ct: Vector3 = gc.renderer.tile_to_world3d(best.x + cols * gap / 2, best.y + (row0 + rows / 2) * gap)
	gc.set("_cam_target", ct); gc.set("_cam_zoom", zoom); gc.call("_apply_camera")
	var gui = main.find_child("GameUI", true, false)
	if gui != null: gui.visible = false
	await frames(15)
	var img1 := get_viewport().get_texture().get_image()
	img1.save_png(out + "_a.png")
	await get_tree().create_timer(0.6).timeout
	await frames(3)
	var img2 := get_viewport().get_texture().get_image()
	img2.save_png(out + "_b.png")
	var diff := 0
	for y in range(0, img1.get_height(), 3):
		for x in range(0, img1.get_width(), 3):
			if img1.get_pixel(x, y).is_equal_approx(img2.get_pixel(x, y)) == false: diff += 1
	print("[SHOT] verschiedene Pixel zwischen den Aufnahmen: ", diff)
	get_tree().quit()
