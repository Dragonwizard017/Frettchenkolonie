class_name LoadingOverlay
extends Control
## Ladebildschirm (v15.8): Balken, auf dem ein Frettchen läuft - je weiter es gelaufen ist, desto mehr ist geladen.
##
## Benutzung (Coroutine):
##     var steps: Array = [{"label": "Text …", "weight": 3.0, "fn": func(): ...}, ...]
##     await loading.run("Titel", steps)            # optional ctx-Dictionary: ctx["fail"] = true -> Fehler-Abschluss
##
## Zwischen zwei Schritten werden Bilder gezeichnet (Anzeige aktualisiert sich), der Schritt selbst blockiert
## den Hauptthread - das Frettchen springt danach also ein Stück weiter (weich nachgezogen).
## Das Frettchen ist das echte Modell (ferret.glb, Clip "Run") in einem kleinen SubViewport mit transparentem Hintergrund.
##
## Alle ladenden Abläufe (neue Welt, Spielstand laden, Testwelt) laufen über diesen Overlay.

const FERRET_SCENE: PackedScene = preload("res://assets/ferret.glb")
const TRACK_WIDTH: float = 520.0
const FERRET_W: float = 150.0
const FERRET_H: float = 100.0
const BAR_H: float = 16.0

var _title: Label
var _label: Label
var _percent: Label
var _bar: ProgressBar
var _track: Control
var _ferret_box: SubViewportContainer
var _view: SubViewport
var _anim: AnimationPlayer

var _shown: float = 0.0       # angezeigter Fortschritt 0..1 (läuft dem Ziel weich hinterher)
var _target: float = 0.0
var _running: bool = false
var _t0_msec: int = 0         # Startzeitpunkt (für die Mindest-Anzeigedauer)
## Mindest-Laufzeit des Balkens: sehr schnelles Laden würde das Frettchen nur kurz aufblitzen lassen.
const MIN_DURATION: float = 1.0
## Nur für Tests: Verlauf der angezeigten Werte (Fortschritt je Schritt).
var debug_log: Array = []

func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP       # fängt Klicks ab, solange geladen wird
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	set_process(false)

func _build_ui() -> void:
	var dim := ColorRect.new(); dim.color = Color(0.095, 0.07, 0.048, 1.0)   # deckend, sonst scheint das Menü durch
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var cc := CenterContainer.new(); cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(cc)
	var vb := VBoxContainer.new(); vb.custom_minimum_size = Vector2(TRACK_WIDTH, 0)
	vb.add_theme_constant_override("separation", 6); cc.add_child(vb)

	_title = UITheme.lbl("", "Heading"); _title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 32); vb.add_child(_title)
	_label = UITheme.lbl("", "Muted"); _label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 15); vb.add_child(_label)

	# Laufstrecke: hier läuft das Frettchen (freie Positionierung), direkt darunter der Balken
	_track = Control.new(); _track.custom_minimum_size = Vector2(TRACK_WIDTH, FERRET_H - 6.0)
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE; vb.add_child(_track)
	_bar = ProgressBar.new(); _bar.theme_type_variation = "StorageBar"
	_bar.min_value = 0.0; _bar.max_value = 100.0; _bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(TRACK_WIDTH, BAR_H); vb.add_child(_bar)
	_percent = UITheme.lbl("0 %", "Small"); _percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(_percent)

	_build_ferret()

