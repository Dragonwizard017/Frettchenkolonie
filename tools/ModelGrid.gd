extends Node
# Nutzung: ... res://_t/ModelGrid.tscn -- <ausgabe.png> <zoom> <erste_zeile> <zeilen> [abstand]
# Setzt jedes Gebäude mit eigenem Modell auf benachbarte Kacheln (Raster 7 breit) und rendert es.
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "/home/claude/grid.png"
	var zoom: float = float(a[1]) if a.size() > 1 else 16.0
	var row0: int = int(a[2]) if a.size() > 2 else 0
	var rows: int = int(a[3]) if a.size() > 3 else 8
	var gap: int = int(a[4]) if a.size() > 4 else 1
	GraphicsSettings.set_realistic(false)
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate(); add_child(main)
	for i in 30: await get_tree().process_frame
	var intro = main.get("_intro")
	if intro != null: intro.call("skip")
	for i in 5: await get_tree().process_frame
	var gc = main.get("_game_ctrl")
	gc.call("start_new_game", "SMALL", "qa-seed", "Modelle")
	for i in 10: await get_tree().process_frame
	# Reihenfolge: alle Gebäude-IDs mit Override (alphabetisch)
	var ids: Array = []
	for k in gc.renderer.BUILDING_MODEL_OVERRIDES.keys(): ids.append(str(k))
	ids.sort()
	_print_ids(ids)
	# freies Rechteck suchen (kein Wasser, keine Gebäude)
	var cols := 7
	var w: int = cols * gap + 1; var h: int = (ids.size() / cols + 1) * gap + 1
	var best := Vector2i(-1, -1)
	for x in range(3, gc.world_gen.w - w - 2):
		for y in range(3, gc.world_gen.h - h - 2):
			var ok := true
			for dx in range(0, w, 1):
				for dy in range(0, h, 1):
					var t: Dictionary = gc.world[x + dx][y + dy]
					if t.get("building") != null or str(t.get("biome", "")) == "WATER": ok = false; break
				if not ok: break
			if ok and best.x < 0: best = Vector2i(x, y)
	if best.x < 0: best = Vector2i(5, 5)
	print("[GRID] Start ", best)
	var placed: Array = []
	for i in ids.size():
		var tx: int = best.x + (i % cols) * gap
		var ty: int = best.y + (i / cols) * gap
		var b = BuildingSys.build_free(ids[i], tx, ty, gc.world, 0)
		if b != null:
			b.placed_day = 0
			gc.renderer.add_building(b)
			placed.append([ids[i], tx, ty])
	var line := ""
	for p in placed: line += "%s@(%d,%d) " % [p[0], p[1], p[2]]
	print("[GRID] ", placed.size(), " platziert: ", line.substr(0, 400))
	for i in 20: await get_tree().process_frame
	# Kamera auf gewählte Zeilen
	var cy_tile: float = best.y + (row0 + rows * 0.5) * gap
	var cx_tile: float = best.x + cols * gap * 0.5
	gc.set("_cam_target", gc.renderer.tile_to_world3d(int(cx_tile), int(cy_tile)))
	gc.set("_cam_zoom", zoom)
	gc.call("_apply_camera")
	var hud = main.find_child("GameUI", true, false)
	if hud != null: hud.visible = false
	for i in 25: await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("[GRID] gespeichert ", out)
	get_tree().quit()
func _print_ids(ids: Array) -> void:
	var s := ""
	for i in ids.size(): s += "%d:%s " % [i, ids[i]]
	print("[GRID-IDS] ", s)
