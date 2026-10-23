## ExploreSystem.gd
## Feature (v16.6, Logistik-Update Phase 4): Erkundung ("Nebel des Unbekannten").
## Große Welten (Größe "HUGE", 120x120) werden komplett erzeugt, aber nur ein Heimat-Bereich ist
## bekannt. Der Rest bleibt Nebel, bis Erkundungsstationen (Gebäude btype "EXPLORER") ihn Ring für
## Ring aufdecken. Klassische Welten (SMALL/MEDIUM/LARGE) und alte Saves haben `enabled == false`:
## dort ist die ganze Karte bekannt und nichts ändert sich.
##
## - `mask`: 1 Byte je Kachel (255 = aufgedeckt, 0 = Nebel; 255, weil der Shader das R8-Byte als 0..1 liest). Wird als R8-Textur an den Terrain-Shader gegeben
##   (globale Shader-Parameter explore_enabled / explore_mask / explore_world): unaufgedeckte Kacheln werden
##   dort verworfen (Insel im Nebel). Vegetation/Wasser filtert der Renderer (WorldRenderer3D.apply_fog()).
## - Regeln (GameController): gebaut, Gleise gelegt, Kolonien gegründet wird nur auf aufgedecktem Gebiet.
extends Node

signal revealed_changed

const TILE: float = 2.0   # = WorldRenderer3D.TILE_SIZE (hier fest, damit der Autoload ohne Renderer funktioniert)

var enabled: bool = false
var w: int = 0
var h: int = 0
var mask: PackedByteArray = PackedByteArray()
var revealed_count: int = 0
var dirty: bool = false          # Maske wurde geändert, Textur/Renderer noch nicht aktualisiert
var _img: Image = null
var _tex: ImageTexture = null

func _init() -> void:
	# Globale Shader-Parameter (einmal pro Prozess; müssen VOR dem ersten Terrain-Material existieren)
	var white := Image.create(1, 1, false, Image.FORMAT_R8)
	white.fill(Color(1, 1, 1, 1))
	_tex = ImageTexture.create_from_image(white)
	RenderingServer.global_shader_parameter_add("explore_enabled", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	RenderingServer.global_shader_parameter_add("explore_mask", RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, _tex)
	RenderingServer.global_shader_parameter_add("explore_world", RenderingServer.GLOBAL_VAR_TYPE_VEC2, Vector2(1.0, 1.0))

## Neue Welt: `fog_enabled` false = alles bekannt. Sonst wird ein Kreis um `center` aufgedeckt.
func init_world(world_w: int, world_h: int, fog_enabled: bool, center: Vector2i = Vector2i(0, 0), radius: float = 0.0) -> void:
	enabled = fog_enabled
	w = world_w; h = world_h
	mask = PackedByteArray()
	revealed_count = 0
	if enabled:
		mask.resize(w * h)
		mask.fill(0)
		if radius > 0.0: reveal_circle(center.x, center.y, radius)
	_rebuild_texture()
	dirty = true

func is_revealed(tx: int, ty: int) -> bool:
	if not enabled: return true
	if tx < 0 or ty < 0 or tx >= w or ty >= h: return false
	return mask[ty * w + tx] != 0

## Deckt alle Kacheln im Kreis (Kachelmitten, Radius in Kacheln) auf. Gibt die Zahl NEU aufgedeckter zurück.
func reveal_circle(cx: int, cy: int, r: float) -> int:
	if not enabled or mask.is_empty(): return 0
	var added: int = 0
	var ri: int = int(ceil(r))
	var r2: float = r * r
	for dx in range(-ri, ri + 1):
		for dy in range(-ri, ri + 1):
			if float(dx * dx + dy * dy) > r2: continue
			var tx: int = cx + dx; var ty: int = cy + dy
			if tx < 0 or ty < 0 or tx >= w or ty >= h: continue
			var i: int = ty * w + tx
			if mask[i] == 0:
				mask[i] = 255; added += 1
	if added > 0:
		revealed_count += added
		dirty = true
	return added

func reveal_all() -> void:
	if not enabled: return
	mask.fill(255)
	revealed_count = w * h
	dirty = true

func fraction() -> float:
	if not enabled or w * h == 0: return 1.0
	return float(revealed_count) / float(w * h)

func _rebuild_texture() -> void:
	if not enabled or w <= 0 or h <= 0:
		var white := Image.create(1, 1, false, Image.FORMAT_R8)
		white.fill(Color(1, 1, 1, 1))
		_img = white
		_tex = ImageTexture.create_from_image(white)
		RenderingServer.global_shader_parameter_set("explore_enabled", 0.0)
		RenderingServer.global_shader_parameter_set("explore_mask", _tex)
		return
	_img = Image.create_from_data(w, h, false, Image.FORMAT_R8, mask)
	_tex = ImageTexture.create_from_image(_img)
	RenderingServer.global_shader_parameter_set("explore_world", Vector2(float(w) * TILE, float(h) * TILE))
	RenderingServer.global_shader_parameter_set("explore_mask", _tex)
	RenderingServer.global_shader_parameter_set("explore_enabled", 1.0)

## Maske in die Shader-Textur übertragen (vom GameController gedrosselt aufgerufen).
## Gibt true zurück, wenn sich etwas geändert hat (dann Renderer-Vegetation/Wasser neu filtern).
func flush() -> bool:
	if not dirty: return false
	dirty = false
	if enabled and _img != null and _tex != null and _img.get_width() == w and _img.get_height() == h:
		_img.set_data(w, h, false, Image.FORMAT_R8, mask)
		_tex.update(_img)
	else:
		_rebuild_texture()
	revealed_changed.emit()
	return true

# ── Speichern: Lauflängen-Kodierung (RLE) als Text, passt gut zu großen zusammenhängenden Flächen ──
func serialize() -> Dictionary:
	if not enabled: return {"enabled": false}
	var runs: Array = []
	var cur: int = 1 if (mask.size() > 0 and mask[0] != 0) else 0
	var first: int = cur
	var n: int = 0
	for i in mask.size():
		var bit: int = 1 if mask[i] != 0 else 0
		if bit == cur: n += 1
		else:
			runs.append(n); cur = bit; n = 1
	runs.append(n)
	return {"enabled": true, "w": w, "h": h, "first": first, "runs": runs}

func deserialize(data) -> void:
	if not (data is Dictionary) or not bool((data as Dictionary).get("enabled", false)):
		enabled = false
		mask = PackedByteArray(); revealed_count = 0
		_rebuild_texture(); dirty = true
		return
	var d: Dictionary = data as Dictionary
	w = int(d.get("w", w)); h = int(d.get("h", h))
	enabled = true
	mask = PackedByteArray(); mask.resize(w * h); mask.fill(0)
	var v: int = int(d.get("first", 0)); var i: int = 0
	for r in (d.get("runs", []) as Array):
		var cnt: int = int(r)
		for k in cnt:
			if i >= mask.size(): break
			mask[i] = 255 if v == 1 else 0; i += 1
		v = 1 - v
	revealed_count = 0
	for b in mask: if b != 0: revealed_count += 1
	_rebuild_texture()
	dirty = true
