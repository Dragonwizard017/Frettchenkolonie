class_name RealismFX
extends Node
## Schaltbarer Realismus-Modus (v15.4).
##
## AN:  - prozeduraler Himmel (Wolken, Sonnenscheibe, Sonnenauf-/untergangsglühen, Sterne)
##      - Sonne wandert über den Tag (Schatten wandern, warmes Licht morgens/abends)
##      - Tonemapping (ACES), Glow/Bloom, Farbkorrektur
##      - Umgebungslicht aus dem Himmel + SSAO (Forward+)
##      - weichere, weiter reichende Schatten
##      - Dunst; Volumetrik ("Lichtstrahlen" durch Bäume) nur in perspektivischer Kamera
##      - 4x MSAA, Wolkenschatten auf dem Boden (Terrain-Shader)
## AUS: exakt der vorherige Zustand (Werte werden beim Einschalten gemerkt).
##
## Die Einstellung kommt aus GraphicsSettings.realistic.

const SKY_SHADER: String = "res://assets/shaders/sky_realistic.gdshader"

var _env: Environment = null
var _sun: DirectionalLight3D = null
var _fill: DirectionalLight3D = null
var _viewport: Viewport = null
var _season: SeasonVisuals = null

var _sky_mat: ShaderMaterial = null
var _sky: Sky = null
var _active: bool = false
var _saved: Dictionary = {}
var _base_az: float = 0.0
var _cloud_off: Vector2 = Vector2.ZERO
var _persp: bool = false

func setup(env: Environment, sun: DirectionalLight3D, fill: DirectionalLight3D,
		vp: Viewport, season: SeasonVisuals) -> void:
	_env = env; _sun = sun; _fill = fill; _viewport = vp; _season = season
	if _sun != null:
		var s0: Vector3 = (_sun.global_transform.basis * Vector3.FORWARD) * -1.0   # Richtung ZUR Sonne
		_base_az = atan2(s0.x, s0.z)
	GraphicsSettings.changed.connect(_on_changed)
	_on_changed()

func _on_changed() -> void:
	if GraphicsSettings.realistic and not _active: _enable()
	elif not GraphicsSettings.realistic and _active: _disable()

# ── Ein-/Ausschalten ─────────────────────────────────────────────────────────
func _enable() -> void:
	if _env == null: return
	_active = true
	_saved = {
		"bg_mode": _env.background_mode, "sky": _env.sky,
		"amb_src": _env.ambient_light_source, "refl": _env.reflected_light_source,
		"tonemap": _env.tonemap_mode, "exposure": _env.tonemap_exposure,
		"glow": _env.glow_enabled, "ssao": _env.ssao_enabled,
		"fog": _env.fog_enabled, "vfog": _env.volumetric_fog_enabled,
		"adj": _env.adjustment_enabled,
		"sh_mode": _sun.directional_shadow_mode if _sun else 0,
		"sh_dist": _sun.directional_shadow_max_distance if _sun else 100.0,
		"sh_blur": _sun.shadow_blur if _sun else 1.0,
		"sun_ang": _sun.light_angular_distance if _sun else 0.0,
		"sun_rot": _sun.rotation if _sun else Vector3.ZERO,
		"fill_sky": _fill.sky_mode if _fill else 0,
		"msaa": _viewport.msaa_3d if _viewport else 0,
	}
	if _sky_mat == null:
		_sky_mat = ShaderMaterial.new()
		_sky_mat.shader = load(SKY_SHADER) as Shader
		_sky = Sky.new()
		_sky.sky_material = _sky_mat
		_sky.radiance_size = Sky.RADIANCE_SIZE_128
	_env.background_mode = Environment.BG_SKY
	_env.sky = _sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_sky_contribution = 1.0
	_env.ambient_light_energy = 0.7
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 0.98   # ACES hellt auf -> knapp unter 1, sonst überbelichtet
	_env.glow_enabled = true
	_env.glow_intensity = 0.4
	_env.glow_strength = 0.9
	_env.glow_bloom = 0.03
	_env.glow_hdr_threshold = 1.15
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	_env.adjustment_enabled = true
	_env.adjustment_contrast = 1.08
	_env.adjustment_saturation = 1.04
	if GraphicsSettings.is_forward_plus():
		_env.ssao_enabled = true
		_env.ssao_radius = 1.8
		_env.ssao_intensity = 2.0
		_env.ssao_power = 1.5
		_env.ssao_detail = 0.4
	_env.fog_light_color = Color(0.72, 0.82, 0.92)
	_env.fog_sun_scatter = 0.35
	_env.fog_sky_affect = 0.12   # Himmel nicht auswaschen
	if _sun != null:
		_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		_sun.directional_shadow_max_distance = 170.0
		_sun.shadow_blur = 1.6
		_sun.light_angular_distance = 0.5
		_sun.light_volumetric_fog_energy = 1.5
	if _fill != null:
		_fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY      # keine zweite "Sonnenscheibe"
	if _viewport != null:
		_viewport.msaa_3d = Viewport.MSAA_4X
	_persp = false
	_apply_camera_mode(true)

