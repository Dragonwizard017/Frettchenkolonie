## GameController.gd  –  3D-Version
## Kamera = Camera3D mit orthographischer Projektion (klassische Iso-Perspektive).
## Kamerabewegung per WASD / Rechtsklick-Drag.
## Klick-Auswahl per PhysicsRaycast auf Terrain + Gebäude.
extends Node3D

var renderer: WorldRenderer3D = null
var camera:   Camera3D        = null
var _sun_light:  DirectionalLight3D = null
var _fill_light: DirectionalLight3D = null
var _world_env:  Environment       = null

var world:     Array          = []
var world_gen: WorldGenerator = null
var explosions: Array         = []

# ── Feature (v11.4, Speicherslot-System) ─────────────────────────────────────
# current_world_name = Anzeigename der Kolonie (vom Spieler in der Welt-
# Erstellung vergeben); current_save_slot = daraus abgeleiteter, eindeutiger
# Dateiname im Speicherordner. Wird von SaveSystem.load_game() beim Laden
# ueberschrieben, damit "Speichern" im Pause-Menue immer in denselben Slot
# zurueckschreibt.
var current_world_name: String = "Meine Kolonie"
var current_save_slot:  String = ""

# ── Kamera-State ──────────────────────────────────────────────────────────────
const CAM_SPEED:   float = 14.0
const ZOOM_MIN:    float = 12.0
const ZOOM_MAX:    float = 60.0
const ZOOM_STEP:   float = 3.0
const CAM_ANGLE_X: float = -52.0
const CAM_ANGLE_Y: float =  45.0

var _cam_zoom:   float   = 28.0
var _cam_target: Vector3 = Vector3.ZERO

# ── Drag-State ────────────────────────────────────────────────────────────────
var _is_right_drag:  bool    = false
var _drag_world_hit: Vector3 = Vector3.ZERO
var _touch_moved:    bool    = false
var _path_dragging:  bool    = false
var _day_prev:       int     = -1

# ── Feature (v11.2, First-Person-Modus) ─────────────────────────────────────
var player: PlayerController = null
var _fp_hud:  Control = null
var _minigame: Control = null   # MinigameOverlay.gd
var _fp_mode: bool = false
var _hud_node:        Control = null
var _build_menu_node: Control = null
# Feature (v11.25, Positions-Persistenz): sobald der Spieler einmal eine
# "echte" Position hat (Neustart-Spawn, geladener Spielstand, oder ein
# Frettchenmodus-/Laufbefehl-Aufenthalt), bleibt diese Flag true und
# _toggle_fp_mode() teleportiert beim naechsten Betreten NICHT mehr auf die
# Iso-Kamera-Zielposition, sondern laesst den Spieler exakt dort, wo er beim
# letzten Verlassen stand (Nutzeranfrage: "am selben Ort wie beim
# Verlassen"). Nur beim allerersten Mal (frisch generierte Welt, noch kein
# einziger Frettchenmodus-Aufenthalt) gibt es ueberhaupt eine Position, die
# gesetzt werden muss - daher der Fallback auf _cam_target NUR wenn diese
# Flag noch false ist.
var _player_pos_valid: bool = false
const INTERACT_RANGE: float = 2.6   # Welteinheiten (~1.3 Tiles)
# Ressourcentyp -> max. Belohnung pro Minispiel-Durchlauf
const MINIGAME_MAX_REWARD: Dictionary = {
	"WOOD": 18.0, "STONE": 14.0, "BERRIES": 16.0, "IRON": 12.0, "WATER": 20.0
}
# aktuell anvisiertes Ziel waehrend des First-Person-Umherlaufens, siehe
# _update_fp_interaction(). "" type = kein Ziel in Reichweite.
var _fp_target_kind: String = ""   # "NODE" | "WATER"
var _fp_target_res:  String = ""
var _fp_target_tile: Vector2i = Vector2i(-1, -1)
# ══════════════════════════════════════════════════════════════════════════════
func _ready() -> void:
	renderer = get_node("WorldRenderer3D") as WorldRenderer3D
	camera   = get_node("Camera3D") as Camera3D
	_sun_light  = get_node_or_null("Sun") as DirectionalLight3D
	_fill_light = get_node_or_null("Fill") as DirectionalLight3D
	var world_env_node: WorldEnvironment = get_node_or_null("WorldEnv") as WorldEnvironment
	if world_env_node != null:
		_world_env = world_env_node.environment
	player = get_node_or_null("PlayerController") as PlayerController
	_fp_hud = get_node_or_null("GameUI/UIRoot/FPHud") as Control
	_minigame = get_node_or_null("GameUI/UIRoot/MinigameOverlay") as Control
	_hud_node = get_node_or_null("GameUI/UIRoot/HUD") as Control
	_build_menu_node = get_node_or_null("GameUI/UIRoot/BuildMenu") as Control
	if _minigame and not _minigame.minigame_finished.is_connected(_on_minigame_finished):
		_minigame.minigame_finished.connect(_on_minigame_finished)
	_connect_signals()

func _connect_signals() -> void:
	# Bug7-Fix: Guard gegen doppelte Verbindungen beim Neu-Starten
	if GameState.notification_requested.is_connected(_on_notification): return
	GameState.notification_requested.connect(_on_notification)
	GameState.hud_update_requested.connect(_on_hud_update)
	GameState.build_menu_update_requested.connect(_on_build_menu_update)
	GameState.building_selected.connect(_on_building_selected)
	GameState.building_deselected.connect(_on_building_deselected)
	# Feature (v11.9, Frettchen-Klick-Interaktion / Legendäre Frettchen):
	GameState.ferret_selected.connect(_on_ferret_selected)
	GameState.ferret_became_legendary.connect(_on_ferret_became_legendary)
	GameState.game_over_triggered.connect(_on_game_over)
	GameState.placement_mode_changed.connect(_on_placement_mode_changed)
	GameState.state_changed.connect(_on_state_changed_fp)

## Feature (v11.2, First-Person-Modus): waehrend des First-Person-Umsehens
## ist die Maus gefangen (MOUSE_MODE_CAPTURED) - das Pause-Menue braucht aber
## einen normalen, sichtbaren Mauszeiger zum Klicken. Ohne diesen Handler
## waere das Pause-Menue waehrend des FP-Modus unbedienbar.
func _on_state_changed_fp(new_state: GameState.State) -> void:
	if not _fp_mode: return
	if new_state == GameState.State.PAUSED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif new_state == GameState.State.PLAYING and not _is_minigame_active():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func start_new_game(world_size: String, seed_str: String, world_name: String) -> void:
	world_gen = WorldGenerator.new()
	world     = world_gen.generate(world_size, seed_str)
	# Feature (v11.4, Speicherslot-System): Kolonie-Name des Spielers wird jetzt
	# tatsaechlich verwendet (vorher wurde der Parameter verworfen) - daraus
	# wird der eindeutige Speicherslot fuer diese Welt abgeleitet.
	current_world_name = world_name.strip_edges() if world_name.strip_edges() != "" else "Meine Kolonie"
	current_save_slot  = _make_unique_save_slot(current_world_name)
	ResourceSys.init(); BuildingSys.init(); PopMgr.init(5)
	DayNight.init(); TechTreeSys.init(); DroughtSys.init()
	SeasonSys.init(); ExpeditionSys.init()
	AchievementSys.init()  # Feature (v11.8, Achievement-System)
	PlayerAccessories.init()  # Feature (v12.2, Phase 4)
	DistrictSys.init()     # Feature (v11.11, Distrikt-System)
	WaterSys.init(world, world_gen.w, world_gen.h)
	explosions = []; _day_prev = -1
	@warning_ignore("integer_division")
	var cx: int = world_gen.w / 2; var cy: int = world_gen.h / 2
	BuildingSys.build_free("CONSTRUCTION_YARD_1", cx, cy, world)
	# Feature (v11.0, Lagersystem): die Kolonie startet jetzt direkt mit einem
	# physisch vorhandenen Lagergebaeude (statt die Startressourcen nur
	# abstrakt im globalen Pool zu haben) - sonst koennte die Kolonie
	# softlocken, sobald Produktionsgebaeude ihr eigenes lokales Lager voll
	# haben und niemand zum Abtransportieren da ist. Sucht eine freie,
	# bebaubare Nachbarkachel des Bauhofs.
	var start_storage_pos: Vector2i = _find_free_tile_near(cx, cy, world)
	if start_storage_pos.x >= 0:
		BuildingSys.build_free("STORAGE", start_storage_pos.x, start_storage_pos.y, world)
	_setup_renderer()
	_cam_target = renderer.tile_to_world3d(cx, cy); _cam_target.y = 0.0
	_apply_camera()
	# Feature (v11.2, First-Person-Modus): Spieler-Frettchen startet direkt
	# neben dem Bauhof, sichtbar (aber bewegungslos) bis der Modus aktiviert wird.
	if player != null:
		player.teleport_to(renderer.tile_to_world3d(cx + 1, cy))
		player.movement_enabled = false
		_player_pos_valid = true
	GameState.set_state(GameState.State.PLAYING); SoundSys.start_music()
	GameState.notify("Willkommen in deiner Kolonie!")
	_on_hud_update(); _on_build_menu_update()

