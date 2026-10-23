## PlayerController.gd
## Feature (v11.2, First-Person-Modus): steuerbares Spieler-Frettchen.
## Eigenständiger CharacterBody3D, KOMPLETT getrennt vom normalen
## FerretEntity/PopMgr-System - das Spieler-Frettchen ist kein Kolonie-NPC und
## wird nicht vom Bedürfnis-/Arbeits-System verwaltet. Es nutzt dasselbe
## ferret.glb-Modell wie die Kolonie-Frettchen (siehe WorldRenderer3D), damit
## es optisch dazu passt, wenn man von der Iso-Ansicht aus zusieht.
##
## Bewegung per WASD (move_up/down/left/right, bereits im InputMap für die
## Kamera vorhanden, hier zweitverwendet), Umsehen per Mausbewegung (Yaw am
## Body, Pitch an der Kamera). Kollidiert gegen das bestehende Terrain-Trimesh
## (Layer 1) und Gebäude-Kollisionsformen (Layer 2) - dadurch funktioniert
## das Laufen über Hügel/Berge automatisch korrekt, ohne eigene
## Höhenabfrage-Logik.
class_name PlayerController
extends CharacterBody3D

const PLAYER_SPEED: float = 6.0     # Welteinheiten/Sek (TILE_SIZE=2.0 -> ~3 Tiles/Sek)
const GRAVITY:       float = 18.0
const JUMP_VELOCITY: float = 7.5    # Feature (v11.2-Hotfix): Sprung - erlaubt
## Feature (v13.3, First-Person): Bessere Kamera-Positionen für FP-Modus
const FP_CAMERA_HEIGHT: float = 0.5  # Auge des Frettchens über Boden
const FP_CAMERA_FOV: float = 75.0    # Weiteres Sichtfeld für FP
## Feature (v13.6, Mehrfach-Sprung): 1 zusätzlicher Sprung in der Luft erlaubt,
## damit man nicht auf einen exakt getimten Boden-Sprung angewiesen ist.
const MAX_AIR_JUMPS: int = 1
## Feature (v13.6, Coyote-Time): kurzes Zeitfenster nach dem Verlassen einer
## Kante, in dem ein Sprung noch als "Boden-Sprung" zählt (typisches
## Platformer-Pattern, fühlt sich fairer an als exaktes Pixel-Timing).
const COYOTE_TIME: float = 0.12

                                     # Klippen hochzusteigen die hoher als ein
                                     # Tile sind. Wert bewusst moderat - zu hoch
                                     # würde das Frettchen aus der Welt katapultieren.
const MOUSE_SENS:    float = 0.0028
const PITCH_MIN_DEG: float = -75.0
const PITCH_MAX_DEG: float =  75.0
const EYE_HEIGHT:    float = 0.55   # über dem Körper-Ursprung - "Ferret-Cam"

# Feature (v12.1): gleicher Boden-Offset wie bei den NPC-Frettchen
# (WorldRenderer3D.FERRET_Y = 0.35) - fürs Tile-Höhen-Snapping beim
# Laufbefehl (_process_external_walk()), damit das Frettchen-Ich optisch
# genauso "auf" dem Terrain steht wie die NPCs, nicht im Boden versinkt.
const FOOT_OFFSET: float = 0.35

const FERRET_SCENE: PackedScene = preload("res://assets/ferret.glb")
const FERRET_MODEL_SCALE: float = 2.2

# Feature (v12.0, Phase 3): deutlich vom natürlichen Fellton (warmes
# Beige/Tan, siehe ferret.glb) unterscheidbarer Tint fürs Frettchen-Ich -
# kühles Blau, kommt in der natürlichen Fellpalette nicht vor und ist auch
# aus der Distanz in der Iso-Ansicht gut erkennbar. Multiplikativ auf
# albedo_color angewendet (siehe _apply_player_tint()) - das erhält die
# Textur-Details (Schattierung/Muster), färbt aber sichtbar um, statt das
# Modell komplett einfarbig zu machen.
const PLAYER_TINT: Color = Color(0.5, 0.72, 1.05)

