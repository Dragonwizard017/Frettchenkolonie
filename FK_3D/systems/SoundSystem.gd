## SoundSystem.gd
## Soundeffekte: prozedurales Audio via AudioStreamGeneratorPlayback
## (verhindert den FMallocBinned2 Crash, siehe Changes-Historie).
## Musik (v12.6): echte Audiodateien statt prozeduraler Töne. Die
## Musikzone (Hauptmenü / Spiel) wird automatisch aus GameState.state_changed
## abgeleitet - kein manuelles Steuern an den einzelnen Aufrufstellen nötig.
extends Node

var master_vol: float = 0.8
var sfx_vol: float    = 0.7
var music_vol: float  = 0.6

const POOL_SIZE := 8
const MIX_RATE  := 22050
const BUF_SIZE  := 1024  # Samples per generator buffer chunk

var _sfx_pool:   Array = []  # Array[AudioStreamPlayer]  – Generator-basiert
var _sfx_idx:    int   = 0

# Wir speichern pro Player eine laufende Sinus-Phase und den Rest-Samplelcount
var _sfx_state:   Array = []  # [{freq, phase, vol, remaining}]

# ── Musik (echte Audiodateien, v12.6) ────────────────────────────────────────
# Hauptmenü: die beiden "New Dawn Frontier"-Titel.
const MENU_TRACKS: Array[AudioStream] = [
	preload("res://assets/music/menu_new_dawn_frontier_1.mp3"),
	preload("res://assets/music/menu_new_dawn_frontier_2.mp3"),
]
# Im Spiel: die beiden "Cozy Block Building"-Titel, zufällig variierend.
const GAME_TRACKS: Array[AudioStream] = [
	preload("res://assets/music/game_cozy_block_building_1.mp3"),
	preload("res://assets/music/game_cozy_block_building_2.mp3"),
]
# Zufällige Pause zwischen zwei Musikstücken IM SPIEL (Nutzerwunsch: 10-60s).
const GAME_TRACK_GAP_MIN := 10.0
const GAME_TRACK_GAP_MAX := 60.0
# Feature (v14.4, Nutzerwunsch "Fretchenmodus mehr zu einem Cosy-Game
# machen"): eigene, ruhigere Musik-Variante fürs Frettchen-Ich - es gibt
# keine eigenen Tracks dafür, darum werden dieselben "Cozy Block Building"-
# Stücke wiederverwendet, aber spürbar gedrosselt (leiser, minimal tiefere
# Tonhöhe = gemächlicher) und mit längeren Pausen dazwischen - fühlt sich
# dadurch bewusst ruhiger/entspannter an als die normale Kolonie-Ansicht.
const FP_TRACK_GAP_MIN := 25.0
const FP_TRACK_GAP_MAX := 75.0
const FP_MUSIC_PITCH   := 0.94
const FP_MUSIC_VOL_MULT := 0.75

# ── Feature (v16.8, Lokfuehrer-Modus): im Zug (Fahrt in Ich-Perspektive) ─────
# soll die Musik noch ruhiger wirken (tiefer + leiser als im Frettchenmodus),
# dafür hört man die Geräusche des Zuges (prozedural, kein neues WAV).
const RIDE_MUSIC_PITCH := 0.90
const RIDE_MUSIC_VOL_MULT := 0.6
const _TRAIN_SPEED_REF: float = 3.0   # Volltempo der Züge (RailSys.TRAIN_SPEED) - ohne Zirkelbezug

enum MusicZone { NONE, MENU, GAME }

var _music_player: AudioStreamPlayer = null
var _music_gap_timer: Timer = null
var _music_zone: MusicZone = MusicZone.NONE
var _last_track: AudioStream = null
var _fp_mode_active: bool = false
var _riding_active: bool = false

# v16.8: Zustand des Zug-Audio-Generators.
var _train_player: AudioStreamPlayer = null
var _train_phase: int = 0          # laufender Sample-Zaehler der Zug-Phase
var _train_rumble: float = 0.0     # geglättetes Rollrauschen (Tiefpass-Weißes Rauschen)
var _train_on: bool = false
var _train_speed01: float = 0.0    # Tempo 0..1 (beim Mitfahrer: t.speed/RailSys.TRAIN_SPEED)
var _train_click_run: float = 0.0  # seit dem letzten Doppel-Klack zurückgelegte Kacheln
var _train_click_open: float = 0.0 # verbleibende Samples des laufenden Klack-Musters

