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
var _season_vis: SeasonVisuals     = null   # v15.4: sichtbare Jahreszeiten
var _realism:    RealismFX         = null   # v15.4: schaltbarer Realismus-Modus

var world:     Array          = []
var world_gen: WorldGenerator = null
var explosions: Array         = []

# ── Feature (v11.4, Speicherslot-System) ─────────────────────────────────────
# current_world_name = Anzeigename der Kolonie (vom Spieler in der Welt-
# Erstellung vergeben); current_save_slot = daraus abgeleiteter, eindeutiger
# Dateiname im Speicherordner. Wird von SaveSystem.load_game() beim Laden
# überschrieben, damit "Speichern" im Pause-Menü immer in denselben Slot
# zurückschreibt.
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
var _explore_timer: float = 0.0       # v16.6: Drossel für das Übertragen der Aufdeck-Maske an Shader/Renderer
var _anim_speed_seen: float = 1.0   # v16.3-Fix: zuletzt an die Gebäude-Animationen gemeldetes Spieltempo
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
# _toggle_fp_mode() teleportiert beim nächsten Betreten NICHT mehr auf die
# Iso-Kamera-Zielposition, sondern lässt den Spieler exakt dort, wo er beim
# letzten Verlassen stand (Nutzeranfrage: "am selben Ort wie beim
# Verlassen"). Nur beim allerersten Mal (frisch generierte Welt, noch kein
# einziger Frettchenmodus-Aufenthalt) gibt es überhaupt eine Position, die
# gesetzt werden muss - daher der Fallback auf _cam_target NUR wenn diese
# Flag noch false ist.
var _player_pos_valid: bool = false
const INTERACT_RANGE: float = 2.6   # Welteinheiten (~1.3 Tiles)
# Ressourcentyp -> max. Belohnung pro Minispiel-Durchlauf
# Feature (v13.6, Bauen als Minispiel): "BUILD" ist kein Rohstoff, sondern
# der max. Baufortschritt (in denselben Einheiten wie
# BuildingEntity.construction_work_needed), den ein Durchlauf "Mitbauen"
# geben kann.
const MINIGAME_MAX_REWARD: Dictionary = {
	"WOOD": 18.0, "STONE": 14.0, "BERRIES": 16.0, "IRON": 12.0, "WATER": 20.0,
	"BUILD": 24.0,
}
# aktuell anvisiertes Ziel während des First-Person-Umherlaufens, siehe
# _update_fp_interaction(). "" type = kein Ziel in Reichweite.
var _fp_target_kind: String = ""   # "NODE" | "WATER" | "BUILD"
var _fp_target_res:  String = ""
var _fp_target_tile: Vector2i = Vector2i(-1, -1)
var _fp_target_site: BuildingEntity = null  # Feature (v13.6): nur bei kind == "BUILD" gesetzt
var _fp_target_train: TrainEntity = null     # Feature (v16.4): nur bei kind == "TRAIN" gesetzt

# Feature (v13.4, Performance): Wasser-Update nur alle 100ms
var _water_update_timer: float = 0.0
## Feature (v14.5, Timberborn-Feld-System): siehe _process() weiter unten.
var _field_visual_timer: float = 0.0
const WATER_UPDATE_INTERVAL: float = 0.1
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
	# v15.4: Jahreszeiten-Optik (Schnee, Laub, Partikel, Eis) + Realismus-Modus
	_season_vis = SeasonVisuals.new(); _season_vis.name = "SeasonVisuals"
	add_child(_season_vis); _season_vis.setup(renderer)
	_realism = RealismFX.new(); _realism.name = "RealismFX"
	add_child(_realism); _realism.setup(_world_env, _sun_light, _fill_light, get_viewport(), _season_vis)
	_fp_hud = get_node_or_null("GameUI/UIRoot/FPHud") as Control
	_minigame = get_node_or_null("GameUI/UIRoot/MinigameOverlay") as Control
	_hud_node = get_node_or_null("GameUI/UIRoot/HUD") as Control
	_build_menu_node = get_node_or_null("GameUI/UIRoot/BuildMenu") as Control
	if _minigame and not _minigame.minigame_finished.is_connected(_on_minigame_finished):
		_minigame.minigame_finished.connect(_on_minigame_finished)
	_connect_signals()

func _connect_signals() -> void:
	# Bug7-Fix: Guard gegen doppelte Verbindungen beim Neu-Starten.
	# Bug-Fix (v14.1, gemeldet: "Nachrichten werden immer zweimal angezeigt"):
	# der Guard hing bisher an notification_requested/_on_notification() -
	# dieser Signal-Pfad wurde entfernt (siehe unten), der Guard läuft daher
	# jetzt stattdessen über hud_update_requested, damit er weiterhin
	# zuverlässig verhindert, dass bei einem Neustart ALLE Verbindungen
	# hier unten doppelt gesetzt werden.
	if GameState.hud_update_requested.is_connected(_on_hud_update): return
	# NotificationLayer.gd verbindet GameState.notification_requested bereits
	# selbst direkt mit seiner eigenen show_notification()-Methode (siehe
	# dort, _ready()). Hier war dasselbe Signal ZUSÄTZLICH an eine eigene
	# _on_notification() gehängt, die den "Notifications"-Node im Baum
	# gesucht und darauf NOCHMAL show_notification() aufgerufen hat - jede
	# Meldung erschien dadurch doppelt. Diese redundante zweite Verbindung
	# (und die jetzt nutzlose _on_notification()-Funktion) wurden entfernt.
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

## Feature (v11.2, First-Person-Modus): während des First-Person-Umsehens
## ist die Maus gefangen (MOUSE_MODE_CAPTURED) - das Pause-Menü braucht aber
## einen normalen, sichtbaren Mauszeiger zum Klicken. Ohne diesen Handler
## wäre das Pause-Menü während des FP-Modus unbedienbar.
func _on_state_changed_fp(new_state: GameState.State) -> void:
	if not _fp_mode: return
	if new_state == GameState.State.PAUSED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif new_state == GameState.State.PLAYING and not _is_minigame_active():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func start_new_game(world_size: String, seed_str: String, world_name: String) -> void:
	for st in new_game_steps(world_size, seed_str, world_name): (st["fn"] as Callable).call()

## v15.8: Spielstart in Schritten (für den Ladebildschirm). start_new_game() führt sie nacheinander aus.
func new_game_steps(world_size: String, seed_str: String, world_name: String) -> Array:
	var steps: Array = []
	steps.append({"label": "Welt wird erzeugt …", "weight": 22.0, "fn": func(): _ng_generate(world_size, seed_str, world_name)})
	steps.append({"label": "Kolonie wird gegründet …", "weight": 4.0, "fn": _ng_found_colony})
	steps.append_array(_setup_renderer_steps())
	steps.append({"label": "Letzte Handgriffe …", "weight": 2.0, "fn": _ng_finish})
	return steps

## Heimat-Bereich einer Entdeckerkarte (Radius in Kacheln um die Kartenmitte), alles dahinter ist Nebel.
const START_REVEAL_RADIUS: float = 26.0

func _ng_generate(world_size: String, seed_str: String, world_name: String) -> void:
	world_gen = WorldGenerator.new()
	world     = world_gen.generate(world_size, seed_str)
	# Feature (v16.6, Erkundung): nur "HUGE" hat Nebel; klassische Welten sind komplett bekannt.
	var fog: bool = world_size == "HUGE"
	var mid := Vector2i(world_gen.w / 2, world_gen.h / 2)
	if fog: world_gen.push_iron_outside(world, mid.x, mid.y, START_REVEAL_RADIUS + 2.0)
	ExploreSys.init_world(world_gen.w, world_gen.h, fog, mid, START_REVEAL_RADIUS)
	# Feature (v11.4, Speicherslot-System): Kolonie-Name des Spielers wird jetzt
	# tatsächlich verwendet (vorher wurde der Parameter verworfen) - daraus
	# wird der eindeutige Speicherslot für diese Welt abgeleitet.
	current_world_name = world_name.strip_edges() if world_name.strip_edges() != "" else "Meine Kolonie"
	current_save_slot  = _make_unique_save_slot(current_world_name)

func _ng_found_colony() -> void:
	ResourceSys.init(); BuildingSys.init(); PopMgr.init(5)
	DayNight.init(); TechTreeSys.init(); DroughtSys.init()
	SeasonSys.init(); ExpeditionSys.init()
	AchievementSys.init()  # Feature (v11.8, Achievement-System)
	PlayerAccessories.init()  # Feature (v12.2, Phase 4)
	DistrictSys.init()     # Feature (v11.11, Distrikt-System)
	ColonySys.init()       # Feature (v16.0, Kolonie-Fundament)
	RailSys.init()         # Feature (v16.2, Schiene)
	ColonySys.rename(0, current_world_name)
	FarmSys.init()         # Feature (v14.5, Timberborn-Feld-System)
	WaterSys.init(world, world_gen.w, world_gen.h)
	explosions = []; _day_prev = -1
	@warning_ignore("integer_division")
	var cx: int = world_gen.w / 2; var cy: int = world_gen.h / 2
	BuildingSys.build_free("CONSTRUCTION_YARD_1", cx, cy, world)
	# Feature (v11.0, Lagersystem): die Kolonie startet jetzt direkt mit einem
	# physisch vorhandenen Lagergebäude (statt die Startressourcen nur
	# abstrakt im globalen Pool zu haben) - sonst könnte die Kolonie
	# softlocken, sobald Produktionsgebäude ihr eigenes lokales Lager voll
	# haben und niemand zum Abtransportieren da ist. Sucht eine freie,
	# bebaubare Nachbarkachel des Bauhofs.
	var start_storage_pos: Vector2i = _find_free_tile_near(cx, cy, world)
	if start_storage_pos.x >= 0:
		BuildingSys.build_free("STORAGE", start_storage_pos.x, start_storage_pos.y, world)
	# Feature (v16.0, Kolonie-Fundament): die Startkolonie bekommt ihr Rathaus gratis -
	# es legt das Kolonie-Gebiet fest (siehe ColonySystem.gd).
	var hall_pos: Vector2i = _find_free_tile_ring(cx, cy, world, 2, 6)
	if hall_pos.x >= 0:
		BuildingSys.build_free("TOWN_HALL", hall_pos.x, hall_pos.y, world, 0)
		ColonySys.set_hall(0, hall_pos.x, hall_pos.y)
	else:
		ColonySys.set_hall(0, cx, cy)
	# Feature (v16.7, Nachbarn): auf Entdeckerkarten liegen im Nebel fremde Kolonien (siehe NeighborSystem.gd)
	NeighborSys.reset()
	if ExploreSys.enabled: NeighborSys.spawn(self)

