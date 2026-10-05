extends Node
func _boxes(n: Node, out: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh and (n as Node3D).is_visible_in_tree():
		out.append((n as MeshInstance3D).global_transform * (n as MeshInstance3D).mesh.get_aabb())
	for c in n.get_children(): _boxes(c, out)
func _ready() -> void:
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate(); add_child(main)
	for i in 5: await get_tree().process_frame
	var gc = main.get("_game_ctrl")
	gc.call("start_new_game", "MEDIUM", "qa-seed", "QA")
	gc.call("bootstrap_test_colony")
	for i in 20: await get_tree().process_frame
	var rend = gc.renderer
	var seen := {}
	for b in BuildingSys.buildings:
		var key := "%d,%d" % [b.tile_x, b.tile_y]
		var root: Node3D = rend._building_nodes.get(key)
		if root == null: continue
		var bx: Array = []
		for c in root.get_children():
			if c is MeshInstance3D or c.get_child_count() > 0: _boxes(c, bx)
		var u: AABB; var first := true
		for bb in bx:
			if first: u = bb; first = false
			else: u = u.merge(bb)
		if first: continue
		var ctr: Vector3 = u.get_center()
		var dx: float = ctr.x - root.global_position.x
		var dz: float = ctr.z - root.global_position.z
		if not seen.has(b.id):
			seen[b.id] = true
			print("[BLD] %-18s Offset Modellmitte zu Kachelmitte: dx=%.2f dz=%.2f  Höhe=%.2f  Unterkante y=%.2f (Kachel y=%.2f)" % [b.id, dx, dz, u.size.y, u.position.y, root.global_position.y])
	get_tree().quit()
