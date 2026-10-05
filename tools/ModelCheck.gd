extends Node
func _aabb(n: Node, xf: Transform3D, out: Array) -> void:
	var t := xf
	if n is Node3D: t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var a: AABB = (n as MeshInstance3D).mesh.get_aabb()
		out.append(t * a)
	for c in n.get_children(): _aabb(c, t, out)
func _info(path: String) -> void:
	var ps: PackedScene = load(path) as PackedScene
	if ps == null: print("[MODEL] FEHLT/NICHT LADBAR: ", path); return
	var inst: Node = ps.instantiate()
	var boxes: Array = []
	_aabb(inst, Transform3D.IDENTITY, boxes)
	var u: AABB = AABB(); var first := true
	for b in boxes:
		if first: u = b; first = false
		else: u = u.merge(b)
	var meshes := 0; var mats := {}
	var stack := [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			meshes += 1
			var m: Mesh = (n as MeshInstance3D).mesh
			if m: for i in m.get_surface_count():
				var mt: Material = m.surface_get_material(i)
				mats[mt.resource_name if mt else "NULL"] = true
		for c in n.get_children(): stack.append(c)
	print("[MODEL] %s  meshes=%d  size=(%.3f, %.3f, %.3f)  min=(%.3f, %.3f, %.3f)  mats=%s" % [path.get_file(), meshes, u.size.x, u.size.y, u.size.z, u.position.x, u.position.y, u.position.z, str(mats.keys())])
	var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap: print("[MODEL]   Animationen(", ap.get_animation_list().size(), "): ", ", ".join(ap.get_animation_list()))
	var sk: Skeleton3D = inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk: print("[MODEL]   Skeleton: ", sk.get_bone_count(), " Knochen")
	inst.free()
func _ready() -> void:
	for p in ["ferret","building","well_building","storage_building","water_tower","statue","pine_tree","bush"]:
		_info("res://assets/%s.glb" % p)
	for p in ["crown","top_hat","wizard_hat","bandana","bowtie","scarf","medal","monocle","eyepatch","cape"]:
		_info("res://assets/accessories/%s.glb" % p)
	get_tree().quit()