func _ng_finish() -> void:
	@warning_ignore("integer_division")
	var cx: int = world_gen.w / 2; var cy: int = world_gen.h / 2
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
## für eine "Testwelt", die alle Systeme (Distrikte, Tech Tree, Legendäre
## Frettchen, Achievements, ...) sofort zum Ausprobieren bereitstellt, ohne
## dass der Nutzer erst manuell stundenlang aufbauen muss.
##
## WICHTIG: nutzt ausschliesslich echte Spiel-APIs (BuildingSys.build_free(),
## TechTreeSys, PopMgr, ResourceSys.force_add()) statt eine Save-Datei per
## Hand zusammenzubasteln - das garantiert einen konsistenten, ladbaren
## Zustand (exakt dieselben Codepfade wie normales Spielen), ohne dass ich
## das Ergebnis in einer echten Godot-Instanz gegenprüfen könnte.
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
	# übrig bleibt.
	TechTreeSys.unlocked_epochs = ["EPOCH_1", "EPOCH_2", "EPOCH_3"]
	TechTreeSys.unlocked = []
	for sid in TechTreeSys.SECTION_ORDER:
		for tier in range(1, 8):
			var tid: String = "%s_%d" % [sid, tier]
			if TechTreeSys.NODES.has(tid):
				TechTreeSys.unlocked.append(tid)

	# ── Ressourcen grosszügig auffüllen (force_add ignoriert Lagerkapazität -
	# bewusst, damit die Testwelt nicht schon beim Start durch volle Lager
	# blockiert).
	for pair in [["WOOD",400.0],["STONE",300.0],["BERRIES",150.0],["PLANKS",120.0],
			["TOOLS",80.0],["FOOD",150.0],["IRON",60.0],["IRON_BARS",40.0],
			["MACHINES",20.0],["COAL",60.0],["STEEL",30.0],["MEAT",60.0],
			["WHEAT",60.0],["COOKED_MEAT",30.0],["BREAD",30.0]]:
		ResourceSys.force_add(str(pair[0]), float(pair[1]))
	ResourceSys.water = 40.0
	ResourceSys.science = 120.0

	# ── Gebäude: eine repräsentative Auswahl über alle 4 Epochen verteilt.
	# build_free() prüft weder Ressourcenkosten noch Tech-Freischaltung
	# (das ist reine Build-Menu-UI-Logik) - lediglich die Tile-Vorbedingungen
	# (nicht besetzt, kein Wasser) werden hier selbst geprüft, siehe
	# _bootstrap_find_free_tiles().
	var epoch1: Array = ["LUMBERJACK","LUMBERJACK","QUARRY","BERRY_GATHERER",
		"HOUSE","HOUSE","HOUSE","GATHERING_PLACE","FORESTER","RESEARCH_HUT"]
	var epoch2: Array = ["SAWMILL","WORKSHOP","WATER_TOWER","TAVERN","LARGE_STORAGE",
		"DISTRICT_GATE","FARMHOUSE","COOKHOUSE","HUNTER_HUT"]
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

	# WELL separat mit Wassernähe suchen (siehe near_water=true) - eigener
	# Aufruf, damit es nicht zufällig eine der obigen Tiles "verbraucht".
	var well_tiles: Array = _bootstrap_find_free_tiles(cx, cy, world, 1, true)
	if not well_tiles.is_empty():
		var wb: BuildingEntity = BuildingSys.build_free("WELL", well_tiles[0].x, well_tiles[0].y, world)
		if wb != null: placed.append(wb)

	# ── Bevölkerung: zusätzlich zu den 5 Start-Frettchen (aus start_new_game())
	# 10 weitere, einige davon echten Gebäuden zugewiesen, eines als
	# legendär markiert (für Accessoires/Holy-Glow-Testing).
	for _i in 10:
		var f: FerretEntity = FerretEntity.create_random()
		f.pos = Vector2(float(cx) + randf_range(-5.0, 5.0), float(cy) + randf_range(-5.0, 5.0))
		f.target_pos = f.pos
		PopMgr.ferrets.append(f)
	# Bug-Fix (v14.6): die Frettchen wurden der Reihe nach verteilt - der
	# Brunnen wurde als LETZTES Gebäude erzeugt, wenn keine freien Frettchen
	# mehr übrig waren. Ergebnis: 0 Arbeiter an Brunnen/Wasserturm, Wasser
	# dauerhaft 0, die komplette Testkolonie verdurstete innerhalb von ~3
	# Spieltagen. Lebensnotwendige Versorger (Wasser, Beeren) kommen jetzt zuerst.
	var _vital: Array = []
	var _rest: Array = []
	for pb in placed:
		var pbe: BuildingEntity = pb
		if pbe.collects_resource == "WATER" or pbe.collects_resource == "BERRIES": _vital.append(pbe)
		else: _rest.append(pbe)
	placed = _vital + _rest
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
	# artige Achievements/Legendär-Fortschritt plausibel wirken.
	DayNight.day_count = 65

	_setup_renderer()
	GameState.notify("🛠️ Testwelt aufgebaut: %d Gebäude, %d Frettchen." % [placed.size() + 2, PopMgr.ferrets.size()])
	_on_hud_update(); _on_build_menu_update()

## Sucht bis zu "count" freie, unbebaute, nicht-Wasser-Tiles rund um (cx,cy) -
## spiralförmig nach aussen wachsend, damit auch bei vielen angeforderten
## Tiles genug Platz gefunden wird. "near_water" filtert zusätzlich auf
## Tiles mit einem Wasser-Tile in max. 4 Kacheln Entfernung (für WELL etc.).
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
## speichert unter dem regulären Speicherslot dieser Session (siehe
## start_new_game() - current_save_slot wurde dort bereits gesetzt).
func save_now() -> void:
	SaveSys.save(current_save_slot, self)

func _setup_renderer() -> void:
	for st in _setup_renderer_steps(): (st["fn"] as Callable).call()

## v15.8: Renderer-Aufbau als Schritte (Gelände, Wasser, Bäume ... siehe WorldRenderer3D.build_world_steps()).
func _setup_renderer_steps() -> Array:
	if renderer == null: renderer = get_node_or_null("WorldRenderer3D") as WorldRenderer3D
	# Feature (v16.2, Schiene): Gleisnetz kennt die Welt; Darstellung hängt direkt unter dem
	# GameController (NICHT unter dem Renderer: build_world() räumt dessen Kinder ab).
	# ACHTUNG: diese Funktion läuft beim AUFBAU der Schrittliste - also bevor die Welt erzeugt/geladen
	# ist. Die Welt-Referenz für RailSys wird deshalb erst im ersten Schritt unten gesetzt.
	if get_node_or_null("RailRenderer") == null:
		var rr := RailRenderer.new(); rr.name = "RailRenderer"; add_child(rr)
	var steps: Array = [{"label": "Landschaft wird vorbereitet …", "weight": 1.0, "fn": func():
		renderer.world = world; renderer.world_w = world_gen.w; renderer.world_h = world_gen.h
		RailSys.world = world}]
	steps.append_array(renderer.build_world_steps())
	# Feature (v12.1): PlayerController braucht eine Referenz auf den
	# Renderer, um beim Mittelklick-Laufbefehl die Tile-Höhe direkt
	# abzufragen (siehe PlayerController._process_external_walk()).
	steps.append({"label": "", "weight": 0.3, "fn": func():
		if player != null: player.renderer = renderer})
	return steps

## Sucht eine freie, bebaubare Kachel in der Nähe von (cx, cy) - genutzt, um
## beim Koloniestart ein erstes Lagergebäude neben dem Bauhof zu platzieren,
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

## Feature (v16.0, Kolonie-Fundament): nächste freie, bebaubare Kachel in
## wachsenden Ringen (Abstand min_r..max_r, Chebyshev) um (cx, cy).
## Frei = kein Gebäude, kein Wasser, kein Feld.
func _find_free_tile_ring(cx: int, cy: int, w: Array, min_r: int, max_r: int) -> Vector2i:
	for r in range(min_r, max_r + 1):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r: continue
				var tx: int = cx + dx; var ty: int = cy + dy
				if tx < 0 or ty < 0 or tx >= w.size(): continue
				var col: Array = w[tx]
				if ty >= col.size(): continue
				var tile: Dictionary = col[ty]
				if tile.get("building") != null: continue
				if str(tile.get("biome", "")) == "WATER": continue
				if FarmSys.has_field(tx, ty): continue
				if RailSys.has_rail(tx, ty): continue
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
	# Während eines aktiven Minispiels steht der Spieler zusätzlich still.
	if not _fp_mode:
		_handle_camera_keys(delta)
	elif not _is_minigame_active():
		_update_fp_interaction()
	DayNight.update(dt)
	DroughtSys.update(dt)
	# Feature (v14.5, Timberborn-Feld-System): Wachstum läuft unabhängig von
	# Tag/Nacht und Bauernhof-Arbeitern zentral hier (siehe FarmFieldSystem.gd).
	FarmSys.update(dt)
	_update_day_night_visuals()
	
	# Feature (v13.4, Performance): Wasser-Simulation nur alle 100ms updaten
	_water_update_timer += dt
	# v16.6: auf großen Karten (Fläche > 80x80) seltener simulieren/neu zeichnen - die Kosten wachsen mit der Fläche
	var area_factor: float = 1.0 if world_gen == null else maxf(1.0, float(world_gen.w * world_gen.h) / 6400.0)
	if _water_update_timer >= WATER_UPDATE_INTERVAL * area_factor:
		WaterSys.update(_water_update_timer, world)
		_water_update_timer = 0.0
	if _day_prev != DayNight.day_count:
		_day_prev = DayNight.day_count
		SeasonSys.update(DayNight.day_count)
		renderer.refresh_buildings()
	if DroughtSys.is_drought:
		# v16.0: Dürre-Verbrauch je Kolonie aus deren eigenem Wassertank.
		for cid_v in ColonySys.ids():
			var cid: int = int(cid_v)
			ResourceSys.use_colony(cid)
			var extra: float = float(PopMgr.get_count(cid)) * 0.03 * dt
			ResourceSys.remove_water(extra)
			if ResourceSys.water < 1.0:
				for f in PopMgr.ferrets_of(cid):
					var fe: FerretEntity = f as FerretEntity
					fe.needs["water"] = maxf(0.0, float(fe.needs["water"]) - 2.0 * dt)
		ResourceSys.use_colony(ColonySys.active_id)
	BuildingSys.update(dt, DayNight.is_day, world)
	PopMgr.update(dt, DayNight.is_day, world); ExpeditionSys.update(dt)
	RailSys.update(dt)      # v16.2: Züge fahren, laden und entladen
	# Bug-Fix (Gebäude werden nicht gebaut/kein Baufortschritt): vorher lief
	# dieser Aufruf NUR beim Tageswechsel (alle 180 Sekunden!) und addierte
	# einen einmaligen Sprung - der Fortschrittsbalken stand fast immer
	# still. Jetzt läuft die Konstruktion JEDEN Frame kontinuierlich weiter.
	_process_construction(dt)
	renderer.apply_drought(DroughtSys.is_drought)
	renderer.update_ferrets(PopMgr.ferrets)
	# Wasserphysik: Oberflächen-Mesh nur gedrosselt neu bauen (kein voller
	# Terrain-Rebuild, aber trotzdem zu teuer für jeden einzelnen Frame) -
	# ca. 3x/Sekunde reicht aus, um Fluss/Verdunstung sichtbar zu machen.
	if Engine.get_process_frames() % maxi(20, int(20.0 * area_factor)) == 0: renderer.refresh_water(world)
	if Engine.get_process_frames() % 30 == 0:
		renderer.refresh_vegetation()
		renderer.refresh_storage_labels(BuildingSys.buildings)
		renderer.refresh_building_anims(BuildingSys.buildings)
		renderer.refresh_haul_lines(PopMgr.ferrets)
	NeighborSys.check_discovery(get_process_delta_time())   # v16.7: Nachbar entdeckt, sobald sein Dorf aufgedeckt ist
	# Feature (v16.6, Erkundung): Aufdeck-Maske gedrosselt an Shader/Vegetation/Wasser übertragen
	if ExploreSys.dirty:
		_explore_timer += dt_real_for_explore()
		if _explore_timer >= 0.5:
			_explore_timer = 0.0
			if ExploreSys.flush():
				renderer.apply_fog()   # Wasser im neuen Gebiet zeichnet der normale Wasser-Rhythmus nach
	# Tempowechsel/Pause sofort an die Arbeits-Animationen weitergeben (nicht erst nach <=30 Frames).
	if not is_equal_approx(GameState.game_speed, _anim_speed_seen):
		_anim_speed_seen = GameState.game_speed
		renderer.refresh_building_anims(BuildingSys.buildings)
	# Feature (v14.5, Timberborn-Feld-System): Feld-Einfärbung (Wachstums-
	# Fortschritt) nur gelegentlich neu aufbauen, nicht jeden Frame - ein
	# refresh_terrain() baut das GESAMTE Terrain-Mesh neu (siehe
	# WorldRenderer3D._build_terrain_mesh()), das ist bei 200s Wachstumszeit
	# völlig ausreichend granular. Übersprungen, wenn gerade gar nichts
	# wächst (spart die Kosten komplett, solange niemand Landwirtschaft
	# betreibt).
	_field_visual_timer += dt
	if _field_visual_timer >= 4.0:
		_field_visual_timer = 0.0
		if FarmSys.has_growing_fields(): renderer.refresh_terrain()
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
## steuert seit Projektbeginn z.B. ob Sammler/Werkstätten arbeiten), aber
## KEINE sichtbare Auswirkung - Sonne, Umgebungslicht und Himmelfarbe blieben
## immer gleich. Dadurch wirkte es, als gäbe es gar keinen Tag/Nacht-Wechsel.
## Diese Funktion blendet Sonnenlicht/Fülllicht/Himmel weich zwischen
## Tag- und Nachtwerten, mit kurzen Übergangsphasen um Sonnenuntergang/
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

	# v15.4: Saison-Töne überlagern, Partikel dem Fokus folgen lassen, Realismus-Modus aktualisieren
	var dt_frame: float = get_process_delta_time()
	if _season_vis != null:
		_season_vis.apply_lighting(_sun_light, _fill_light, _world_env, night_t)
		var focus: Vector3 = _cam_target
		if _fp_mode and player != null: focus = player.global_position
		_season_vis.process_visuals(dt_frame, focus)
	if _realism != null:
		_realism.update_frame(dt_frame, pct, night_t)

