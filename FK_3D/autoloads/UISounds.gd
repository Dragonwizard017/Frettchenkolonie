extends Node
## Sound-Rückmeldung für UI-Aktionen (v15.8).
##
## Hängt sich AUTOMATISCH an jedes Control, das in den Baum kommt (Signal `node_added`) -
## neue UI braucht also nichts zu tun:
##   - Button           -> Klick (CheckButton/CheckBox: Schalter an/aus, jeweils anderer Ton)
##   - Maus über Button -> leises Hover-Ticken
##   - HSlider          -> Tick beim Ziehen
##   - OptionButton     -> Auswahl-Ton
##   - Fenster          -> Öffnen / Schließen (erkannt am Namen, siehe WINDOWS; reagiert auf das
##                         eigene `visible`, nicht auf versteckte Eltern -> keine Sound-Flut)
##   - Meldungen        -> rote Meldungen = Fehlerton
## Lautstärke = SoundSys.master_vol * SoundSys.sfx_vol (derselbe Effekt-Regler wie im Pause-Menü).
##
## Sounds sind selbst synthetisierte WAVs (assets/sfx/, erzeugt von tools/gen_sfx.py).
## Manuell: UISounds.play("confirm"), UISounds.play("done") usw.

const SFX_DIR: String = "res://assets/sfx/"
const NAMES: PackedStringArray = ["click", "hover", "open", "close", "toggle_on", "toggle_off",
	"select", "tick", "error", "confirm", "done"]
## relative Lautstärke je Sound (hover soll kaum auffallen)
const GAIN: Dictionary = {"click": 0.9, "hover": 0.45, "open": 0.8, "close": 0.75, "toggle_on": 0.8,
	"toggle_off": 0.7, "select": 0.8, "tick": 0.5, "error": 0.9, "confirm": 0.85, "done": 0.9}
## Mindestabstand je Sound (ms), damit schnelles Überfahren/Ziehen nicht rattert
const MIN_GAP: Dictionary = {"hover": 55, "tick": 70, "click": 35}

## Namen der Fenster/Panels, die beim Öffnen/Schließen klingen sollen.
const WINDOWS: PackedStringArray = ["AchievementPanel", "DistrictPanel", "ColonyPanel", "LinePanel", "WorldMapPanel", "NeighborPanel", "ExpeditionPanel", "GraveyardPanel",
	"StatsPanel", "TechTreePanel", "FerretProfilePanel", "DevToolsPanel", "BuildingInfo", "PauseMenu",
	"LoadScreen", "WorldCreation", "GameOverScreen", "MinigameOverlay", "ProductionChainPanel"]

const POOL_SIZE: int = 6

var enabled: bool = true
## Wird vom Ladebildschirm gesetzt: während des Ladens bauen sich UI-Teile um - dabei still sein.
var suppress_windows: bool = false

var _streams: Dictionary = {}
var _pool: Array = []
var _pool_idx: int = 0
var _last_msec: Dictionary = {}
var _click_pending: bool = false
var _window_frame: int = -1          # Frame, in dem zuletzt ein Fenster-Ton lief (unterdrückt den Klick davor)
var play_log: Array = []             # nur für Tests: (Name) je abgespielter Sound, max. 200

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS     # auch im Pause-Menü hörbar
	for n in NAMES:
		var st: AudioStream = load(SFX_DIR + "ui_%s.wav" % n) as AudioStream
		if st != null: _streams[n] = st
		else: push_warning("UISounds: Sound fehlt: ui_%s.wav" % n)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p); _pool.append(p)
	get_tree().node_added.connect(_on_node_added)
	GameState.notification_requested.connect(_on_notification)

# ── Öffentliche API ──────────────────────────────────────────────────────────────────────────
func play(sound: String, gain: float = 1.0) -> void:
	if not enabled or not _streams.has(sound): return
	var now: int = Time.get_ticks_msec()
	var gap: int = int(MIN_GAP.get(sound, 0))
	if gap > 0 and now - int(_last_msec.get(sound, -100000)) < gap: return
	_last_msec[sound] = now
	var vol: float = SoundSys.master_vol * SoundSys.sfx_vol * float(GAIN.get(sound, 1.0)) * gain
	if vol <= 0.001: return
	var p: AudioStreamPlayer = _pool[_pool_idx] as AudioStreamPlayer
	_pool_idx = (_pool_idx + 1) % _pool.size()
	p.stream = _streams[sound] as AudioStream
	p.volume_db = linear_to_db(clampf(vol, 0.0, 1.0))
	p.pitch_scale = randf_range(0.97, 1.03)     # minimale Variation gegen "Maschinengewehr"-Effekt
	p.play()
	play_log.append(sound)
	if play_log.size() > 200: play_log.pop_front()

# ── Automatisches Anhängen ───────────────────────────────────────────────────────────────────
func _on_node_added(n: Node) -> void:
	if n is Button: _wire_button(n as Button)
	elif n is HSlider: _wire_slider(n as HSlider)
	if n is Control and WINDOWS.has(String(n.name)): _wire_window(n as Control)

func _wire_button(b: Button) -> void:
	if b.has_meta("_uisnd"): return
	b.set_meta("_uisnd", true)
	b.mouse_entered.connect(func():
		if not b.disabled: play("hover"))
	if b is OptionButton:
		(b as OptionButton).item_selected.connect(func(_i): play("select"))
		b.pressed.connect(func(): _click())
		return
	var is_check: bool = b is CheckButton or b is CheckBox
	if is_check:
		b.toggled.connect(func(on: bool): play("toggle_on" if on else "toggle_off"))
	else:
		b.pressed.connect(func():
			# Schließen-Knöpfe: den Ton macht das Fenster selbst ("close"), kein extra Klick
			if String(b.name) == "CloseBtn": return
			_click())

func _wire_slider(s: HSlider) -> void:
	if s.has_meta("_uisnd"): return
	s.set_meta("_uisnd", true)
	s.drag_started.connect(func(): s.set_meta("_drag", true))
	s.drag_ended.connect(func(_changed: bool): s.set_meta("_drag", false))
	s.value_changed.connect(func(_v: float):
		if bool(s.get_meta("_drag", false)): play("tick"))

func _wire_window(c: Control) -> void:
	if c.has_meta("_uisnd_win"): return
	c.set_meta("_uisnd_win", true)
	c.set_meta("_vis", c.visible)
	c.visibility_changed.connect(func():
		# nur auf das EIGENE visible reagieren (visibility_changed feuert auch, wenn ein Elternteil
		# versteckt wird - das wäre eine Sound-Flut beim Wechsel ins Hauptmenü)
		var v: bool = c.visible
		if v == bool(c.get_meta("_vis", v)): return
		c.set_meta("_vis", v)
		if suppress_windows: return
		_window_frame = Engine.get_process_frames()
		play("open" if v else "close"))

## Klick verzögert (Ende des Frames) abspielen: öffnet/schließt der Klick ein Fenster, spielt NUR der
## Fenster-Ton (sonst klingt Klick + Öffnen doppelt).
func _click() -> void:
	if _click_pending: return
	_click_pending = true
	call_deferred("_flush_click")

func _flush_click() -> void:
	_click_pending = false
	if _window_frame == Engine.get_process_frames(): return
	play("click")

func _on_notification(_msg: String, color: Color) -> void:
	if color.r >= 0.7 and color.g <= 0.36 and color.b <= 0.3: play("error")
