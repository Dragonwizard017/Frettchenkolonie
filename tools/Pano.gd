extends Node
# godot ... res://_t/Pano.tscn -- <seed> <hoehe> <ausgabe_praefix> [dx dy]
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var seed_s: String = a[0] if a.size() > 0 else "qa-seed"
	var height: float = float(a[1]) if a.size() > 1 else 7.0
	var prefix: String = a[2] if a.size() > 2 else "/home/claude/pano/face"
	var off := Vector2(float(a[3]) if a.size() > 3 else 0.0, float(a[4]) if a.size() > 4 else 0.0)
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for i in 5: await get_tree().process_frame
	var gc = main.get("_game_ctrl")
	gc.call("start_new_game", "MEDIUM", seed_s, "Pano")
	gc.call("bootstrap_test_colony")
	for i in 20: await get_tree().process_frame
	# Spiel-Logik und UI stilllegen, Kamera selbst führen
	gc.set_process(false); gc.set_process_unhandled_input(false)
	var ui = gc.get_node_or_null("GameUI"); if ui: ui.visible = false
	var cx: int = gc.world_gen.w / 2; var cy: int = gc.world_gen.h / 2
	var FACE := int(a[5]) if a.size() > 5 else 1536
	var svp := SubViewport.new(); svp.size = Vector2i(FACE, FACE); svp.msaa_3d = Viewport.MSAA_4X
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(svp)
	var cam := Camera3D.new(); svp.add_child(cam); cam.current = true
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 90.0; cam.near = 0.1; cam.far = 600.0
	# Licht & Himmel
	var sun: DirectionalLight3D = gc._sun_light
	sun.rotation_degrees = Vector3(-38.0, 150.0, 0.0); sun.light_energy = 1.35; sun.light_color = Color(1.0, 0.95, 0.85)
	if gc._fill_light: gc._fill_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY   # keine zweite "Sonnenscheibe"
	var env: Environment = gc._world_env
	var sky := Sky.new(); var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.28, 0.5, 0.82); psm.sky_horizon_color = Color(0.74, 0.86, 0.95)
	psm.ground_horizon_color = Color(0.70, 0.83, 0.90); psm.ground_bottom_color = Color(0.58, 0.72, 0.62)
	psm.sun_angle_max = 25.0; psm.sun_curve = 0.15
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY; env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY; env.ambient_light_energy = 0.9
	env.fog_enabled = true; env.fog_light_color = Color(0.74, 0.86, 0.95); env.fog_density = 0.0075; env.fog_sky_affect = 0.0
	var base: Vector3 = gc.renderer.tile_to_world3d(cx + int(off.x), cy + int(off.y)); base.y += height
	var dirs := {
		"front": [Vector3(0,0,-1), Vector3.UP], "right": [Vector3(1,0,0), Vector3.UP],
		"back": [Vector3(0,0,1), Vector3.UP], "left": [Vector3(-1,0,0), Vector3.UP],
		"up": [Vector3(0,1,0), Vector3(0,0,1)], "down": [Vector3(0,-1,0), Vector3(0,0,-1)]}
	DirAccess.make_dir_recursive_absolute(prefix.get_base_dir())
	for k in dirs:
		_hide_labels(gc)
		cam.look_at_from_position(base, base + (dirs[k][0] as Vector3), dirs[k][1] as Vector3)
		for i in 8: await get_tree().process_frame
		var img := svp.get_texture().get_image()
		img.save_png("%s_%s.png" % [prefix, k])
	print("[PANO] fertig base=", base, " face=", FACE)
	get_tree().quit()

func _hide_labels(n: Node) -> void:
	for c in n.get_children():
		if c is Label3D: (c as Label3D).visible = false
		_hide_labels(c)
