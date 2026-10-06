extends Node
# Kontaktblatt aller Frettchen-Clips: godot ... res://_t/ClipSheet.tscn -- <prefix>
func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/home/claude/clips"
	await get_tree().process_frame
	var svp := SubViewport.new(); svp.size = Vector2i(1500, 1100); svp.own_world_3d = true; svp.msaa_3d = Viewport.MSAA_4X
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(svp)
	var env := Environment.new(); env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.62, 0.72, 0.82)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color(0.85, 0.85, 0.92); env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new(); we.environment = env; svp.add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45, 150, 0); sun.light_energy = 1.0; svp.add_child(sun)
	var scene: PackedScene = load("res://assets/ferret.glb") as PackedScene
	var names: Array = []
	var probe: Node = scene.instantiate(); var ap0: AnimationPlayer = probe.find_child("AnimationPlayer", true, false)
	for n in ap0.get_animation_list(): names.append(n)
	probe.free()
	names.sort()
	var aps: Array = []
	for i in names.size():
		var fn := Node3D.new(); fn.scale = Vector3.ONE * 2.2
		fn.position = Vector3((i % 4) * 1.75, -(i / 4) * 1.15, 0)
		fn.rotation_degrees.y = 90
		var inst: Node = scene.instantiate(); fn.add_child(inst); svp.add_child(fn)
		var lb := Label3D.new(); lb.text = names[i]; lb.font_size = 64; lb.pixel_size = 0.0045; lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.position = fn.position + Vector3(0, 0.62, 0.3); lb.modulate = Color(0.1, 0.1, 0.15); lb.no_depth_test = true; svp.add_child(lb)
		aps.append(inst.find_child("AnimationPlayer", true, false))
	var cam := Camera3D.new(); svp.add_child(cam); cam.fov = 34
	var center := Vector3(2.6, -1.55, 0)
	cam.look_at_from_position(center + Vector3(0, 0.4, 11.0), center, Vector3.UP)
	for tt in [0.30, 0.70]:
		for i in names.size():
			var a: Animation = (aps[i] as AnimationPlayer).get_animation(names[i])
			(aps[i] as AnimationPlayer).play(names[i]); (aps[i] as AnimationPlayer).seek(a.length * tt, true)
		for k in 8: await get_tree().process_frame
		svp.get_texture().get_image().save_png("%s_%d.png" % [out, int(tt * 100)])
		print("[CLIPS] ", tt)
	get_tree().quit()