var camera: Camera3D = null
var ferret_visual: Node3D = null
var _anim_player: AnimationPlayer = null
var _pitch: float = 0.0

# Feature (v12.2, Phase 4): Zustand fürs "harte Landung"-Tracking (Umhang-
# Boost + PLAYER_HARD_LANDINGS_10-Erfolg). Wird über die Fallhöhe erkannt
# (nicht über die Landegeschwindigkeit) - robuster, da unabhängig vom
# genauen Frame-Timing der Geschwindigkeits-Nullsetzung beim Bodenkontakt.
var _was_on_floor_prev: bool = true
var _fall_start_y: float = 0.0
var _landing_stagger_timer: float = 0.0
var _jumps_remaining: int = MAX_AIR_JUMPS  # Feature (v13.6): verbleibende Luft-Sprünge
var _coyote_timer: float = 0.0             # Feature (v13.6): Coyote-Time-Restdauer

## Wird von GameController gesteuert: nur wenn aktiv, reagiert der
## Controller überhaupt auf Bewegungseingaben/Schwerkraft - sonst bleibt er
## regungslos stehen (z.B. während eines aktiven Minispiels).
var movement_enabled: bool = true

# Feature (v11.26, Mittelklick-Laufbefehl): unabhängig vom First-Person-
# Modus (auch aktiv wenn movement_enabled=false, also während man die
# Iso-Ansicht steuert) - lässt das Frettchen-Ich geradlinig zu einem per
# Mittelklick gewählten Ziel laufen, mit echter Schwerkraft/Bewegungszeit
# und Lauf-Animation, statt zu teleportieren. Bewusst dieselbe simple
# "geradlinig zum Ziel"-Logik wie FerretEntity._move_toward() bei den
# NPC-Frettchen (kein A*/Hindernisumgehung) - siehe Nutzer-Bestätigung.
var _external_walk_active: bool = false
var _external_walk_target: Vector3 = Vector3.ZERO

## Feature (v16.4, Logistik-Update Phase 3): Mitfahren im Zug. Solange `_ride_anchor`
## gesetzt ist, wird der Spieler NICHT per Physik bewegt, sondern jeden Frame an den
## Anker (Lok-Knoten des Zuges) gehängt: Position = Anker + `_ride_local` (gedreht mit
## der geglätteten Zugrichtung, damit scharfe Gleiskurven nicht ruckeln), Blick =
## Zugrichtung + freies Umsehen mit der Maus. Gesteuert vom GameController
## (_board_train()/_exit_train()).
var _ride_anchor: Node3D = null
var _ride_local: Vector3 = Vector3.ZERO
var _ride_yaw_smooth: float = 0.0
var _ride_look_yaw: float = 0.0

# Feature (v12.1): Referenz auf den WorldRenderer3D, von GameController
# gesetzt (siehe GameController._setup_renderer()). Wird NUR für den
# Mittelklick-Laufbefehl gebraucht (Tile-Höhen-Abfrage, siehe
# _process_external_walk()).
var renderer: WorldRenderer3D = null

func _ready() -> void:
	process_priority = 100   # v16.4: nach dem RailRenderer (der die Lok bewegt), sonst hängt die Kamera 1 Frame hinterher
	# Feature (v13.3, First-Person): Kamera für Frettchen-Perspektive optimiert
	collision_layer = 4   # eigener Layer - nichts anderes soll am Spieler kollidieren
	collision_mask  = 1 | 2  # Terrain (1) + Gebäude (2)

	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 0.85
	cs.shape = shape
	cs.position = Vector3(0.0, 0.45, 0.0)
	add_child(cs)

	ferret_visual = FERRET_SCENE.instantiate() as Node3D
	ferret_visual.scale = Vector3.ONE * FERRET_MODEL_SCALE
	_disable_shadows_visual(ferret_visual)
	_apply_player_tint(ferret_visual)
	add_child(ferret_visual)
	_anim_player = ferret_visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
	FerretAnimUtil.ensure_loops(_anim_player)   # v15.4
	_set_clip("Idle")

	camera = Camera3D.new()
	camera.name = "FPCamera"
	camera.position = Vector3(0.0, EYE_HEIGHT, 0.0)
	camera.fov = 80.0
	add_child(camera)

	# Feature (v12.2, Phase 4): Accessoire-Modelle folgen automatisch jeder
	# Änderung der Ausrüstung (Charakter-Editor UND Spielstand-Laden lösen
	# beide dasselbe Signal aus, siehe PlayerAccessories.gd).
	PlayerAccessories.equipment_changed.connect(refresh_accessories)
	refresh_accessories()