## Feature (v11.14, Testwelt): baut auf der GERADE per start_new_game()
## erzeugten, leeren Kolonie automatisch eine weit entwickelte Kolonie auf -
## fuer eine "Testwelt", die alle Systeme (Distrikte, Tech Tree, Legendäre
## Frettchen, Achievements, ...) sofort zum Ausprobieren bereitstellt, ohne
## dass der Nutzer erst manuell stundenlang aufbauen muss.
##
## WICHTIG: nutzt ausschliesslich echte Spiel-APIs (BuildingSys.build_free(),
## TechTreeSys, PopMgr, ResourceSys.force_add()) statt eine Save-Datei per
## Hand zusammenzubasteln - das garantiert einen konsistenten, ladbaren
## Zustand (exakt dieselben Codepfade wie normales Spielen), ohne dass ich
## das Ergebnis in einer echten Godot-Instanz gegenpruefen koennte.
func bootstrap_test_colony() -> void:
	@warning_ignore("integer_division")
	var cx: int = world_gen.w / 2
	@warning_ignore("integer_division")
	var cy: int = world_gen.h / 2

	# ── Tech Tree: Epoche 1-3 freigeschaltet, je Themenbereich die ersten 7
	# Stufen erforscht (Voraussetzungsketten sind pro Sektion streng linear -
	# Tier N braucht Tier N-1 - daher reicht ein einfacher 1..7-Range je
	# Sektion, um einen widerspruchsfreien Fortschritt zu erzeugen). Epoche 4
	# bleibt bewusst gesperrt, damit noch Forschungsfortschritt zum Testen
	# uebrig bleibt.
	TechTreeSys.unlocked_epochs = ["EPOCH_1", "EPOCH_2", "EPOCH_3"]
	TechTreeSys.unlocked = []
	for sid in TechTreeSys.SECTION_ORDER:
		for tier in range(1, 8):
			var tid: String = "%s_%d" % [sid, tier]
			if TechTreeSys.NODES.has(tid):
				TechTreeSys.unlocked.append(tid)

	# ── Ressourcen grosszuegig auffuellen (force_add ignoriert Lagerkapazitaet -
	# bewusst, damit die Testwelt nicht schon beim Start durch volle Lager
	# blockiert).
	for pair in [["WOOD",400.0],["STONE",300.0],["BERRIES",150.0],["PLANKS",120.0],
			["TOOLS",80.0],["FOOD",150.0],["IRON",60.0],["IRON_BARS",40.0],
			["MACHINES",20.0],["COAL",60.0],["STEEL",30.0],["MEAT",60.0],
			["WHEAT",60.0],["COOKED_MEAT",30.0],["BREAD",30.0]]:
		ResourceSys.force_add(str(pair[0]), float(pair[1]))
	ResourceSys.water = 40.0
	ResourceSys.science = 120.0

	# ── Gebaeude: eine repraesentative Auswahl ueber alle 4 Epochen verteilt.
	# build_free() prueft weder Ressourcenkosten noch Tech-Freischaltung
	# (das ist reine Build-Menu-UI-Logik) - lediglich die Tile-Vorbedingungen
	# (nicht besetzt, kein Wasser) werden hier selbst geprueft, siehe
	# _bootstrap_find_free_tiles().
	var epoch1: Array = ["LUMBERJACK","LUMBERJACK","QUARRY","BERRY_GATHERER",
		"HOUSE","HOUSE","HOUSE","GATHERING_PLACE","FORESTER","RESEARCH_HUT"]
	var epoch2: Array = ["SAWMILL","WORKSHOP","WATER_TOWER","TAVERN","LARGE_STORAGE",
		"DISTRICT_GATE","CROP_FIELD","COOKHOUSE","WHEAT_FARM","HUNTER_HUT"]
	var epoch3: Array = ["IRON_MINE","COAL_MINE","SMELTER","WAREHOUSE","THEATER"]
	var epoch4: Array = ["MACHINE_FACTORY","STATUE"]

	var all_ids: Array = epoch1 + epoch2 + epoch3 + epoch4
	var tiles: Array = _bootstrap_find_free_tiles(cx, cy, world, all_ids.size(), false)
	var placed: Array = []
	var ti: int = 0
	for bid in all_ids:
		if ti >= tiles.size(): break
		var t: Vector2i = tiles[ti]; ti += 1
		var b: BuildingEntity = BuildingSys.build_free(bid, t.x, t.y, world)
		if b != null:
			b.placed_day = 0
			placed.append(b)

	# WELL separat mit Wassernaehe suchen (siehe near_water=true) - eigener
	# Aufruf, damit es nicht zufaellig eine der obigen Tiles "verbraucht".
	var well_tiles: Array = _bootstrap_find_free_tiles(cx, cy, world, 1, true)
	if not well_tiles.is_empty():
		var wb: BuildingEntity = BuildingSys.build_free("WELL", well_tiles[0].x, well_tiles[0].y, world)
		if wb != null: placed.append(wb)

	# ── Bevoelkerung: zusaetzlich zu den 5 Start-Frettchen (aus start_new_game())
	# 10 weitere, einige davon echten Gebaeuden zugewiesen, eines als
	# legendaer markiert (fuer Accessoires/Holy-Glow-Testing).
	for _i in 10:
		var f: FerretEntity = FerretEntity.create_random()
		f.pos = Vector2(float(cx) + randf_range(-5.0, 5.0), float(cy) + randf_range(-5.0, 5.0))
		f.target_pos = f.pos
		PopMgr.ferrets.append(f)
	var idle_ferrets: Array = PopMgr.ferrets.duplicate()
	for b2 in placed:
		var be: BuildingEntity = b2
		if be.max_workers <= 0: continue
		while be.assigned_workers.size() < mini(be.max_workers, 2) and not idle_ferrets.is_empty():
			var fe: FerretEntity = idle_ferrets.pop_back()
			be.assign_worker(fe)

	if PopMgr.ferrets.size() > 0:
		var legend: FerretEntity = PopMgr.ferrets[0]
		legend.is_legendary = true
		legend.career_days = FerretEntity.LEGENDARY_THRESHOLD_DAYS
		legend.legendary_title = "Testwelt-Legende"
		legend.legendary_accessories = FerretAccessories.pick_random_set()

	# ── Kolonie-Alter: Tag 65 statt Tag 0, damit z.B. "50 Tage ohne Verlust"-
	# artige Achievements/Legendaer-Fortschritt plausibel wirken.
	DayNight.day_count = 65

	_setup_renderer()
	GameState.notify("🛠️ Testwelt aufgebaut: %d Gebäude, %d Frettchen." % [placed.size() + 2, PopMgr.ferrets.size()])
	_on_hud_update(); _on_build_menu_update()

## Sucht bis zu "count" freie, unbebaute, nicht-Wasser-Tiles rund um (cx,cy) -
## spiralfoermig nach aussen wachsend, damit auch bei vielen angeforderten
## Tiles genug Platz gefunden wird. "near_water" filtert zusaetzlich auf
## Tiles mit einem Wasser-Tile in max. 4 Kacheln Entfernung (fuer WELL etc.).
func _bootstrap_find_free_tiles(cx: int, cy: int, world_ref: Array, count: int, near_water: bool) -> Array:
	var found: Array = []
	var radius: int = 2
	var max_radius: int = 45
	while found.size() < count and radius <= max_radius:
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius: continue
				var tx: int = cx + dx; var ty: int = cy + dy
				if tx < 0 or ty < 0 or tx >= world_ref.size(): continue
				var col: Array = world_ref[tx]
				if ty < 0 or ty >= col.size(): continue
				var tile: Dictionary = col[ty]
				if tile.get("building") != null: continue
				if str(tile.get("biome", "")) == "WATER": continue
				if near_water and not _bootstrap_has_water_nearby(world_ref, tx, ty, 4): continue
				found.append(Vector2i(tx, ty))
				if found.size() >= count: break
			if found.size() >= count: break
		radius += 1
	return found

