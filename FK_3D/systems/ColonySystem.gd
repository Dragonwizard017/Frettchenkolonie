## ColonySystem.gd
## Feature (v16.0, Kolonie-Fundament / Logistik-Update Phase 0+1): EINE Karte,
## MEHRERE Kolonien. Eine Kolonie ist ein Rathaus (btype "TOWN_HALL") plus alles,
## was in seinem Gebietsradius steht. Bewusst als Schicht ÜBER dem Bezirkssystem
## (DistrictSystem) gebaut: jeder Bezirk und jedes Gebäude/Frettchen trägt eine
## colony_id; Bezirke verschiedener Kolonien sind nie verbunden.
##
## Zuordnung Kachel -> Kolonie: das NÄCHSTE Rathaus, dessen Radius die Kachel
## noch umfasst (colony_of_tile()). Liegt eine Kachel in keinem Gebiet, ist sie
## "Niemandsland" (-1) - dort darf (ausser Dev-Modus) nicht gebaut werden.
##
## Ressourcen: jede Kolonie hat einen eigenen Pool (siehe ResourceSystem.pools).
## "Aktiv" ist die Kolonie, die der Spieler gerade ansieht und für die er baut
## (HUD, Baumenü, Kosten). Die Simulation läuft für ALLE Kolonien gleichzeitig.
extends Node

signal active_changed(colony_id: int)

const TERRITORY_RADIUS: float = 16.0    # Standard-Gebietsradius (Tiles) um ein Rathaus
const MIN_HALL_DISTANCE: float = 20.0   # Mindestabstand zwischen zwei Rathäusern (Tiles)
const MIN_FERRETS_TO_FOUND: int = 5     # so viele Frettchen muss die Gründer-Kolonie mindestens haben
const SETTLERS: int = 3                 # so viele Frettchen ziehen als Siedler mit
const NPC_RADIUS: float = 10.0          # Gebietsradius einer Nachbarkolonie

const COLONY_COLORS: Array = [
	[0.35, 0.65, 0.95], [0.95, 0.62, 0.30], [0.55, 0.85, 0.45],
	[0.85, 0.50, 0.85], [0.95, 0.85, 0.35], [0.40, 0.85, 0.80],
]
const COLONY_NAMES: Array = [
	"Nordhain", "Sonnental", "Eichenfurt", "Mooshaus", "Birkenau",
	"Fellbach", "Pfotenstein", "Schnüffelau", "Buchenhain", "Quellwiese",
]

## id (int) -> {"name": String, "color": Array[3], "hall_x": int, "hall_y": int,
##              "radius": float, "founded_day": int}
var colonies: Dictionary = {}
var active_id: int = 0
var next_id: int = 1
## true, wenn ein Spielstand ohne Kolonie-Daten (vor v16.0) geladen wurde - der
## GameController legt dann nachträglich ein Rathaus für Kolonie 0 an.
var needs_migration: bool = false

func init() -> void:
	colonies = {0: _make_colony("Hauptkolonie", -1, -1, 0, 0)}
	active_id = 0
	next_id = 1
	needs_migration = false

func _make_colony(cname: String, hx: int, hy: int, day: int, color_idx: int) -> Dictionary:
	return {
		"name": cname,
		"color": (COLONY_COLORS[color_idx % COLONY_COLORS.size()] as Array).duplicate(),
		"hall_x": hx, "hall_y": hy,
		"radius": TERRITORY_RADIUS,
		"founded_day": day,
	}

func ids() -> Array:
	var r: Array = colonies.keys()
	r.sort()
	return r

func count() -> int:
	return colonies.size()

func has_colony(id: int) -> bool:
	return colonies.has(id)

func get_name_of(id: int) -> String:
	return str((colonies.get(id, {}) as Dictionary).get("name", "Unbekannt"))

func get_color_of(id: int) -> Color:
	var c: Array = (colonies.get(id, {}) as Dictionary).get("color", [0.7, 0.7, 0.7]) as Array
	return Color(float(c[0]), float(c[1]), float(c[2]))

func get_radius(id: int) -> float:
	return float((colonies.get(id, {}) as Dictionary).get("radius", TERRITORY_RADIUS))

## Kachel des Rathauses; (-1,-1), solange noch keines gesetzt wurde.
func get_hall_tile(id: int) -> Vector2i:
	var c: Dictionary = colonies.get(id, {}) as Dictionary
	return Vector2i(int(c.get("hall_x", -1)), int(c.get("hall_y", -1)))

func set_hall(id: int, tx: int, ty: int) -> void:
	if not colonies.has(id): return
	(colonies[id] as Dictionary)["hall_x"] = tx
	(colonies[id] as Dictionary)["hall_y"] = ty

func set_radius(id: int, r: float) -> void:
	if not colonies.has(id): return
	(colonies[id] as Dictionary)["radius"] = r

func rename(id: int, new_name: String) -> void:
	var t: String = new_name.strip_edges()
	if t == "" or not colonies.has(id): return
	(colonies[id] as Dictionary)["name"] = t