func _ready() -> void:
	for i in POOL_SIZE:
		var p := _make_gen_player()
		_sfx_pool.append(p)
		_sfx_state.append({"freq": 0.0, "phase": 0.0, "vol": 0.0, "rem": 0, "delay": 0})

	# Musik-Player: spielt die echten mp3-Dateien (kein Generator nötig).
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	add_child(_music_player)
	_music_player.finished.connect(_on_music_track_finished)

	# Pause-Timer zwischen zwei Spiel-Musikstücken. Bewusst als Kind-Node
	# statt get_tree().create_timer() - siehe Changes-Historie (Lambda-Capture-
	# Crash in NotificationLayer, gleiche Fehlerklasse wird hier vermieden).
	_music_gap_timer = Timer.new()
	_music_gap_timer.name = "MusicGapTimer"
	_music_gap_timer.one_shot = true
	add_child(_music_gap_timer)
	_music_gap_timer.timeout.connect(_play_next_track)

	_apply_music_player_volume()
	GameState.state_changed.connect(_on_game_state_changed)
	_on_game_state_changed(GameState.current_state)

	# v16.8: eigener Generator-Player fürs dauerhafte Zugfahrt-Geräusch (Rollen +
	# Klick-Klack der Koppeln). Wird nur bei aktiver Zugfahrt bespielt.
	_train_player = AudioStreamPlayer.new()
	_train_player.name = "TrainPlayer"
	var tgen := AudioStreamGenerator.new()
	tgen.mix_rate = float(MIX_RATE)
	tgen.buffer_length = 0.20
	_train_player.stream = tgen
	_train_player.volume_db = -8.0
	add_child(_train_player)

func _make_gen_player() -> AudioStreamPlayer:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = float(MIX_RATE)
	gen.buffer_length = 0.10
	var p := AudioStreamPlayer.new()
	p.stream = gen
	p.volume_db = -6.0
	add_child(p)
	p.play()
	return p

func _process(dt: float) -> void:
	# SFX-Pool befüllen
	for i in POOL_SIZE:
		var st: Dictionary = _sfx_state[i]
		if int(st["rem"]) <= 0: continue
		var p: AudioStreamPlayer = _sfx_pool[i]
		var pb = p.get_stream_playback()
		if pb == null: continue
		var to_fill: int = mini(pb.get_frames_available(), mini(int(st["rem"]), BUF_SIZE))
		var frame := Vector2.ZERO
		for _s in to_fill:
			# v16.8: optionales Start-Delay (verbraucht stummeSamples, damit Töne
			# nacheinander klingen koennen - Glocke/Pfeife).
			if int(st["delay"]) > 0:
				st["delay"] = int(st["delay"]) - 1
				pb.push_frame(Vector2.ZERO)
				continue
			var t: float = float(st["phase"]) / float(MIX_RATE)
			var env: float = clampf(float(st["rem"]) / float(MIX_RATE) * 6.0, 0.0, 1.0)
			var s: float = sin(TAU * float(st["freq"]) * t) * float(st["vol"]) * env
			frame = Vector2(s, s)
			pb.push_frame(frame)
			st["phase"] = int(st["phase"]) + 1
			st["rem"] = int(st["rem"]) - 1
	# v16.8: Zugfahrt-Geräusch (nur wenn der Generator läuft)
	if _train_player != null and _train_player.playing:
		var tb = _train_player.get_stream_playback()
		if tb != null:
			var want: int = tb.get_frames_available()
			if want > 0: _push_train_frames(tb, want)

## v16.8: Zustand des Zuggeräuschs setzen. Wird von GameController._update_ride_prompt()
## je Frame aufgerufen; `speed01` = normiertes Zugtempo 0..1 (Zugtempo / TRAIN_SPEED).
func set_train_audio(active: bool, speed01: float) -> void:
	_train_on = active
	_train_speed01 = clampf(speed01, 0.0, 1.0)
	if _train_player == null: return
	if active:
		if not _train_player.playing:
			_train_phase = 0; _train_rumble = 0.0; _train_click_open = 0.0
			_train_player.play()
	else:
		if _train_player.playing:
			_train_player.stop()
		_train_click_open = 0.0

