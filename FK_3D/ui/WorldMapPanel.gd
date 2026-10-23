## WorldMapPanel.gd
## Feature (v16.6, Logistik-Update Phase 4): Weltkarte. Zeigt die ganze Welt von oben: Gelände nach Biom
## (Nebel = dunkel), Gebiete und Rathäuser der Kolonien, Gleise, Bahnhöfe, Depots, Erkundungsstationen und
## Züge. Ein Klick auf die Karte springt mit der Kamera dorthin (nur auf bekanntes Gebiet).
## Das Gelände-Bild wird nur bei Änderung der bekannten Fläche neu berechnet, die Markierungen laufend (1,5 s).
extends PanelContainer

const TARGET_PX: int = 480
const BIOME_COLORS: Dictionary = {
	"WATER": Color(0.28, 0.48, 0.74), "BEACH": Color(0.86, 0.80, 0.57), "PLAINS": Color(0.46, 0.72, 0.36),
	"FOREST": Color(0.24, 0.52, 0.28), "HILLS": Color(0.56, 0.60, 0.40), "MOUNTAIN": Color(0.52, 0.52, 0.55),
}
const FOG_COLOR: Color = Color(0.10, 0.12, 0.17)

var _rect: TextureRect = null
var _info: Label = null
var _scale: int = 4
var _base: Image = null
var _base_key: String = ""
var _timer: float = 0.0

func _ready() -> void:
	hide()
	MenuManager.register(self)
	_build()
	visibility_changed.connect(_on_visibility)

func _on_visibility() -> void:
	if visible: _refresh(true)

func open() -> void:
	show(); _refresh(true)

func _gc() -> Node:
	return get_tree().root.find_child("GameScreen", true, false)

func _build() -> void:
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 6); add_child(vb)
	var hdr := HBoxContainer.new(); vb.add_child(hdr)
	var tl := Label.new(); tl.text = "🧭 Weltkarte"
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.add_theme_font_size_override("font_size", 15)
	tl.add_theme_color_override("font_color", Color(0.95, 0.80, 0.45))
	hdr.add_child(tl)
	var cb := Button.new(); cb.text = "X"; cb.pressed.connect(hide); hdr.add_child(cb)
	vb.add_child(HSeparator.new())
	_rect = TextureRect.new()
	_rect.custom_minimum_size = Vector2(TARGET_PX, TARGET_PX)
	_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_rect.gui_input.connect(_on_map_input)
	vb.add_child(_rect)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 11)
	_info.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_info)
	var legend := Label.new()
	legend.text = "Farbige Ringe = Kolonie-Gebiete · weiß = Rathaus · gelb = Bahnhof · grau = Depot · türkis = Erkundungsstation · orange Linie = Gleis · roter Punkt = Zug · Klick = Kamera dorthin"
	legend.add_theme_font_size_override("font_size", 9)
	legend.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(legend)

func _process(delta: float) -> void:
	if not visible: return
	_timer += delta
	if _timer >= 1.5:
		_timer = 0.0
		_refresh(false)

func _biome_color(tile: Dictionary) -> Color:
	var c: Color = BIOME_COLORS.get(str(tile.get("biome", "")), Color(0.5, 0.5, 0.5))
	var shade: float = 0.82 + clampf(float(tile.get("height", 0.0)) / 20.0, 0.0, 1.0) * 0.30
	return Color(c.r * shade, c.g * shade, c.b * shade, 1.0)

