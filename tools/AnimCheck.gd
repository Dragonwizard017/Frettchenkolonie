extends Node
func _ready() -> void:
	var inst: Node = (load("res://assets/ferret.glb") as PackedScene).instantiate()
	add_child(inst)
	var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
	var sk: Skeleton3D = inst.find_child("Skeleton3D", true, false)
	for n in ap.get_animation_list():
		var a: Animation = ap.get_animation(n)
		print("[ANIM] %-14s Länge=%.2fs Loop=%s Tracks=%d" % [n, a.length, ["AUS","LINEAR","PINGPONG"][a.loop_mode], a.get_track_count()])
	FerretAnimUtil.ensure_loops(ap)
	ap.play("Run"); ap.advance(0.0)
	var p0: Array = []; for i in sk.get_bone_count(): p0.append(sk.get_bone_pose_rotation(i))
	ap.advance(0.25)
	var moved := 0
	for i in sk.get_bone_count():
		if sk.get_bone_pose_rotation(i).angle_to(p0[i]) > 0.02: moved += 1
	print("[ANIM] Run: ", moved, " von ", sk.get_bone_count(), " Knochen bewegen sich nach 0.25s")
	ap.advance(5.0)
	print("[ANIM] Run nach 5.25s weiter aktiv: ", ap.is_playing(), " Position=", "%.2f" % ap.current_animation_position)
	get_tree().quit()