func is_riding() -> bool:
	return _ride_anchor != null

## Hängt den Spieler an `anchor` (Lok-Knoten) - `local_pos` ist die Position des
## Körper-Ursprungs relativ zur Lok (Kamera = + EYE_HEIGHT darüber).
func attach_to(anchor: Node3D, local_pos: Vector3) -> void:
	_ride_anchor = anchor
	_ride_local = local_pos
	_ride_look_yaw = 0.0
	_ride_yaw_smooth = anchor.rotation.y
	_external_walk_active = false
	velocity = Vector3.ZERO

## Steigt aus (Teleport an `world_pos`, Blick bleibt wie zuletzt).
func detach(world_pos: Vector3, yaw: float) -> void:
	_ride_anchor = null
	teleport_to(world_pos, yaw)

func _process(delta: float) -> void:
	if _ride_anchor == null: return
	# Anker weg (Zug abgebaut / neue Welt) oder Fahrt offiziell beendet: einfach loslassen,
	# die normale Physik setzt den Spieler wieder auf den Boden.
	if not is_instance_valid(_ride_anchor) or RailSys.riding == null:
		_ride_anchor = null
		return
	_ride_yaw_smooth = lerp_angle(_ride_yaw_smooth, _ride_anchor.rotation.y, 1.0 - exp(-7.0 * delta))
	global_position = _ride_anchor.global_position + Basis(Vector3.UP, _ride_yaw_smooth) * _ride_local
	# Lok-Vorwärts ist +X (siehe RailRenderer) -> Körper-Vorwärts (-Z) = Lok-Yaw - 90 Grad
	rotation.y = _ride_yaw_smooth - PI * 0.5 + _ride_look_yaw
	velocity = Vector3.ZERO

## v16.6: im Frettchenmodus nicht in den Nebel laufen - zurück auf die letzte bekannte Kachel.
var _last_known_pos: Vector3 = Vector3.ZERO
func _fog_guard() -> void:
	if not ExploreSys.enabled: return
	var tx: int = int(floorf(global_position.x / ExploreSys.TILE)); var ty: int = int(floorf(global_position.z / ExploreSys.TILE))
	if ExploreSys.is_revealed(tx, ty):
		_last_known_pos = global_position
	elif _last_known_pos != Vector3.ZERO:
		global_position = _last_known_pos
		velocity = Vector3.ZERO