## Bug-Fix (Gebäude werden nicht gebaut/kein Baufortschritt): Bisher hing
## JEDER Baufortschritt komplett davon ab, dass mindestens ein Frettchen
## explizit im Bauhof (Typ "BUILDER") arbeitete - ohne das blieb
## construction_progress für immer bei 0, ohne jede Rückmeldung an den
## Spieler. Jetzt gibt es einen garantierten Grundfortschritt (die
## Kolonie baut auch ohne zugewiesene Bauhof-Arbeiter irgendwann fertig),
## plus einen Bonus pro Bauhof-Arbeiter für schnelleren Bau.
##
## Feature (v10.13): der Bonus war bisher ein einzelner GLOBALER Wert (Summe
## ALLER Bauhof-Arbeiter über ALLE Bauhöfe), der gleichermassen auf JEDE
## Baustelle angewendet wurde - eine Baustelle baute also genauso schnell,
## egal ob 0 oder 5 Frettchen dort tatsächlich standen. Jetzt laufen
## Bau-Frettchen physisch zu ihrer Baustelle (siehe FerretEntity.
## _update_builder_work()) und nur die Anzahl der Frettchen, die GERADE AN
## DIESER Baustelle stehen (work_state == "BUILDING"), zählt für deren
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
		# benötigte Baumaterial nicht vollständig an der Baustelle angeliefert
		# wurde - vorher gab es BASE_RATE-Fortschritt völlig unabhängig
		# davon, ob überhaupt Ressourcen vorhanden waren. Siehe
		# FerretEntity._update_builder_work() für die Anlieferungslogik.
		if not s.is_fully_supplied(): continue
		var here: int = int(presence.get(s.get_instance_id(), 0))
		var rate: float = (BASE_RATE + float(here) * WORKER_RATE) * speed_mult
		s.construction_progress = minf(s.construction_work_needed, s.construction_progress + rate * dt)
		if s.construction_progress >= s.construction_work_needed:
			# Feature (Tech Tree): eine Baustelle, die eigentlich ein Umbau
			# ist (siehe BuildingEntity.start_rebuild()), verwandelt sich
			# jetzt in ihr Zielgebäude, statt einfach nur "fertig" zu sein.
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
## PopMgr.update() etc. in _process()) läuft in BEIDEN Modi unverändert
## weiter (siehe Nutzeranfrage: "realistischer, soll normal weiterlaufen") -
## es ändert sich nur, welche Kamera aktiv ist und wie Eingaben interpretiert
## werden.
func _toggle_fp_mode() -> void:
	# Feature (v13.4, Bugfix): FP-Mode sollte immer erreichbar sein,
	# solange die Basis-Nodes initialisiert sind
	if player == null or camera == null or renderer == null:
		GameState.notify("Fehler: Spieler-Komponenten nicht geladen", Color(0.8, 0.2, 0.1))
		return
	# Nur wenn Minigame läuft oder in Platzierungs-Modus: blockieren
	if _is_minigame_active() or not GameState.placement_mode.is_empty():
		GameState.notify("Kann nicht während Minigame/Platzierung", Color(0.8, 0.6, 0.2))
		return
	_fp_mode = not _fp_mode
	if _fp_mode:
		# Feature (v11.25): NUR beim allerersten Frettchenmodus-Aufenthalt
		# überhaupt (frisch generierte/geladene Welt ohne gültige
		# Spielerposition) wird auf die aktuelle Iso-Kamera-Zielposition
		# teleportiert, damit der allererste Übergang sich nicht wie ein
		# Sprung ins Leere anfühlt. Bei jedem weiteren Betreten bleibt der
		# Spieler exakt dort, wo er beim letzten Verlassen des Modus stand
		# (bzw. wo ihn ein Laufbefehl in der Iso-Ansicht zuletzt hingeführt
		# hat) - kein erneutes Teleportieren nötig, da player.global_position
		# bereits korrekt ist.
		if not _player_pos_valid:
			var spawn_tile: Vector2i = renderer.world3d_to_tile(_cam_target)
			var spawn_pos: Vector3 = renderer.tile_to_world3d(spawn_tile.x, spawn_tile.y)
			player.teleport_to(spawn_pos)
			_player_pos_valid = true
		# Feature (v11.26): ein evtl. noch laufender Mittelklick-Laufbefehl
		# darf im First-Person-Modus nicht die WASD-Steuerung übersteuern.
		player.cancel_walk()
		player.movement_enabled = true
		player.ferret_visual.visible = false
		player.camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if _hud_node: _hud_node.visible = false
		if _build_menu_node: _build_menu_node.visible = false
		if _fp_hud: _fp_hud.show()
		_fp_target_kind = ""; _fp_target_res = ""; _fp_target_site = null; _fp_target_ferret = null
		if _fp_hud: _fp_hud.set_prompt("")
	else:
		if RailSys.riding != null: _exit_train(true)   # v16.4: Fahrt beenden, bevor die Iso-Ansicht übernimmt
		player.movement_enabled = false
		player.ferret_visual.visible = true
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if _hud_node: _hud_node.visible = true
		if _build_menu_node: _build_menu_node.visible = true
		if _fp_hud: _fp_hud.hide()
	# Feature (v12.3, Tutorial-Überarbeitung):
	GameState.fp_mode_changed.emit(_fp_mode)
	# Feature (v14.4, Nutzerwunsch "Fretchenmodus mehr zu einem Cosy-Game
	# machen"): entspanntere, gedrosselte Musik während des Frettchenmodus.
	SoundSys.set_fp_mode(_fp_mode)

## Feature (v12.3, Tutorial-Überarbeitung): sucht ausgehend von (around_tx,
## around_ty) spiralförmig die nächste tatsächlich bebaubare Tile (kein
## Gebäude drauf, kein Wasser-Biom - dieselbe Regel wie in _place_building()
## oben) - fürs interaktive "baue hier"-Tutorial, damit der markierte Punkt
## garantiert gültig ist, unabhängig vom zufällig generierten Terrain rund
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

## Feature (v14.4, Nutzerwunsch "Cosy-Interaktionen mit anderen Frettchen"):
## kleine, kostenlose Streichel-Interaktion mit einem nahen Kolonie-Frettchen
## im Frettchenmodus - kein Minispiel, kein Ressourcenertrag, rein zur
## Atmosphäre. Kleiner Glücks-Bonus fürs bepetzte Frettchen, mit Cooldown
## pro Frettchen (verhindert Dauer-Spam-Klicken auf dasselbe Tier).
const PET_RANGE: float = 2.2
const PET_COOLDOWN: float = 20.0
var _fp_target_ferret: FerretEntity = null
var _last_pet_time: Dictionary = {}   # Frettchen-Instanz-ID -> Zeitpunkt (Unix-Zeit)
const PET_FLAVOR_TEXTS: Array = [
	"schnuppert neugierig an dir und lässt sich streicheln 🥰",
	"kuschelt sich kurz an dich 💕",
	"macht ein kleines Freudenhüpfchen 🐾",
	"schaut dich verträumt an, während du es streichelst ✨",
	"rollt sich zufrieden auf den Rücken 😊",
]

func _pet_ferret() -> void:
	if _fp_target_ferret == null or not is_instance_valid(_fp_target_ferret): return
	var fid: int = _fp_target_ferret.get_instance_id()
	var now: float = Time.get_ticks_msec() / 1000.0
	var last: float = float(_last_pet_time.get(fid, -1000.0))
	if now - last < PET_COOLDOWN:
		if _fp_hud: _fp_hud.set_prompt("💤 %s braucht noch eine Pause..." % _fp_target_ferret.ferret_name)
		return
	_last_pet_time[fid] = now
	var needs: Dictionary = _fp_target_ferret.needs
	needs["happiness"] = minf(100.0, float(needs.get("happiness", 50.0)) + 8.0)
	# v15.6: das Frettchen reagiert sichtbar (Streichel-Pose oder Freudensprung)
	var joy: bool = randf() < 0.4
	_fp_target_ferret.react_clip = "Jump_Joy" if joy else "Pet"
	_fp_target_ferret.react_until = now + (1.0 if joy else 1.5)
	var flavor: String = str(PET_FLAVOR_TEXTS[randi() % PET_FLAVOR_TEXTS.size()])
	GameState.notify("🐹 %s %s" % [_fp_target_ferret.ferret_name, flavor], Color(0.75, 0.4, 0.65))
	SoundSys.play_notify()

## Sucht in INTERACT_RANGE um den Spieler die nächstgelegene erntbare
## Ressourcenülle (resource_node WOOD/STONE/BERRIES/IRON) ODER ein
## WATER-Tile, und aktualisiert den FPHud-Prompt entsprechend. Wasser hat
## keinen "resource_node"-Eintrag (das Wasserschöpfen ist hier rein
## kosmetisch/Minispiel-bezogen, unabhängig vom dynamischen WaterSystem.gd),
## daher zwei getrennte Suchstrategien.
func _update_fp_interaction() -> void:
	# Feature (v16.4, Mitfahren): während der Fahrt gibt es nur den Fahrt-/Aussteigen-Hinweis.
	if RailSys.riding != null:
		_update_ride_prompt(); return
	var ptile: Vector2i = renderer.world3d_to_tile(player.global_position)
	var best_d: float = INF
	var best_kind: String = ""; var best_res: String = ""; var best_tile: Vector2i = Vector2i(-1,-1)
	var best_site: BuildingEntity = null
	# Feature (v12.2, Phase 4): radius_tiles auf 3 angehoben (vorher 2) - bei
	# maximal möglichem Interaktionsreichweiten-Boost (Krone*Monokel =
	# 1.35*1.20 = 1.62x, siehe PlayerAccessories.BOOSTS) würde ein Tile-Suchradius
	# von nur 2 manche Ziele in Boost-Reichweite gar nicht erst finden.
	var radius_tiles: int = 3
	# Feature (v12.2, Phase 4): Krone- und Monokel-Boost verlängern die
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
	# Feature (v13.6, Bauen als Minispiel): zusätzlich zu Ressourcen-Knoten
	# und Wasser auch offene, voll belieferte Baustellen in Reichweite
	# suchen. Nutzt dieselbe interact_range wie oben, aber eine eigene
	# Distanzmessung zur Baustellen-Weltposition statt zu einem Tile-Zentrum,
	# da Gebäude auch mehrere Tiles gross sein können.
	for site_any in BuildingSys.get_construction_sites():
		var site: BuildingEntity = site_any as BuildingEntity
		if site == null or not site.is_under_construction or site.is_rebuild: continue
		if not site.is_fully_supplied(): continue
		var site_pos: Vector3 = renderer.tile_to_world3d(site.tile_x, site.tile_y)
		var d: float = player.global_position.distance_to(site_pos)
		if d > interact_range: continue
		if d < best_d:
			best_d = d; best_kind = "BUILD"; best_res = "BUILD"
			best_tile = Vector2i(site.tile_x, site.tile_y); best_site = site
	# Feature (v14.4, Cosy-Interaktion): ein nahes Kolonie-Frettchen darf
	# gestreichelt werden - kurze, persönliche Reichweite (PET_RANGE), bekommt
	# aber Vorrang vor einem weiter entfernten Sammel-/Bau-Ziel, da es sich
	# unnatürlich anfühlen würde, direkt neben einem Frettchen zu stehen und
	# stattdessen einen Ressourcen-Prompt angezeigt zu bekommen.
	_fp_target_ferret = renderer.find_nearest_ferret_3d(player.global_position, PopMgr.ferrets, PET_RANGE)
	if _fp_target_ferret != null:
		best_kind = "FERRET"
	# Feature (v16.4): ein am Bahnsteig haltender Zug in Reichweite zum Einsteigen
	# (schlägt Ressourcen, Baustellen UND das Streicheln: Bahnhöfe liegen oft mitten in der Kolonie,
	# ein Frettchen in der Nähe soll das Einsteigen nicht blockieren - der Zug hält ja nur kurz).
	_fp_target_train = _find_boardable_train()
	if _fp_target_train != null: best_kind = "TRAIN"
	_fp_target_kind = best_kind; _fp_target_res = best_res; _fp_target_tile = best_tile
	_fp_target_site = best_site
	if _fp_hud == null: return
	if best_kind == "":
		_fp_hud.set_prompt("")
	elif best_kind == "TRAIN":
		_fp_hud.set_prompt("[E] 🚂 Einsteigen · %s" % str((RailSys.lines.get(_fp_target_train.line_id, {}) as Dictionary).get("name", "Zug")))
	elif best_kind == "FERRET":
		_fp_hud.set_prompt("[E] 🐾 %s streicheln" % _fp_target_ferret.ferret_name)
	elif best_kind == "BUILD":
		_fp_hud.set_prompt("[E] 🔨 Mitbauen")
	else:
		var icon: String = str(BuildingData.RESOURCE_ICONS.get(best_res, "?"))
		var verb: String = {"WOOD":"Holz fällen","STONE":"Stein brechen","BERRIES":"Beeren pflücken",
			"IRON":"Erz abbauen","WATER":"Wasser schöpfen"}.get(best_res, "Sammeln")
		_fp_hud.set_prompt("[E] %s %s" % [icon, verb])

func dt_real_for_explore() -> float:
	return get_process_delta_time()

## Feature (v16.6): Nebel-Regel. true = auf dieser Kachel darf nichts gebaut/gelegt werden (unerforscht).
func _fog_blocks(tx: int, ty: int, silent: bool = false) -> bool:
	if ExploreSys.is_revealed(tx, ty): return false
	if not silent:
		GameState.notify("Dieses Gebiet ist noch unerforscht - eine Erkundungsstation (Epoche 5) deckt die Karte auf.", Color(0.85, 0.55, 0.15))
	return true

## Feature (v16.4, Logistik-Update Phase 3): Mitfahren im Zug (Ich-Perspektive).
## Man steigt ein, solange ein Zug am Bahnhof HÄLT (Zustand DWELL), sitzt dann auf dem
## Führerhaus der Lok (Kamera über dem Dach, freier Umblick) und steigt an einem
## beliebigen Halt wieder aus - die Fahrt dazwischen ist reines Mitfahren.
const RIDE_BOARD_RANGE: float = 3.2             # Welteinheiten, gemessen zu Lok UND Waggons
const RIDE_SEAT: Vector3 = Vector3(-0.40, 0.42, 0.0)   # Körper-Ursprung relativ zur Lok; v16.9: GLB-Lok mit Führerhäuschen (Kabine roh x -0.63..-0.17, Fensterband roh y 0.85-1.05, Dach 1.14) → Sitz in Kabinnenmitte, Kamera (= +0.55) auf Fensterhöhe im Führerstand; Frettchen-Optik ist im Fahrtmodus unsichtbar