func _refresh(force_base: bool) -> void:
	var gc: Node = _gc()
	if gc == null or gc.world.is_empty() or _rect == null: return
	var w: int = gc.world_gen.w; var h: int = gc.world_gen.h
	_scale = maxi(1, TARGET_PX / maxi(w, h))
	var key: String = "%d_%d_%d_%d" % [w, h, ExploreSys.revealed_count, ExploreSys.enabled]
	if force_base or _base == null or key != _base_key:
		_base_key = key
		_base = Image.create(w * _scale, h * _scale, false, Image.FORMAT_RGBA8)
		for x in w:
			for y in h:
				var col: Color = _biome_color((gc.world[x] as Array)[y] as Dictionary) if ExploreSys.is_revealed(x, y) else FOG_COLOR
				_base.fill_rect(Rect2i(x * _scale, y * _scale, _scale, _scale), col)
	var img: Image = _base.duplicate() as Image
	# Gleise
	for k in RailSys.rails:
		var v: Vector2i = RailSys.key_vec(int(k))
		_dot(img, v.x, v.y, Color(0.95, 0.60, 0.20), maxi(1, _scale / 3))
	# Gebäude mit Bedeutung für die Karte
	for b in BuildingSys.buildings:
		var be: BuildingEntity = b
		if not _colony_visible(be.colony_id): continue
		match be.btype:
			"TOWN_HALL": _dot(img, be.tile_x, be.tile_y, Color(1, 1, 1), maxi(2, _scale))
			"STATION": _dot(img, be.tile_x, be.tile_y, Color(1.0, 0.85, 0.25), maxi(2, _scale * 3 / 4))
			"DEPOT": _dot(img, be.tile_x, be.tile_y, Color(0.65, 0.65, 0.70), maxi(2, _scale * 3 / 4))
			"EXPLORER": _dot(img, be.tile_x, be.tile_y, Color(0.35, 0.95, 0.95), maxi(2, _scale * 3 / 4))
	# Züge
	for tv in RailSys.trains:
		var t: TrainEntity = tv
		_dot(img, roundi(t.head.x), roundi(t.head.y), Color(1.0, 0.25, 0.25), maxi(2, _scale))
	# Kolonie-Gebiete als Ringe
	for cid in ColonySys.ids():
		if not _colony_visible(int(cid)): continue
		var hall: Vector2i = ColonySys.get_hall_tile(int(cid))
		if hall.x < 0: continue
		_ring(img, hall.x, hall.y, ColonySys.get_radius(int(cid)), ColonySys.get_color_of(int(cid)))
	_rect.texture = ImageTexture.create_from_image(img)
	var known: String = "%d%% der Karte bekannt" % int(ExploreSys.fraction() * 100.0) if ExploreSys.enabled else "komplett bekannt (keine Entdeckerkarte)"
	_info.text = "%dx%d Kacheln · %s · %d Kolonie(n) · %d Gleiskacheln · %d Zug/Züge" % [w, h, known, ColonySys.count(), RailSys.rails.size(), RailSys.trains.size()]

## Nachbarkolonien erscheinen erst, wenn sie entdeckt sind.
func _colony_visible(cid: int) -> bool:
	return not ColonySys.is_npc(cid) or NeighborSys.is_discovered(cid)

func _dot(img: Image, tx: int, ty: int, col: Color, size: int) -> void:
	var cx: int = tx * _scale + _scale / 2; var cy: int = ty * _scale + _scale / 2
	var half: int = size / 2
	var r := Rect2i(cx - half, cy - half, maxi(1, size), maxi(1, size)).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	if r.size.x > 0 and r.size.y > 0: img.fill_rect(r, col)

func _ring(img: Image, tx: int, ty: int, radius: float, col: Color) -> void:
	var cx: float = float(tx * _scale + _scale / 2); var cy: float = float(ty * _scale + _scale / 2)
	var rp: float = radius * float(_scale)
	var steps: int = maxi(48, int(rp * 3.0))
	for i in steps:
		var a: float = TAU * float(i) / float(steps)
		var px: int = int(cx + cos(a) * rp); var py: int = int(cy + sin(a) * rp)
		if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height(): img.set_pixel(px, py, col)

func _on_map_input(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton) or not (ev as InputEventMouseButton).pressed or (ev as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT: return
	var gc: Node = _gc()
	if gc == null or _base == null: return
	var tex_size: Vector2 = Vector2(_base.get_width(), _base.get_height())
	var disp: float = minf(_rect.size.x, _rect.size.y)
	var off: Vector2 = (_rect.size - Vector2(disp, disp)) * 0.5
	var local: Vector2 = ((ev as InputEventMouseButton).position - off) / disp
	if local.x < 0.0 or local.y < 0.0 or local.x > 1.0 or local.y > 1.0: return
	var tx: int = clampi(int(local.x * float(gc.world_gen.w)), 0, gc.world_gen.w - 1)
	var ty: int = clampi(int(local.y * float(gc.world_gen.h)), 0, gc.world_gen.h - 1)
	if not ExploreSys.is_revealed(tx, ty):
		GameState.notify("Dieses Gebiet ist noch unerforscht."); return
	if gc.has_method("focus_tile"): gc.call("focus_tile", tx, ty)