## v16.8: Das eigentliche Zuggeräusch, sampleweise gepusht:
## - Rollrauschen (Tiefpass-gefiltertes Rauschen) + tiefes Brummen, Pegel/Tempo
##   folgt dem Zugtempo (Rattern wird lauter/höher bei Fahrt),
## - "Klack-Klack" der Koppeln alle ~0.42 Kacheln (zwei kurze Impulse),
## - alles **skaliert mit master*sfx-Lautstärke**.
func _push_train_frames(pb, want: int) -> void:
	var rate: float = float(MIX_RATE)
	var vol: float = clampf(master_vol * sfx_vol, 0.0, 1.0)
	var sp: float = _train_speed01 if _train_on else 0.0
	var audible: bool = sp > 0.001 and vol > 0.001
	var click_pitch_gap: float = 0.42   # Kacheln zwischen zwei Doppel-Klacken
	var click_len: float = 0.055        # Sekunden pro Klack-Muster
	for _s in want:
		if not audible:
			pb.push_frame(Vector2.ZERO)
			continue
		_train_phase += 1
		# Strecke seit Start der Klack-Pause (Tempo -> Abstand fühlt sich echt an)
		_train_click_run += sp * _TRAIN_SPEED_REF / rate
		if _train_click_run >= click_pitch_gap:
			_train_click_run -= click_pitch_gap
			_train_click_open = click_len * rate
		# Roll-Geräusch
		var n: float = randf_range(-1.0, 1.0)
		_train_rumble += (n - _train_rumble) * 0.06
		var hum: float = sin(TAU * (22.0 + 26.0 * sp) * float(_train_phase) / rate)
		var s: float = _train_rumble * 0.75 + hum * 0.30
		# Klack-Klack-Envelope: zwei kurze Impulse im Musterfenster
		if _train_click_open > 0.0:
			var ct: float = 1.0 - _train_click_open / (click_len * rate)   # 0..1
			var a: float = 0.0
			if ct < 0.14: a = (0.14 - ct)
			elif ct > 0.42 and ct < 0.58: a = (0.58 - ct) * 0.8
			s += a * randf_range(-0.9, 0.9)
			_train_click_open -= 1.0
		s = clampf(s * sp * 0.42 * vol, -1.0, 1.0)
		pb.push_frame(Vector2(s, s))

func _tone(freq: float, duration: float, vol: float, delay: float = 0.0) -> void:
	var actual: float = vol * master_vol * sfx_vol
	if actual < 0.001: return
	var idx: int = _sfx_idx % POOL_SIZE
	_sfx_idx += 1
	_sfx_state[idx]["freq"] = freq
	_sfx_state[idx]["phase"] = 0
	_sfx_state[idx]["vol"] = actual
	_sfx_state[idx]["rem"] = int(duration * MIX_RATE)
	_sfx_state[idx]["delay"] = int(delay * MIX_RATE)   # v16.8: Töne nacheinander (Glocke/Pfeife)

# ── Musik-Steuerung ───────────────────────────────────────────────────────────
## Legacy-Einstiegspunkte: werden weiterhin von GameController.gd (Spielstart)
## und PauseMenu.gd (zurück ins Hauptmenü) aufgerufen, sind aber seit v12.6
## No-Ops - die Musikzone wird automatisch aus GameState.state_changed
## abgeleitet (siehe _on_game_state_changed). So bleiben bestehende Aufrufe
## gefahrlos bestehen, ohne die Musik doppelt zu steuern.
func start_music() -> void: pass
func stop_music()  -> void: pass

## v15.9: Intro-Steuerung - pausiert die Menü-Musik, solange ein Video-Intro
## mit eingebackener Musik läuft (sonst Doppel-Audio, betrifft nur noch das
## Story-Intro - das Menü-Intro v13 hat keine Audiospur). Spielt nichts um,
## nur stream_paused an/aus - danach läuft der aktuelle Titel nahtlos weiter.
func pause_music() -> void:
	if _music_player != null and _music_player.playing:
		_music_player.stream_paused = true