func _rail_renderer() -> RailRenderer:
	return get_node_or_null("RailRenderer") as RailRenderer

func _find_boardable_train() -> TrainEntity:
	var rr: RailRenderer = _rail_renderer()
	if rr == null: return null
	var best: TrainEntity = null; var best_d: float = RIDE_BOARD_RANGE
	var pp: Vector3 = player.global_position
	for tv in RailSys.trains:
		var t: TrainEntity = tv
		if t.state != "DWELL" or t.line_id < 0: continue
		for part in rr.train_part_positions(t):
			var p: Vector3 = part
			if absf(p.y - pp.y) > 2.5: continue
			var d: float = Vector2(p.x, p.z).distance_to(Vector2(pp.x, pp.z))
			if d < best_d: best_d = d; best = t
	return best

func _board_train(t: TrainEntity) -> void:
	if t == null or not RailSys.trains.has(t) or t.state != "DWELL": return
	var rr: RailRenderer = _rail_renderer()
	var loco: Node3D = rr.get_loco_node(t) if rr != null else null
	if loco == null: return
	RailSys.riding = t
	t.manual = false   # v16.8: beim Einsteigen fährt erstmal die Automatik
	player.attach_to(loco, RIDE_SEAT)
	AchievementSys.report_train_ride()
	_fp_target_kind = ""; _fp_target_train = null
	SoundSys.set_riding(true)   # v16.8: ruhigere Musik + Begrüßungs-Pfeife
	GameState.notify("🚂 Du fährst mit: %s · [W]/[S] selbst fahren · [T] Automatik" % str((RailSys.lines.get(t.line_id, {}) as Dictionary).get("name", "Zug")), Color(0.45, 0.8, 0.5))

## forced = true: Fahrt endet ohne Halt (Zug weg / Frettchenmodus verlassen) - dann steigt man
## einfach neben dem Gleis ab.
func _exit_train(forced: bool) -> void:
	var t: TrainEntity = RailSys.riding
	RailSys.riding = null
	if t != null:
		t.manual = false   # v16.8: Ausgestiegen -> Automatik übernimmt
	SoundSys.set_riding(false)     # v16.8: Musik hoch + Zuggeräusch aus
	SoundSys.set_train_audio(false, 0.0)
	var tile: Vector2i
	if t != null: tile = RailSys.exit_tile(t)
	else: tile = renderer.world3d_to_tile(player.global_position)
	player.detach(renderer.tile_to_world3d(tile.x, tile.y), player.rotation.y)
	_fp_target_kind = ""
	if _fp_hud: _fp_hud.set_prompt("")
	GameState.notify("🚪 Du bist ausgestiegen." if not forced else "🚪 Du bist vom Zug abgestiegen.", Color(0.45, 0.8, 0.5))

func _update_ride_prompt() -> void:
	var t: TrainEntity = RailSys.riding
	if t == null or not RailSys.trains.has(t) or t.line_id < 0 or not RailSys.lines.has(t.line_id):
		_exit_train(true); return
	var stops: Array = (RailSys.lines[t.line_id] as Dictionary)["stops"] as Array
	var stop_name: String = ""
	if not stops.is_empty():
		var sb = RailSys.station_at_key(int(stops[t.next_stop % stops.size()]))
		if sb != null: stop_name = RailSys.get_station_name(sb as BuildingEntity)
	if t.state == "DWELL":
		_fp_target_kind = "TRAIN_EXIT"
		if _fp_hud: _fp_hud.set_prompt("[E] 🚪 Aussteigen · %s · [W] vorzeitig abfahren" % stop_name)
	else:
		_fp_target_kind = ""
		if _fp_hud:
			if t.state == "MOVING":
				if t.manual:
					_fp_hud.set_prompt("🚂 Fahrt nach %s · %.0f %% · [W] Gas · [S] Bremse · [T] Automatik" % [stop_name, clampf(t.speed / RailSys.TRAIN_SPEED, 0.0, 1.0) * 100.0])
				else:
					_fp_hud.set_prompt("🚂 Fahrt nach %s · [W]/[S] selbst fahren" % stop_name)
			else:
				_fp_hud.set_prompt("🚂 Der Zug wartet auf freie Strecke")
	# v16.8: Zuggeräusche (Rattern/Klacken) an das SoundSystem melden; steht der
	# Zug, verstummt das Rollgeräusch.
	SoundSys.set_train_audio(t.state == "MOVING" and t.speed > 0.05, t.speed / RailSys.TRAIN_SPEED)

## Wird per "interact"-Taste (E) ausgelöst, wenn ein Ziel in Reichweite ist.
func _try_start_fp_interaction() -> void:
	if _fp_target_kind == "": return
	if _fp_target_kind == "TRAIN_EXIT":
		_exit_train(false); return
	if _fp_target_kind == "TRAIN":
		_board_train(_fp_target_train); return
	if _fp_target_kind == "FERRET":
		_pet_ferret()
		return
	if _minigame == null: return
	var max_reward: float = float(MINIGAME_MAX_REWARD.get(_fp_target_res, 10.0))
	if _fp_target_kind == "BUILD":
		# Feature (v13.6, Bauen als Minispiel): Baustelle könnte sich seit
		# dem letzten _update_fp_interaction()-Tick geändert haben (z.B.
		# durch einen NPC-Bauhof-Arbeiter fertiggestellt worden sein) -
		# knapp vor Start nochmal absichern.
		if _fp_target_site == null or not is_instance_valid(_fp_target_site) \
				or not _fp_target_site.is_under_construction or not _fp_target_site.is_fully_supplied():
			_fp_target_kind = ""; _fp_target_res = ""; _fp_target_site = null; _fp_target_ferret = null
			return
		var remaining: float = _fp_target_site.construction_work_needed - _fp_target_site.construction_progress
		_minigame.start_build(minf(max_reward, maxf(1.0, remaining)))
	else:
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
## Mechanik fürs Spieler-Frettchen). Bei den vier knotenbasierten Ressourcen
## (WOOD/STONE/BERRIES/IRON) wird zusätzlich der "resource_node" an Ort und
## Stelle um den geernteten Betrag reduziert (gleiche Erschöpfungs-/Regenerations-
## Logik wie bei NPC-Frettchen, siehe WorldGenerator.tick_resource_nodes()) -
## das Minispiel ersetzt die NPC-Ernte nicht, es ist eine zusätzliche,
## physisch am selben Knoten ansetzende Erntemöglichkeit.
##
## Feature (v13.6, Bauen als Minispiel): resource == "BUILD" ist ein
## Sonderfall - hier landet die Belohnung NICHT im Ressourcen-Lager, sondern
## direkt als construction_progress auf der zuvor anvisierten Baustelle
## (_fp_target_site). So kann der Spieler eine Baustelle durch aktives
## "Mitbauen" spürbar beschleunigen, zusätzlich zu den normalen
## Bauhof-Arbeitern (siehe _process_construction()).
func _on_minigame_finished(resource: String, reward: float) -> void:
	player.movement_enabled = _fp_mode
	# Feature (v12.2, Phase 4): "perfekt" wird VOR den Boosts anhand des
	# rohen Minispiel-Ergebnisses bestimmt (Boosts sollen nicht künstlich
	# "perfekte" Ergebnisse erzeugen, die der Spieler eigentlich nicht
	# geschafft hat - der PLAYER_PERFECT_20-Erfolg soll echtes
	# Spielergeschick wiederspiegeln).
	var max_reward: float = float(MINIGAME_MAX_REWARD.get(resource, 10.0))
	var is_perfect: bool = reward >= max_reward - 0.5
	# Zauberhut- (%) und Medaille- (flat) Boost - NUR auf tatsächliche
	# Beute (reward > 0), kein Bonus auf ein "Nichts erbeutet"-Ergebnis.
	if reward > 0.0:
		reward *= PlayerAccessories.get_boost_mult("minigame_reward_mult")
		reward += PlayerAccessories.get_boost_flat("minigame_flat_bonus")
	var node_just_depleted: bool = false
	if resource == "BUILD":
		if reward > 0.0 and _fp_target_site != null and is_instance_valid(_fp_target_site) \
				and _fp_target_site.is_under_construction:
			var site: BuildingEntity = _fp_target_site
			var applied: float = minf(reward, site.construction_work_needed - site.construction_progress)
			applied = maxf(0.0, applied)
			site.construction_progress += applied
			if site.construction_progress >= site.construction_work_needed:
				site.is_under_construction = false
				site.assigned_builder = null
				SoundSys.play_notify()
				GameState.notify("%s fertig gebaut!" % site.name)
			reward = applied
		else:
			reward = 0.0
		_fp_target_site = null
	elif reward > 0.0:
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
		if resource == "BUILD":
			if reward > 0.5:
				_fp_hud.show_floaty("🔨 +%d Baufortschritt" % int(round(reward)), true)
			else:
				_fp_hud.show_floaty("Nichts bewirkt...", false)
		else:
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
## Button._gui_input) überhaupt die Chance hatte, das Klick-Event als
## "verarbeitet" zu markieren - die Engine ruft Node._input() schlicht
## unabhängig vom GUI-Konsum auf. Klickte man z.B. den "+"-Button in der
## Gebäude-Info-UI (etwa um die Frettchenzahl zu erhöhen), feuerte ZWEI
## Dinge gleichzeitig: der Button-eigene pressed-Handler (UI reagiert
## korrekt) UND dieser Handler hier, der per Raycast die Tile HINTER der UI
## an der Klick-Bildschirmposition traf und über _select_tile()/
## building_deselected meist sofort wieder die gerade geöffnete UI schloss.
## _unhandled_input() wird von der Engine garantiert NUR aufgerufen, wenn kein
## Control das Event zuvor konsumiert hat (Buttons/Container haben per
## Default MOUSE_FILTER_STOP) - damit erreichen Klicks auf UI-Elemente die
## 3D-Welt darunter nicht mehr.
func _unhandled_input(event: InputEvent) -> void:
	if not GameState.is_playing(): return
	if event is InputEventKey and (event as InputEventKey).pressed:
		match (event as InputEventKey).keycode:
			KEY_ESCAPE:
				# Feature (v11.2, First-Person-Modus): Priorität - läuft ein
				# Minispiel, bricht ESC nur dieses ab; im First-Person-Umherlaufen
				# (ohne Minispiel) verlässt ESC den Modus zurück zur Kolonie-
				# Ansicht; sonst unverändertes altes Verhalten.
				if _is_minigame_active(): _minigame.cancel()
				elif _fp_mode: _toggle_fp_mode()
				elif not GameState.placement_mode.is_empty(): GameState.cancel_placement()
				# Bug-Fix (v13.7): früher rief ESC eine eigene, lokale
				# _toggle_pause()-Kopie auf, die (anders als GameState.toggle_pause(),
				# das über HUD-/TouchOverlay-Pausenbutton läuft) den
				# tutorial_active-Guard nicht kannte - dadurch konnte ESC während
				# des Tutorials trotzdem das echte Pausenmenü über die
				# Tutorial-Box legen. Jetzt nutzen ESC und alle anderen Pause-Wege
				# dieselbe zentrale Funktion.
				else: GameState.toggle_pause()
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
	# Linksklick-Tile-Auswahl/Pfad-Malen) wird dafür komplett übersprungen.
	if _fp_mode and not _is_minigame_active():
		if event is InputEventMouseMotion:
			player.apply_look((event as InputEventMouseMotion).relative)
		return
	if _fp_mode and _is_minigame_active():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# Bug-Fix (v11.12): Mausrad über einem geöffneten UI-Panel (z.B.
		# beim Scrollen im Tech Tree oder einer Liste) hat bisher zusätzlich
		# die Kamera gezoomt, da _unhandled_input() Mausrad-Events auch dann
		# bekommt, wenn ein darüberliegendes Control sie nicht explizit als
		# behandelt markiert (z.B. Container mit MOUSE_FILTER_IGNORE, oder ein
		# ScrollContainer ohne aktuell scrollbaren Inhalt). Statt jede
		# Container-Hierarchie einzeln abzudichten: generische Sperre - wenn
		# die Maus GERADE über irgendeinem GUI-Control steht (Panel, Button,
		# Scrollbereich, ...), wird das Kamera-Zoom für dieses Event komplett
		# übersprungen.
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
				# Feature (v11.26): Laufbefehl fürs Frettchen-Ich. Nur in der
				# Iso-Ansicht (nicht während man den Frettchenmodus selbst
				# steuert - dort gibt WASD/Maus-Look vor) und nicht über
				# einem UI-Element (sonst würde z.B. ein Mittelklick auf ein
				# Panel versehentlich einen Laufbefehl auslösen).
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

