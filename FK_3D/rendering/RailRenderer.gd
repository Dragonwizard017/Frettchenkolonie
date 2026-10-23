class_name RailRenderer
extends Node3D
## Feature (v16.2, Logistik-Update Phase 2): zeichnet das Gleisnetz und die Züge.
## - Je Gleiskachel EIN Mesh (SurfaceTool): Schotterbett, zwei Schienen, Schwellen für jede
##   verbundene Richtung. Nur geänderte Kacheln (RailSys.dirty) werden neu gebaut.
## - Höhen: eine Kachel ist flach; zum höheren Nachbarn steigt das Gleis in der
##   zweiten Hälfte der Kachel an (Rampe), siehe rail_y_at().
## - Züge: Lok + Waggons folgen der Spur des Lok-Kopfes (TrainEntity.trail).

const TS: float = WorldRenderer3D.TILE_SIZE
const HS: float = WorldRenderer3D.HEIGHT_SCALE
const BALLAST: Color = Color(0.46, 0.43, 0.39)
const SLEEPER: Color = Color(0.34, 0.23, 0.14)
const STEEL: Color = Color(0.30, 0.31, 0.34)
const WAGON_SPACING: float = 0.66      # in Kacheln
const SUBDIV: int = 4
# v16.9: echte GLB-Modelle fuer Loco/Waggon statt Box-Platzhalter
# (assets/loco.glb / wagon.glb, beide Boden y=0, Laenge entlang +X).
const LOCO_SCENE: PackedScene = preload("res://assets/loco.glb")
const WAGON_SCENE: PackedScene = preload("res://assets/wagon.glb")
const LOCO_SCALE: float = 1.0           # roh 1.29 x 0.80 x 1.14 - passt 1:1 zum Gleismassstab
const WAGON_SCALE: float = 0.62         # roh 1.12 lang -> 0.69, damit der Wagen spitz nach dem Vorderwagen liegt (WAGON_SPACING = 0.66)

var _mat: StandardMaterial3D
var _tile_nodes: Dictionary = {}       # Schlüssel -> MeshInstance3D
var _train_nodes: Dictionary = {}      # Zug-ID -> Node3D

func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.roughness = 0.9

func _process(_delta: float) -> void:
	if RailSys.world.is_empty(): return
	if RailSys.all_dirty:
		RailSys.all_dirty = false
		RailSys.dirty = {}
		for n in _tile_nodes.values(): (n as Node).queue_free()
		_tile_nodes = {}
		for k in RailSys.rails: _build_tile(int(k))
	elif not RailSys.dirty.is_empty():
		var keys: Array = RailSys.dirty.keys()
		RailSys.dirty = {}
		for k in keys: _build_tile(int(k))
	_update_trains()

# ── Höhenfunktion (gemeinsam für Gleis-Mesh und Zug) ─────────────────────────
## Höhe (Welteinheiten) der Gleisoberfläche an der Kachel-Position p
## (ganzzahlig = Kachelmitte). Flach bis kurz vor die Kante, dann Rampe auf die
## Höhe des höheren Nachbarn - so greifen Gleis und Nachbarkachel nahtlos ineinander.
func rail_y_at(p: Vector2) -> float:
	var tx: int = roundi(p.x); var ty: int = roundi(p.y)
	var hT: float = RailSys.height_at(tx, ty)
	var o: Vector2 = p - Vector2(float(tx), float(ty))
	var nx: int = tx; var ny: int = ty
	var s: float = 0.0
	if absf(o.x) >= absf(o.y):
		nx = tx + (1 if o.x > 0.0 else -1); s = absf(o.x) / 0.5
	else:
		ny = ty + (1 if o.y > 0.0 else -1); s = absf(o.y) / 0.5
	var hN: float = hT
	if RailSys.is_node(nx, ny) and RailSys.slope_ok(tx, ty, nx, ny): hN = RailSys.height_at(nx, ny)
	var edge: float = maxf(hT, hN)
	var r: float = clampf((s - 0.45) / 0.55, 0.0, 1.0) if edge > hT else 0.0
	return (hT + (edge - hT) * r) * HS

func _world_pos(p: Vector2) -> Vector3:
	return Vector3(p.x * TS + TS * 0.5, rail_y_at(p), p.y * TS + TS * 0.5)

# ── Gleis-Mesh ───────────────────────────────────────────────────────────────
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for v in [a, b, c, a, c, d]:
		st.set_color(col); st.add_vertex(v)