func _bootstrap_has_water_nearby(world_ref: Array, tx: int, ty: int, r: int) -> bool:
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var nx: int = tx + dx; var ny: int = ty + dy
			if nx < 0 or ny < 0 or nx >= world_ref.size(): continue
			var col: Array = world_ref[nx]
			if ny < 0 or ny >= col.size(): continue
			if str((col[ny] as Dictionary).get("biome", "")) == "WATER": return true
	return false

## Feature (v11.14, Testwelt): Aufruf durch Main.gd nach bootstrap_test_colony(),
## speichert unter dem regulaeren Speicherslot dieser Session (siehe
## start_new_game() - current_save_slot wurde dort bereits gesetzt).
func save_now() -> void:
	SaveSys.save(current_save_slot, self)

func _setup_renderer() -> void:
	if renderer == null: renderer = get_node_or_null("WorldRenderer3D") as WorldRenderer3D
	renderer.world = world; renderer.world_w = world_gen.w; renderer.world_h = world_gen.h
	renderer.build_world()
	# Feature (v12.1): PlayerController braucht eine Referenz auf den
	# Renderer, um beim Mittelklick-Laufbefehl die Tile-Hoehe direkt
	# abzufragen (siehe PlayerController._process_external_walk()).
	if player != null: player.renderer = renderer

## Sucht eine freie, bebaubare Kachel in der Naehe von (cx, cy) - genutzt, um
## beim Koloniestart ein erstes Lagergebaeude neben dem Bauhof zu platzieren,
## ohne dabei auf Wasser oder ein bereits belegtes Tile zu treffen.
func _find_free_tile_near(cx: int, cy: int, w: Array) -> Vector2i:
	var offsets: Array = [Vector2i(2,0), Vector2i(0,2), Vector2i(-2,0), Vector2i(0,-2),
		Vector2i(2,2), Vector2i(-2,-2), Vector2i(2,-2), Vector2i(-2,2),
		Vector2i(3,0), Vector2i(0,3), Vector2i(-3,0), Vector2i(0,-3)]
	for off in offsets:
		var tx: int = cx + off.x; var ty: int = cy + off.y
		if tx < 0 or ty < 0 or tx >= w.size(): continue
		var col: Array = w[tx]
		if ty >= col.size(): continue
		var tile: Dictionary = col[ty]
		if tile.get("building") != null: continue
		if str(tile.get("biome","")) == "WATER": continue
		return Vector2i(tx, ty)
	return Vector2i(-1, -1)

func _apply_camera() -> void:
	if camera == null: return
	camera.size = _cam_zoom
	var dist: float = _cam_zoom * 1.8
	var rad_y: float = deg_to_rad(CAM_ANGLE_Y); var rad_x: float = deg_to_rad(CAM_ANGLE_X)
	var dx: float = cos(-rad_x) * sin(rad_y); var dy: float = sin(-rad_x)
	var dz: float = cos(-rad_x) * cos(rad_y)
	camera.position = _cam_target + Vector3(dx, dy, dz) * dist
	camera.look_at(_cam_target, Vector3.UP)