## Feature (v11.26): gemeinsame Raycast-Basis für _screen_to_tile() (das nur
## die Tile-Koordinate braucht) UND den neuen Mittelklick-Laufbefehl (der die
## tatsächliche Terrain-Weltposition inkl. Höhe braucht, damit der Spieler
## nicht auf halber Höhe eines Hügels als Ziel landet). Bisher war dieser
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
	# aktiven Platzierungsmodus prüfen (sonst würde ein Klick auf ein
	# Frettchen versehentlich ein Gebäude/einen Weg mitten drauf bauen).
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
		"RAIL":     _place_rail(tx, ty, GameState.placement_sub)
		"FIELD":    _place_field(tx, ty, GameState.placement_sub)
		"TERRAIN":
			if _fog_blocks(tx, ty): return
			if GameState.placement_sub == "RAISE":
				# Crash-Fix: build_world() ist ein KOMPLETTER Neuaufbau (löscht und
				# erzeugt Terrain, Kollision, ALLE Gebäude und Frettchen neu). Für
				# eine einzelne Höhenänderung reicht refresh_terrain() (Mesh +
				# Kollision), siehe auch _handle_drag_paint().
				WorldGenerator.raise_terrain(world, tx, ty); renderer.refresh_terrain()
			elif GameState.placement_sub == "DYNAMITE":
				WorldGenerator.place_dynamite(world, tx, ty, explosions)
		_: _select_tile(tx, ty)

func _handle_drag_paint(screen_pos: Vector2) -> void:
	var tv := _screen_to_tile(screen_pos)
	if GameState.placement_mode == "PATH":
		_place_path(tv.x, tv.y, GameState.placement_sub, true)
	elif GameState.placement_mode == "RAIL":
		_place_rail(tv.x, tv.y, GameState.placement_sub, true)
	elif GameState.placement_mode == "FIELD":
		_place_field(tv.x, tv.y, GameState.placement_sub, true)
	elif GameState.placement_mode == "TERRAIN" and GameState.placement_sub == "RAISE" and not _fog_blocks(tv.x, tv.y, true):
		# Crash-Fix: InputEventMouseMotion kann mehrfach PRO FRAME ausgelöst
		# werden. Mit dem vorherigen renderer.build_world() (voller Teardown +
		# Neuaufbau von Terrain, Kollision, allen Gebäuden UND Frettchen) wurden
		# beim Ziehen der Maus etliche StaticBody3D/Mesh-Generationen pro Sekunde
		# erzeugt, deren queue_free() noch ausstand, während schon die nächste
		# Generation aufgebaut wurde. Das häufte sich beim Aufschütten von
		# Terrain über längere Zeit auf und liess das Spiel irgendwann
		# abstürzen. refresh_terrain() baut nur Mesh + Kollision neu, nicht
		# Gebäude/Frettchen, und ist damit sicher für häufige Aufrufe.
		WorldGenerator.raise_terrain(world, tv.x, tv.y); renderer.refresh_terrain()

func _place_building(tx: int, ty: int, building_id: String) -> void:
	if building_id.is_empty() or world_gen == null: return
	var tile: Dictionary = (world[tx] as Array)[ty] as Dictionary
	if tile.get("building") != null: GameState.notify("Hier steht bereits ein Gebäude!"); return
	# Feature (v14.5, Timberborn-Feld-System): eine Feld-Kachel blockiert wie
	# ein Weg das Bebauen, bis sie wieder entfernt wird (Feld-Werkzeug,
	# Sub-Modus "CLEAR") - verhindert, dass ein Gebäude versehentlich mitten
	# auf bereits wachsendem Getreide landet.
	if FarmSys.has_field(tx, ty):
		GameState.notify("Hier liegt eine Feld-Kachel - erst mit dem Feld-Werkzeug entfernen!"); return
	# Feature (Wasserphysik): Dämme müssen direkt auf/im Wasser stehen
	# können, um den lokalen Abfluss zu drosseln - alle anderen Gebäude
	# bleiben weiterhin von Wasser-Tiles ausgeschlossen.
	if str(tile.get("biome","")) == "WATER" and building_id != "DAM":
		GameState.notify("Nicht auf Wasser bauen!"); return
	if _fog_blocks(tx, ty): return   # v16.6: im Nebel nichts bauen
	# Feature (v16.0, Kolonie-Fundament): ein Rathaus gründet eine neue Kolonie.
	if building_id == "TOWN_HALL":
		_found_colony(tx, ty); return
	if RailSys.has_rail(tx, ty) and building_id != "STATION" and building_id != "DEPOT":
		GameState.notify("Hier liegt ein Gleis!"); return
	# Gebäude dürfen nur im Gebiet der AKTIVEN Kolonie stehen (Dev-Modus: überall).
	if not GameState.dev_all_buildings:
		var owner_id: int = ColonySys.colony_of_tile(tx, ty)
		if owner_id < 0:
			GameState.notify("Außerhalb eines Kolonie-Gebiets! Baue innerhalb des Rathaus-Radius oder gründe mit einem Rathaus eine neue Kolonie.", Color(0.85, 0.55, 0.15)); return
		if ColonySys.is_npc(owner_id):
			GameState.notify("Dieses Gebiet gehört der Nachbarkolonie '%s' - bau außerhalb ihres Gebiets." % ColonySys.get_name_of(owner_id), Color(0.85, 0.55, 0.15)); return
		if owner_id != ColonySys.active_id:
			GameState.notify("Dieses Gebiet gehört zu '%s' - wechsle über das Kolonien-Panel (🏛️) dorthin." % ColonySys.get_name_of(owner_id), Color(0.85, 0.55, 0.15)); return
	if not GameState.dev_all_buildings and not BuildingSys.can_build(building_id):
		GameState.notify("Nicht genug Ressourcen!"); return
	var b: BuildingEntity = BuildingSys.build(building_id, tx, ty, world, GameState.dev_all_buildings)
	if b != null:
		b.placed_day = DayNight.day_count
		renderer.add_building(b); SoundSys.play_build()
		GameState.cancel_placement(); renderer.clear_ghost()

## Feature (v16.0, Kolonie-Fundament / Phase 1): gründet an (tx, ty) eine NEUE Kolonie.
## Das Gründungspaket (Rathaus-Kosten) wird der aktiven Kolonie abgezogen und wird
## zum Startbestand der neuen; dazu gibt es gratis Bauhof + Lager und
## ColonySys.SETTLERS Siedler-Frettchen aus der Gründerkolonie.
func _found_colony(tx: int, ty: int) -> void:
	if _fog_blocks(tx, ty): return
	var tile: Dictionary = (world[tx] as Array)[ty] as Dictionary
	if tile.get("building") != null: GameState.notify("Hier steht bereits ein Gebäude!"); return
	if FarmSys.has_field(tx, ty):
		GameState.notify("Hier liegt eine Feld-Kachel - erst mit dem Feld-Werkzeug entfernen!"); return
	var err: String = ColonySys.can_found_at(tx, ty)
	if err != "":
		GameState.notify(err, Color(0.85, 0.55, 0.15)); return
	var from_id: int = ColonySys.active_id
	var have: int = PopMgr.get_count(from_id)
	if have < ColonySys.MIN_FERRETS_TO_FOUND:
		GameState.notify("Für eine neue Kolonie braucht '%s' mindestens %d Frettchen (jetzt %d)." % [ColonySys.get_name_of(from_id), ColonySys.MIN_FERRETS_TO_FOUND, have], Color(0.85, 0.55, 0.15)); return
	var costs: Dictionary = (BuildingData.BUILDINGS["TOWN_HALL"] as Dictionary)["costs"] as Dictionary
	if not GameState.dev_all_buildings and not ResourceSys.can_afford(costs):
		GameState.notify("Nicht genug Ressourcen für das Gründungspaket!"); return
	if not GameState.dev_all_buildings: ResourceSys.spend(costs)

	var new_id: int = ColonySys.register_colony(ColonySys.pick_new_name(), tx, ty, DayNight.day_count)
	ResourceSys.create_pool(new_id, costs)   # Gründungspaket = Startbestand
	var placed: Array = []
	var hall: BuildingEntity = BuildingSys.build_free("TOWN_HALL", tx, ty, world, new_id)
	if hall != null: placed.append(hall)
	var yard_pos: Vector2i = _find_free_tile_ring(tx, ty, world, 2, 6)
	if yard_pos.x >= 0:
		var yb: BuildingEntity = BuildingSys.build_free("CONSTRUCTION_YARD_1", yard_pos.x, yard_pos.y, world, new_id)
		if yb != null: placed.append(yb)
	var store_pos: Vector2i = _find_free_tile_ring(tx, ty, world, 2, 6)
	if store_pos.x >= 0:
		var sb: BuildingEntity = BuildingSys.build_free("STORAGE", store_pos.x, store_pos.y, world, new_id)
		if sb != null: placed.append(sb)
	for pb in placed:
		var pbe: BuildingEntity = pb
		pbe.placed_day = DayNight.day_count
		renderer.add_building(pbe)
	var moved: int = PopMgr.transfer_ferrets(from_id, new_id, ColonySys.SETTLERS, Vector2(float(tx), float(ty)))
	SoundSys.play_build()
	GameState.cancel_placement(); renderer.clear_ghost()
	focus_colony(new_id)
	GameState.notify("🏛️ Kolonie '%s' gegründet! %d Siedler sind eingezogen." % [ColonySys.get_name_of(new_id), moved], Color(0.45, 0.85, 0.5))

# ══════════════════════════════════════════════════════════════════════════════
# DEV-WERKZEUGE (v16.5) - werden vom DevToolsPanel aufgerufen (nur im Dev-Modus sichtbar)
# Rückgabe String = Meldung für den Spieler ("" = nichts melden).
# ══════════════════════════════════════════════════════════════════════════════
func dev_add_all_resources(amount: float) -> String:
	for k in ResourceSys.resources.keys(): ResourceSys.force_add(str(k), amount)
	GameState.hud_update_requested.emit()
	return "🛠️ +%d aller Ressourcen (%s)" % [int(amount), ColonySys.get_name_of(ColonySys.active_id)]

func dev_unlock_all_epochs(count: int) -> String:
	var n: int = 0
	while n < count:
		var eid: String = TechTreeSys.get_next_epoch_id()
		if eid == "": break
		TechTreeSys.unlocked_epochs.append(eid)
		GameState.tech_unlocked.emit(eid)
		n += 1
	GameState.build_menu_update_requested.emit()
	return "🛠️ %d Epoche(n) freigeschaltet (jetzt Epoche %d)" % [n, TechTreeSys.get_epoch()] if n > 0 else "🛠️ Höchste Epoche bereits erreicht."

func dev_unlock_all_tech() -> String:
	var n: int = 0
	for tid in TechTreeSys.NODES.keys():
		if not (tid in TechTreeSys.unlocked):
			TechTreeSys.unlocked.append(tid); n += 1
	BuildingSys.recalculate_all_bonuses()
	GameState.build_menu_update_requested.emit()
	return "🛠️ %d Tech-Knoten freigeschaltet" % n

func dev_spawn_ferrets(n: int) -> String:
	var hall: Vector2i = ColonySys.get_hall_tile(ColonySys.active_id)
	for i in n:
		var f: FerretEntity = FerretEntity.create_random()
		f.colony_id = ColonySys.active_id
		if hall.x >= 0:
			f.pos = Vector2(float(hall.x) + randf_range(-2.0, 2.0), float(hall.y) + randf_range(-2.0, 2.0))
			f.target_pos = f.pos
		PopMgr.ferrets.append(f)
	GameState.hud_update_requested.emit()
	return "🛠️ +%d Frettchen in %s" % [n, ColonySys.get_name_of(ColonySys.active_id)]

func dev_fill_needs() -> String:
	for f in PopMgr.ferrets_of(ColonySys.active_id):
		var fe: FerretEntity = f
		for k in fe.needs.keys(): fe.needs[k] = 100.0
		fe.health = 100.0
	ResourceSys.water = ResourceSys.water_capacity
	return "🛠️ Frettchen und Wassertank aufgefüllt"

func dev_finish_construction() -> String:
	var n: int = 0
	for site in BuildingSys.get_construction_sites():
		var s: BuildingEntity = site
		for res in s.costs: s.delivered_resources[res] = float(s.costs[res])
		s.construction_progress = maxf(s.construction_progress, s.construction_work_needed - 0.01)
		n += 1
	return "🛠️ %d Baustelle(n) werden fertig" % n

func dev_set_time(frac: float) -> String:
	DayNight.time = DayNight.day_length * clampf(frac, 0.0, 0.999)
	DayNight.update(0.0)
	return "🛠️ Uhrzeit: %s" % DayNight.display_time

func dev_next_season() -> String:
	var total: int = 0
	for sd in SeasonSys.SEASONS: total += int((sd as Dictionary)["days"])
	var in_year: int = DayNight.day_count % total
	var acc: int = 0; var to_next: int = 1
	for sd2 in SeasonSys.SEASONS:
		acc += int((sd2 as Dictionary)["days"])
		if in_year < acc: to_next = acc - in_year; break
	DayNight.day_count += to_next
	SeasonSys.update(DayNight.day_count)
	return "🛠️ Jahreszeit: %s (Tag %d)" % [SeasonSys.get_season_name(), DayNight.day_count]