func _physics_process(delta: float) -> void:
	if _ride_anchor != null:
		velocity = Vector3.ZERO
		return
	_fog_guard()
	# Feature (v11.26): Laufbefehl hat Vorrang und läuft UNABHAENGIG von
	# movement_enabled (der ja normalerweise FP-Steuerung sperrt, während
	# man in der Iso-Ansicht ist - genau DANN soll der Laufbefehl aber
	# funktionieren).
	if _external_walk_active:
		_process_external_walk(delta)
		return
	if not movement_enabled:
		velocity = Vector3.ZERO
		return
	var currently_on_floor: bool = is_on_floor()
	if not currently_on_floor:
		if _was_on_floor_prev:
			_fall_start_y = global_position.y  # Beginn eines Falls/Sprungs
		velocity.y -= GRAVITY * delta
	else:
		if not _was_on_floor_prev:
			# Feature (v12.2, Phase 4): gerade gelandet - Fallhöhe seit
			# Absprung prüfen. Schwelle (1.8) bewusst grösser als die
			# rechnerisch max. per Sprung erreichbare Höhe (1.56, siehe
			# JUMP_VELOCITY-Kommentar oben) - ein normaler Sprung löst die
			# harte Landung NICHT aus, nur ein tatsächlicher Sturz von einer
			# höheren Klippe.
			var fall_dist: float = _fall_start_y - global_position.y
			if fall_dist > 1.8:
				AchievementSys.report_player_hard_landing()
				# Umhang-Boost: keine Verlangsamung bei harter Landung.
				if PlayerAccessories.get_boost_flat("soft_landing_flat") <= 0.0:
					_landing_stagger_timer = 1.0
		velocity.y = 0.0
		_jumps_remaining = MAX_AIR_JUMPS  # Feature (v13.6): Luft-Sprünge bei Landung auffüllen
		_coyote_timer = COYOTE_TIME        # Feature (v13.6): Coyote-Fenster neu starten

	if not currently_on_floor:
		_coyote_timer -= delta

	# Bug-Fix (v11.2b): Sprung nutzt jetzt die eigene "fp_jump"-Action
	# (Leertaste) statt "ui_accept". "ui_accept" wurde intern auch vom
	# Godot-UI-System verarbeitet (fokussierter Button = Space = Klick),
	# was zum ungewollten Öffnen des Pause-Menüs führte. "fp_jump" ist
	# exklusiv, wird nicht vom UI-System abgefangen.
	#
	# Bug-Fix (v13.6, KRITISCH): Dieser Block lag vorher INNERHALB des
	# "else"-Zweigs von "if not currently_on_floor" - das bedeutet, er
	# wurde nur ausgeführt, wenn der Spieler GERADE AUF DEM BODEN steht.
	# Dadurch war es unmöglich, in der Luft zu springen (Doppel-/Multi-Jump
	# war komplett unerreichbar) und auch die Coyote-Time (kurzes
	# Sprung-Fenster direkt nach dem Verlassen einer Kante) griff nie.
	# Jetzt liegt der Check ausserhalb beider Zweige und wird JEDEN Frame
	# geprüft, egal ob am Boden oder in der Luft.
	if Input.is_action_just_pressed("fp_jump"):
		var can_jump: bool = currently_on_floor or _coyote_timer > 0.0 or _jumps_remaining > 0
		if can_jump:
			velocity.y = JUMP_VELOCITY * PlayerAccessories.get_boost_mult("jump_height_mult")
			if not currently_on_floor:
				# Boden-Sprung nutzt weder Coyote noch Luft-Sprung-Kontingent;
				# nur ein echter Sprung "aus der Luft heraus" (Coyote-Fenster
				# ODER Luft-Sprung) verbraucht eine Ladung.
				if _coyote_timer > 0.0:
					_coyote_timer = 0.0
				else:
					_jumps_remaining -= 1
			AchievementSys.report_player_jump()
			get_viewport().set_input_as_handled()
	_was_on_floor_prev = currently_on_floor
	if _landing_stagger_timer > 0.0:
		_landing_stagger_timer -= delta

	var move := Vector3.ZERO
	if Input.is_action_pressed("move_up"):    move -= transform.basis.z
	if Input.is_action_pressed("move_down"):  move += transform.basis.z
	if Input.is_action_pressed("move_left"):  move -= transform.basis.x
	if Input.is_action_pressed("move_right"): move += transform.basis.x
	var moving: bool = move.length() > 0.01
	if moving:
		move = move.normalized()
	# Feature (v12.2, Phase 4): Zylinder- (Tempo), Schal- (Winter-Immunität)
	# und Landungs-Stagger-Boost/Malus alle multiplikativ verknüpft.
	var speed_mult: float = PlayerAccessories.get_boost_mult("move_speed_mult") * _winter_speed_mult()
	if _landing_stagger_timer > 0.0: speed_mult *= 0.4
	velocity.x = move.x * PLAYER_SPEED * speed_mult
	velocity.z = move.z * PLAYER_SPEED * speed_mult
	var pos_before: Vector3 = global_position
	move_and_slide()

	_set_clip("Run" if moving else "Idle")
	# Sichtkörper läuft "voraus" in Bewegungsrichtung - bei reinem
	# Stillstehen behält er die zuletzt per Maus gesetzte Blickrichtung
	# (rotation.y des Body selbst, siehe apply_look()).

	# Feature (v12.2, Phase 4): Fortschritts-Tracking für die
	# Frettchen-Ich-Erfolge (Weitgereist/Kolonieoberhaupt/Entdecker) - NUR
	# während eines echten Frettchenmodus-Aufenthalts (movement_enabled),
	# nicht während eines Mittelklick-Laufbefehls in der Iso-Ansicht (siehe
	# Kommentar bei _process_external_walk() - andere Bewegungsart, zählt
	# bewusst nicht zu "im Frettchenmodus zurückgelegt").
	if renderer != null:
		var dist_moved: float = pos_before.distance_to(global_position)
		var tile: Vector2i = renderer.world3d_to_tile(global_position)
		AchievementSys.report_player_tick(delta, dist_moved, tile)

