class_name PanoramaBackground
extends ColorRect
## Rotierendes 360°-Panorama als Menühintergrund (Minecraft-Stil).
## Das Bild (assets/panorama/colony_panorama.jpg) ist ein aus einer echten
## Kolonie gerenderter Equirect-Streifen (±45° Breitengrad, siehe General).
## Fehlt die Datei, bleibt ein ruhiger dunkler Hintergrund.
##
## Läuft nur, solange der Node sichtbar ist (kein Verbrauch im Spiel).

const PANO_PATH: String = "res://assets/panorama/colony_panorama.jpg"
const SHADER_PATH: String = "res://assets/panorama/panorama.gdshader"
const SPEED_DEG: float = 2.2          # Grad pro Sekunde (~160 s je Umdrehung)

static var _yaw: float = 0.35          # geteilt, damit die Drehung beim Menüwechsel nicht springt
var _mat: ShaderMaterial = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color("1c1611")
	var tex: Texture2D = load(PANO_PATH) as Texture2D
	var shader: Shader = load(SHADER_PATH) as Shader
	if tex == null or shader == null:
		push_warning("PanoramaBackground: Panorama oder Shader nicht gefunden - Fallback-Hintergrund")
		set_process(false)
		return
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("pano", tex)
	material = _mat
	resized.connect(_update_aspect)
	visibility_changed.connect(func(): set_process(is_visible_in_tree()))
	_update_aspect()
	set_process(is_visible_in_tree())

func set_dim(amount: float) -> void:
	if _mat: _mat.set_shader_parameter("dim", clampf(amount, 0.0, 1.0))

func _update_aspect() -> void:
	if _mat and size.y > 1.0:
		_mat.set_shader_parameter("aspect", size.x / size.y)

func _process(delta: float) -> void:
	_yaw = fposmod(_yaw + deg_to_rad(SPEED_DEG) * delta, TAU)
	if _mat: _mat.set_shader_parameter("yaw", _yaw)