func _build_tile(k: int) -> void:
	if _tile_nodes.has(k):
		(_tile_nodes[k] as Node).queue_free(); _tile_nodes.erase(k)
	if not RailSys.rails.has(k): return
	var v: Vector2i = RailSys.key_vec(k)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center: Vector2 = Vector2(float(v.x), float(v.y))
	var c3: Vector3 = _world_pos(center)
	# Nabe in der Kachelmitte
	var hub_y: float = c3.y + 0.03
	_quad(st, Vector3(c3.x - 0.45, hub_y, c3.z - 0.45), Vector3(c3.x + 0.45, hub_y, c3.z - 0.45),
		Vector3(c3.x + 0.45, hub_y, c3.z + 0.45), Vector3(c3.x - 0.45, hub_y, c3.z + 0.45), BALLAST)
	for d in RailSys.connections(v.x, v.y):
		_add_arm(st, center, d as Vector2i)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_tile_nodes[k] = mi

## Eine Halbstrecke von der Kachelmitte bis zur Kante in Richtung d.
func _add_arm(st: SurfaceTool, center: Vector2, d: Vector2i) -> void:
	var dir := Vector3(float(d.x), 0.0, float(d.y))
	var perp := Vector3(-dir.z, 0.0, dir.x)
	var step: float = 0.5 / float(SUBDIV)          # in Kacheln
	for i in SUBDIV:
		var p0: Vector2 = center + Vector2(float(d.x), float(d.y)) * (step * float(i))
		var p1: Vector2 = center + Vector2(float(d.x), float(d.y)) * (step * float(i + 1))
		var a: Vector3 = _world_pos(p0); var b: Vector3 = _world_pos(p1)
		# Schotter
		_ribbon(st, a, b, perp, 0.0, 0.45, 0.03, BALLAST)
		# Schwelle (quer) in der Mitte des Teilstücks
		var m: Vector3 = (a + b) * 0.5
		var half_len: float = (b - a).length() * 0.5
		var sl0: Vector3 = m - dir * minf(0.07, half_len * 0.5)
		var sl1: Vector3 = m + dir * minf(0.07, half_len * 0.5)
		_ribbon(st, sl0, sl1, perp, 0.0, 0.42, 0.07, SLEEPER)
		# Schienen
		for side in [-1.0, 1.0]:
			_ribbon(st, a, b, perp, 0.28 * side, 0.035, 0.12, STEEL)

## Flaches Band entlang a->b, seitlich um `off` verschoben, Halbbreite `hw`, Höhe `lift` über a/b.y.
func _ribbon(st: SurfaceTool, a: Vector3, b: Vector3, perp: Vector3, off: float, hw: float, lift: float, col: Color) -> void:
	var a0: Vector3 = a + perp * (off - hw) + Vector3(0, lift, 0)
	var a1: Vector3 = a + perp * (off + hw) + Vector3(0, lift, 0)
	var b0: Vector3 = b + perp * (off - hw) + Vector3(0, lift, 0)
	var b1: Vector3 = b + perp * (off + hw) + Vector3(0, lift, 0)
	_quad(st, a0, a1, b1, b0, col)

# ── Züge ─────────────────────────────────────────────────────────────────────
## v16.9: sammelt die lokalen Mesh-AABBs eines GLB-Baums (gleiche Technik wie
## WorldRenderer3D._collect_local_aabbs) - fuer die XZ-Zentrierung der Modelle.
func _collect_mesh_aabbs(n: Node, xf: Transform3D, out: Array, is_root: bool) -> void:
	var t: Transform3D = xf
	if n is Node3D and not is_root: t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(t * (n as MeshInstance3D).mesh.get_aabb())
	for c in n.get_children(): _collect_mesh_aabbs(c, t, out, false)

## v16.9: faerbt Mesh-Flaechen der Zug-GLBs um:
## - M_Linie (Kabine / Ladung) -> Linienfarbe (opak), analog _tint_building_wall()
## - M_Glas (Fenster) -> transparent erzwingen (Blender-Export liefert opak!)
func _tint_lini_col(n: Node, col: Color) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var m: Material = mi.mesh.surface_get_material(i)
				if m == null: continue
				if m.resource_name == "M_Linie":
					var tinted := StandardMaterial3D.new()
					tinted.albedo_color = col; tinted.roughness = 0.7
					mi.set_surface_override_material(i, tinted)
				elif m.resource_name == "M_Glas":
					var glass := StandardMaterial3D.new()
					glass.albedo_color = Color(0.77, 0.91, 0.98, 0.30)
					glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					glass.roughness = 0.12; glass.metallic = 0.2
					glass.cull_mode = BaseMaterial3D.CULL_DISABLED
					mi.set_surface_override_material(i, glass)
	for c in n.get_children(): _tint_lini_col(c, col)