## Feature (v12.2, Phase 4): Schal-Boost negiert den winterlichen
## Tempo-Malus. Malus bewusst neu eingeführt (gab es vorher nicht) - erst
## dadurch hat der Schal-Boost überhaupt eine Wirkung.
func _winter_speed_mult() -> float:
	if SeasonSys.get_season_name() == "Winter" and PlayerAccessories.get_boost_flat("winter_immunity_flat") <= 0.0:
		return 0.75
	return 1.0

## Wird von GameController bei jeder gefangenen InputEventMouseMotion
## aufgerufen, während der First-Person-Modus aktiv ist und kein Minispiel
## läuft. Yaw dreht den ganzen Body (= auch die Laufrichtung), Pitch nur die
## Kamera - klassisches FPS-Schema.
func apply_look(rel: Vector2) -> void:
	if _ride_anchor != null:
		_ride_look_yaw -= rel.x * MOUSE_SENS      # im Zug: Blick relativ zur Fahrtrichtung
	else:
		rotation.y -= rel.x * MOUSE_SENS
	_pitch = clampf(_pitch - rel.y * MOUSE_SENS,
		deg_to_rad(PITCH_MIN_DEG), deg_to_rad(PITCH_MAX_DEG))
	camera.rotation.x = _pitch

## Setzt den Spieler an eine Tile-Position (Weltkoordinaten kommen von
## WorldRenderer3D.tile_to_world3d()). Ein kleiner Y-Versatz nach oben sorgt
## dafür, dass der Spieler sicher AUF dem Terrain landet (fällt per
## Schwerkraft den letzten kurzen Weg), statt bei ungenauer Höhe im Boden
## stecken zu bleiben.
## v15.6: Clip wechseln (weich überblendet); fehlt der Clip (altes Modell), Run/Stopp wie früher.
func _set_clip(n: String) -> void:
	if _anim_player == null: return
	if not _anim_player.has_animation(n):
		if n == "Idle":
			if _anim_player.is_playing(): _anim_player.stop(true)
		elif _anim_player.has_animation("Run") and not _anim_player.is_playing():
			_anim_player.play("Run")
		return
	if _anim_player.current_animation != n or not _anim_player.is_playing():
		_anim_player.play(n, 0.15)

func teleport_to(world_pos: Vector3, yaw: float = 0.0) -> void:
	global_position = world_pos + Vector3(0.0, 1.2, 0.0)
	velocity = Vector3.ZERO
	rotation.y = yaw
	_pitch = 0.0
	_external_walk_active = false  # Bug-Vorbeugung: ein Teleport überschreibt einen laufenden Laufbefehl
	if camera: camera.rotation.x = 0.0

