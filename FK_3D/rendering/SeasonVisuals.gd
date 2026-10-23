class_name SeasonVisuals
extends Node3D
## Sichtbare Jahreszeiten (v15.4).
##
## Rechnet aus SeasonSys + Tageszeit eine KONTINUIERLICHE Jahres-Phase aus und
## überblendet daraus weich (Keyframes jeweils in der Saison-MITTE):
##   - Boden-Tönung der Vegetation + SCHNEE   (globale Shader-Parameter, gelesen vom
##                                              Terrain-Shader season_terrain.gdshader)
##   - Laub-/Busch-Farben                     (gemeinsame Materialien von pine_tree/bush.glb)
##   - Eis auf dem Wasser
##   - Sonnenfarbe/-stärke, Himmelston        (apply_lighting)
##   - Partikel: Schneefall (Winter), fallendes Laub (Herbst), Blütenblätter (Frühling)
##
## Frühling = 0, Sommer = 1, Herbst = 2, Winter = 3 (wie SeasonSys.SEASONS).

# Keyframes in der Mitte der jeweiligen Saison: [Frühling, Sommer, Herbst, Winter]
const K_GRASS: Array = [Vector3(1.04, 1.12, 0.92), Vector3(0.92, 1.05, 0.80),
	Vector3(1.62, 0.90, 0.50), Vector3(0.86, 0.92, 0.98)]
const K_TREE: Array = [Color(1.0, 1.06, 0.94), Color(0.92, 1.0, 0.88),
	Color(1.14, 0.96, 0.76), Color(0.90, 0.97, 1.0)]
const K_BUSH: Array = [Color(1.0, 1.08, 1.0), Color(0.94, 1.0, 0.88),
	Color(1.9, 0.88, 0.48), Color(0.88, 0.93, 0.97)]
const K_SNOW: Array = [0.0, 0.0, 0.0, 1.0]
const K_SUN: Array = [Color(1.0, 0.97, 0.90), Color(1.0, 0.95, 0.84),
	Color(1.0, 0.80, 0.60), Color(0.80, 0.90, 1.0)]
const K_SUN_E: Array = [1.0, 1.12, 0.95, 0.82]
const K_SKY: Array = [Color(1, 1, 1), Color(1, 1, 1), Color(1.06, 0.95, 0.86), Color(0.88, 0.95, 1.06)]
const K_CLOUD: Array = [0.45, 0.33, 0.62, 0.74]

# aktuelle (interpolierte) Werte - von RealismFX/GameController gelesen
var phase: float = 0.0
var snow: float = 0.0
var grass_tint: Vector3 = Vector3.ONE
var sun_tint: Color = Color.WHITE
var sun_energy_mult: float = 1.0
var sky_tint: Color = Color.WHITE
var cloud_cover: float = 0.45
var frozen: float = 0.0

var _renderer: Node = null
var _tree_mats: Array = []   # {"mat": StandardMaterial3D, "base": Color, "leaf": bool}
var _bush_mats: Array = []
var _acc: float = 1.0
var _p_snow: GPUParticles3D = null
var _p_leaf: GPUParticles3D = null
var _p_petal: GPUParticles3D = null

func setup(renderer: Node) -> void:
	_renderer = renderer
	_gather_foliage_materials()
	_p_snow = _make_particles("Snowfall", 2600, 14.0, 0.15, Color(0.96, 0.98, 1.0), 0.7, 30.0, false)
	_p_leaf = _make_particles("FallingLeaves", 170, 11.0, 0.30, Color.WHITE, 1.4, 30.0, true)
	_p_petal = _make_particles("Petals", 230, 12.0, 0.15, Color(1.0, 0.80, 0.88), 0.9, 30.0, false)
	_set_leaf_gradient()
	_acc = 99.0   # sofort beim ersten Frame anwenden
	process_visuals(0.0, Vector3.ZERO)

# ── Jahres-Phase ─────────────────────────────────────────────────────────────
func _season_day_float() -> float:
	var frac: float = DayNight.time / maxf(0.01, DayNight.day_length)
	return float(SeasonSys.season_day) + clampf(frac, 0.0, 0.999)

func _phase() -> float:
	var cs: int = SeasonSys.current_season
	var days: float = float(SeasonSys.SEASONS[cs]["days"])
	return float(cs) + clampf(_season_day_float() / days, 0.0, 0.9999)

