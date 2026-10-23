extends Node
## Grafik-Einstellungen (v15.4): schaltbarer Realismus-Modus + globale Shader-Parameter.
##
## - Registriert die GLOBALEN Shader-Parameter, die Terrain-/Himmel-Shader lesen
##   (müssen existieren, BEVOR der erste Shader kompiliert -> darum ein Autoload,
##   das als erstes geladen wird).
## - Hält den Schalter "Realistische Grafik" und speichert ihn in user://graphics.cfg.
## Die eigentliche Umgebungs-/Licht-Umschaltung macht rendering/RealismFX.gd
## (hört auf das Signal `changed`).

signal changed

const PATH: String = "user://graphics.cfg"

var realistic: bool = false
## v15.7: UI-Größe (skaliert nur die Oberfläche, nicht die 3D-Welt). Wählbar im Pause-Menü.
const UI_SCALES: Array = [0.85, 1.0, 1.15]
var ui_scale: float = 1.0
var _loaded: bool = false

func _init() -> void:
	_register_globals()

func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		realistic = bool(cf.get_value("graphics", "realistic", false))
		ui_scale = float(cf.get_value("graphics", "ui_scale", 1.0))
		if not UI_SCALES.has(ui_scale): ui_scale = 1.0
	_loaded = true
	_push_globals()
	_apply_ui_scale()

func set_realistic(v: bool) -> void:
	if v == realistic: return
	realistic = v
	_push_globals()
	_save()
	changed.emit()

func set_ui_scale(v: float) -> void:
	if not UI_SCALES.has(v) or is_equal_approx(v, ui_scale): return
	ui_scale = v
	_apply_ui_scale()
	_save()

func _apply_ui_scale() -> void:
	# content_scale_factor wirkt bei Stretch-Modus "canvas_items" nur auf 2D/UI, nicht auf die 3D-Szene
	get_tree().root.content_scale_factor = ui_scale

func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("graphics", "realistic", realistic)
	cf.set_value("graphics", "ui_scale", ui_scale)
	cf.save(PATH)

## Welche Renderer-Features stehen zur Verfügung? (SSAO/Volumetrik nur Forward+)
func is_forward_plus() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"

func _register_globals() -> void:
	var defs: Array = [
		["season_snow", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		["season_grass_tint", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ONE],
		["realism_enabled", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		["realism_cloud_shadow", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
	]
	# (global_shader_parameter_get_list() ist Editor-only -> hier einfach hinzufügen;
	#  ein Autoload-_init läuft pro Prozess genau einmal)
	for d in defs:
		RenderingServer.global_shader_parameter_add(d[0], d[1], d[2])

func _push_globals() -> void:
	RenderingServer.global_shader_parameter_set("realism_enabled", 1.0 if realistic else 0.0)
	RenderingServer.global_shader_parameter_set("realism_cloud_shadow", 0.85 if realistic else 0.0)