func dev_start_drought() -> String:
	DroughtSys.force_drought()
	return "🛠️ Dürre gestartet"

func dev_end_drought() -> String:
	DroughtSys.phase = "WET"; DroughtSys.is_drought = false; DroughtSys.timer = 0.0
	GameState.drought_ended.emit()
	return "🛠️ Dürre beendet"

## Gründet an einem passenden freien Ort eine neue Kolonie (gratis, Siedler werden bei Bedarf
## erzeugt) und wechselt dorthin. "" = Erfolg (die Gründung meldet selbst).
func dev_found_colony() -> String:
	var site: Vector2i = _dev_find_colony_site()
	if site.x < 0: return "🛠️ Kein Platz für eine weitere Kolonie (20 Kacheln Abstand zu jedem Rathaus)."
	var prev_dev: bool = GameState.dev_all_buildings
	GameState.dev_all_buildings = true
	var need: int = ColonySys.MIN_FERRETS_TO_FOUND - PopMgr.get_count(ColonySys.active_id)
	if need > 0: dev_spawn_ferrets(need)
	_found_colony(site.x, site.y)
	GameState.dev_all_buildings = prev_dev
	return ""

## Passende freie Stelle für eine weitere Kolonie: aufgedeckt, mind. 20 Kacheln von jedem Rathaus und ZU FUSS vom
## Rathaus der aktiven Kolonie erreichbar (BFS über aufgedecktes Land), damit die Test-Linie eine Strecke findet.
## Bevorzugt eine Stelle 22-34 Kacheln entfernt.
func _dev_find_colony_site() -> Vector2i:
	var start: Vector2i = ColonySys.get_hall_tile(ColonySys.active_id)
	if start.x < 0: return Vector2i(-1, -1)
	var dist: Dictionary = {start: 0}
	var q: Array = [start]
	var best := Vector2i(-1, -1); var best_score: float = -1.0
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		var dc: int = int(dist[c])
		var t0: Dictionary = (world[c.x] as Array)[c.y] as Dictionary
		if dc >= 20 and t0.get("building") == null and not FarmSys.has_field(c.x, c.y) and not RailSys.has_rail(c.x, c.y) and ColonySys.can_found_at(c.x, c.y) == "":
			var eu: float = Vector2(c).distance_to(Vector2(start))
			if eu >= 21.0:
				var score: float = 100.0 - absf(eu - 28.0)   # nahe 28 Kacheln ist ideal
				if score > best_score: best_score = score; best = c
		if dc > 60: continue
		for d in RailSys.DIRS:
			var n: Vector2i = c + (d as Vector2i)
			if n.x < 3 or n.y < 3 or n.x >= world_gen.w - 3 or n.y >= world_gen.h - 3 or dist.has(n): continue
			if not ExploreSys.is_revealed(n.x, n.y): continue
			var t: Dictionary = (world[n.x] as Array)[n.y] as Dictionary
			var bi: String = str(t.get("biome", ""))
			if bi == "WATER" or bi == "MOUNTAIN": continue
			dist[n] = dc + 1; q.append(n)
	return best

func dev_reveal_all() -> String:
	if not ExploreSys.enabled: return "🛠️ Diese Welt hat keinen Nebel (nur 'Entdecker'-Karten)."
	ExploreSys.reveal_all()
	return "🛠️ Karte komplett aufgedeckt"

func dev_reveal_ring(r: float) -> String:
	if not ExploreSys.enabled: return "🛠️ Diese Welt hat keinen Nebel (nur 'Entdecker'-Karten)."
	var h: Vector2i = ColonySys.get_hall_tile(ColonySys.active_id)
	var n: int = ExploreSys.reveal_circle(h.x, h.y, r)
	return "🛠️ Radius %d um das Rathaus aufgedeckt (+%d Kacheln, %d%% bekannt)" % [int(r), n, int(ExploreSys.fraction() * 100.0)]

func dev_neighbors_reveal() -> String:
	if NeighborSys.neighbors.is_empty(): return "🛠️ Keine Nachbarn (nur Entdeckerkarten)."
	for cid in NeighborSys.cids():
		var h: Vector2i = ColonySys.get_hall_tile(int(cid))
		ExploreSys.reveal_circle(h.x, h.y, 10.0)
	NeighborSys.check_discovery(2.0)
	return "🛠️ %d Nachbarn aufgedeckt" % NeighborSys.neighbors.size()

func dev_neighbors_rep(amount: float) -> String:
	var n: int = 0
	for cid in NeighborSys.cids():
		var nb: Dictionary = NeighborSys.neighbors[cid] as Dictionary
		if not bool(nb["discovered"]): continue
		nb["rep"] = clampf(float(nb["rep"]) + amount, NeighborSys.REP_MIN, NeighborSys.REP_MAX); n += 1
	NeighborSys.neighbors_changed.emit()
	return "🛠️ Ruf %+d bei %d entdeckten Nachbarn" % [int(amount), n]

func dev_neighbors_request() -> String:
	var n: int = 0
	for cid in NeighborSys.cids():
		var nb: Dictionary = NeighborSys.neighbors[cid] as Dictionary
		if bool(nb["discovered"]) and not bool(nb["annexed"]) and (nb["request"] as Dictionary).is_empty():
			NeighborSys._new_request(int(cid), DayNight.day_count); n += 1
	return "🛠️ %d neue Aufträge" % n

func dev_annex_first() -> String:
	for cid in NeighborSys.cids():
		var nb: Dictionary = NeighborSys.neighbors[cid] as Dictionary
		if bool(nb["discovered"]) and not bool(nb["annexed"]):
			var err: String = NeighborSys.annex(int(cid), self, true)
			return "🛠️ " + (err if err != "" else "%s annektiert" % ColonySys.get_name_of(int(cid)))
	return "🛠️ Kein entdeckter, noch nicht annektierter Nachbar."

## Deckt einen Korridor zwischen zwei Kacheln auf (nur Dev: damit die Test-Strecke durch den Nebel führen darf).
func _dev_reveal_corridor(a: Vector2i, b: Vector2i) -> void:
	var steps: int = maxi(1, int(Vector2(a).distance_to(Vector2(b)) / 3.0))
	for i in steps + 1:
		var p: Vector2 = Vector2(a).lerp(Vector2(b), float(i) / float(steps))
		ExploreSys.reveal_circle(int(p.x), int(p.y), 5.0)

## Baut eine Handelslinie vom aktiven Kolonie-Rathaus zum Bahnhof des ersten erreichbaren Nachbarn: Bahnhof+Depot
## bei dir, eingeebnete Strecke mit Gleisen, Linie (gewünschte Ware hin, Angebot zurück) und ein Zug.
func dev_neighbor_line() -> String:
	if NeighborSys.neighbors.is_empty(): return "🛠️ Keine Nachbarn (nur Entdeckerkarten)."
	dev_neighbors_reveal()
	var ca: int = ColonySys.active_id
	var ha: Vector2i = ColonySys.get_hall_tile(ca)
	var pa: Vector2i = _find_free_tile_ring(ha.x, ha.y, world, 2, 7)
	if pa.x < 0: return "🛠️ Kein freier Platz für einen Bahnhof."
	var target_cid: int = -1; var nb_station: BuildingEntity = null; var route: Array = []
	for cid in NeighborSys.cids():
		var nb: Dictionary = NeighborSys.neighbors[cid] as Dictionary
		if bool(nb["annexed"]): continue
		var sb: BuildingEntity = null
		for s in RailSys.get_buildings_of("STATION"):
			if (s as BuildingEntity).colony_id == int(cid): sb = s
		if sb == null: continue
		var hb: Vector2i = ColonySys.get_hall_tile(int(cid))
		_dev_reveal_corridor(pa, hb)
		var r: Array = _dev_bfs_route(pa, Vector2i(sb.tile_x, sb.tile_y))
		if r.size() >= 3: target_cid = int(cid); nb_station = sb; route = r; break
	if target_cid < 0: return "🛠️ Keine Landverbindung zu einem Nachbarn gefunden (Wasser/Gebirge im Weg)."
	var prev_dev: bool = GameState.dev_all_buildings
	GameState.dev_all_buildings = true
	GameState.dev_unlimited_storage = true
	var st_a: BuildingEntity = BuildingSys.build_free("STATION", pa.x, pa.y, world, ca)
	if st_a == null:
		GameState.dev_all_buildings = prev_dev
		return "🛠️ Bahnhof konnte nicht gebaut werden."
	var h0: float = float(((world[pa.x] as Array)[pa.y] as Dictionary).get("height", 0.0))
	for v in route:
		var rt: Dictionary = (world[(v as Vector2i).x] as Array)[(v as Vector2i).y] as Dictionary
		rt["height"] = h0; rt["resource_node"] = null; rt["path"] = null
	var depot_pos := Vector2i(-1, -1)
	for d in RailSys.DIRS:
		var c: Vector2i = pa + (d as Vector2i)
		if c in route or c.x < 0 or c.y < 0 or c.x >= world_gen.w or c.y >= world_gen.h: continue
		var dt: Dictionary = (world[c.x] as Array)[c.y] as Dictionary
		if dt.get("building") != null or FarmSys.has_field(c.x, c.y) or RailSys.has_rail(c.x, c.y): continue
		var bi: String = str(dt.get("biome", ""))
		if bi == "WATER" or bi == "MOUNTAIN": continue
		depot_pos = c; break
	var depot: BuildingEntity = null
	if depot_pos.x >= 0:
		var dtile: Dictionary = (world[depot_pos.x] as Array)[depot_pos.y] as Dictionary
		dtile["height"] = h0; dtile["resource_node"] = null
		depot = BuildingSys.build_free("DEPOT", depot_pos.x, depot_pos.y, world, ca)
	for bl in [st_a, depot]:
		if bl != null:
			(bl as BuildingEntity).placed_day = DayNight.day_count
			renderer.add_building(bl as BuildingEntity)
	renderer.refresh_terrain()
	for i in range(1, route.size() - 1):
		var rv: Vector2i = route[i]
		if not RailSys.has_rail(rv.x, rv.y): RailSys.place_rail(rv.x, rv.y)
	var pf: Dictionary = NeighborSys.profile_of(target_cid)
	var wants: Array = pf.get("wants", []) as Array
	var offers: Array = (pf.get("offers", {}) as Dictionary).keys()
	var line: int = RailSys.create_line()
	RailSys.add_stop(line, RailSys.key(pa.x, pa.y))
	RailSys.add_stop(line, RailSys.key(nb_station.tile_x, nb_station.tile_y))
	if not wants.is_empty(): RailSys.add_shipment(line, str(wants[0]), 0, 1)
	if not offers.is_empty(): RailSys.add_shipment(line, str(offers[0]), 1, 0)
	var prev_c: int = ResourceSys.current_colony
	ResourceSys.use_colony(ca)
	if not wants.is_empty(): ResourceSys.force_add(str(wants[0]), 300.0)
	ResourceSys.use_colony(prev_c)
	var tmsg: String = RailSys.buy_train(depot, line) if depot != null else "kein Platz für ein Depot"
	GameState.dev_all_buildings = prev_dev
	GameState.build_menu_update_requested.emit()
	if tmsg != "": return "🛠️ Handelslinie gebaut, aber: " + tmsg
	return "🛠️ Handelslinie zu %s gebaut (%s → hin, %s zurück), %d Gleise, 1 Zug" % [ColonySys.get_name_of(target_cid), str(wants[0]) if not wants.is_empty() else "-", str(offers[0]) if not offers.is_empty() else "-", route.size() - 2]

func dev_cycle_colony() -> String:
	var ids: Array = ColonySys.player_ids()
	if ids.size() < 2: return "🛠️ Es gibt nur eine Kolonie."
	var i: int = ids.find(ColonySys.active_id)
	focus_colony(int(ids[(i + 1) % ids.size()]))
	return "🛠️ Aktive Kolonie: %s" % ColonySys.get_name_of(ColonySys.active_id)

## Kürzester Landweg (4er-Nachbarschaft) zwischen zwei Kacheln, ohne Wasser/Gebirge/Gebäude/Felder.
func _dev_bfs_route(a: Vector2i, b: Vector2i) -> Array:
	var prev: Dictionary = {a: a}
	var q: Array = [a]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if c == b: break
		for d in RailSys.DIRS:
			var n: Vector2i = c + (d as Vector2i)
			if n.x < 0 or n.y < 0 or n.x >= world_gen.w or n.y >= world_gen.h or prev.has(n): continue
			var t: Dictionary = (world[n.x] as Array)[n.y] as Dictionary
			var bi: String = str(t.get("biome", ""))
			if bi == "WATER" or bi == "MOUNTAIN": continue
			if not ExploreSys.is_revealed(n.x, n.y): continue
			if t.get("building") != null and n != b: continue
			if FarmSys.has_field(n.x, n.y): continue
			prev[n] = c; q.append(n)
	if not prev.has(b): return []
	var path: Array = []; var cur: Vector2i = b
	while cur != a:
		path.push_front(cur); cur = prev[cur]
	path.push_front(a)
	return path