static func _key(arr: Array, p: float) -> Variant:
	var x: float = fposmod(p - 0.5, 4.0)
	var i: int = int(floor(x))
	var t: float = smoothstep(0.0, 1.0, x - float(i))
	var a: Variant = arr[i % 4]
	var b: Variant = arr[(i + 1) % 4]
	if a is float: return lerpf(a as float, b as float, t)
	return a.lerp(b, t)

# ── Pro Frame ────────────────────────────────────────────────────────────────
## focus = Weltpunkt, um den herum Partikel fallen (Kamerafokus bzw. Spieler).
func process_visuals(delta: float, focus: Vector3) -> void:
	_acc += delta
	if _acc >= 0.2:
		_acc = 0.0
		_recompute()
	for pn in [_p_snow, _p_leaf, _p_petal]:
		if pn != null:
			(pn as GPUParticles3D).global_position = Vector3(focus.x, focus.y + 22.0, focus.z)

func _recompute() -> void:
	phase = _phase()
	var new_snow: float = _key(K_SNOW, phase) as float
	grass_tint = _key(K_GRASS, phase) as Vector3
	sun_tint = _key(K_SUN, phase) as Color
	sun_energy_mult = _key(K_SUN_E, phase) as float
	sky_tint = _key(K_SKY, phase) as Color
	cloud_cover = _key(K_CLOUD, phase) as float
	snow = new_snow
	RenderingServer.global_shader_parameter_set("season_snow", snow)
	RenderingServer.global_shader_parameter_set("season_grass_tint", grass_tint)

	_apply_foliage()

	var new_frozen: float = smoothstep(0.55, 0.95, snow)
	if absf(new_frozen - frozen) > 0.01 or (new_frozen == 0.0) != (frozen == 0.0):
		frozen = new_frozen
		if _renderer != null and _renderer.has_method("set_water_frozen"):
			_renderer.call("set_water_frozen", frozen)

	# Partikel-Intensitäten je Saison (d = Tag in der Saison, 0..15)
	var cs: int = SeasonSys.current_season
	var d: float = _season_day_float()
	var snow_r: float = 0.0
	var leaf_r: float = 0.0
	var petal_r: float = 0.0
	if cs == 3:
		var edge: float = smoothstep(0.0, 1.5, d) * (1.0 - smoothstep(13.5, 15.0, d))
		snow_r = (0.35 + 0.65 * sin(d * PI / 15.0)) * edge
	elif cs == 2:
		leaf_r = smoothstep(0.5, 3.0, d) * (1.0 - smoothstep(12.0, 15.0, d)) * 0.85
	elif cs == 0:
		petal_r = smoothstep(2.0, 5.0, d) * (1.0 - smoothstep(11.0, 14.0, d)) * 0.6
	_set_rate(_p_snow, snow_r)
	_set_rate(_p_leaf, leaf_r)
	_set_rate(_p_petal, petal_r)

func _set_rate(p: GPUParticles3D, r: float) -> void:
	if p == null: return
	p.emitting = r > 0.02
	p.amount_ratio = clampf(r, 0.0, 1.0)

# ── Laub-/Busch-Farben ───────────────────────────────────────────────────────
func _collect_mats(scene: PackedScene, out: Array) -> void:
	if scene == null: return
	var inst: Node = scene.instantiate()
	var stack: Array = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var m: Mesh = (n as MeshInstance3D).mesh
			for i in m.get_surface_count():
				var sm: StandardMaterial3D = m.surface_get_material(i) as StandardMaterial3D
				if sm != null:
					var nm: String = sm.resource_name.to_lower()
					var found := false
					for e in out:
						if (e as Dictionary)["mat"] == sm: found = true
					if not found:
						out.append({"mat": sm, "base": sm.albedo_color, "leaf": nm.begins_with("leaves") or nm == "green"})
		for c in n.get_children(): stack.append(c)
	inst.free()

func _gather_foliage_materials() -> void:
	if _renderer == null: return
	_collect_mats(_renderer.get("PINE_TREE_SCENE") as PackedScene, _tree_mats)
	_collect_mats(_renderer.get("BUSH_SCENE") as PackedScene, _bush_mats)

