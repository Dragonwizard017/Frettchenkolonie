extends Node
## v16.9: Modell-Sichtpruefung fuer die neuen Zug-/Gebaeude-GLBs.
## Aufruf (Fenstermodus, NICHT headless):
##   godot --path . res://_t/VehShot.tscn -- <ausgabe-praefix>
## Erzeugt <praefix>_<modell>_<winkel>.png: front (+X-Blick), seite (+Z) und
## fuer jedes Modell "sitz_f"/"sitz_b" (Kameraposition des Spielers im Zug,
## Blick +X bzw. -X).

const MODELS := {
	"loco": "res://assets/loco.glb",
	"wagon": "res://assets/wagon.glb",
	"station": "res://assets/station.glb",
	"depot": "res://assets/depot.glb",
}

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "veh_"
	await get_tree().process_frame
	var svp := SubViewport.new()
	svp.size = Vector2i(1400, 800)
	svp.own_world_3d = true
	svp.msaa_3d = Viewport.MSAA_4X
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(svp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.68, 0.8)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.82, 0.9)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new(); we.environment = env; svp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 120, 0)
	sun.light_energy = 1.1
	svp.add_child(sun)
	# Boden-Referenzplatte (y=0)
	var gm := BoxMesh.new(); gm.size = Vector3(3.2, 0.04, 3.2)
	var gmat := StandardMaterial3D.new(); gmat.albedo_color = Color(0.42, 0.62, 0.33)
	var g := MeshInstance3D.new(); g.mesh = gm; g.material_override = gmat
	svp.add_child(g)
	# Achsen-Marker: ROT = +X (Fahrtrichtung), GELB = +Z, Gruen = Boden
	for mk in [[Vector3(1.4, 0.08, 0), Color(0.85, 0.2, 0.2)], [Vector3(0, 0.08, 1.4), Color(0.95, 0.9, 0.3)]]:
		var mm := BoxMesh.new(); mm.size = Vector3(0.22, 0.16, 0.22)
		var m5 := StandardMaterial3D.new(); m5.albedo_color = mk[1]
		var m6 := MeshInstance3D.new(); m6.mesh = mm; m6.position = mk[0]; m6.material_override = m5
		svp.add_child(m6)
	var holder := Node3D.new(); svp.add_child(holder)
	var cam := Camera3D.new(); cam.fov = 40; svp.add_child(cam)
	var fcam := Camera3D.new(); fcam.fov = 65; svp.add_child(fcam)
	for i in 12: await get_tree().process_frame
	for m in MODELS.keys():
		for c in holder.get_children():
			holder.remove_child(c); c.free()
		var packed: PackedScene = load(MODELS[m])
		var inst: Node = packed.instantiate()
		holder.add_child(inst)
		var ctr := _aabb_center(inst)
		inst.position = Vector3(-ctr.x, -ctr.y, -ctr.z)   # XZ-Zentrierung (Export geparkt), Boden auf y=0
		await get_tree().process_frame
		# Kamera-Winkel: pos = Richtung * Distanz, Blick zum Zentrum.
		# "px" = von +X gesehen (Fahrtrichtung entgegen), "mx" = von -X (Fahrtrichtung),
		# "pz" = von +Z (Seitenansicht), "top" = von oben.
		var angles := {
			"px": [Vector3(2.6, 1.1, 0.0)],
			"mx": [Vector3(-2.6, 1.1, 0.0)],
			"pz": [Vector3(0.0, 1.1, 2.6)],
			"top": [Vector3(0.0, 3.2, 0.35)],
		}
		for shot in angles.keys():
			var dir: Vector3 = angles[shot][0]
			var tgt: Vector3 = Vector3(0.0, 0.55, 0.0)
			cam.look_at_from_position(tgt + dir, tgt, Vector3.UP)
			for f in 8: await get_tree().process_frame
			svp.get_texture().get_image().save_png(out + str(m) + "_" + str(shot) + ".png")
		# Sitz-Blick quer durch die Lok (Kameraposition wie im Spiel)
		cam.current = false
		fcam.current = true
		var sp := Vector3(-0.22, 1.0, 0.0)
		fcam.look_at_from_position(sp, sp + Vector3(1, 0, 0), Vector3.UP)
		for f in 8: await get_tree().process_frame
		svp.get_texture().get_image().save_png(out + str(m) + "_sitz_f.png")
		fcam.look_at_from_position(sp, sp + Vector3(-1, 0, 0), Vector3.UP)
		for f in 8: await get_tree().process_frame
		svp.get_texture().get_image().save_png(out + str(m) + "_sitz_b.png")
		fcam.current = false
		cam.current = true
	print("[VEHSHOT] fertig: ", out, "_*.png")
	get_tree().quit()

func _aabb_center(n: Node) -> Vector3:
	var boxes: Array = []
	_collect_aabbs(n, Transform3D.IDENTITY, boxes, true)
	if boxes.is_empty(): return Vector3.ZERO
	var u: AABB = boxes[0]
	for i in range(1, boxes.size()): u = u.merge(boxes[i] as AABB)
	return u.get_center()

func _collect_aabbs(n: Node, xf: Transform3D, out_boxes: Array, is_root: bool) -> void:
	var t: Transform3D = xf
	if n is Node3D and not is_root: t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out_boxes.append(t * (n as MeshInstance3D).mesh.get_aabb())
	for c in n.get_children(): _collect_aabbs(c, t, out_boxes, false)