func resume_music() -> void:
	if _music_player != null:
		_music_player.stream_paused = false

func _zone_for_state(s: GameState.State) -> MusicZone:
	match s:
		GameState.State.PLAYING, GameState.State.PAUSED:
			return MusicZone.GAME
		GameState.State.INTRO:
			# v15.13: INTRO ist transparent - die aktuelle Musik läuft durch
			# (Nutzerwunsch: epische Menü-Musik startet mit dem Spiel und geht
			# nahtlos durchs Menü-Intro bis ins Hauptmenü, ohne Cut/Neustart).
			# Das Menü-Intro v13 hat keine eigene Audiospur; das Story-Intro
			# schon, wird aber separat per pause_music()/resume_music()
			# stummgeschaltet (siehe Main._on_start_game).
			return MusicZone.NONE
		_:
			# MAIN_MENU, WORLD_CREATION, LOAD_SCREEN, GAME_OVER -> Menü-Musik
			return MusicZone.MENU

func _on_game_state_changed(s: GameState.State) -> void:
	var new_zone: MusicZone = _zone_for_state(s)
	if new_zone == MusicZone.NONE:
		# v15.13: INTRO ändert nichts - laufender Titel spielt weiter.
		return
	if new_zone == _music_zone:
		return
	_music_zone = new_zone
	_music_gap_timer.stop()
	_last_track = null
	_play_next_track()

func _current_pool() -> Array:
	return MENU_TRACKS if _music_zone == MusicZone.MENU else GAME_TRACKS

func _pick_random_track(pool: Array) -> AudioStream:
	if pool.is_empty():
		return null
	if pool.size() == 1:
		return pool[0]
	var choice: AudioStream = pool[randi() % pool.size()]
	var guard: int = 0
	# Nicht zweimal hintereinander denselben Titel spielen, solange Alternativen da sind.
	while choice == _last_track and guard < 8:
		choice = pool[randi() % pool.size()]
		guard += 1
	return choice

func _play_next_track() -> void:
	var pool: Array = _current_pool()
	var track: AudioStream = _pick_random_track(pool)
	if track == null:
		return
	_last_track = track
	_music_player.stream = track
	_music_player.pitch_scale = _music_pitch_now()
	_music_player.play()

## v16.8: aktives Musik-Tempo je Modus - im Zug noch etwas tiefer als im
## Frettchenmodus (gemächlichere Fahrt-Atmosphäre).
func _music_pitch_now() -> float:
	if _music_zone != MusicZone.GAME: return 1.0
	if _riding_active: return RIDE_MUSIC_PITCH
	if _fp_mode_active: return FP_MUSIC_PITCH
	return 1.0

func _on_music_track_finished() -> void:
	if _music_zone == MusicZone.GAME:
		# Nutzerwunsch: kleine Pause zwischen den Musikstücken im Spiel - im
		# Frettchenmodus länger, damit es ruhiger/weniger "vollgepackt" wirkt.
		if _fp_mode_active:
			_music_gap_timer.wait_time = randf_range(FP_TRACK_GAP_MIN, FP_TRACK_GAP_MAX)
		else:
			_music_gap_timer.wait_time = randf_range(GAME_TRACK_GAP_MIN, GAME_TRACK_GAP_MAX)
		_music_gap_timer.start()
	else:
		# Hauptmenü: die beiden Titel wechseln nahtlos, ohne Pause.
		_play_next_track()

## Feature (v14.4): wird von GameController._toggle_fp_mode() aufgerufen.
## Ändert NICHT die Musik-Zone selbst (das Frettchen-Ich läuft ja immer noch
## während GameState.State.PLAYING) - senkt nur Lautstärke/Tonhöhe des
## aktuell laufenden Stücks und sorgt dafür, dass das NÄCHSTE Stück ebenfalls
## gedrosselt startet.
func set_fp_mode(active: bool) -> void:
	if _fp_mode_active == active: return
	_fp_mode_active = active
	_apply_music_player_volume()
	if _music_player.playing:
		_music_player.pitch_scale = _music_pitch_now()

