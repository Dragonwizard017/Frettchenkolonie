extends Node
# Panorama mit Realismus-Modus + Saison-Optik.
# godot ... res://_t/Pano2.tscn -- <seed> <hoehe> <prefix> <face> <saison 0-3> <tageszeit 0-1> [dx dy]
func _hide_labels(n: Node) -> void:
	for c in n.get_children():
		if c is Label3D: (c as Label3D).visible = false
		_hide_labels(c)
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var seed_s: String = a[0] if a.size() > 0 else "alpha"
	var height: float = float(a[1]) if a.size() > 1 else 7.0
	var prefix: String = a[2] if a.size() > 2 else "/home/claude/pano2/f"
	var FACE: int = int(a[3]) if a.size() > 3 else 1536
	var S: int = int(a[4]) if a.size() > 4 else 1
	var pct: float = float(a[5]) if a.size() > 5 else 0.66
	var off := Vector2(float(a[6]) if a.size() > 6 else 0.0, float(a[7]) if a.size() > 7 else 0.0)
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate(); add_child(main)
	for i in 5: await get_tree().process_frame
	var gc = main.get("_game_ctrl")
	gc.call("start_new_game", "MEDIUM", seed_s, "Pano")
	gc.call("bootstrap_test_colony")
	for i in 20: await get_tree().process_frame
	var day: int = S * 15 + 7
	DayNight.day_count = day; gc.set("_day_prev", day); SeasonSys.update(day)
	DayNight.time = DayNight.day_length * pct
	GraphicsSettings.set_realistic(true)
	for i in 6: await get_tree().process_frame
	# EIN Logik-Frame: wendet Saison-Töne + Realismus (Sonnenstand, Himmel) an, danach einfrieren
	gc.call("_process", 0.05)
	gc.set_process(false); gc.set_process_unhandled_input(false)
	var ui = gc.get_node_or_null("GameUI"); if ui: ui.visible = false
	var env: Environment = gc._world_env
	# Iso-Kamera ist ortho -> Dunst manuell für die Perspektiv-Aufnahme aktivieren (dezent, ohne Volumetrik)
	env.fog_enabled = true; env.fog_density = 0.0030; env.fog_light_color = Color(0.74, 0.82, 0.92)
	env.fog_sky_affect = 0.05; env.fog_sun_scatter = 0.0   # Sonnen-Streulicht erzeugte einen lila Hof
	env.glow_intensity = 0.25
	env.volumetric_fog_enabled = false
	var rfx = gc.get("_realism")
	if rfx and rfx._sky_mat: rfx._sky_mat.set_shader_parameter("cloud_cover", 0.55)   # mehr Wolken fürs Menü
	var svp := SubViewport.new(); svp.size = Vector2i(FACE, FACE); svp.msaa_3d = Viewport.MSAA_4X
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(svp)
	var cam := Camera3D.new(); svp.add_child(cam); cam.current = true
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE; cam.fov = 90.0; cam.near = 0.1; cam.far = 600.0
	var cx: int = gc.world_gen.w / 2; var cy: int = gc.world_gen.h / 2
	var base: Vector3 = gc.renderer.tile_to_world3d(cx + int(off.x), cy + int(off.y)); base.y += height
	var dirs := {
		"front": [Vector3(0,0,-1), Vector3.UP], "right": [Vector3(1,0,0), Vector3.UP],
		"back": [Vector3(0,0,1), Vector3.UP], "left": [Vector3(-1,0,0), Vector3.UP],
		"up": [Vector3(0,1,0), Vector3(0,0,1)], "down": [Vector3(0,-1,0), Vector3(0,0,-1)]}
	DirAccess.make_dir_recursive_absolute(prefix.get_base_dir())
	var faces: Array = (a[8] as String).split(",") if a.size() > 8 else ["front", "right", "back", "left", "up", "down"]
	for k in faces:
		_hide_labels(gc)
		cam.look_at_from_position(base, base + (dirs[k][0] as Vector3), dirs[k][1] as Vector3)
		for i in 10: await get_tree().process_frame
		svp.get_texture().get_image().save_png("%s_%s.png" % [prefix, k])
		print("[PANO] ", k)
	print("[PANO] fertig base=", base, " sun=", gc._sun_light.rotation_degrees)
	get_tree().quit()