## v16.9: instanziert ein Zug-GLB. Die Exporte stehen seitlich geparkt
## (AABB-Mitte != Ursprung, siehe Probe), darum wird XZ ueber die Mesh-AABBs
## zentriert; der Boden liegt bereits bei y=0 (Raeder auf Schienenoberkante),
## darum bleibt Y unveraendert. Zurueck kommt ein skalierter Container-Knoten.
func _prep_vehicle(scene: PackedScene, s: float, col: Color) -> Node3D:
	var inst := scene.instantiate() as Node3D
	var boxes: Array = []
	_collect_mesh_aabbs(inst, Transform3D.IDENTITY, boxes, true)
	if not boxes.is_empty():
		var u: AABB = boxes[0]
		for i in range(1, boxes.size()): u = u.merge(boxes[i] as AABB)
		inst.position = Vector3(-u.get_center().x, 0.0, -u.get_center().z)
	_tint_lini_col(inst, col)
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * s
	holder.add_child(inst)
	return holder

func _make_train_node(t: TrainEntity) -> Node3D:
	var root := Node3D.new()
	var line_col: Color = RailSys.line_color(t.line_id) if t.line_id >= 0 else Color(0.55, 0.55, 0.6)
	var loco := _prep_vehicle(LOCO_SCENE, LOCO_SCALE, line_col)
	loco.name = "Loco"
	root.add_child(loco)
	for i in t.wagons:
		var w := _prep_vehicle(WAGON_SCENE, WAGON_SCALE, line_col)
		w.name = "Wagon%d" % i
		root.add_child(w)
	root.set_meta("line_id", t.line_id)
	root.set_meta("wagons", t.wagons)
	return root

## v16.4: Lok-Knoten eines Zuges (Anker für den mitfahrenden Spieler).
func get_loco_node(t: TrainEntity) -> Node3D:
	var n: Node3D = _train_nodes.get(t.id) as Node3D
	return n.get_node_or_null("Loco") as Node3D if n != null else null

## v16.4: Weltpositionen von Lok und Waggons (zum Einsteigen: nah an IRGENDEINEM Teil des Zuges).
func train_part_positions(t: TrainEntity) -> Array:
	var out: Array = [_world_pos(t.head)]
	for i in t.wagons:
		var tp: Array = _trail_point(t, WAGON_SPACING * float(i + 1))
		out.append(_world_pos(tp[0] as Vector2))
	return out

## Punkt in `dist` Kacheln Entfernung entlang der Spur (Kopf zuerst), samt Blickrichtung.
func _trail_point(t: TrainEntity, dist: float) -> Array:
	var pts: Array = [t.head]
	pts.append_array(t.trail)
	var left: float = dist
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]; var b: Vector2 = pts[i + 1]
		var seg: float = a.distance_to(b)
		if seg <= 0.0001: continue
		if left <= seg:
			return [a.lerp(b, left / seg), (a - b) / seg]
		left -= seg
	return [pts[pts.size() - 1], t.heading]

func _place_part(node: Node3D, p: Vector2, dir: Vector2) -> void:
	var w: Vector3 = _world_pos(p)
	node.position = Vector3(w.x, w.y + 0.12, w.z)
	node.rotation.y = atan2(-dir.y, dir.x)

func _update_trains() -> void:
	var alive: Dictionary = {}
	for tv in RailSys.trains:
		var t: TrainEntity = tv
		alive[t.id] = true
		var node: Node3D = _train_nodes.get(t.id) as Node3D
		if node != null and (int(node.get_meta("line_id", -2)) != t.line_id or int(node.get_meta("wagons", -1)) != t.wagons):
			node.queue_free(); node = null; _train_nodes.erase(t.id)   # Farbe/Länge hat sich geändert
		if node == null:
			node = _make_train_node(t); add_child(node); _train_nodes[t.id] = node
		_place_part(node.get_node("Loco") as Node3D, t.head, t.heading)
		for i in t.wagons:
			var tp: Array = _trail_point(t, WAGON_SPACING * float(i + 1))
			_place_part(node.get_node("Wagon%d" % i) as Node3D, tp[0] as Vector2, tp[1] as Vector2)
		# im Depot geparkte Züge (ohne Linie) stehen sichtbar, laufen aber nicht
	for id in _train_nodes.keys():
		if not alive.has(id):
			(_train_nodes[id] as Node).queue_free(); _train_nodes.erase(id)
