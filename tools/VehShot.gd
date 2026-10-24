extends Node
## v16.10: Modell-Sichtpruefung fuer die Zug-GLBs (loco/wagon mit Innenleben
## aus FrettchenModell/glb_zug) + Gebaeude-GLBs (station/depot).
## Aufruf (Fenstermodus, NICHT headless):
##   godot --path . --resolution 1280x720 res://_t/VehShot.tscn -- <ausgabe-praefix>
## Erzeugt pro Modell 4 Winkel (px = +X-Gegenueber, mx = von -X, pz = +Z, top)
## plus "sitz_f"/"sitz_b" (Fahrerhaus-Blick +X / -X ab Kamera_Sitz) und einen
## "zug_*"-Koppelmodus: Loko + 3 Waggons im echten Waggonabstand (LOCO_HITCH /
## WAGON_SPACING analog RailRenderer) - Sichtpruefung der Koppelungsabstaende.

const MODELS := {
	"loco": "res://assets/loco.glb",
	"wagon": "res://assets/wagon.glb",
	"station": "res://assets/station.glb",
	"depot": "res://assets/depot.glb",
}
const LOCO_HITCH: float = 1.27       # analog RailRenderer
const WAGON_SPACING: float = 0.66

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
	for mk in [[Vector3(1.4, 0.08, 0), Color(0.85, 0.2, 0.2)], [Vector3(0, 0.08, 1.4), Color(0.95, 0.9, 0.3)]]:
		var mm := BoxMesh.new(); mm.size = Vector3(0.22, 0.16, 0.22)
		var m5 := StandardMaterial3D.new(); m5.albedo_color = mk[1]
		var m6 := MeshInstance3D.new(); m6.mesh = mm; m6.position = mk[0]; m6.material_override = m5
		svp.add_child(m6)
	var holder := Node3D.new(); svp.add_child(holder)
	var cam := Camera3D.new(); cam.fov = 40; svp.add_child(cam)
	var fcam := Camera3D.new(); fcam.fov = 65; svp.add_child(fcam)
	var sp := Vector3(-0.5, 0.65, 0.0)   # = Kamera_Sitz der GLB-Lok
	for i in 12: await get_tree().process_frame
	for m in MODELS.keys():
		for c in holder.get_children():
			holder.remove_child(c); c.free()
		var packed: PackedScene = load(MODELS[m])
		var inst: Node = packed.instantiate()
		holder.add_child(inst)
		var ctr := _aabb_center(inst)
		inst.position = Vector3(-ctr.x, -ctr.y, -ctr.z)   # XZ-Zentrierung, Boden auf y=0
		await get_tree().process_frame
		var angles := {
			"px": [Vector3(2.6, 1.1, 0.0)],
			"mx": [Vector3(-2.6, 1.1, 0.0)],
			"pz": [Vector3(0.0, 1.1, 2.6)],
			"top": [Vector3(0.0, 3.2, 0.35)],
		}
		var top_abs: float = _aabb_top(inst)
		if top_abs > 1.4:   # Gebaeude weiter weg zoomen
			angles["px"][0] *= 1.8; angles["mx"][0] *= 1.8; angles["pz"][0] *= 1.8; angles["top"][0] *= 1.8
		cam.current = true; fcam.current = false
		for shot in angles.keys():
			var dir: Vector3 = angles[shot][0]
			var tgt: Vector3 = Vector3(0.0, 0.55, 0.0)
			cam.look_at_from_position(tgt + dir, tgt, Vector3.UP)
			for f in 8: await get_tree().process_frame
			svp.get_texture().get_image().save_png(out + str(m) + "_" + str(shot) + ".png")
		# Sitz-Blick quer durch die Fuehrerhausbosse (ab Kamera_Sitz-Anker), Blick +X / -X
		cam.current = false; fcam.current = true
		fcam.look_at_from_position(sp, sp + Vector3(1, 0, 0), Vector3.UP)
		for f in 8: await get_tree().process_frame
		svp.get_texture().get_image().save_png(out + str(m) + "_sitz_f.png")
		fcam.look_at_from_position(sp, sp + Vector3(-1, 0, 0), Vector3.UP)
		for f in 8: await get_tree().process_frame
		svp.get_texture().get_image().save_png(out + str(m) + "_sitz_b.png")
	# ── Koppelmodus: Loco + 3 Waggons im echten Waggonabstand ──
	for c in holder.get_children():
		holder.remove_child(c); c.free()
	var kop: Node = load("res://assets/loco.glb").instantiate()
	holder.add_child(kop)
	var offsets: Array[float] = [0.0, -LOCO_HITCH, -LOCO_HITCH - WAGON_SPACING, -LOCO_HITCH - 2.0 * WAGON_SPACING]
	for i in range(1, offsets.size()):
		var w2: Node = load("res://assets/wagon.glb").instantiate()
		holder.add_child(w2)
		w2.position = Vector3(offsets[i], 0.0, 0.0)
	await get_tree().process_frame
	# Hebel sichtbar kippen (Gas vorn, Bremse rueck), damit man die Animation sieht
	var hb := kop.find_child("Hebel_Bremse", true, false) as Node3D
	if hb != null: hb.rotation.z = 0.45
	var hg := kop.find_child("Hebel_Gas", true, false) as Node3D
	if hg != null: hg.rotation.z = -0.3
	# Kamera: Seitenansicht ueber die ganze Koppel und von oben
	cam.current = true; fcam.current = false
	cam.look_at_from_position(Vector3(-0.2, 1.3, 4.6), Vector3(-0.6, 0.45, 0.0), Vector3.UP)
	for f in 8: await get_tree().process_frame
	svp.get_texture().get_image().save_png(out + "zug_seite.png")
	cam.look_at_from_position(Vector3(-0.7, 4.5, 0.35), Vector3(-0.7, 0.0, 0.0), Vector3.UP)
	for f in 8: await get_tree().process_frame
	svp.get_texture().get_image().save_png(out + "zug_top.png")
	# Fahrerhaus-Blick ab Kamera_Sitz-Anker (wie im Spiel)
	fcam.current = true; cam.current = false
	fcam.clear_current(); fcam.make_current()
	fcam.look_at_from_position(sp, sp + Vector3(1, 0, 0), Vector3.UP)
	for f in 8: await get_tree().process_frame
	svp.get_texture().get_image().save_png(out + "zug_sitz_f.png")
	print("[VEHSHOT] fertig: ", out, "_*.png")
	get_tree().quit()

func _aabb_top(n: Node) -> float:
	var boxes: Array = []
	_collect_aabbs(n, Transform3D.IDENTITY, boxes, true)
	if boxes.is_empty(): return 0.0
	var u: AABB = boxes[0]
	for i in range(1, boxes.size()): u = u.merge(boxes[i] as AABB)
	return u.end.y

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