## EIN Klick: zwei Kolonien, zwei Bahnhöfe, Depot, eingeebnete Strecke mit Gleisen, Linie
## (Bretter A->B, Holz B->A) und ein Zug. Das Gelände entlang der Strecke wird eingeebnet.
func dev_rail_test_line() -> String:
	if ColonySys.player_count() < 2:
		var msg: String = dev_found_colony()
		if msg != "": return msg
	var ids: Array = ColonySys.player_ids()
	var ca: int = int(ids[0]); var cb: int = int(ids[1])
	var ha: Vector2i = ColonySys.get_hall_tile(ca); var hb: Vector2i = ColonySys.get_hall_tile(cb)
	var pa: Vector2i = _find_free_tile_ring(ha.x, ha.y, world, 2, 7)
	var pb: Vector2i = _find_free_tile_ring(hb.x, hb.y, world, 2, 7)
	if pa.x < 0 or pb.x < 0: return "🛠️ Kein freier Platz für die Bahnhöfe."
	var route: Array = _dev_bfs_route(pa, pb)
	if route.size() < 3: return "🛠️ Keine Landverbindung zwischen den Kolonien (Wasser/Gebirge im Weg)."
	var prev_dev: bool = GameState.dev_all_buildings
	GameState.dev_all_buildings = true
	GameState.dev_unlimited_storage = true   # Züge sollen in der Test-Linie immer entladen können
	var st_a: BuildingEntity = BuildingSys.build_free("STATION", pa.x, pa.y, world, ca)
	var st_b: BuildingEntity = BuildingSys.build_free("STATION", pb.x, pb.y, world, cb)
	if st_a == null or st_b == null:
		GameState.dev_all_buildings = prev_dev
		return "🛠️ Bahnhöfe konnten nicht gebaut werden."
	# Strecke und Bahnhöfe einebnen (alle Kacheln auf die Höhe von Bahnhof A), Vorkommen räumen
	var h0: float = float(((world[pa.x] as Array)[pa.y] as Dictionary).get("height", 0.0))
	for v in route:
		var rt: Dictionary = (world[(v as Vector2i).x] as Array)[(v as Vector2i).y] as Dictionary
		rt["height"] = h0; rt["resource_node"] = null; rt["path"] = null
	# Depot direkt neben Bahnhof A (nicht auf der Strecke)
	var depot_pos := Vector2i(-1, -1)
	for d in RailSys.DIRS:
		var c: Vector2i = pa + (d as Vector2i)
		if c in route or c.x < 0 or c.y < 0 or c.x >= world_gen.w or c.y >= world_gen.h: continue
		var dt: Dictionary = (world[c.x] as Array)[c.y] as Dictionary
		if dt.get("building") != null or FarmSys.has_field(c.x, c.y) or RailSys.has_rail(c.x, c.y): continue
		var bi: String = str(dt.get("biome", ""))
		if bi == "WATER" or bi == "MOUNTAIN": continue
		depot_pos = c; break
	var depot: BuildingEntity = null
	if depot_pos.x >= 0:
		var dtile: Dictionary = (world[depot_pos.x] as Array)[depot_pos.y] as Dictionary
		dtile["height"] = h0; dtile["resource_node"] = null
		depot = BuildingSys.build_free("DEPOT", depot_pos.x, depot_pos.y, world, ca)
	for bl in [st_a, st_b, depot]:
		if bl != null:
			(bl as BuildingEntity).placed_day = DayNight.day_count
			renderer.add_building(bl as BuildingEntity)
	renderer.refresh_terrain()
	for i in range(1, route.size() - 1):
		var rv: Vector2i = route[i]
		if not RailSys.has_rail(rv.x, rv.y): RailSys.place_rail(rv.x, rv.y)
	# Linie + Fracht + Zug; Startvorrat, damit sofort etwas fährt
	var line: int = RailSys.create_line()
	RailSys.add_stop(line, RailSys.key(pa.x, pa.y))
	RailSys.add_stop(line, RailSys.key(pb.x, pb.y))
	RailSys.add_shipment(line, "PLANKS", 0, 1)
	RailSys.add_shipment(line, "WOOD", 1, 0)
	var prev_c: int = ResourceSys.current_colony
	ResourceSys.use_colony(ca); ResourceSys.force_add("PLANKS", 300.0)
	ResourceSys.use_colony(cb); ResourceSys.force_add("WOOD", 300.0)
	ResourceSys.use_colony(prev_c)
	var tmsg: String = RailSys.buy_train(depot, line) if depot != null else "kein Platz für ein Depot"
	GameState.dev_all_buildings = prev_dev
	GameState.build_menu_update_requested.emit()
	if tmsg != "": return "🛠️ Test-Linie gebaut, aber: " + tmsg
	return "🛠️ Test-Linie gebaut (Lager-Limit aus): %s ↔ %s, %d Gleise, 1 Zug" % [RailSys.get_station_name(st_a), RailSys.get_station_name(st_b), route.size() - 2]

func dev_buy_train() -> String:
	var depots: Array = RailSys.get_buildings_of("DEPOT")
	if depots.is_empty(): return "🛠️ Kein fertiges Depot."
	var lids: Array = RailSys.lines.keys(); lids.sort()
	var lid: int = int(lids[0]) if not lids.is_empty() else -1
	var prev_dev: bool = GameState.dev_all_buildings
	GameState.dev_all_buildings = true
	var err: String = RailSys.buy_train(depots[0] as BuildingEntity, lid)
	GameState.dev_all_buildings = prev_dev
	return "🛠️ " + (err if err != "" else "Zug gekauft" + (" und auf die erste Linie gesetzt" if lid >= 0 else " (keine Linie vorhanden)"))

func dev_halt_trains(seconds: float) -> String:
	var n: int = 0
	for tv in RailSys.trains:
		var t: TrainEntity = tv
		if t.line_id >= 0 and t.state != "DEPOT":
			t.state = "DWELL"; t.timer = seconds; n += 1
	return "🛠️ %d Zug/Züge halten %d s an" % [n, int(seconds)]

func dev_teleport_to_train() -> String:
	if RailSys.trains.is_empty(): return "🛠️ Es gibt keinen Zug."
	var rr: RailRenderer = _rail_renderer()
	if rr == null: return "🛠️ Kein Gleis-Renderer."
	if not _fp_mode: _toggle_fp_mode()
	var t: TrainEntity = RailSys.trains[0]
	var parts: Array = rr.train_part_positions(t)
	player.teleport_to((parts[0] as Vector3) + Vector3(1.5, 0.5, 1.0))
	return "🛠️ Du stehst neben Zug %d - mit 'Alle Züge 30 s anhalten' kannst du einsteigen ([E])" % t.id

## v16.8 (Lokführer-Modus): sofort in den ersten Zug mit Linie setzen - zum schnellen
## Testen des Lokführer-Modus ohne Anlaufphase. Bremst fahrende Züge vorher auf
## Halt (DWELL), sonst verlangt _board_train einen Halt.
func dev_ride_train() -> String:
	if RailSys.trains.is_empty(): return "🛠️ Es gibt keinen Zug."
	var rr: RailRenderer = _rail_renderer()
	if rr == null: return "🛠️ Kein Gleis-Renderer."
	var target: TrainEntity = null
	for tv in RailSys.trains:
		var t: TrainEntity = tv
		if t.line_id >= 0 and RailSys.lines.has(t.line_id) and rr.get_loco_node(t) != null:
			target = t
			break
	if target == null: return "🛠️ Kein Zug mit Linie im Depot/eingeteilt."
	if not _fp_mode: _toggle_fp_mode()
	target.state = "DWELL"
	target.timer = 30.0   # Zeit zum Umsehen, [W] fährt vorzeitig ab
	_board_train(target)
	if RailSys.riding != target: return "🛠️ Einstieg fehlgeschlagen (Zug-Knoten fehlt?)."
	return "🛠️ Du steuerst Zug %d ([W] Gas / [S] Bremse / [T] Automatik)." % target.id

func dev_remove_trains() -> String:
	if RailSys.riding != null: _exit_train(true)
	var n: int = RailSys.trains.size()
	RailSys.trains.clear()
	return "🛠️ %d Zug/Züge entfernt" % n

func dev_remove_rails() -> String:
	var keys: Array = RailSys.rails.keys()
	for k in keys:
		var v: Vector2i = RailSys.key_vec(int(k))
		RailSys.remove_rail(v.x, v.y)
	return "🛠️ %d Gleis(e) entfernt" % keys.size()

## v16.6: Kamera auf eine Kachel setzen (Weltkarte). Im Frettchenmodus passiert nichts.
func focus_tile(tx: int, ty: int) -> void:
	if renderer == null or _fp_mode: return
	_cam_target = renderer.tile_to_world3d(tx, ty)
	_apply_camera()

## Wechselt die aktive Kolonie und springt (außerhalb des Frettchenmodus) mit der
## Kamera zu ihrem Rathaus. Genutzt vom Kolonien-Panel und nach einer Gründung.
func focus_colony(id: int) -> void:
	if not ColonySys.has_colony(id): return
	ColonySys.set_active(id)
	var h: Vector2i = ColonySys.get_hall_tile(id)
	if h.x >= 0 and renderer != null and not _fp_mode:
		# y bleibt die echte Gelände-Höhe, sonst liegt das Rathaus bei hohem Gelände weit
		# oberhalb der Bildmitte (die Kamera zielt auf die Ebene y=0, siehe _apply_camera()).
		_cam_target = renderer.tile_to_world3d(h.x, h.y)
		_apply_camera()
	_on_hud_update(); _on_build_menu_update()

## Spielstände von vor v16.0 kennen keine Kolonien: Kolonie 0 bekommt nachträglich
## ihr Rathaus (gratis) und ein Gebiet, das alle vorhandenen Gebäude umfasst - so
## wird nichts plötzlich "Niemandsland". Siehe SaveSystem._lg_restore().
func migrate_colonies_after_load() -> void:
	if not ColonySys.needs_migration: return
	ColonySys.needs_migration = false
	@warning_ignore("integer_division")
	var ax: int = world_gen.w / 2
	@warning_ignore("integer_division")
	var ay: int = world_gen.h / 2
	for b in BuildingSys.buildings:
		var be: BuildingEntity = b
		if be.btype == "BUILDER": ax = be.tile_x; ay = be.tile_y; break
	var hp: Vector2i = _find_free_tile_ring(ax, ay, world, 2, 8)
	var hx: int = ax; var hy: int = ay
	if hp.x >= 0:
		var hall: BuildingEntity = BuildingSys.build_free("TOWN_HALL", hp.x, hp.y, world, 0)
		if hall != null: hall.placed_day = DayNight.day_count
		hx = hp.x; hy = hp.y
	ColonySys.set_hall(0, hx, hy)
	ColonySys.rename(0, current_world_name)
	var far: float = 0.0
	for b2 in BuildingSys.buildings:
		var be2: BuildingEntity = b2
		far = maxf(far, Vector2(float(hx), float(hy)).distance_to(Vector2(float(be2.tile_x), float(be2.tile_y))))
	ColonySys.set_radius(0, maxf(ColonySys.TERRITORY_RADIUS, far + 3.0))

func _place_path(tx: int, ty: int, path_type: String, silent: bool = false) -> void:
	if world_gen == null: return
	if tx < 0 or ty < 0 or tx >= world_gen.w or ty >= world_gen.h: return
	if _fog_blocks(tx, ty, silent): return
	var tile: Dictionary = (world[tx] as Array)[ty] as Dictionary
	if tile.get("building") != null or str(tile.get("biome","")) in ["WATER","MOUNTAIN"]: return
	if tile.get("path") != null: return
	if FarmSys.has_field(tx, ty): return
	var pt: Dictionary = BuildingData.PATH_TYPES.get(path_type, {}) as Dictionary
	var costs: Dictionary = pt.get("costs", {}) as Dictionary
	# Bug-Fix (v14.5, beim Bauernhof-Feature entdeckt): "if not silent: notify();
	# return" auf einer Zeile gehört in GDScript BEIDES zum if-Block (Python-
	# Semantik) - bei silent==true (Drag-Malen) wurde darum auch das return
	# übersprungen. Der Code lief dann weiter bis zu ResourceSys.spend(costs),
	# das bei fehlenden Ressourcen intern scheitert (spend() prüft can_afford
	# erneut) - der Weg wurde am Ende aber trotzdem kostenlos gesetzt, weil das
	# vorzeitige Aussteigen fehlte. Jetzt: return immer, Meldung nur wenn nicht silent.
	if not GameState.dev_all_buildings and not ResourceSys.can_afford(costs):
		if not silent: GameState.notify("Nicht genug Ressourcen für Weg!")
		return
	if not GameState.dev_all_buildings: ResourceSys.spend(costs)
	tile["path"] = {"type": path_type}
	renderer.refresh_terrain(); _on_hud_update()