func _build_ferret() -> void:
	_ferret_box = SubViewportContainer.new()
	_ferret_box.stretch = true
	_ferret_box.size = Vector2(FERRET_W, FERRET_H)
	_ferret_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.add_child(_ferret_box)
	_view = SubViewport.new()
	_view.size = Vector2i(int(FERRET_W * 2.0), int(FERRET_H * 2.0))      # 2x für scharfe Kanten
	_view.transparent_bg = true
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_4X
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_ferret_box.add_child(_view)
	var inst: Node3D = FERRET_SCENE.instantiate() as Node3D
	inst.rotation_degrees.y = 90.0                  # Blick nach rechts (+X), wie die Laufrichtung des Balkens
	_view.add_child(inst)
	_anim = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	FerretAnimUtil.ensure_loops(_anim)
	var cam := Camera3D.new(); _view.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 0.50
	cam.look_at_from_position(Vector3(0.0, 0.205, 3.0), Vector3(0.0, 0.205, 0.0), Vector3.UP)
	cam.current = true
	var key := DirectionalLight3D.new(); key.rotation_degrees = Vector3(-35.0, -25.0, 0.0); key.light_energy = 1.25
	_view.add_child(key)
	var fill := DirectionalLight3D.new(); fill.rotation_degrees = Vector3(-20.0, 150.0, 0.0); fill.light_energy = 0.7
	_view.add_child(fill)

# ── Ablauf ───────────────────────────────────────────────────────────────────────────────────
func run(title: String, steps: Array, ctx: Dictionary = {}) -> void:
	if _running: return
	_running = true
	debug_log.clear()
	_title.text = title; _label.text = ""
	_shown = 0.0; _target = 0.0
	_t0_msec = Time.get_ticks_msec()
	_apply_visuals()
	modulate.a = 1.0
	visible = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if _anim != null and _anim.has_animation("Run"):
		_anim.play("Run"); _anim.speed_scale = 1.5
	set_process(true)
	UISounds.suppress_windows = true            # beim Umbauen der UI keine Fenster-Sounds

	var total: float = 0.0
	for st in steps: total += float((st as Dictionary).get("weight", 1.0))
	total = maxf(total, 0.001)
	var done: float = 0.0
	for st in steps:
		var sd: Dictionary = st
		var lbl: String = str(sd.get("label", ""))
		if lbl != "": _label.text = lbl
		_target = done / total
		await get_tree().process_frame            # Anzeige aktualisieren, BEVOR der (blockierende) Schritt läuft
		await get_tree().process_frame
		debug_log.append({"label": _label.text, "shown": _shown, "target": _target})
		(sd["fn"] as Callable).call()
		done += float(sd.get("weight", 1.0))
		_target = done / total

	var failed: bool = bool(ctx.get("fail", false))
	_label.text = "Laden fehlgeschlagen" if failed else "Fertig!"
	if not failed: _target = 1.0
	var guard: int = 0
	while _shown < _target - 0.002 and guard < 600:     # das Frettchen läuft das letzte Stück ins Ziel
		await get_tree().process_frame; guard += 1
	UISounds.play("error" if failed else "done")
	var tw: Tween = create_tween()
	tw.tween_interval(0.35)
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	await tw.finished
	visible = false
	set_process(false)
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	UISounds.suppress_windows = false
	_running = false

func _process(delta: float) -> void:
	# Angezeigter Fortschritt zieht dem Ziel nach (große Sprünge schneller) und ist durch die
	# Mindest-Laufzeit gedeckelt: bei sehr schnellem Laden läuft das Frettchen trotzdem sichtbar.
	var cap: float = float(Time.get_ticks_msec() - _t0_msec) / 1000.0 / MIN_DURATION
	if _shown < _target:
		var gap: float = _target - _shown
		_shown = minf(minf(_target, cap), _shown + delta * maxf(0.6, gap * 8.0))
	_apply_visuals()

func _apply_visuals() -> void:
	_bar.value = _shown * 100.0
	_percent.text = "%d %%" % int(round(_shown * 100.0))
	# Frettchen mittig auf dem Fortschrittspunkt, Pfoten knapp über dem Balken
	var x: float = _shown * TRACK_WIDTH - FERRET_W * 0.5
	_ferret_box.position = Vector2(clampf(x, -FERRET_W * 0.35, TRACK_WIDTH - FERRET_W * 0.65), 0.0)
