class_name IntroPlayer
extends Control
## Vollbild-Video-Intro (v15.9): spielt die Blender-Startanimationen (Theora-OGV)
## als überblendungsfreien Einstieg — Menü-Intro beim Kaltstart, Story-Intro bei
## "Kolonie gründen". Das Video füllt den Bildschirm im Cover-Verfahren (keine
## Balken, minimaler Beschnitt an exotischen Seitenverhältnissen).
##
## Benutzung (Coroutine, kehrt erst nach Ende/Skip zurück):
##     await intro.play("res://assets/videos/intro_menu.ogv")
##
## Klick / Touch / ESC / Leertaste bricht ab. Der Skip-Hinweis erscheint bewusst
## erst nach 3 Sekunden (Kino-Feeling, trotzdem entdeckbar).

signal playback_done(was_skipped: bool)

const SKIP_HINT_DELAY: float = 3.0
const BASE_W: float = 1920.0
const BASE_H: float = 1080.0

var _player: VideoStreamPlayer = null
var _hint: Label = null
var _t: float = 0.0
var _running: bool = false
var _done: bool = false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_player = VideoStreamPlayer.new()
	# Fix v15.11: VideoStreamPlayer hat in Godot 4 nur `expand: bool`
	# (kein expand_mode-Enum wie TextureRect) -> EXPAND_IGNORE_SIZE existiert nicht.
	_player.expand = true
	_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_player)
	_hint = Label.new()
	_hint.text = "Klicken oder ESC zum Überspringen"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.anchor_left = 0.0; _hint.anchor_right = 1.0
	_hint.offset_top = -64; _hint.offset_bottom = -32
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.modulate.a = 0.0
	add_child(_hint)
	visible = false
	set_process(false)
	_fit_cover()
	resized.connect(_fit_cover)

## Cover-Rechnung: Video-Seitenverhältnis bleibt exakt (kein Verzerren, kein
## Balken) — an ungebräuchlichen Fensterformaten wird dezent beschnitten.
func _fit_cover() -> void:
	var vs: Vector2 = get_viewport_rect().size
	if vs.x < 1.0 or vs.y < 1.0:
		return
	var s: float = maxf(vs.x / BASE_W, vs.y / BASE_H)
	var w: float = BASE_W * s
	var h: float = BASE_H * s
	_player.position = Vector2((vs.x - w) * 0.5, (vs.y - h) * 0.5)
	_player.size = Vector2(w, h)

func play(path: String) -> void:
	if _running:
		return
	var stream: VideoStream = load(path) as VideoStream
	if stream == null:
		push_warning("IntroPlayer: Video fehlt: %s" % path)
		playback_done.emit(true)
		return
	_running = true
	_done = false
	_t = 0.0
	_hint.modulate.a = 0.0
	_player.stream = stream
	visible = true
	set_process(true)
	_fit_cover()
	_player.finished.connect(_on_finished, CONNECT_ONE_SHOT)
	_player.play()
	await playback_done
	visible = false
	set_process(false)
	_player.stop()

func skip() -> void:
	if not _running or _done:
		return
	_done = true
	_player.stop()
	playback_done.emit(true)

func _on_finished() -> void:
	if _done:
		return
	_done = true
	playback_done.emit(false)

func _process(delta: float) -> void:
	if not _running:
		return
	_t += delta
	if _t >= SKIP_HINT_DELAY and _hint.modulate.a < 1.0:
		_hint.modulate.a = 1.0

func _gui_input(event: InputEvent) -> void:
	if not _running:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			skip()
	elif event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		if st.pressed:
			skip()

func _input(event: InputEvent) -> void:
	if not _running or not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		skip()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var k: InputEventKey = event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_SPACE:
			skip()
			get_viewport().set_input_as_handled()