## Feature (v11.26, Mittelklick-Laufbefehl): startet eine geradlinige
## Laufbewegung zum Ziel (XZ-Ebene, Höhe folgt der normalen Schwerkraft/
## Terrain-Kollision in _process_external_walk()). Ein bereits laufender
## Befehl wird SOFORT durch den neuen ersetzt (Nutzer-Bestätigung: "dann
## umlenken" statt den Klick zu ignorieren).
func start_walk_to(world_pos: Vector3) -> void:
	_external_walk_target = world_pos
	_external_walk_active = true

## Feature (v11.26): wird von GameController._toggle_fp_mode() beim
## Betreten des First-Person-Modus aufgerufen - ein evtl. noch laufender
## Mittelklick-Laufbefehl darf die WASD-Steuerung NICHT weiter überstimmen
## (siehe _physics_process(): _external_walk_active hat sonst Vorrang vor
## movement_enabled).
func cancel_walk() -> void:
	_external_walk_active = false

## Wird jeden Physik-Frame aufgerufen, während ein Laufbefehl aktiv ist -
## bewegt den Spieler geradlinig (XZ) zum Ziel. Stoppt automatisch, sobald
## das Ziel (grob) erreicht ist.
##
## Bug-Fix (v12.1): die ursprüngliche Version (v11.26/v12.0) nutzte
## move_and_slide() mit echter Schwerkraft/Kollision gegen das
## Terrain-Trimesh, plus einen Sprungimpuls als "Step-Up-Assist" für
## Höhenstufen (HEIGHT_SCALE=1.2, senkrechte Kollisionskanten, siehe
## WorldRenderer3D._col_body) - das hat sich laut Nutzer-Test aber weiterhin
## an Stufen aufgehängt (vermutlich reagiert is_on_floor()/die
## Kollisionsnormalen-Erkennung bei den steilen 90°-Kanten nicht zuverlässig
## genug, um den Sprungimpuls im richtigen Frame auszulösen). Nutzeranfrage:
## "mache es einfach so, dass es funktioniert wie bei den NPC-Frettchen".
## NPC-Frettchen (FerretEntity._move_toward() + WorldRenderer3D) nutzen
## UEBERHAUPT KEINE Physik/Kollision für ihre Bewegung - sie sind reine
## Positions-Daten (Vector2), deren Y-Höhe jeden Frame direkt aus der
## Tile-Höhe unter der aktuellen (gerundeten) Position gelesen wird
## (`fn.position.y = tile_to_world3d(int(fe.pos.x), int(fe.pos.y)).y + ...`)
## - dadurch "springt"/"steigt" ihre Darstellung Höhenstufen automatisch
## mit, ganz ohne Schwerkraft-/Kollisions-Simulation. Repliziert dasselbe
## Prinzip hier 1:1 fürs Frettchen-Ich während eines Laufbefehls: KEIN
## move_and_slide(), KEINE Schwerkraft - global_position wird direkt
## gesetzt, X/Z linear zum Ziel bewegt, Y = Tile-Höhe an der aktuellen
## Position (per renderer.tile_to_world3d(), s.o.). Funktioniert
## zwangsläufig genauso zuverlässig wie bei den NPCs, weil es exakt
## dieselbe Methode ist.
func _process_external_walk(delta: float) -> void:
	var to_target: Vector3 = _external_walk_target - global_position
	to_target.y = 0.0
	var dist: float = to_target.length()
	if dist < 0.15:
		_external_walk_active = false
		velocity = Vector3.ZERO
		_set_clip("Idle")
		return
	var dir: Vector3 = to_target / dist  # normalisiert (dist > 0.15, keine Div/0-Gefahr)
	# Feature (v12.2, Phase 4): Zylinder-Tempo-Boost gilt auch für den
	# Laufbefehl (zählt aber bewusst NICHT zu den Frettchen-Ich-Erfolgen,
	# siehe Kommentar im FP-Bewegungszweig oben).
	var step: float = PLAYER_SPEED * PlayerAccessories.get_boost_mult("move_speed_mult") * delta
	if step > dist: step = dist
	var new_pos: Vector3 = global_position + dir * step
	if renderer != null:
		var tv: Vector2i = renderer.world3d_to_tile(new_pos)
		var ground_y: float = renderer.tile_to_world3d(tv.x, tv.y).y
		new_pos.y = ground_y + FOOT_OFFSET
	global_position = new_pos
	# Gleiche Yaw-Konvention wie bei den NPC-Frettchen (WorldRenderer3D:
	# "fn.rotation.y = atan2(dir.x, dir.y) + FERRET_ROT_OFFSET", wobei deren
	# 2D dir.x/dir.y exakt den 3D-Weltachsen X/Z entsprechen, siehe
	# WorldRenderer3D.tile_to_world3d()) - dasselbe ferret.glb-Modell, daher
	# dieselbe Formel für korrekte Blickrichtung.
	rotation.y = atan2(dir.x, dir.z)
	_set_clip("Run")