## Feature (v16.2, Schiene): Gleis-Werkzeug, analog zu _place_path() (Drag-Malen über
## _handle_drag_paint()). sub == "PLACE" legt ein Gleis an (kostet RAIL_COSTS aus dem
## Pool der aktiven Kolonie), sub == "REMOVE" entfernt es wieder (ohne Erstattung).
func _place_rail(tx: int, ty: int, sub: String, silent: bool = false) -> void:
	if world_gen == null: return
	if tx < 0 or ty < 0 or tx >= world_gen.w or ty >= world_gen.h: return
	if sub == "REMOVE":
		if RailSys.remove_rail(tx, ty): _on_hud_update()
		return
	var err: String = RailSys.can_place_rail(tx, ty)
	if err != "":
		if not silent and not err.begins_with("Hier liegt schon"): GameState.notify(err, Color(0.85, 0.55, 0.15))
		return
	var costs: Dictionary = RailSys.RAIL_COSTS
	if not GameState.dev_all_buildings and not ResourceSys.can_afford(costs):
		if not silent: GameState.notify("Nicht genug Ressourcen für Gleis!")
		return
	if not GameState.dev_all_buildings: ResourceSys.spend(costs)
	var had_path: bool = ((world[tx] as Array)[ty] as Dictionary).get("path") != null
	RailSys.place_rail(tx, ty)
	if had_path: renderer.refresh_terrain()   # Weg-Färbung der Kachel wegnehmen
	_on_hud_update()

## Feature (v14.5, Timberborn-Feld-System): Feld-Werkzeug, analog im Aufbau
## zu _place_path() (siehe dort) - unterstützt genauso Drag-Malen über
## _handle_drag_paint(). sub == "SET" legt eine neue Feld-Kachel an
## (kostenlos - siehe Design-Entscheidung: keine Bewässerungspflicht, freie
## Platzierung im ganzen Bezirk), sub == "CLEAR" entfernt eine bestehende
## wieder (z.B. um Platz für ein Gebäude zu schaffen oder ein Feld
## zurückzubauen - der Fortschritt des Feldes geht dabei verloren).
func _place_field(tx: int, ty: int, sub: String, silent: bool = false) -> void:
	if world_gen == null: return
	if tx < 0 or ty < 0 or tx >= world_gen.w or ty >= world_gen.h: return
	if _fog_blocks(tx, ty, silent): return
	if sub == "CLEAR":
		FarmSys.remove_field(tx, ty)
		renderer.refresh_terrain()
		return
	var tile: Dictionary = (world[tx] as Array)[ty] as Dictionary
	if FarmSys.has_field(tx, ty): return
	if tile.get("building") != null or tile.get("path") != null:
		if not silent: GameState.notify("Hier ist bereits etwas anderes gebaut!")
		return
	# Nur Wiesen sind Ackerland - Wald/Hügel/Berg tragen Bäume/Gestein,
	# Wasser/Strand scheiden ohnehin aus (siehe WorldGenerator-Biome).
	if str(tile.get("biome","")) != "PLAINS":
		if not silent: GameState.notify("Felder nur auf Wiesen-Kacheln möglich!")
		return
	var did: int = DistrictSys.get_district_for_tile(tx, ty)
	if FarmSys.register_field(tx, ty, did):
		renderer.refresh_terrain()

func _select_tile(tx: int, ty: int) -> void:
	renderer.set_selection(tx, ty)
	var tile: Dictionary = (world[tx] as Array)[ty] as Dictionary
	var bld = tile.get("building", null)
	if bld != null:
		var b: BuildingEntity = bld as BuildingEntity
		renderer.selected_building = b; GameState.building_selected.emit(b)
		# Feature (v11.1, Logistik-Feinschliff): Gebäude-Ketten-Vorschau
		# anzeigen (Produktionsgebäude → Lagerhaus → Baustelle).
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
	if renderer.selected_building.btype == "TOWN_HALL":
		GameState.notify("Das Rathaus kann nicht verkauft werden.", Color(0.8, 0.3, 0.1)); return
	if ColonySys.is_npc(renderer.selected_building.colony_id):
		GameState.notify("Das gehört einer fremden Kolonie.", Color(0.8, 0.3, 0.1)); return
	var bname: String = renderer.selected_building.name
	var stx: int = renderer.selected_building.tile_x
	var sty: int = renderer.selected_building.tile_y
	BuildingSys.sell(renderer.selected_building, world)
	renderer.remove_building(stx, sty)
	renderer.selected_building = null; renderer.clear_selection()
	GameState.building_deselected.emit(); GameState.notify(bname + " verkauft!")

func upgrade_selected_building() -> void:
	if renderer.selected_building == null: return
	if ColonySys.is_npc(renderer.selected_building.colony_id):
		GameState.notify("Das gehört einer fremden Kolonie.", Color(0.8, 0.3, 0.1)); return
	if renderer.selected_building.upgrade():
		renderer.add_building(renderer.selected_building)
		GameState.notify("Upgrade auf Stufe %d!" % renderer.selected_building.level); _on_hud_update()
	else: GameState.notify("Upgrade nicht möglich!")

## Feature (Tech Tree): startet den per Tech-Tree freigeschalteten Umbau des
## gerade ausgewählten Gebäudes (siehe BuildingInfo.gd RebuildBtn).
func rebuild_selected_building() -> void:
	if renderer.selected_building == null: return
	var bname: String = renderer.selected_building.name
	if BuildingSys.start_rebuild(renderer.selected_building):
		GameState.notify("Umbau von " + bname + " gestartet!"); _on_hud_update()
	else:
		GameState.notify("Umbau nicht möglich!")

# ── UI-Callbacks ──────────────────────────────────────────────────────────────
func _on_hud_update() -> void:
	var hud := get_node_or_null("GameUI/UIRoot/HUD")
	if hud and hud.has_method("refresh"): hud.call("refresh")

func _on_build_menu_update() -> void:
	var bm := get_node_or_null("GameUI/UIRoot/BuildMenu")
	if bm and bm.has_method("refresh"): bm.call("refresh")

func _on_building_selected(b: BuildingEntity) -> void:
	# v16.0: wer ein Gebäude einer anderen Kolonie anklickt, wechselt automatisch
	# dorthin - Kosten (Upgrade/Umbau) und Anzeige beziehen sich dann auf deren Pool.
	if b != null and ColonySys.has_colony(b.colony_id) and b.colony_id != ColonySys.active_id:
		ColonySys.set_active(b.colony_id)
	var bi := get_node_or_null("GameUI/UIRoot/BuildingInfo")
	if bi and bi.has_method("show_building"): bi.call("show_building", b, self)

func _on_building_deselected() -> void:
	var bi := get_node_or_null("GameUI/UIRoot/BuildingInfo")
	if bi: bi.hide()

## Feature (v11.9, Frettchen-Klick-Interaktion): öffnet das Profil-Panel des
## angeklickten Frettchens (Muster identisch zu _on_building_selected() oben).
func _on_ferret_selected(f) -> void:
	var fp := get_node_or_null("GameUI/UIRoot/FerretProfilePanel")
	if fp and fp.has_method("show_ferret"): fp.call("show_ferret", f)

## Feature (v11.9, Legendäre Frettchen): auffälliges, klickbares Popup bei
## Legendär-Werden (siehe ui/LegendaryToast.gd) - Klick darauf öffnet direkt
## das Profil des betroffenen Frettchens (ferret_selected wird von dort aus
## erneut emittiert).
func _on_ferret_became_legendary(f) -> void:
	var root := get_tree().get_root()
	var lt := root.find_child("LegendaryToast", true, false)
	if lt and lt.has_method("show_toast"): lt.call("show_toast", f)

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
		"RAIL":     hint.text = "Gleis: Klicken/Halten zum Malen  |  ESC = Abbrechen"
		"FIELD":    hint.text = "Klicken/Halten zum Malen  |  ESC = Abbrechen"
		"TERRAIN":  hint.text = "Klicken/Halten auf Terrain  |  ESC = Abbrechen"

# ── Speichern / Laden ─────────────────────────────────────────────────────────
## Feature (v11.4, Speicherslot-System): erzeugt aus dem vom Spieler
## eingegebenen Kolonienamen einen gültigen, eindeutigen Speicherslot-Namen -
## verbotene Dateisystemzeichen werden entfernt, bei Namenskollision mit einem
## bereits vorhandenen Speicherstand wird "(2)", "(3)", ... angehängt.
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

## Feature (v11.4, Speicherslot-System): kompakte Metadaten für die
## Welt-Auswahl-Liste - wird von SaveSystem.save() aufgerufen und oben in
## jeder Speicherdatei abgelegt, damit das Laden-Menü Name/Tag/Jahreszeit/
## Bevölkerung/Seed anzeigen kann, ohne den ganzen Spielstand einzulesen.
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
	for st in deserialize_world_steps(data): (st["fn"] as Callable).call()

## v15.8: Welt-Wiederherstellung in Schritten (Ladebildschirm). deserialize_world() führt sie nacheinander aus.
func deserialize_world_steps(data: Dictionary) -> Array:
	if data.is_empty(): return []
	var steps: Array = [{"label": "Welt wird rekonstruiert …", "weight": 8.0, "fn": func():
		_dw_world(data)
		WaterSys.init(world, world_gen.w, world_gen.h)}]
	steps.append_array(_setup_renderer_steps())
	steps.append({"label": "", "weight": 0.5, "fn": _dw_finish})
	return steps

func _dw_world(data: Dictionary) -> void:
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

func _dw_finish() -> void:
	@warning_ignore("integer_division")
	_cam_target = renderer.tile_to_world3d(world_gen.w/2, world_gen.h/2); _cam_target.y = 0.0
	_apply_camera()
	# Feature (v11.2, First-Person-Modus): Spieler-Frettchen auch beim Laden
	# eines Spielstands sauber positionieren (Speicherstände vor v11.2 kennen
	# keine Spielerposition). Feature (v11.25): dies ist nur noch der
	# FALLBACK für Speicherstände OHNE gespeicherte Spielerposition (vor
	# v11.25) - deserialize_player() (separat aufgerufen, siehe
	# SaveSystem.load_game()) überschreibt das anschliessend mit der
	# tatsächlich gespeicherten Position, falls vorhanden.
	if player != null:
		@warning_ignore("integer_division")
		player.teleport_to(renderer.tile_to_world3d(world_gen.w/2 + 1, world_gen.h/2))
		player.movement_enabled = false
		_player_pos_valid = true

## Feature (v11.25, Positions-Persistenz): Spielerposition + Blickrichtung
## (Yaw) fürs Speichern. Wird separat von serialize_world() gehalten (nicht
## Teil der Tile-Daten), da es sich um Spieler- statt Weltzustand handelt -
## gleiches Muster wie ResourceSys/BuildingSys/etc., die auch je ein eigenes
## Top-Level-Feld im Speicherstand haben (siehe SaveSystem.save()).
func serialize_player() -> Dictionary:
	if player == null: return {}
	var p: Vector3 = player.global_position
	return {"pos": [p.x, p.y, p.z], "yaw": player.rotation.y, "valid": _player_pos_valid}

## Wird NACH deserialize_world() aufgerufen (siehe SaveSystem.load_game()) -
## deserialize_world() setzt bereits einen sinnvollen Fallback-Spawnpunkt
## (für Speicherstände vor v11.25), hier wird das bei Bedarf mit der
## tatsächlich gespeicherten Position überschrieben.
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

# Feature (v13.0, Tutorial-Pausier-Funktion): wird vom TutorialManager
# aufgerufen um die Simulation während des Tutorials zu pausieren/fortsetzen.
#
# Bug-Fix (v13.7, KRITISCH): die alte Version wechselte dafür zusätzlich in
# GameState.State.PAUSED. Genau dieser State steuert aber auch die
# Sichtbarkeit des ECHTEN Pausenmenüs (PauseMenu._on_state_changed) - beim
# Start des Tutorials öffnete sich also automatisch das reguläre Pausenmenü
# (Speed-Buttons, Lautstärke, Speichern, Dev-Mode-Passwortfeld ...) und legte
# sich über die Tutorial-Box. Beide Panels konkurrierten um Klicks, was sich
# für Spieler wie ein kaputtes/nicht anklickbares Menü anfühlte.
#
# Schlimmer noch: GameController._process() UND _unhandled_input() prüfen
# beide zuerst "GameState.is_playing()" (== State.PLAYING) und brechen sonst
# sofort ab. Im State.PAUSED war deshalb während des GESAMTEN Tutorials auch
# jede Welt-Interaktion gesperrt - inklusive der Kachel-Platzierung, die der
# Tutorial-Schritt "Baue deinen ersten Holzfäller" ausdrücklich verlangt.
#
# Die Zeit wird jetzt AUSSCHLIESSLICH über game_speed=0 eingefroren (siehe
# GameController._process(): "dt = delta * GameState.game_speed * ..." wird
# dadurch 0, alle Bedürfnisse/Produktion/Wasser stehen still), OHNE den
# State zu wechseln - State bleibt durchgehend PLAYING, Kamera, Bau-Platzierung
# und Frettchenmodus funktionieren also normal weiter, und das echte
# Pausenmenü bleibt zu (siehe auch GameState.toggle_pause(): sperrt sich
# selbst zusätzlich über den tutorial_active-Guard, falls doch mal ESC o.ä.
# durchkommen sollte).
func set_simulation_paused(paused: bool) -> void:
	GameState.game_speed = 0.0 if paused else 1.0