## Feature (v12.5, Touch-Controls): direkte Zoom-Methoden für das TouchOverlay.
## Identisch mit dem Mausrad-Zoom, aber ohne InputEvent-Simulation.
func _touch_zoom_in() -> void:
	_cam_zoom = clampf(_cam_zoom - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
	_apply_camera()

func _touch_zoom_out() -> void:
	_cam_zoom = clampf(_cam_zoom + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
	_apply_camera()

# ══════════════════════════════════════════════════════════════════════════════
func _process(delta: float) -> void:
	if not GameState.is_playing(): return
	var dt: float = delta * GameState.game_speed * SeasonSys.production_multiplier
	# Feature (v11.2, First-Person-Modus): die Iso-Kamera-Steuerung (WASD)
	# wird im First-Person-Modus nicht mehr ausgewertet, da WASD dort die
	# Spielerbewegung steuert (siehe PlayerController._physics_process()).
	# Waehrend eines aktiven Minispiels steht der Spieler zusaetzlich still.
	if not _fp_mode:
		_handle_camera_keys(delta)
	elif not _is_minigame_active():
		_update_fp_interaction()
	DayNight.update(dt); DroughtSys.update(dt)
	_update_day_night_visuals()
	WaterSys.update(dt, world)
	if _day_prev != DayNight.day_count:
		_day_prev = DayNight.day_count
		SeasonSys.update(DayNight.day_count)
		renderer.refresh_buildings()
	if DroughtSys.is_drought:
		var extra: float = float(PopMgr.get_count()) * 0.03 * dt
		ResourceSys.remove_water(extra)
		if ResourceSys.water < 1.0:
			for f in PopMgr.ferrets:
				var fe: FerretEntity = f as FerretEntity
				fe.needs["water"] = maxf(0.0, float(fe.needs["water"]) - 2.0 * dt)
	BuildingSys.update(dt, DayNight.is_day, world)
	PopMgr.update(dt, DayNight.is_day, world); ExpeditionSys.update(dt)
	# Bug-Fix (Gebäude werden nicht gebaut/kein Baufortschritt): vorher lief
	# dieser Aufruf NUR beim Tageswechsel (alle 180 Sekunden!) und addierte
	# einen einmaligen Sprung - der Fortschrittsbalken stand fast immer
	# still. Jetzt läuft die Konstruktion JEDEN Frame kontinuierlich weiter.
	_process_construction(dt)
	renderer.apply_drought(DroughtSys.is_drought)
	renderer.update_ferrets(PopMgr.ferrets)
	# Wasserphysik: Oberflaechen-Mesh nur gedrosselt neu bauen (kein voller
	# Terrain-Rebuild, aber trotzdem zu teuer fuer jeden einzelnen Frame) -
	# ca. 3x/Sekunde reicht aus, um Fluss/Verdunstung sichtbar zu machen.
	if Engine.get_process_frames() % 20 == 0: renderer.refresh_water(world)
	if Engine.get_process_frames() % 30 == 0:
		renderer.refresh_vegetation()
		renderer.refresh_storage_labels(BuildingSys.buildings)
		renderer.refresh_haul_lines(PopMgr.ferrets)
	if Engine.get_process_frames() % 60 == 0:
		_on_hud_update()
		# Bug-Fix (v10.14): "kann nach Verbrauch der Startressourcen nichts
		# mehr bauen, obwohl genug Ressourcen vorhanden sind". Ursache:
		# BuildMenu.refresh() (das die "kann ich mir leisten"-Sperre der
		# Buttons berechnet) lief bisher NUR bei building_placed/sold -
		# nicht wenn Ressourcen rein durch Produktion nachwuchsen. Waren die
		# Buttons einmal wegen leerem Lager deaktiviert, blieben sie es
		# dauerhaft eingefroren, selbst nachdem wieder genug da war. Jetzt
		# wird das BuildMenu im selben 1-Sekunden-Takt wie das HUD neu
		# bewertet.
		_on_build_menu_update()

## Feature (v10.13): bisher gab es einen Tag/Nacht-*Zyklus* (DayNightSystem.gd,
## steuert seit Projektbeginn z.B. ob Sammler/Werkstaetten arbeiten), aber
## KEINE sichtbare Auswirkung - Sonne, Umgebungslicht und Himmelfarbe blieben
## immer gleich. Dadurch wirkte es, als gaebe es gar keinen Tag/Nacht-Wechsel.
## Diese Funktion blendet Sonnenlicht/Fuelllicht/Himmel weich zwischen
## Tag- und Nachtwerten, mit kurzen Uebergangsphasen um Sonnenuntergang/
## -aufgang statt eines harten Umschaltens.
func _update_day_night_visuals() -> void:
	if _sun_light == null or _world_env == null: return
	var pct: float = DayNight.time / maxf(0.01, DayNight.day_length)  # 0..1 über den ganzen Zyklus
	var night_t: float
	if pct < 0.65:
		night_t = 0.0
	elif pct < 0.80:
		night_t = smoothstep(0.65, 0.80, pct)
	elif pct < 0.95:
		night_t = 1.0
	else:
		night_t = 1.0 - smoothstep(0.95, 1.0, pct)

	_sun_light.light_energy = lerpf(1.15, 0.08, night_t)
	_sun_light.light_color = Color(1.0, 0.95, 0.85).lerp(Color(0.55, 0.62, 0.85), night_t)
	if _fill_light != null:
		_fill_light.light_energy = lerpf(0.35, 0.05, night_t)
	_world_env.ambient_light_color = Color(0.30, 0.34, 0.44).lerp(Color(0.06, 0.07, 0.12), night_t)
	_world_env.ambient_light_energy = lerpf(0.55, 0.18, night_t)
	_world_env.background_color = Color(0.52, 0.65, 0.78).lerp(Color(0.03, 0.04, 0.09), night_t)

## Bug-Fix (Gebäude werden nicht gebaut/kein Baufortschritt): Bisher hing
## JEDER Baufortschritt komplett davon ab, dass mindestens ein Frettchen
## explizit im Bauhof (Typ "BUILDER") arbeitete - ohne das blieb
## construction_progress für immer bei 0, ohne jede Rückmeldung an den
## Spieler. Jetzt gibt es einen garantierten Grundfortschritt (die
## Kolonie baut auch ohne zugewiesene Bauhof-Arbeiter irgendwann fertig),
## plus einen Bonus pro Bauhof-Arbeiter für schnelleren Bau.
##
## Feature (v10.13): der Bonus war bisher ein einzelner GLOBALER Wert (Summe
## ALLER Bauhof-Arbeiter ueber ALLE Bauhoefe), der gleichermassen auf JEDE
## Baustelle angewendet wurde - eine Baustelle baute also genauso schnell,
## egal ob 0 oder 5 Frettchen dort tatsaechlich standen. Jetzt laufen
## Bau-Frettchen physisch zu ihrer Baustelle (siehe FerretEntity.
## _update_builder_work()) und nur die Anzahl der Frettchen, die GERADE AN
## DIESER Baustelle stehen (work_state == "BUILDING"), zaehlt fuer deren
## Tempo.
func _process_construction(dt: float) -> void:
	if dt <= 0.0: return
	const BASE_RATE: float   = 0.35  # Fortschritt/Sek auch ohne dass jemand vor Ort ist
	const WORKER_RATE: float = 0.7   # zusätzlich je Frettchen, das GERADE HIER baut
	# Feature (Tech Tree): globaler Bautempo-Bonus aus dem Themenbereich
	# "Bauwesen & Logistik" (siehe TechTree.gd, Keys "construction_speed_bonus").
	var speed_mult: float = 1.0 + TechTreeSys.get_global_bonus("construction_speed_bonus")
	var presence: Dictionary = {}    # Baustelle (instance_id) -> Anzahl Frettchen vor Ort
	for f in PopMgr.ferrets:
		var fe: FerretEntity = f
		if fe.work_state == "BUILDING" and fe.construction_site != null:
			var sid: int = (fe.construction_site as BuildingEntity).get_instance_id()
			presence[sid] = int(presence.get(sid, 0)) + 1
	for site in BuildingSys.get_construction_sites():
		var s: BuildingEntity = site as BuildingEntity
		# Feature (v11.0, Lagersystem): kein Baufortschritt mehr, solange das
		# benoetigte Baumaterial nicht vollstaendig an der Baustelle angeliefert
		# wurde - vorher gab es BASE_RATE-Fortschritt voellig unabhaengig
		# davon, ob ueberhaupt Ressourcen vorhanden waren. Siehe
		# FerretEntity._update_builder_work() fuer die Anlieferungslogik.
		if not s.is_fully_supplied(): continue
		var here: int = int(presence.get(s.get_instance_id(), 0))
		var rate: float = (BASE_RATE + float(here) * WORKER_RATE) * speed_mult
		s.construction_progress = minf(s.construction_work_needed, s.construction_progress + rate * dt)
		if s.construction_progress >= s.construction_work_needed:
			# Feature (Tech Tree): eine Baustelle, die eigentlich ein Umbau
			# ist (siehe BuildingEntity.start_rebuild()), verwandelt sich
			# jetzt in ihr Zielgebaeude, statt einfach nur "fertig" zu sein.
			if s.is_rebuild:
				var new_name: String = str(BuildingData.BUILDINGS.get(s.rebuild_target_id, {}).get("name", s.name))
				s.finish_rebuild()
				SoundSys.play_notify()
				GameState.notify("Umbau abgeschlossen: %s!" % new_name)
			else:
				s.is_under_construction = false
				# Bug6-Fix: assigned_builder ist BuildingEntity – kein current_construction_site-Feld
				s.assigned_builder = null
				SoundSys.play_notify()
				GameState.notify("%s fertig gebaut!" % s.name)

# ══════════════════════════════════════════════════════════════════════════════
# KAMERA
# ══════════════════════════════════════════════════════════════════════════════
func _handle_camera_keys(delta: float) -> void:
	if camera == null: return
	var basis := camera.global_transform.basis
	var cam_right := Vector3(basis.x.x, 0.0, basis.x.z).normalized()
	var cam_fwd   := Vector3(-basis.z.x, 0.0, -basis.z.z).normalized()
	var move := Vector3.ZERO
	if Input.is_action_pressed("move_right"): move += cam_right
	if Input.is_action_pressed("move_left"):  move -= cam_right
	if Input.is_action_pressed("move_down"):  move -= cam_fwd
	if Input.is_action_pressed("move_up"):    move += cam_fwd
	if move != Vector3.ZERO:
		_cam_target += move.normalized() * CAM_SPEED * delta; _apply_camera()

# ══════════════════════════════════════════════════════════════════════════════
# FIRST-PERSON-MODUS (v11.2)
# ══════════════════════════════════════════════════════════════════════════════
func _is_minigame_active() -> bool:
	return _minigame != null and bool(_minigame.is_active())

## Schaltet zwischen isometrischer Kolonie-Ansicht und First-Person-Steuerung
## des Spieler-Frettchens um. Die Kolonie-Simulation (BuildingSys.update(),
## PopMgr.update() etc. in _process()) laeuft in BEIDEN Modi unveraendert
## weiter (siehe Nutzeranfrage: "realistischer, soll normal weiterlaufen") -
## es aendert sich nur, welche Kamera aktiv ist und wie Eingaben interpretiert
## werden.
func _toggle_fp_mode() -> void:
	if player == null or camera == null or renderer == null: return
	if _is_minigame_active(): return
	_fp_mode = not _fp_mode
	if _fp_mode:
		# Feature (v11.25): NUR beim allerersten Frettchenmodus-Aufenthalt
		# ueberhaupt (frisch generierte/geladene Welt ohne gueltige
		# Spielerposition) wird auf die aktuelle Iso-Kamera-Zielposition
		# teleportiert, damit der allererste Uebergang sich nicht wie ein
		# Sprung ins Leere anfuehlt. Bei jedem weiteren Betreten bleibt der
		# Spieler exakt dort, wo er beim letzten Verlassen des Modus stand
		# (bzw. wo ihn ein Laufbefehl in der Iso-Ansicht zuletzt hingefuehrt
		# hat) - kein erneutes Teleportieren noetig, da player.global_position
		# bereits korrekt ist.
		if not _player_pos_valid:
			var spawn_tile: Vector2i = renderer.world3d_to_tile(_cam_target)
			var spawn_pos: Vector3 = renderer.tile_to_world3d(spawn_tile.x, spawn_tile.y)
			player.teleport_to(spawn_pos)
			_player_pos_valid = true
		# Feature (v11.26): ein evtl. noch laufender Mittelklick-Laufbefehl
		# darf im First-Person-Modus nicht die WASD-Steuerung uebersteuern.
		player.cancel_walk()
		player.movement_enabled = true
		player.ferret_visual.visible = false
		player.camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if _hud_node: _hud_node.visible = false
		if _build_menu_node: _build_menu_node.visible = false
		if _fp_hud: _fp_hud.show()
		_fp_target_kind = ""; _fp_target_res = ""
		if _fp_hud: _fp_hud.set_prompt("")
	else:
		player.movement_enabled = false
		player.ferret_visual.visible = true
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if _hud_node: _hud_node.visible = true
		if _build_menu_node: _build_menu_node.visible = true
		if _fp_hud: _fp_hud.hide()
	# Feature (v12.3, Tutorial-Ueberarbeitung):
	GameState.fp_mode_changed.emit(_fp_mode)

## Feature (v12.3, Tutorial-Ueberarbeitung): sucht ausgehend von (around_tx,
## around_ty) spiralfoermig die naechste tatsaechlich bebaubare Tile (kein
## Gebaeude drauf, kein Wasser-Biom - dieselbe Regel wie in _place_building()
## oben) - fuers interaktive "baue hier"-Tutorial, damit der markierte Punkt
## garantiert gueltig ist, unabhaengig vom zufaellig generierten Terrain rund
## um den Startpunkt.
func find_nearby_buildable_tile(around_tx: int, around_ty: int, max_radius: int = 8) -> Vector2i:
	if world_gen == null: return Vector2i(-1, -1)
	for r in range(0, max_radius + 1):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r: continue  # nur der aktuelle "Ring"
				var tx: int = around_tx + dx; var ty: int = around_ty + dy
				if tx < 0 or ty < 0 or tx >= world_gen.w or ty >= world_gen.h: continue
				var tile: Dictionary = (world[tx] as Array)[ty] as Dictionary
				if tile.get("building") != null: continue
				if str(tile.get("biome", "")) == "WATER": continue
				if tile.get("path") != null: continue
				return Vector2i(tx, ty)
	return Vector2i(-1, -1)

## Sucht in INTERACT_RANGE um den Spieler die naechstgelegene erntbare
## Ressourcenquelle (resource_node WOOD/STONE/BERRIES/IRON) ODER ein
## WATER-Tile, und aktualisiert den FPHud-Prompt entsprechend. Wasser hat
## keinen "resource_node"-Eintrag (das Wasserschoepfen ist hier rein
## kosmetisch/Minispiel-bezogen, unabhaengig vom dynamischen WaterSystem.gd),
## daher zwei getrennte Suchstrategien.
func _update_fp_interaction() -> void:
	var ptile: Vector2i = renderer.world3d_to_tile(player.global_position)
	var best_d: float = INF
	var best_kind: String = ""; var best_res: String = ""; var best_tile: Vector2i = Vector2i(-1,-1)
	# Feature (v12.2, Phase 4): radius_tiles auf 3 angehoben (vorher 2) - bei
	# maximal moeglichem Interaktionsreichweiten-Boost (Krone*Monokel =
	# 1.35*1.20 = 1.62x, siehe PlayerAccessories.BOOSTS) wuerde ein Tile-Suchradius
	# von nur 2 manche Ziele in Boost-Reichweite gar nicht erst finden.
	var radius_tiles: int = 3
	# Feature (v12.2, Phase 4): Krone- und Monokel-Boost verlaengern die
	# Interaktionsreichweite (stacken multiplikativ, siehe
	# PlayerAccessories.BOOSTS).
	var interact_range: float = INTERACT_RANGE * PlayerAccessories.get_boost_mult("interact_range_mult")
	for dx in range(-radius_tiles, radius_tiles + 1):
		for dy in range(-radius_tiles, radius_tiles + 1):
			var tx: int = ptile.x + dx; var ty: int = ptile.y + dy
			if tx < 0 or ty < 0 or tx >= renderer.world_w or ty >= renderer.world_h: continue
			var tile: Dictionary = (world[tx] as Array)[ty] as Dictionary
			var d: float = player.global_position.distance_to(renderer.tile_to_world3d(tx, ty))
			if d > interact_range: continue
			var nd = tile.get("resource_node")
			if nd != null and not bool((nd as Dictionary).get("depleted", false)) and float((nd as Dictionary).get("amount",0.0)) > 0.5:
				if d < best_d:
					best_d = d; best_kind = "NODE"; best_res = str((nd as Dictionary)["type"]); best_tile = Vector2i(tx, ty)
			elif str(tile.get("biome","")) == "WATER":
				if d < best_d:
					best_d = d; best_kind = "WATER"; best_res = "WATER"; best_tile = Vector2i(tx, ty)
	_fp_target_kind = best_kind; _fp_target_res = best_res; _fp_target_tile = best_tile
	if _fp_hud == null: return
	if best_kind == "":
		_fp_hud.set_prompt("")
	else:
		var icon: String = str(BuildingData.RESOURCE_ICONS.get(best_res, "?"))
		var verb: String = {"WOOD":"Holz faellen","STONE":"Stein brechen","BERRIES":"Beeren pfluecken",
			"IRON":"Erz abbauen","WATER":"Wasser schoepfen"}.get(best_res, "Sammeln")
		_fp_hud.set_prompt("[E] %s %s" % [icon, verb])

## Wird per "interact"-Taste (E) ausgeloest, wenn ein Ziel in Reichweite ist.
func _try_start_fp_interaction() -> void:
	if _fp_target_kind == "" or _minigame == null: return
	var max_reward: float = float(MINIGAME_MAX_REWARD.get(_fp_target_res, 10.0))
	match _fp_target_res:
		"WOOD":    _minigame.start_wood(max_reward)
		"STONE":   _minigame.start_stone(max_reward)
		"BERRIES": _minigame.start_berries(max_reward)
		"IRON":    _minigame.start_iron(max_reward)
		"WATER":   _minigame.start_water(max_reward)
		_: return
	player.movement_enabled = false
	if _fp_hud: _fp_hud.set_prompt("")

## Feature (v11.2): Belohnung landet direkt im globalen Lagerpool (Nutzer-
## entscheidung: "Landen direkt im globalen Lager", keine eigene Inventar-
## Mechanik fuers Spieler-Frettchen). Bei den vier knotenbasierten Ressourcen
## (WOOD/STONE/BERRIES/IRON) wird zusaetzlich der "resource_node" an Ort und
## Stelle um den geernteten Betrag reduziert (gleiche Erschoepfungs-/Regenerations-
## Logik wie bei NPC-Frettchen, siehe WorldGenerator.tick_resource_nodes()) -
## das Minispiel ersetzt die NPC-Ernte nicht, es ist eine zusaetzliche,
## physisch am selben Knoten ansetzende Erntemoeglichkeit.
func _on_minigame_finished(resource: String, reward: float) -> void:
	player.movement_enabled = _fp_mode
	# Feature (v12.2, Phase 4): "perfekt" wird VOR den Boosts anhand des
	# rohen Minispiel-Ergebnisses bestimmt (Boosts sollen nicht kuenstlich
	# "perfekte" Ergebnisse erzeugen, die der Spieler eigentlich nicht
	# geschafft hat - der PLAYER_PERFECT_20-Erfolg soll echtes
	# Spielergeschick wiederspiegeln).
	var max_reward: float = float(MINIGAME_MAX_REWARD.get(resource, 10.0))
	var is_perfect: bool = reward >= max_reward - 0.5
	# Zauberhut- (%) und Medaille- (flat) Boost - NUR auf tatsaechliche
	# Beute (reward > 0), kein Bonus auf ein "Nichts erbeutet"-Ergebnis.
	if reward > 0.0:
		reward *= PlayerAccessories.get_boost_mult("minigame_reward_mult")
		reward += PlayerAccessories.get_boost_flat("minigame_flat_bonus")
	var node_just_depleted: bool = false
	if reward > 0.0:
		if resource == "WATER":
			ResourceSys.add_water(reward)
		else:
			if _fp_target_tile.x >= 0 and _fp_target_tile.x < renderer.world_w and _fp_target_tile.y < renderer.world_h:
				var tile: Dictionary = (world[_fp_target_tile.x] as Array)[_fp_target_tile.y] as Dictionary
				var nd = tile.get("resource_node")
				if nd != null:
					var ndd: Dictionary = nd
					var taken: float = minf(reward, float(ndd.get("amount", 0.0)))
					ndd["amount"] = float(ndd["amount"]) - taken
					if float(ndd["amount"]) <= 0.5:
						if not bool(ndd.get("depleted", false)): node_just_depleted = true
						ndd["depleted"] = true; ndd["regen_timer"] = 0.0
					reward = taken
			ResourceSys.add(resource, reward)
		_on_hud_update()
	# Feature (v12.2, Phase 4): Frettchen-Ich-Fortschritt melden.
	AchievementSys.report_player_minigame(reward, is_perfect, SeasonSys.get_season_name() == "Winter")
	if node_just_depleted: AchievementSys.report_player_node_depleted()
	if _fp_hud:
		var icon: String = str(BuildingData.RESOURCE_ICONS.get(resource, "?"))
		if reward > 0.5:
			_fp_hud.show_floaty("+%d %s" % [int(round(reward)), icon], true)
		else:
			_fp_hud.show_floaty("Nichts erbeutet...", false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _fp_mode else Input.MOUSE_MODE_VISIBLE

# ══════════════════════════════════════════════════════════════════════════════
# INPUT
# ══════════════════════════════════════════════════════════════════════════════
## Bug-Fix (v10.19): war zuvor _input(), nicht _unhandled_input(). In Godot 4
## wird _input() auf JEDEM Node aufgerufen, BEVOR das GUI-System (Control/
## Button._gui_input) ueberhaupt die Chance hatte, das Klick-Event als
## "verarbeitet" zu markieren - die Engine ruft Node._input() schlicht
## unabhaengig vom GUI-Konsum auf. Klickte man z.B. den "+"-Button in der
## Gebaeude-Info-UI (etwa um die Frettchenzahl zu erhoehen), feuerte ZWEI
## Dinge gleichzeitig: der Button-eigene pressed-Handler (UI reagiert
## korrekt) UND dieser Handler hier, der per Raycast die Tile HINTER der UI
## an der Klick-Bildschirmposition traf und ueber _select_tile()/
## building_deselected meist sofort wieder die gerade geoeffnete UI schloss.
## _unhandled_input() wird von der Engine garantiert NUR aufgerufen, wenn kein
## Control das Event zuvor konsumiert hat (Buttons/Container haben per
## Default MOUSE_FILTER_STOP) - damit erreichen Klicks auf UI-Elemente die
## 3D-Welt darunter nicht mehr.
func _unhandled_input(event: InputEvent) -> void:
	if not GameState.is_playing(): return
	if event is InputEventKey and (event as InputEventKey).pressed:
		match (event as InputEventKey).keycode:
			KEY_ESCAPE:
				# Feature (v11.2, First-Person-Modus): Prioritaet - laeuft ein
				# Minispiel, bricht ESC nur dieses ab; im First-Person-Umherlaufen
				# (ohne Minispiel) verlaesst ESC den Modus zurueck zur Kolonie-
				# Ansicht; sonst unveraendertes altes Verhalten.
				if _is_minigame_active(): _minigame.cancel()
				elif _fp_mode: _toggle_fp_mode()
				elif not GameState.placement_mode.is_empty(): GameState.cancel_placement()
				else: _toggle_pause()
			# Bug-Fix (v11.2b): Leertaste pausiert im FP-Modus NICHT mehr -
			# wird dort als Sprung-Taste (fp_jump) vom PlayerController
			# verarbeitet und per set_input_as_handled() als konsumiert
			# markiert. Hier deshalb Guard gegen _fp_mode.
			KEY_SPACE:
				if not _fp_mode: GameState.toggle_pause()
			KEY_1: GameState.set_game_speed(1.0)
			KEY_2: GameState.set_game_speed(2.0)
			KEY_3: GameState.set_game_speed(3.0)
			KEY_F:
				if not _is_minigame_active() and GameState.placement_mode.is_empty():
					_toggle_fp_mode()
			KEY_E:
				if _fp_mode and not _is_minigame_active():
					_try_start_fp_interaction()
	# Feature (v11.2): im First-Person-Modus (ausserhalb eines Minispiels)
	# steuert die Maus ausschliesslich die Blickrichtung - die gesamte
	# bestehende Iso-Kamera-Maussteuerung (Zoom, Rechtsklick-Drag,
	# Linksklick-Tile-Auswahl/Pfad-Malen) wird dafuer komplett uebersprungen.
	if _fp_mode and not _is_minigame_active():
		if event is InputEventMouseMotion:
			player.apply_look((event as InputEventMouseMotion).relative)
		return
	if _fp_mode and _is_minigame_active():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# Bug-Fix (v11.12): Mausrad ueber einem geoeffneten UI-Panel (z.B.
		# beim Scrollen im Tech Tree oder einer Liste) hat bisher ZUSAETZLICH
		# die Kamera gezoomt, da _unhandled_input() Mausrad-Events auch dann
		# bekommt, wenn ein darueberliegendes Control sie nicht explizit als
		# behandelt markiert (z.B. Container mit MOUSE_FILTER_IGNORE, oder ein
		# ScrollContainer ohne aktuell scrollbaren Inhalt). Statt jede
		# Container-Hierarchie einzeln abzudichten: generische Sperre - wenn
		# die Maus GERADE über irgendeinem GUI-Control steht (Panel, Button,
		# Scrollbereich, ...), wird das Kamera-Zoom fuer dieses Event komplett
		# uebersprungen.
		var over_ui: bool = get_viewport().gui_get_hovered_control() != null
		if (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN) and over_ui:
			return
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_cam_zoom = clampf(_cam_zoom - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX); _apply_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				_cam_zoom = clampf(_cam_zoom + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX); _apply_camera()
			MOUSE_BUTTON_RIGHT:
				_is_right_drag = mb.pressed; _touch_moved = false
				if mb.pressed: _drag_world_hit = _raycast_plane(mb.position, 0.0)
			MOUSE_BUTTON_MIDDLE:
				# Feature (v11.26): Laufbefehl fuers Frettchen-Ich. Nur in der
				# Iso-Ansicht (nicht waehrend man den Frettchenmodus selbst
				# steuert - dort gibt WASD/Maus-Look vor) und nicht ueber
				# einem UI-Element (sonst wuerde z.B. ein Mittelklick auf ein
				# Panel versehentlich einen Laufbefehl ausloesen).
				if mb.pressed and not _fp_mode and not _is_minigame_active() \
						and get_viewport().gui_get_hovered_control() == null:
					_start_player_walk_to_screen(mb.position)
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_path_dragging = not GameState.placement_mode.is_empty()
					_touch_moved = false; _update_ghost(mb.position)
				else:
					_path_dragging = false
					if not _touch_moved: _handle_click(mb.position)
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _is_right_drag:
			var cur_hit := _raycast_plane(mm.position, 0.0)
			var diff := _drag_world_hit - cur_hit; diff.y = 0.0
			_cam_target += diff; _apply_camera(); _touch_moved = true
		else:
			_update_ghost(mm.position)
			if _path_dragging: _handle_drag_paint(mm.position)
	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		var d0 := _raycast_plane(sd.position - sd.relative, 0.0)
		var d1 := _raycast_plane(sd.position, 0.0)
		var diff := d0 - d1; diff.y = 0.0
		_cam_target += diff; _apply_camera(); _touch_moved = true
	if event is InputEventScreenTouch:
		if (event as InputEventScreenTouch).pressed:
			_touch_moved = false
		elif not _touch_moved:
			# Feature (v12.5, Touch-Controls): wenn der Laufbefehl-Modus im
			# TouchOverlay aktiv ist, leitet das Overlay den Tap als Walk-Ziel
			# weiter statt ihn als normalen Klick zu behandeln.
			var touch_ov: Node = get_node_or_null("GameUI/UIRoot/TouchOverlay")
			if touch_ov != null and touch_ov.has_method("consume_walk_tap"):
				if touch_ov.call("consume_walk_tap", (event as InputEventScreenTouch).position):
					return
			_handle_click((event as InputEventScreenTouch).position)
	if event is InputEventMagnifyGesture:
		_cam_zoom = clampf(_cam_zoom / (event as InputEventMagnifyGesture).factor, ZOOM_MIN, ZOOM_MAX)
		_apply_camera()

# ══════════════════════════════════════════════════════════════════════════════
# RAYCAST
# ══════════════════════════════════════════════════════════════════════════════
func _raycast_plane(screen_pos: Vector2, plane_y: float) -> Vector3:
	if camera == null: return Vector3.ZERO
	var from := camera.project_ray_origin(screen_pos)
	var dir  := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001: return Vector3.ZERO
	var t := (plane_y - from.y) / dir.y
	if t < 0.0: t = 0.0
	return from + dir * t

## Feature (v11.26): gemeinsame Raycast-Basis fuer _screen_to_tile() (das nur
## die Tile-Koordinate braucht) UND den neuen Mittelklick-Laufbefehl (der die
## tatsaechliche Terrain-Weltposition inkl. Hoehe braucht, damit der Spieler
## nicht auf halber Hoehe eines Huegels als Ziel landet). Bisher war dieser
## Code direkt in _screen_to_tile() dupliziert - jetzt ausgelagert.
func _screen_to_world3d(screen_pos: Vector2) -> Vector3:
	if camera == null: return Vector3.ZERO
	var space := get_viewport().find_world_3d().direct_space_state
	var from  := camera.project_ray_origin(screen_pos)
	var to    := from + camera.project_ray_normal(screen_pos) * 500.0
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = 1
	var hit := space.intersect_ray(params)
	if hit.is_empty(): return _raycast_plane(screen_pos, 0.0)
	return hit["position"] as Vector3

func _screen_to_tile(screen_pos: Vector2) -> Vector2i:
	var world_pos: Vector3 = _screen_to_world3d(screen_pos)
	return Vector2i(int(world_pos.x / WorldRenderer3D.TILE_SIZE), int(world_pos.z / WorldRenderer3D.TILE_SIZE))

## Feature (v11.26, Mittelklick-Laufbefehl): ermittelt aus der Klickposition
## die Ziel-Tile und startet eine geradlinige Laufbewegung (siehe
## PlayerController.start_walk_to()) dorthin. Ausserhalb der Weltgrenzen
## geklickt -> Befehl wird ignoriert (kein Ziel gesetzt).
func _start_player_walk_to_screen(screen_pos: Vector2) -> void:
	if player == null or world_gen == null or renderer == null: return
	var world_pos: Vector3 = _screen_to_world3d(screen_pos)
	var tv: Vector2i = renderer.world3d_to_tile(world_pos)
	if tv.x < 0 or tv.y < 0 or tv.x >= world_gen.w or tv.y >= world_gen.h: return
	var target: Vector3 = renderer.tile_to_world3d(tv.x, tv.y)
	player.start_walk_to(target)
	_player_pos_valid = true

func _update_ghost(screen_pos: Vector2) -> void:
	if GameState.placement_mode == "BUILDING" and not GameState.placement_sub.is_empty():
		var tv := _screen_to_tile(screen_pos)
		renderer.update_ghost(tv.x, tv.y, GameState.placement_sub)
	else: renderer.clear_ghost()

# ══════════════════════════════════════════════════════════════════════════════
# SPIELAKTIONEN
# ══════════════════════════════════════════════════════════════════════════════
func _handle_click(screen_pos: Vector2) -> void:
	# Feature (v11.9, Frettchen-Klick-Interaktion): nur außerhalb eines
	# aktiven Platzierungsmodus pruefen (sonst wuerde ein Klick auf ein
	# Frettchen versehentlich ein Gebaeude/einen Weg mitten drauf bauen).
	if GameState.placement_mode.is_empty():
		var clicked_ferret: FerretEntity = renderer.find_ferret_at_screen_pos(screen_pos, camera, PopMgr.ferrets)
		if clicked_ferret != null:
			GameState.ferret_selected.emit(clicked_ferret)
			return
	var tv := _screen_to_tile(screen_pos)
	var tx: int = tv.x; var ty: int = tv.y
	if world_gen == null: return
	if tx < 0 or ty < 0 or tx >= world_gen.w or ty >= world_gen.h:
		renderer.clear_selection(); GameState.building_deselected.emit(); return
	match GameState.placement_mode:
		"BUILDING": _place_building(tx, ty, GameState.placement_sub)
		"PATH":     _place_path(tx, ty, GameState.placement_sub)
		"TERRAIN":
			if GameState.placement_sub == "RAISE":
				# Crash-Fix: build_world() ist ein KOMPLETTER Neuaufbau (loescht und
				# erzeugt Terrain, Kollision, ALLE Gebaeude und Frettchen neu). Fuer
				# eine einzelne Hoehenaenderung reicht refresh_terrain() (Mesh +
				# Kollision), siehe auch _handle_drag_paint().
				WorldGenerator.raise_terrain(world, tx, ty); renderer.refresh_terrain()
			elif GameState.placement_sub == "DYNAMITE":
				WorldGenerator.place_dynamite(world, tx, ty, explosions)
		_: _select_tile(tx, ty)

func _handle_drag_paint(screen_pos: Vector2) -> void:
	var tv := _screen_to_tile(screen_pos)
	if GameState.placement_mode == "PATH":
		_place_path(tv.x, tv.y, GameState.placement_sub, true)
	elif GameState.placement_mode == "TERRAIN" and GameState.placement_sub == "RAISE":
		# Crash-Fix: InputEventMouseMotion kann mehrfach PRO FRAME ausgeloest
		# werden. Mit dem vorherigen renderer.build_world() (voller Teardown +
		# Neuaufbau von Terrain, Kollision, allen Gebaeuden UND Frettchen) wurden
		# beim Ziehen der Maus etliche StaticBody3D/Mesh-Generationen pro Sekunde
		# erzeugt, deren queue_free() noch ausstand, waehrend schon die naechste
		# Generation aufgebaut wurde. Das haeufte sich beim Aufschuetten von
		# Terrain ueber laengere Zeit auf und liess das Spiel irgendwann
		# abstuerzen. refresh_terrain() baut nur Mesh + Kollision neu, nicht
		# Gebaeude/Frettchen, und ist damit sicher fuer haeufige Aufrufe.
		WorldGenerator.raise_terrain(world, tv.x, tv.y); renderer.refresh_terrain()

func _place_building(tx: int, ty: int, building_id: String) -> void:
	if building_id.is_empty() or world_gen == null: return
	var tile: Dictionary = (world[tx] as Array)[ty] as Dictionary
	if tile.get("building") != null: GameState.notify("Hier steht bereits ein Gebaeude!"); return
	# Feature (Wasserphysik): Daemme muessen direkt auf/im Wasser stehen
	# koennen, um den lokalen Abfluss zu drosseln - alle anderen Gebaeude
	# bleiben weiterhin von Wasser-Tiles ausgeschlossen.
	if str(tile.get("biome","")) == "WATER" and building_id != "DAM":
		GameState.notify("Nicht auf Wasser bauen!"); return
	if not GameState.dev_all_buildings and not BuildingSys.can_build(building_id):
		GameState.notify("Nicht genug Ressourcen!"); return
	var b: BuildingEntity = BuildingSys.build(building_id, tx, ty, world, GameState.dev_all_buildings)
	if b != null:
		b.placed_day = DayNight.day_count
		renderer.add_building(b); SoundSys.play_build()
		GameState.cancel_placement(); renderer.clear_ghost()

func _place_path(tx: int, ty: int, path_type: String, silent: bool = false) -> void:
	if world_gen == null: return
	if tx < 0 or ty < 0 or tx >= world_gen.w or ty >= world_gen.h: return
	var tile: Dictionary = (world[tx] as Array)[ty] as Dictionary
	if tile.get("building") != null or str(tile.get("biome","")) in ["WATER","MOUNTAIN"]: return
	if tile.get("path") != null: return
	var pt: Dictionary = BuildingData.PATH_TYPES.get(path_type, {}) as Dictionary
	var costs: Dictionary = pt.get("costs", {}) as Dictionary
	if not GameState.dev_all_buildings and not ResourceSys.can_afford(costs):
		if not silent: GameState.notify("Nicht genug Ressourcen fuer Weg!"); return
	if not GameState.dev_all_buildings: ResourceSys.spend(costs)
	tile["path"] = {"type": path_type}
	renderer.refresh_terrain(); _on_hud_update()

func _select_tile(tx: int, ty: int) -> void:
	renderer.set_selection(tx, ty)
	var tile: Dictionary = (world[tx] as Array)[ty] as Dictionary
	var bld = tile.get("building", null)
	if bld != null:
		var b: BuildingEntity = bld as BuildingEntity
		renderer.selected_building = b; GameState.building_selected.emit(b)
		# Feature (v11.1, Logistik-Feinschliff): Gebaeude-Ketten-Vorschau
		# anzeigen (Produktionsgebaeude → Lagerhaus → Baustelle).
		renderer.refresh_chain_lines(b)
	else:
		renderer.selected_building = null; GameState.building_deselected.emit()
		renderer.clear_chain_lines()
		if bool(tile.get("ruin",false)) and ResourceSys.has("TOOLS", 5):
			ResourceSys.remove("TOOLS", 5); tile["ruin"] = false
			ResourceSys.force_add("WOOD", float(randi_range(10,30)))
			ResourceSys.force_add("STONE", float(randi_range(5,20)))
			GameState.notify("Ruine erkundet! Beute gefunden!"); _on_hud_update()

func sell_selected_building() -> void:
	if renderer.selected_building == null: return
	var bname: String = renderer.selected_building.name
	var stx: int = renderer.selected_building.tile_x
	var sty: int = renderer.selected_building.tile_y
	BuildingSys.sell(renderer.selected_building, world)
	renderer.remove_building(stx, sty)
	renderer.selected_building = null; renderer.clear_selection()
	GameState.building_deselected.emit(); GameState.notify(bname + " verkauft!")

func upgrade_selected_building() -> void:
	if renderer.selected_building == null: return
	if renderer.selected_building.upgrade():
		renderer.add_building(renderer.selected_building)
		GameState.notify("Upgrade auf Stufe %d!" % renderer.selected_building.level); _on_hud_update()
	else: GameState.notify("Upgrade nicht moeglich!")

## Feature (Tech Tree): startet den per Tech-Tree freigeschalteten Umbau des
## gerade ausgewaehlten Gebaeudes (siehe BuildingInfo.gd RebuildBtn).
func rebuild_selected_building() -> void:
	if renderer.selected_building == null: return
	var bname: String = renderer.selected_building.name
	if BuildingSys.start_rebuild(renderer.selected_building):
		GameState.notify("Umbau von " + bname + " gestartet!"); _on_hud_update()
	else:
		GameState.notify("Umbau nicht moeglich!")

func _toggle_pause() -> void:
	if GameState.current_state == GameState.State.PLAYING:
		GameState.set_state(GameState.State.PAUSED); GameState.game_speed = 0.0
	else:
		GameState.set_state(GameState.State.PLAYING); GameState.game_speed = 1.0

# ── UI-Callbacks ──────────────────────────────────────────────────────────────
func _on_hud_update() -> void:
	var hud := get_node_or_null("GameUI/UIRoot/HUD")
	if hud and hud.has_method("refresh"): hud.call("refresh")

func _on_build_menu_update() -> void:
	var bm := get_node_or_null("GameUI/UIRoot/BuildMenu")
	if bm and bm.has_method("refresh"): bm.call("refresh")

func _on_building_selected(b: BuildingEntity) -> void:
	var bi := get_node_or_null("GameUI/UIRoot/BuildingInfo")
	if bi and bi.has_method("show_building"): bi.call("show_building", b, self)

func _on_building_deselected() -> void:
	var bi := get_node_or_null("GameUI/UIRoot/BuildingInfo")
	if bi: bi.hide()

## Feature (v11.9, Frettchen-Klick-Interaktion): oeffnet das Profil-Panel des
## angeklickten Frettchens (Muster identisch zu _on_building_selected() oben).
func _on_ferret_selected(f) -> void:
	var fp := get_node_or_null("GameUI/UIRoot/FerretProfilePanel")
	if fp and fp.has_method("show_ferret"): fp.call("show_ferret", f)

## Feature (v11.9, Legendäre Frettchen): auffaelliges, klickbares Popup bei
## Legendaer-Werden (siehe ui/LegendaryToast.gd) - Klick darauf oeffnet direkt
## das Profil des betroffenen Frettchens (ferret_selected wird von dort aus
## erneut emittiert).
func _on_ferret_became_legendary(f) -> void:
	var root := get_tree().get_root()
	var lt := root.find_child("LegendaryToast", true, false)
	if lt and lt.has_method("show_toast"): lt.call("show_toast", f)

func _on_notification(msg: String, color: Color) -> void:
	var root := get_tree().get_root()
	var nl := root.find_child("Notifications", true, false)
	if nl and nl.has_method("show_notification"): nl.call("show_notification", msg, color)

func _on_game_over(_cause: String) -> void:
	GameState.set_state(GameState.State.GAME_OVER)

func _on_placement_mode_changed(mode: String, _sub: String) -> void:
	var hint := get_node_or_null("GameUI/UIRoot/PlacementHint")
	if hint == null: return
	if mode.is_empty(): hint.hide(); renderer.clear_ghost(); return
	hint.show()
	match mode:
		"BUILDING": hint.text = "Klicken zum Platzieren  |  ESC = Abbrechen"
		"PATH":     hint.text = "Klicken/Halten zum Malen  |  ESC = Abbrechen"
		"TERRAIN":  hint.text = "Klicken/Halten auf Terrain  |  ESC = Abbrechen"

# ── Speichern / Laden ─────────────────────────────────────────────────────────
## Feature (v11.4, Speicherslot-System): erzeugt aus dem vom Spieler
## eingegebenen Kolonienamen einen gueltigen, eindeutigen Speicherslot-Namen -
## verbotene Dateisystemzeichen werden entfernt, bei Namenskollision mit einem
## bereits vorhandenen Speicherstand wird "(2)", "(3)", ... angehaengt.
func _make_unique_save_slot(raw_name: String) -> String:
	var clean: String = raw_name.strip_edges()
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		clean = clean.replace(ch, "")
	if clean.is_empty(): clean = "Kolonie"
	var existing: Array = SaveSys.get_save_names()
	if not existing.has(clean): return clean
	var i: int = 2
	while existing.has(clean + " (%d)" % i): i += 1
	return clean + " (%d)" % i

## Feature (v11.4, Speicherslot-System): kompakte Metadaten fuer die
## Welt-Auswahl-Liste - wird von SaveSystem.save() aufgerufen und oben in
## jeder Speicherdatei abgelegt, damit das Laden-Menue Name/Tag/Jahreszeit/
## Bevoelkerung/Seed anzeigen kann, ohne den ganzen Spielstand einzulesen.
func get_save_metadata() -> Dictionary:
	return {
		"colony_name": current_world_name,
		"seed": world_gen.seed_val if world_gen != null else 0,
		"day_count": DayNight.day_count,
		"season_name": SeasonSys.get_season_name(),
		"season_icon": SeasonSys.get_season_icon(),
		"population_count": PopMgr.get_count(),
		"world_w": world_gen.w if world_gen != null else 0,
		"world_h": world_gen.h if world_gen != null else 0,
	}

func serialize_world() -> Dictionary:
	if world_gen == null: return {}
	var rows: Array = []
	for x in world_gen.w:
		var col_data: Array = []
		for y in world_gen.h:
			var t: Dictionary = (world[x] as Array)[y] as Dictionary
			col_data.append({"biome": str(t.get("biome","PLAINS")), "height": float(t.get("height",0.0)),
				"path": t.get("path"), "ruin": bool(t.get("ruin",false)),
				"resource_node": t.get("resource_node"),
				"water_level": float(t.get("water_level", 0.0)),
				"is_water_source": bool(t.get("is_water_source", false))})
		rows.append(col_data)
	return {"size_w": world_gen.w, "size_h": world_gen.h, "seed": world_gen.seed_val, "tiles": rows}

func deserialize_world(data: Dictionary) -> void:
	if data.is_empty(): return
	world_gen = WorldGenerator.new()
	world_gen.w = int(data.get("size_w",60)); world_gen.h = int(data.get("size_h",60))
	world_gen.seed_val = int(data.get("seed",0)); world = []
	var tiles: Array = data.get("tiles",[]) as Array
	for x in world_gen.w:
		var col: Array = []
		for y in world_gen.h:
			var td: Dictionary = {}
			if x < tiles.size():
				var tc: Array = tiles[x] as Array
				if y < tc.size(): td = tc[y] as Dictionary
			col.append({"biome": str(td.get("biome","PLAINS")), "height": float(td.get("height",0.0)),
				"building": null, "path": td.get("path"), "resource_node": td.get("resource_node"),
				"ruin": bool(td.get("ruin",false)), "dynamite": false,
				"water_level": float(td.get("water_level", 1.0 if str(td.get("biome","PLAINS")) == "WATER" else 0.0)),
				"is_water_source": bool(td.get("is_water_source", false))})
		world.append(col)
	WaterSys.init(world, world_gen.w, world_gen.h)
	_setup_renderer()
	@warning_ignore("integer_division")
	_cam_target = renderer.tile_to_world3d(world_gen.w/2, world_gen.h/2); _cam_target.y = 0.0
	_apply_camera()
	# Feature (v11.2, First-Person-Modus): Spieler-Frettchen auch beim Laden
	# eines Spielstands sauber positionieren (Speicherstaende vor v11.2 kennen
	# keine Spielerposition). Feature (v11.25): dies ist nur noch der
	# FALLBACK fuer Speicherstaende OHNE gespeicherte Spielerposition (vor
	# v11.25) - deserialize_player() (separat aufgerufen, siehe
	# SaveSystem.load_game()) ueberschreibt das anschliessend mit der
	# tatsaechlich gespeicherten Position, falls vorhanden.
	if player != null:
		@warning_ignore("integer_division")
		player.teleport_to(renderer.tile_to_world3d(world_gen.w/2 + 1, world_gen.h/2))
		player.movement_enabled = false
		_player_pos_valid = true

## Feature (v11.25, Positions-Persistenz): Spielerposition + Blickrichtung
## (Yaw) fuers Speichern. Wird separat von serialize_world() gehalten (nicht
## Teil der Tile-Daten), da es sich um Spieler- statt Weltzustand handelt -
## gleiches Muster wie ResourceSys/BuildingSys/etc., die auch je ein eigenes
## Top-Level-Feld im Speicherstand haben (siehe SaveSystem.save()).
func serialize_player() -> Dictionary:
	if player == null: return {}
	var p: Vector3 = player.global_position
	return {"pos": [p.x, p.y, p.z], "yaw": player.rotation.y, "valid": _player_pos_valid}

## Wird NACH deserialize_world() aufgerufen (siehe SaveSystem.load_game()) -
## deserialize_world() setzt bereits einen sinnvollen Fallback-Spawnpunkt
## (fuer Speicherstaende vor v11.25), hier wird das bei Bedarf mit der
## tatsaechlich gespeicherten Position ueberschrieben.
func deserialize_player(data: Dictionary) -> void:
	if player == null or data.is_empty() or not bool(data.get("valid", false)): return
	var arr: Array = data.get("pos", []) as Array
	if arr.size() != 3: return
	player.global_position = Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	player.rotation.y = float(data.get("yaw", 0.0))
	player.velocity = Vector3.ZERO
	_player_pos_valid = true
	_fp_mode = false

## Wird von SaveSystem nach load_game() aufgerufen.
## Terrain ist fertig, Gebäude sind jetzt in den Tiles → Renderer-Nodes erzeugen.
func post_load_refresh() -> void:
	if renderer != null:
		renderer.refresh_buildings()
		renderer.apply_drought(DroughtSys.is_drought)
	_on_hud_update()
	_on_build_menu_update()