## Feature (v12.2, Phase 4): hängt für jeden belegten Slot in
## PlayerAccessories.equipped das passende Accessoire-Modell direkt an
## ferret_visual (das bereits mit FERRET_MODEL_SCALE=2.2 skaliert ist) - exakt
## dasselbe Prinzip wie WorldRenderer3D._attach_ferret_accessories() bei
## Legendären Frettchen (KEINE Gegen-Skalierung, Position/Rotation direkt aus
## FerretAccessories.ACCESSORIES übernommen - siehe die dortige
## Positionierungs-Historie/-Messung). Wird bei jeder Ausrüstungs-Änderung
## automatisch über PlayerAccessories.equipment_changed neu aufgerufen.
func refresh_accessories() -> void:
	if ferret_visual == null: return
	for c in ferret_visual.get_children():
		if str(c.name).begins_with("AccessoryItem_"):
			c.queue_free()
	for slot in PlayerAccessories.equipped:
		var aid: String = str(PlayerAccessories.equipped[slot])
		if aid == "": continue
		var ad: Dictionary = FerretAccessories.get_accessory(aid)
		if ad.is_empty(): continue
		var scene: PackedScene = load(str(ad.get("glb", "")))
		if scene == null: continue
		var acc_inst := scene.instantiate() as Node3D
		if acc_inst == null: continue
		acc_inst.name = "AccessoryItem_" + aid
		_disable_shadows_visual(acc_inst)
		acc_inst.position = ad.get("offset", Vector3.ZERO) as Vector3
		acc_inst.rotation.x = float(ad.get("rot_x", 0.0))
		acc_inst.rotation.y = float(ad.get("rot_y", 0.0))
		ferret_visual.add_child(acc_inst)

func _disable_shadows_visual(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_disable_shadows_visual(c)

## Feature (v12.0, Phase 3): färbt alle MeshInstance3D-Oberflächen unter
## "n" per Multiplikation mit PLAYER_TINT ein. WICHTIG: nutzt
## set_surface_override_material() mit einer DUPLIZIERTEN Material-Resource
## statt die material-Resource direkt zu verändern - Godot cached
## importierte glTF-Materialien u.U. resourcenübergreifend, ein direktes
## Verändern könnte sonst versehentlich auch die NPC-Frettchen (die
## dasselbe ferret.glb benutzen) mitfärben. Wird nur einmal in _ready()
## aufgerufen, BEVOR später (Phase 4) Accessoires als Kind-Nodes angehängt
## werden - färbt dadurch bewusst nur das Basis-Fell-Modell, nicht
## Accessoires.
func _apply_player_tint(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var src_mat: Material = mi.get_active_material(i)
				var new_mat: Material = (src_mat.duplicate() as Material) if src_mat else StandardMaterial3D.new()
				if new_mat is BaseMaterial3D:
					var bm := new_mat as BaseMaterial3D
					bm.albedo_color = bm.albedo_color * PLAYER_TINT
				mi.set_surface_override_material(i, new_mat)
	for c in n.get_children():
		_apply_player_tint(c)
