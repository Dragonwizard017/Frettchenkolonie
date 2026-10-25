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
## Feature (v16.12, Fenstermodus): Vollbild? Persistiert; auch per F11/Alt+Enter umschaltbar.
var window_fullscreen: bool = false
## v16.12: Minimale Fenstergröße - schützt die UI vor dem Zusammenfallen.
const WINDOW_MIN_SIZE := Vector2i(960, 540)
## v16.12: gemerkte windowed-Position/Größe (beim Vollbild-Wechsel gesichert,
## auch über Neustarts persistiert).
## v16.12: gemerkter windowed-Zustand - Position, Größe, maximiert?
var _win_pos: Vector2i = Vector2i.ZERO
var _win_size: Vector2i = Vector2i.ZERO
var _win_pos_valid: bool = false
var win_maximized: bool = false
var _has_window: bool = false
var _resize_debounce: Timer = null
var _loaded: bool = false

func _init() -> void:
	_register_globals()

func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		realistic = bool(cf.get_value("graphics", "realistic", false))
		ui_scale = float(cf.get_value("graphics", "ui_scale", 1.0))
		if not UI_SCALES.has(ui_scale): ui_scale = 1.0
		# Feature (v16.12): Fenstereinstellungen laden
		window_fullscreen = bool(cf.get_value("window", "fullscreen", false))
		win_maximized = bool(cf.get_value("window", "win_maximized", false))
		var sp: Array = cf.get_value("window", "win_pos", [])
		var ss: Array = cf.get_value("window", "win_size", [])
		if sp.size() == 2 and ss.size() == 2:
			_win_pos = Vector2i(int(sp[0]), int(sp[1]))
			_win_size = Vector2i(int(ss[0]), int(ss[1]))
			_win_pos_valid = _win_pos.x > -3600 and _win_pos.x < 8192 and _win_pos.y > -3600 and _win_pos.y < 8192
			_win_size.x = clampi(_win_size.x, WINDOW_MIN_SIZE.x, 16384)
			_win_size.y = clampi(_win_size.y, WINDOW_MIN_SIZE.y, 16384)
	_loaded = true
	_push_globals()
	_apply_ui_scale()
	_setup_window_tracking()
	# Deferred: erst, wenn die ProjectSettings-Fenster-Eigenschaften angewendet sind.
	_apply_window_settings.call_deferred()

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

## Feature (v16.12): Vollbild umschalten. Wechselt Fenster<->Vollbild,
## merkt sich die windowed-Rect (auch über Neustarts) und restauriert sie.
func set_fullscreen(v: bool) -> void:
	if v == window_fullscreen: return
	window_fullscreen = v
	_apply_window_mode()
	_save()
	changed.emit()

## Feature (v16.12): F11 und Alt+Enter als Hotkeys. Bewusst über
## _unhandled_key_input: solange ein Textfeld (Speichern unter, Dev-Passwort)
## den Fokus hat, konsumiert das GUI die Taste und der Hotkey springt nicht.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo): return
	if event.keycode == KEY_F11 or (event.alt_pressed and event.keycode == KEY_ENTER):
		set_fullscreen(not window_fullscreen)
		get_viewport().set_input_as_handled()

## Feature (v16.12): Fenstergröße/-position während des Resizings merken.
## Debounced, damit beim Ziehen nicht pro Pixel in die Config geschrieben wird.
func _setup_window_tracking() -> void:
	# In Tests/Headless gibt es kein echtes Fenster -> sauber abschalten.
	# (Bewusst nur get_name(): FEATURE_WINDOW existiert in Godot 4.7 nicht.)
	_has_window = DisplayServer.get_name() != "headless"
	if not _has_window:
		return
	_resize_debounce = Timer.new()
	_resize_debounce.one_shot = true
	_resize_debounce.wait_time = 1.2
	_resize_debounce.timeout.connect(_capture_and_save_window)
	add_child(_resize_debounce)
	get_tree().root.size_changed.connect(_on_root_size_changed)

func _on_root_size_changed() -> void:
	if not window_fullscreen and _resize_debounce:
		_resize_debounce.start()

## v16.12: aktuelle windowed-Zustände erfassen und persistieren. Läuft
## debounced nach dem Resizing - und beim Fenster-Schließen
## (NOTIFICATION_WM_CLOSE_REQUEST erreicht den Autoload über den Tree),
## deckt so auch reines Verschieben ab.
func _capture_and_save_window() -> void:
	if not _has_window or window_fullscreen: return
	# Maximiert? Dann nur den Zustand merken - die Maximized-Rect ist sonst
	# keine sinnvolle windowed-Größe für den nächsten Start.
	# (is_maximized() nur am Window-Node: DisplayServer hat das in 4.7 nicht.)
	var maximized: bool = get_tree().root.is_maximized()
	win_maximized = maximized
	if not maximized:
		var pos := DisplayServer.window_get_position()
		var size := DisplayServer.window_get_size()
		if size.x < WINDOW_MIN_SIZE.x or size.y < WINDOW_MIN_SIZE.y: return
		_win_pos = pos
		_win_size = size
		_win_pos_valid = true
	_save()

func _notification(what: int) -> void:
	# v16.12: Fenster wird geschlossen/Beenden -> letzte Position/Größe sichern,
	# sonst fehlt reines Verschieben (ohne Resize) in der Config.
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not window_fullscreen:
		_capture_and_save_window()

func _apply_window_settings() -> void:
	if not _has_window:
		return
	DisplayServer.window_set_min_size(WINDOW_MIN_SIZE)
	_apply_window_mode()

func _apply_window_mode() -> void:
	if not _has_window:
		return
	if window_fullscreen:
		# Vor dem Wechsel die aktuelle windowed-Rect sichern (für Rückwechsel).
		var was_max: bool = get_tree().root.is_maximized()
		win_maximized = was_max
		if not was_max:
			_win_pos = DisplayServer.window_get_position()
			_win_size = DisplayServer.window_get_size()
			_win_pos_valid = true
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		# Gemerkter windowed-Zustand: maximiert wieder maximieren, sonst die
		# letzte gemerkte Größe/Position - Fenster bleibt frei ziehbar.
		if win_maximized:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
			return
		if _win_size.x >= WINDOW_MIN_SIZE.x and _win_size.x <= 16384:
			DisplayServer.window_set_size(_win_size)
		if _win_pos_valid:
			# Nur anwenden, wenn die Position plausibel an einem Monitor liegt
			# (komponentenweise - keine Vector2i-Vergleichsoperatoren).
			var scr := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
			var ok := _win_pos.x > scr.position.x - 120 and _win_pos.y > scr.position.y - 40 \
				and _win_pos.x < scr.position.x + scr.size.x and _win_pos.y < scr.position.y + scr.size.y
			if ok:
				DisplayServer.window_set_position(_win_pos)

func _apply_ui_scale() -> void:
	# content_scale_factor wirkt bei Stretch-Modus "canvas_items" nur auf 2D/UI, nicht auf die 3D-Szene
	get_tree().root.content_scale_factor = ui_scale

func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("graphics", "realistic", realistic)
	cf.set_value("graphics", "ui_scale", ui_scale)
	# Feature (v16.12): Fenstereinstellungen persistieren
	cf.set_value("window", "fullscreen", window_fullscreen)
	cf.set_value("window", "win_maximized", win_maximized)
	if _win_size.x >= WINDOW_MIN_SIZE.x:
		cf.set_value("window", "win_size", [_win_size.x, _win_size.y])
	if _win_pos_valid:
		cf.set_value("window", "win_pos", [_win_pos.x, _win_pos.y])
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