## v16.8: wird von GameController beim Ein-/Aussteigen aufgerufen. Zusätzlich
## zum Frettchenmodus-Drossel (die im Zug ohnehin aktiv ist, da riding nur
## beim Frettchen-Ich geht) senkt das Lautstärke UND Tonhöhe weiter - Musik
## bleibt bewusst im Hintergrund, damit die Zuggeräusche hervortreten.
func set_riding(active: bool) -> void:
	if _riding_active == active: return
	_riding_active = active
	_apply_music_player_volume()
	if _music_player.playing:
		_music_player.pitch_scale = _music_pitch_now()
	if not active:
		set_train_audio(false, 0.0)
	else:
		play_train_whistle()   # Begrüßungspfeife beim Einsteigen

func _apply_music_player_volume() -> void:
	if _music_player == null:
		return
	var lin: float = clampf(master_vol * music_vol, 0.0, 1.0)
	if _fp_mode_active and _music_zone == MusicZone.GAME:
		lin *= FP_MUSIC_VOL_MULT
	if _riding_active and _music_zone == MusicZone.GAME:   # v16.8: im Zug noch leiser
		lin *= RIDE_MUSIC_VOL_MULT
	_music_player.volume_db = linear_to_db(lin) if lin > 0.0001 else -80.0

# ── Soundeffekte ──────────────────────────────────────────────────────────────
func play_build() -> void:
	_tone(440.0, 0.14, sfx_vol * 0.15)
	_tone(554.0, 0.18, sfx_vol * 0.12)
	_tone(659.0, 0.24, sfx_vol * 0.10)

func play_explosion() -> void:
	# Weißes Rauschen via mehrere verstimmte Sinusse
	for i in 6:
		_tone(randf_range(80.0, 320.0), 0.55, sfx_vol * 0.18)

func play_notify() -> void:
	_tone(880.0,  0.10, sfx_vol * 0.18)
	_tone(1108.0, 0.14, sfx_vol * 0.14)

func play_born() -> void:
	for pair in [[523.0,0.14],[659.0,0.14],[784.0,0.14],[1046.0,0.18]]:
		_tone(float((pair as Array)[0]), float((pair as Array)[1]), sfx_vol * 0.18)

func play_death() -> void:
	for pair in [[440.0,0.20],[370.0,0.22],[311.0,0.24],[262.0,0.28]]:
		_tone(float((pair as Array)[0]), float((pair as Array)[1]), sfx_vol * 0.14)

func play_day()   -> void:
	for freq in [523.0, 659.0, 784.0]: _tone(float(freq), 0.30, sfx_vol * 0.11)

func play_night() -> void:
	for freq in [392.0, 330.0, 262.0]: _tone(float(freq), 0.38, sfx_vol * 0.09)

# ── v16.8: Lokführer-Zuggeräusche (prozedural, siehe tools/gen_sfx.py-Prinzip) ──
## Lok-Pfeife: zweistimmiger Dampf-Pfeifen-Akkord (494/660 Hz), gefolgt von
## einem kürzeren zweiten Puff - klingt wie die altbekannte "Tu-Tuu".
func play_train_whistle() -> void:
	var v: float = sfx_vol
	_tone(494.0, 0.55, v * 0.20)
	_tone(660.0, 0.55, v * 0.18)
	_tone(988.0, 0.55, v * 0.07)   # Oberton für Metall-Klang
	_tone(494.0, 0.30, v * 0.15, 0.62)
	_tone(660.0, 0.30, v * 0.14, 0.62)

## Bahnhofs-Glocke: drei aufeinanderfolgende Doppel-Schläge (G6 mit C7-Oberton).
func play_station_bell() -> void:
	var v: float = sfx_vol
	for i in 3:
		var d: float = float(i) * 0.40
		_tone(1568.0, 0.30, v * 0.15, d)
		_tone(2093.0, 0.22, v * 0.09, d)

func set_volumes(master: float, music: float, sfx: float) -> void:
	master_vol = clampf(master / 100.0, 0.0, 1.0)
	music_vol  = clampf(music  / 100.0, 0.0, 1.0)
	sfx_vol    = clampf(sfx   / 100.0, 0.0, 1.0)
	_apply_music_player_volume()
