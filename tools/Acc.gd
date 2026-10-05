extends Node
# godot ... res://_t/Acc.tscn -- <ausgabe.png> [pose] [yaw_grad]
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "/home/claude/acc.png"
	var pose: String = a[1] if a.size() > 1 else "Idle"
	var yaw: float = float(a[2]) if a.size() > 2 else 35.0
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate(); add_child(main)
	for i in 5: await get_tree().process_frame
	var gc = main.get("_game_ctrl")
	gc.call("start_new_game", "SMALL", "qa-seed", "QA")
	for i in 10: await get_tree().process_frame
	var rend = gc.renderer
	var svp := SubViewport.new(); svp.size = Vector2i(1500, 700); svp.own_world_3d = true; svp.msaa_3d = Viewport.MSAA_4X
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(svp)
	var env := Environment.new(); env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.55, 0.68, 0.8)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color(0.8, 0.82, 0.9); env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new(); we.environment = env; svp.add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 140, 0); sun.light_energy = 1.1; svp.add_child(sun)
	var groups := [["CROWN","MONOCLE","BOWTIE","CAPE"], ["TOP_HAT","EYEPATCH","SCARF"], ["WIZARD_HAT","MEDAL"], ["BANDANA"]]
	var FS: float = rend.FERRET_MODEL_SCALE
	for gi in groups.size():
		var fn := Node3D.new(); fn.scale = Vector3.ONE * FS; fn.position = Vector3(gi * 0.85, 0, 0)
		fn.rotation_degrees.y = 0.0
		var inst: Node = rend.FERRET_SCENE.instantiate(); fn.add_child(inst)
		svp.add_child(fn)
		rend.call("_attach_ferret_accessories", fn, groups[gi])
		var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
		if ap and ap.has_animation(pose): ap.play(pose); ap.seek(0.0 if pose != "Run" else 0.2, true)
	var cam := Camera3D.new(); svp.add_child(cam)
	cam.fov = 38
	var center := Vector3(1.27, 0.38, 0.1)
	var r := 3.4; var ry := deg_to_rad(yaw)
	cam.look_at_from_position(center + Vector3(sin(ry) * r, 0.55, cos(ry) * r), center, Vector3.UP)
	for i in 12: await get_tree().process_frame
	svp.get_texture().get_image().save_png(out)
	print("[ACC] ", out)
	get_tree().quit()