## Legt eine neue Kolonie an und gibt ihre ID zurück (Pool/Gebäude/Frettchen
## legt der Aufrufer an, siehe GameController._found_colony()).
func register_colony(cname: String, hx: int, hy: int, day: int, npc: bool = false) -> int:
	var id: int = next_id
	next_id += 1
	colonies[id] = _make_colony(cname, hx, hy, day, id)
	if npc:
		# Feature (v16.7, Nachbarn): fremde Kolonie - kleineres Gebiet, graublaue Farbe, wird nicht vom Spieler gesteuert
		(colonies[id] as Dictionary)["npc"] = true
		(colonies[id] as Dictionary)["radius"] = NPC_RADIUS
		(colonies[id] as Dictionary)["color"] = [0.62, 0.55, 0.78]
	return id

## Feature (v16.7, Nachbarn): ist das eine fremde (nicht vom Spieler geführte) Kolonie?
func is_npc(id: int) -> bool:
	return bool((colonies.get(id, {}) as Dictionary).get("npc", false))

## Macht aus einer Nachbarkolonie eine eigene (Annexion) bzw. umgekehrt.
func set_npc(id: int, v: bool) -> void:
	if not colonies.has(id): return
	(colonies[id] as Dictionary)["npc"] = v
	if not v:
		(colonies[id] as Dictionary)["radius"] = TERRITORY_RADIUS
		(colonies[id] as Dictionary)["color"] = (COLONY_COLORS[id % COLONY_COLORS.size()] as Array).duplicate()

## Nur die Kolonien des Spielers (für Umschalter, Kolonien-Fenster, Zähler).
func player_ids() -> Array:
	var r: Array = []
	for id in ids():
		if not is_npc(int(id)): r.append(int(id))
	return r

func player_count() -> int:
	return player_ids().size()

func pick_new_name() -> String:
	var used: Array = []
	for id in colonies:
		used.append(get_name_of(int(id)))
	for n in COLONY_NAMES:
		if not (str(n) in used): return str(n)
	return "Kolonie %d" % (colonies.size() + 1)

## Wechselt die Kolonie, die der Spieler gerade ansieht/für die er baut.
func set_active(id: int) -> void:
	if not colonies.has(id) or id == active_id or is_npc(id): return
	active_id = id
	ResourceSys.use_colony(id)
	active_changed.emit(id)
	GameState.hud_update_requested.emit()
	GameState.build_menu_update_requested.emit()

## Welcher Kolonie gehört die Kachel? Nächstes Rathaus, dessen Radius sie noch
## umfasst; -1 = Niemandsland.
func colony_of_tile(tx: int, ty: int) -> int:
	var best: int = -1
	var best_d: float = INF
	for id in colonies:
		var c: Dictionary = colonies[id] as Dictionary
		var hx: int = int(c.get("hall_x", -1))
		if hx < 0: continue
		var d: float = Vector2(float(hx), float(int(c.get("hall_y", -1)))).distance_to(Vector2(float(tx), float(ty)))
		if d <= float(c.get("radius", TERRITORY_RADIUS)) and d < best_d:
			best_d = d; best = int(id)
	return best

## Leerer String = hier darf ein neues Rathaus (= neue Kolonie) stehen,
## sonst der Grund als Spielertext.
func can_found_at(tx: int, ty: int) -> String:
	for id in colonies:
		var c: Dictionary = colonies[id] as Dictionary
		var hx: int = int(c.get("hall_x", -1))
		if hx < 0: continue
		var d: float = Vector2(float(hx), float(int(c.get("hall_y", -1)))).distance_to(Vector2(float(tx), float(ty)))
		if d < MIN_HALL_DISTANCE:
			return "Zu nah an '%s'! Neue Kolonien brauchen mindestens %d Kacheln Abstand zu jedem Rathaus." % [get_name_of(int(id)), int(MIN_HALL_DISTANCE)]
	return ""

func serialize() -> Dictionary:
	return {"colonies": colonies.duplicate(true), "active_id": active_id, "next_id": next_id}

func deserialize(data) -> void:
	if not (data is Dictionary) or (data as Dictionary).is_empty():
		# Spielstand vor v16.0: eine einzige Kolonie, Rathaus wird nachgerüstet.
		init()
		needs_migration = true
		return
	var d: Dictionary = data as Dictionary
	# JSON kennt nur String-Keys -> Rückkonvertierung auf int (gleiche Falle wie
	# bei DistrictSys.deserialize()).
	var raw: Dictionary = d.get("colonies", {}) as Dictionary
	colonies = {}
	for k in raw:
		var c: Dictionary = (raw[k] as Dictionary).duplicate(true)
		c["hall_x"] = int(c.get("hall_x", -1)); c["hall_y"] = int(c.get("hall_y", -1))
		c["radius"] = float(c.get("radius", TERRITORY_RADIUS))
		c["founded_day"] = int(c.get("founded_day", 0))
		c["npc"] = bool(c.get("npc", false))
		colonies[int(k)] = c
	if colonies.is_empty():
		init(); needs_migration = true; return
	next_id = int(d.get("next_id", colonies.size()))
	active_id = int(d.get("active_id", 0))
	if not colonies.has(active_id): active_id = 0
	needs_migration = false