func _apply_foliage() -> void:
	var tt: Color = _key(K_TREE, phase) as Color
	var bt: Color = _key(K_BUSH, phase) as Color
	for e in _tree_mats:
		var d: Dictionary = e
		if not bool(d["leaf"]): continue
		var base: Color = d["base"] as Color
		var c := Color(base.r * tt.r, base.g * tt.g, base.b * tt.b, base.a)
		d["mat"].albedo_color = c.lerp(Color(0.88, 0.94, 0.97, base.a), snow * 0.55)   # Raureif/Schnee auf Nadeln
	for e in _bush_mats:
		var d2: Dictionary = e
		if not bool(d2["leaf"]): continue
		var base2: Color = d2["base"] as Color
		var c2 := Color(base2.r * bt.r, base2.g * bt.g, base2.b * bt.b, base2.a)
		d2["mat"].albedo_color = c2.lerp(Color(0.90, 0.95, 0.98, base2.a), snow * 0.5)

# ── Beleuchtung ──────────────────────────────────────────────────────────────
## Nach GameController._update_day_night_visuals() aufrufen: überlagert Saison-Töne.
func apply_lighting(sun: DirectionalLight3D, fill: DirectionalLight3D, env: Environment, night_t: float) -> void:
	var day_w: float = 1.0 - night_t
	if sun != null:
		var tc: Color = Color.WHITE.lerp(sun_tint, day_w)
		sun.light_color = Color(sun.light_color.r * tc.r, sun.light_color.g * tc.g, sun.light_color.b * tc.b)
		sun.light_energy *= lerpf(1.0, sun_energy_mult, day_w)
	if fill != null:
		fill.light_color = Color.WHITE.lerp(sky_tint, day_w * 0.5)
	if env != null and env.background_mode == Environment.BG_COLOR:
		var bg: Color = env.background_color
		env.background_color = Color(bg.r * sky_tint.r, bg.g * sky_tint.g, bg.b * sky_tint.b)
		var am: Color = env.ambient_light_color
		env.ambient_light_color = Color(am.r * sky_tint.r, am.g * sky_tint.g, am.b * sky_tint.b)

# ── Partikel ─────────────────────────────────────────────────────────────────
func _soft_dot_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1)); g.set_color(1, Color(1, 1, 1, 0))
	g.set_offset(0, 0.0); g.set_offset(1, 1.0)
	var t := GradientTexture2D.new()
	t.gradient = g; t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5); t.fill_to = Vector2(1.0, 0.5)
	t.width = 32; t.height = 32
	return t

func _make_particles(pname: String, amount: int, lifetime: float, size: float,
		color: Color, terminal_speed: float, spread_xz: float, is_leaf: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = pname
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime          # Volumen ist sofort gefüllt
	p.local_coords = false
	p.emitting = false
	p.amount_ratio = 0.0
	p.visibility_aabb = AABB(Vector3(-45, -34, -45), Vector3(90, 40, 90))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(spread_xz, 0.5, spread_xz)
	pm.direction = Vector3(0.25 if is_leaf else 0.12, -1.0, 0.08)
	pm.spread = 22.0 if is_leaf else 10.0
	pm.initial_velocity_min = terminal_speed * 0.4
	pm.initial_velocity_max = terminal_speed * 0.9
	pm.gravity = Vector3(0.25 if is_leaf else 0.0, -terminal_speed * 0.9, 0.0)
	pm.damping_min = 0.8; pm.damping_max = 0.9
	pm.scale_min = 0.6; pm.scale_max = 1.3
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.4 if is_leaf else 0.7
	pm.turbulence_noise_scale = 2.2
	if is_leaf:
		pm.angle_min = 0.0; pm.angle_max = 360.0
		pm.angular_velocity_min = -140.0; pm.angular_velocity_max = 140.0
	p.process_material = pm
	var q := QuadMesh.new(); q.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot_texture()
	mat.albedo_color = color
	q.material = mat
	p.draw_pass_1 = q
	add_child(p)
	return p

func _set_leaf_gradient() -> void:
	if _p_leaf == null: return
	var g := Gradient.new()
	g.set_color(0, Color(0.95, 0.45, 0.10)); g.set_offset(0, 0.0)
	g.add_point(0.35, Color(0.80, 0.25, 0.08))
	g.add_point(0.7, Color(0.95, 0.72, 0.15))
	g.set_color(g.get_point_count() - 1, Color(0.62, 0.30, 0.10)); g.set_offset(g.get_point_count() - 1, 1.0)
	var gt := GradientTexture1D.new(); gt.gradient = g
	(_p_leaf.process_material as ParticleProcessMaterial).color_initial_ramp = gt