func _disable() -> void:
	_active = false
	if _env == null or _saved.is_empty(): return
	_env.background_mode = _saved["bg_mode"]
	_env.sky = _saved["sky"]
	_env.ambient_light_source = _saved["amb_src"]
	_env.reflected_light_source = _saved["refl"]
	_env.tonemap_mode = _saved["tonemap"]
	_env.tonemap_exposure = _saved["exposure"]
	_env.glow_enabled = _saved["glow"]
	_env.ssao_enabled = _saved["ssao"]
	_env.fog_enabled = _saved["fog"]
	_env.volumetric_fog_enabled = _saved["vfog"]
	_env.adjustment_enabled = _saved["adj"]
	if _sun != null:
		_sun.directional_shadow_mode = _saved["sh_mode"]
		_sun.directional_shadow_max_distance = _saved["sh_dist"]
		_sun.shadow_blur = _saved["sh_blur"]
		_sun.light_angular_distance = _saved["sun_ang"]
		_sun.rotation = _saved["sun_rot"]
		_sun.light_volumetric_fog_energy = 1.0
	if _fill != null: _fill.sky_mode = _saved["fill_sky"]
	if _viewport != null: _viewport.msaa_3d = _saved["msaa"]

# ── Pro Frame (nur wenn aktiv) ───────────────────────────────────────────────
## pct = Tageszeit 0..1 (DayNight.time/day_length), night_t = 0..1 Nachtanteil
func update_frame(delta: float, pct: float, night_t: float) -> void:
	if not _active or _env == null: return
	# Sonnenbahn: Aufgang im Osten, Mittag hoch, Untergang im Westen
	var t_day: float = clampf(pct / 0.72, 0.0, 1.0)
	var elev_vis: float = sin(t_day * PI)                       # 0..1..0 (sichtbar)
	if pct > 0.72: elev_vis = -0.25 * sin(clampf((pct - 0.72) / 0.28, 0.0, 1.0) * PI)
	var elev_deg: float = lerpf(14.0, 62.0, clampf(sin(t_day * PI), 0.0, 1.0))
	var az: float = _base_az + lerpf(-1.15, 1.15, t_day)
	var el: float = deg_to_rad(elev_deg)
	var to_sun := Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az)).normalized()
	if _sun != null:
		_sun.global_transform.basis = Basis.looking_at(-to_sun, Vector3.UP)
		# tiefstehende Sonne: wärmeres, schwächeres Licht
		var low: float = 1.0 - clampf(elev_deg / 40.0, 0.0, 1.0)
		var warm := Color(1.0, 0.72, 0.48)
		_sun.light_color = _sun.light_color.lerp(warm, low * 0.65 * (1.0 - night_t))

	_cloud_off += Vector2(0.004, 0.0015) * delta
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("night", night_t)
		_sky_mat.set_shader_parameter("sun_elev", elev_vis)
		_sky_mat.set_shader_parameter("cloud_offset", _cloud_off)
		if _season != null:
			_sky_mat.set_shader_parameter("tint", Vector3(_season.sky_tint.r, _season.sky_tint.g, _season.sky_tint.b))
			_sky_mat.set_shader_parameter("cloud_cover", _season.cloud_cover)
	_env.ambient_light_energy = lerpf(0.7, 1.4, night_t)
	_apply_camera_mode(false)

# Dunst/Volumetrik nur mit perspektivischer Kamera (Frettchenmodus/Panorama):
# In der orthografischen Iso-Kamera ist die "Tiefe" riesig und Nebel würde alles verwaschen.
func _apply_camera_mode(force: bool) -> void:
	if _viewport == null: return
	var cam: Camera3D = _viewport.get_camera_3d()
	if cam == null: return
	var persp: bool = cam.projection == Camera3D.PROJECTION_PERSPECTIVE
	if persp == _persp and not force: return
	_persp = persp
	_env.fog_enabled = persp
	_env.fog_density = 0.0028
	var vol: bool = persp and GraphicsSettings.is_forward_plus()
	_env.volumetric_fog_enabled = vol
	if vol:
		_env.volumetric_fog_density = 0.005
		_env.volumetric_fog_albedo = Color(0.92, 0.94, 1.0)
		_env.volumetric_fog_anisotropy = 0.7
		_env.volumetric_fog_length = 90.0
		_env.volumetric_fog_ambient_inject = 0.1
