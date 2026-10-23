## RailSystem.gd
## Feature (v16.2, Logistik-Update Phase 2): Gleisnetz, Linien und Güterzüge.
##
## - Gleise liegen auf dem Kachelraster (`rails`: Schlüssel -> true). Bahnhöfe und Depots
##   (Gebäude btype "STATION" / "DEPOT") sind selbst Knoten des Netzes.
## - Pfadsuche: AStar2D über alle Knoten; zwei Nachbarkacheln sind verbunden, wenn der
##   Höhenunterschied <= MAX_SLOPE ist (steile Hänge: Erde aufschütten / sprengen).
## - Linien: Haltestellen (Bahnhöfe) + Frachten ("res von Halt A nach Halt B").
##   Ein Zug fährt die Halte reihum an: erst alles entladen, was dort hin gehört,
##   dann laden, was dort abfährt. Be-/Entladen läuft direkt gegen den Ressourcen-Pool
##   der Kolonie des Bahnhofs (so verbindet die Bahn die Kolonien).
## - Kein Zug-Zug-Kollisionssystem in v1 (Signale/Ausweichstellen kommen später).
extends Node

const MAX_SLOPE: float = 0.7                  # max. Höhenunterschied (Höheneinheiten) zwischen Nachbarkacheln
const RAIL_COSTS: Dictionary = {"PLANKS": 1, "IRON": 1}                     # je Gleiskachel
const TRAIN_COSTS: Dictionary = {"IRON_BARS": 8, "TOOLS": 8, "PLANKS": 15}  # je Zug
const TRAIN_SPEED: float = 3.0                # Kacheln pro Sekunde
const TRAIN_CAPACITY_PER_WAGON: float = 30.0
const DWELL_TIME: float = 2.5
const RETRY_TIME: float = 2.0
const DIRS: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

# ── Feature (v16.8, Lokführer-Modus): der Mitfahrer kann selbst fahren ───────
# [W] = Gas, [S] = Bremse, [T] = Automatik zurück. Bonus des Selbstfahrens:
# schnell angefahrene Halte ("pünktlich") verkürzen den Stopp, selbst gefahrene
# Ablieferungen beim Nachbarn bringen 25 % mehr Ruf.
const MANUAL_ACCEL: float = 1.6          # Kacheln/s² anfahren mit + speed
const MANUAL_BRAKE: float = 3.2          # Kacheln/s² bremsen mit [S]
const PUNCTUAL_SPEED_FRAC: float = 0.60  # >= 60 % Streckentempo bei Ankunft = "pünktlich"
const PUNCTUAL_DWELL_FACTOR: float = 0.5 # "pünktlich" = halbe Haltezeit
const DRIVER_REP_BONUS: float = 1.25     # Ruf-Multiplikator für selbst gefahrene Lieferungen
const LINE_COLORS: Array = [
	[0.90, 0.35, 0.30], [0.30, 0.65, 0.95], [0.95, 0.80, 0.30],
	[0.45, 0.80, 0.45], [0.80, 0.50, 0.90], [0.95, 0.60, 0.25],
]

var world: Array = []                 # Referenz auf die Spielwelt (vom GameController gesetzt)
var rails: Dictionary = {}            # Schlüssel (int) -> true
var lines: Dictionary = {}            # id -> {"name","color","stops":[key],"shipments":[{res,from,to}],"delivered":float}
var trains: Array = []                # TrainEntity
var station_names: Dictionary = {}    # Schlüssel -> Name
var next_line_id: int = 1
var next_train_id: int = 1
var riding: TrainEntity = null        # v16.4: Zug, in dem der Spieler gerade (Ich-Perspektive) mitfährt
var dirty: Dictionary = {}            # Schlüssel -> true: Kacheln, deren Gleis-Mesh neu gebaut werden muss
var all_dirty: bool = false
var _astar: AStar2D = AStar2D.new()
var _graph_sig: String = "#"

# ── Schlüssel ────────────────────────────────────────────────────────────────
static func key(tx: int, ty: int) -> int: return tx * 4096 + ty
static func key_x(k: int) -> int: return k >> 12
static func key_y(k: int) -> int: return k & 4095
static func key_vec(k: int) -> Vector2i: return Vector2i(k >> 12, k & 4095)

func init() -> void:
	riding = null
	_t_key_prev = false
	rails = {}; lines = {}; trains = []; station_names = {}
	next_line_id = 1; next_train_id = 1
	dirty = {}; all_dirty = true
	_astar.clear(); _graph_sig = "#"

# ── Welt-Abfragen ────────────────────────────────────────────────────────────
func _in_bounds(tx: int, ty: int) -> bool:
	return not world.is_empty() and tx >= 0 and ty >= 0 and tx < world.size() and ty < (world[0] as Array).size()

func height_at(tx: int, ty: int) -> float:
	if not _in_bounds(tx, ty): return 0.0
	return float(((world[tx] as Array)[ty] as Dictionary).get("height", 0.0))

func has_rail(tx: int, ty: int) -> bool:
	return rails.has(key(tx, ty))

## Gebäude (Bahnhof/Depot) auf der Kachel, sonst null.
func rail_building_at(tx: int, ty: int):
	if not _in_bounds(tx, ty): return null
	var bb = ((world[tx] as Array)[ty] as Dictionary).get("building")
	if bb != null and ((bb as BuildingEntity).btype == "STATION" or (bb as BuildingEntity).btype == "DEPOT"):
		if not (bb as BuildingEntity).is_under_construction: return bb
	return null

## Ist die Kachel ein Knoten des Netzes (Gleis oder fertiger Bahnhof/Depot)?
func is_node(tx: int, ty: int) -> bool:
	return rails.has(key(tx, ty)) or rail_building_at(tx, ty) != null

func slope_ok(ax: int, ay: int, bx: int, by: int) -> bool:
	return absf(height_at(ax, ay) - height_at(bx, by)) <= MAX_SLOPE

## Leerer String = Gleis darf hier liegen, sonst der Grund (Spielertext).
func can_place_rail(tx: int, ty: int) -> String:
	if not _in_bounds(tx, ty): return "Außerhalb der Karte."
	if not ExploreSys.is_revealed(tx, ty): return "Dieses Gebiet ist noch unerforscht."
	var tile: Dictionary = (world[tx] as Array)[ty] as Dictionary
	if rails.has(key(tx, ty)): return "Hier liegt schon ein Gleis."
	var biome: String = str(tile.get("biome", ""))
	if biome == "WATER": return "Auf Wasser geht nur mit Brücken (kommen später)."
	if biome == "MOUNTAIN": return "Im Gebirge nicht möglich (Tunnel kommen später)."
	if tile.get("building") != null: return "Hier steht ein Gebäude!"
	if FarmSys.has_field(tx, ty): return "Hier liegt ein Feld."
	if tile.get("resource_node") != null: return "Hier ist ein Vorkommen im Weg (Baum/Stein/Erz)."
	for d in DIRS:
		var nx: int = tx + (d as Vector2i).x; var ny: int = ty + (d as Vector2i).y
		if is_node(nx, ny) and not slope_ok(tx, ty, nx, ny):
			return "Zu steil! Erde aufschütten oder den Hang absprengen (max. %.1f Höhenunterschied zum Nachbargleis)." % MAX_SLOPE
	return ""

func place_rail(tx: int, ty: int) -> void:
	rails[key(tx, ty)] = true
	_rails_version += 1
	if _in_bounds(tx, ty):
		var tile: Dictionary = (world[tx] as Array)[ty] as Dictionary
		tile["path"] = null   # ein Gleis ersetzt einen Weg auf derselben Kachel
	_mark_dirty(tx, ty)

func remove_rail(tx: int, ty: int) -> bool:
	if not rails.erase(key(tx, ty)): return false
	_rails_version += 1
	_mark_dirty(tx, ty)
	return true

func _mark_dirty(tx: int, ty: int) -> void:
	dirty[key(tx, ty)] = true
	for d in DIRS: dirty[key(tx + (d as Vector2i).x, ty + (d as Vector2i).y)] = true

## Nach Geländeänderung (Aufschütten/Sprengen) müssen alle Gleis-Meshes neu.
func terrain_changed() -> void:
	all_dirty = true
	_rails_version += 1   # Steigungen können sich geändert haben -> Graph neu

## Welche Nachbarn sind mit der Kachel verbunden? (für die Gleis-Darstellung)
func connections(tx: int, ty: int) -> Array:
	var out: Array = []
	for d in DIRS:
		var nx: int = tx + (d as Vector2i).x; var ny: int = ty + (d as Vector2i).y
		if is_node(nx, ny) and slope_ok(tx, ty, nx, ny): out.append(d)
	return out

# ── Bahnhöfe / Depots ────────────────────────────────────────────────────────
func get_buildings_of(btype: String) -> Array:
	var out: Array = []
	for b in BuildingSys.buildings:
		var be: BuildingEntity = b
		if be.btype == btype and not be.is_under_construction: out.append(be)
	return out

func get_station_name(b: BuildingEntity) -> String:
	var k: int = key(b.tile_x, b.tile_y)
	if not station_names.has(k):
		var prefix: String = ColonySys.get_name_of(b.colony_id) + "-Bahnhof"
		var n: int = 1
		for v in station_names.values():
			if str(v).begins_with(prefix): n += 1
		station_names[k] = prefix if n == 1 else "%s %d" % [prefix, n]
	return str(station_names[k])

func station_at_key(k: int):
	var v: Vector2i = key_vec(k)
	var bb = rail_building_at(v.x, v.y)
	if bb != null and (bb as BuildingEntity).btype == "STATION": return bb
	return null

# ── Graph + Pfadsuche ────────────────────────────────────────────────────────
func _signature() -> String:
	var s: PackedStringArray = []
	for b in BuildingSys.buildings:
		var be: BuildingEntity = b
		if (be.btype == "STATION" or be.btype == "DEPOT") and not be.is_under_construction:
			s.append(str(key(be.tile_x, be.tile_y)))
	return ",".join(s)

var _rails_version: int = 0

func _ensure_graph() -> void:
	var sig: String = _signature() + "|" + str(_rails_version)
	if sig == _graph_sig: return
	_graph_sig = sig
	_astar.clear()
	var ids: Array = []
	for k in rails: ids.append(int(k))
	for b in get_buildings_of("STATION") + get_buildings_of("DEPOT"):
		var kk: int = key((b as BuildingEntity).tile_x, (b as BuildingEntity).tile_y)
		if not ids.has(kk): ids.append(kk)
	for id in ids:
		var v: Vector2i = key_vec(id)
		_astar.add_point(id, Vector2(v.x, v.y))
	for id2 in ids:
		var v2: Vector2i = key_vec(id2)
		for d in DIRS:
			var nk: int = key(v2.x + (d as Vector2i).x, v2.y + (d as Vector2i).y)
			if _astar.has_point(nk) and slope_ok(v2.x, v2.y, v2.x + (d as Vector2i).x, v2.y + (d as Vector2i).y):
				_astar.connect_points(id2, nk, true)

## Kürzester Gleisweg als Liste von Schlüsseln (leer = keine Verbindung).
func find_path(from_key: int, to_key: int) -> Array:
	_ensure_graph()
	if not _astar.has_point(from_key) or not _astar.has_point(to_key): return []
	var ids: PackedInt64Array = _astar.get_id_path(from_key, to_key)
	var out: Array = []
	for i in ids: out.append(int(i))
	return out

# ── Linien ───────────────────────────────────────────────────────────────────
func create_line() -> int:
	var id: int = next_line_id
	next_line_id += 1
	lines[id] = {
		"name": "Linie %d" % id,
		"color": (LINE_COLORS[(id - 1) % LINE_COLORS.size()] as Array).duplicate(),
		"stops": [], "shipments": [], "delivered": 0.0
	}
	return id

func delete_line(id: int) -> void:
	lines.erase(id)
	for t in trains:
		if (t as TrainEntity).line_id == id: _send_home(t)

func line_color(id: int) -> Color:
	var c: Array = (lines.get(id, {}) as Dictionary).get("color", [0.8, 0.8, 0.8]) as Array
	return Color(float(c[0]), float(c[1]), float(c[2]))

func add_stop(line_id: int, station_key: int) -> void:
	if not lines.has(line_id): return
	((lines[line_id] as Dictionary)["stops"] as Array).append(station_key)

func remove_stop(line_id: int, idx: int) -> void:
	if not lines.has(line_id): return
	var ln: Dictionary = lines[line_id] as Dictionary
	var stops: Array = ln["stops"] as Array
	if idx < 0 or idx >= stops.size(): return
	stops.remove_at(idx)
	var keep: Array = []
	for sh in (ln["shipments"] as Array):
		var s: Dictionary = sh
		if int(s["from"]) == idx or int(s["to"]) == idx: continue
		if int(s["from"]) > idx: s["from"] = int(s["from"]) - 1
		if int(s["to"]) > idx: s["to"] = int(s["to"]) - 1
		keep.append(s)
	ln["shipments"] = keep
	for t in trains:
		var tr: TrainEntity = t
		if tr.line_id == line_id:
			tr.next_stop = 0 if stops.is_empty() else tr.next_stop % stops.size()
			if tr.state == "MOVING" or tr.state == "DWELL": tr.state = "BLOCKED"; tr.timer = 0.0

func add_shipment(line_id: int, res: String, from_idx: int, to_idx: int) -> void:
	if not lines.has(line_id): return
	((lines[line_id] as Dictionary)["shipments"] as Array).append({"res": res, "from": from_idx, "to": to_idx})

func remove_shipment(line_id: int, i: int) -> void:
	if not lines.has(line_id): return
	var ships: Array = (lines[line_id] as Dictionary)["shipments"] as Array
	if i >= 0 and i < ships.size(): ships.remove_at(i)

## "" = Linie ist fahrbereit, sonst Problembeschreibung.
func line_status(line_id: int) -> String:
	if not lines.has(line_id): return "Linie existiert nicht."
	var stops: Array = (lines[line_id] as Dictionary)["stops"] as Array
	if stops.size() < 2: return "Braucht mindestens 2 Haltestellen."
	for i in stops.size():
		if station_at_key(int(stops[i])) == null: return "Bahnhof %d existiert nicht mehr." % (i + 1)
	for i in stops.size():
		var a: int = int(stops[i]); var b: int = int(stops[(i + 1) % stops.size()])
		if a != b and find_path(a, b).is_empty():
			return "Kein Gleispfad zwischen %s und %s." % [get_station_name(station_at_key(a)), get_station_name(station_at_key(b))]
	return ""

# ── Züge ─────────────────────────────────────────────────────────────────────
func create_train(depot: BuildingEntity, line_id: int = -1) -> TrainEntity:
	var t := TrainEntity.new()
	t.id = next_train_id; next_train_id += 1
	t.line_id = line_id
	t.depot_key = key(depot.tile_x, depot.tile_y)
	t.colony_id = depot.colony_id
	t.head = Vector2(float(depot.tile_x), float(depot.tile_y))
	t.trail = [t.head]
	trains.append(t)
	return t

## Kauft einen Zug im Depot (Kosten aus dem Pool der Depot-Kolonie). "" = Erfolg, sonst Fehlertext.
func buy_train(depot: BuildingEntity, line_id: int) -> String:
	var prev: int = ResourceSys.current_colony
	ResourceSys.use_colony(depot.colony_id)
	var ok: bool = GameState.dev_all_buildings or ResourceSys.can_afford(TRAIN_COSTS)
	if ok and not GameState.dev_all_buildings: ResourceSys.spend(TRAIN_COSTS)
	ResourceSys.use_colony(prev)
	if not ok: return "Nicht genug Ressourcen in %s für einen Zug." % ColonySys.get_name_of(depot.colony_id)
	var t: TrainEntity = create_train(depot, -1)
	if line_id >= 0: assign_train(t, line_id)
	return ""

func assign_train(t: TrainEntity, line_id: int) -> void:
	t.line_id = line_id
	t.next_stop = 0
	t.state = "DEPOT" if line_id < 0 else "BLOCKED"
	t.timer = 0.0
	t.manual = false; t.speed = 0.0   # v16.8: nach Linienwechsel fährt wieder die Automatik

func remove_train(t: TrainEntity) -> void:
	trains.erase(t)

func _send_home(t: TrainEntity) -> void:
	t.line_id = -1; t.state = "DEPOT"; t.path = []; t.path_i = 0
	var dv: Vector2i = key_vec(t.depot_key)
	t.head = Vector2(float(dv.x), float(dv.y)); t.trail = [t.head]

func _nearest_node_key(p: Vector2) -> int:
	var best: int = -1; var best_d: float = INF
	var cx: int = roundi(p.x); var cy: int = roundi(p.y)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if is_node(cx + dx, cy + dy):
				var d: float = Vector2(float(cx + dx), float(cy + dy)).distance_to(p)
				if d < best_d: best_d = d; best = key(cx + dx, cy + dy)
	return best

func _plan(t: TrainEntity) -> void:
	var ln: Dictionary = lines.get(t.line_id, {}) as Dictionary
	var stops: Array = ln.get("stops", []) as Array
	if stops.size() < 2:
		t.state = "BLOCKED"; t.timer = RETRY_TIME; return
	t.next_stop = t.next_stop % stops.size()
	var from_k: int = _nearest_node_key(t.head)
	var to_k: int = int(stops[t.next_stop])
	if from_k < 0:
		# Gleis unter dem Zug wurde entfernt -> zurück ins Depot gestellt
		GameState.notify("🚂 Ein Zug stand auf einem entfernten Gleis und wurde ins Depot gestellt.", Color(0.85, 0.55, 0.15))
		_send_home(t); return
	if station_at_key(to_k) == null:
		_blocked(t, "Haltestelle existiert nicht mehr."); return
	var p: Array = find_path(from_k, to_k)
	if p.is_empty():
		_blocked(t, "Kein Gleispfad zum nächsten Halt."); return
	t.path = p; t.path_i = 0; t.state = "MOVING"

func _blocked(t: TrainEntity, why: String) -> void:
	t.state = "BLOCKED"; t.timer = RETRY_TIME
	if t.blocked_day != DayNight.day_count:
		t.blocked_day = DayNight.day_count
		GameState.notify("🚂 Zug %d (%s): %s" % [t.id, str((lines.get(t.line_id, {}) as Dictionary).get("name", "?")), why], Color(0.85, 0.55, 0.15))

func update(dt: float) -> void:
	for t in trains: _update_train(t as TrainEntity, dt)

func _update_train(t: TrainEntity, dt: float) -> void:
	if RailSys.riding != null and RailSys.riding == t:
		_driver_input(t)   # v16.8: Tasten des Mitfahrers zuerst lesen (auch im Bahnhof: [W] = vorzeitige Abfahrt)
	match t.state:
		"DEPOT":
			if t.line_id >= 0 and lines.has(t.line_id) and (((lines[t.line_id] as Dictionary)["stops"] as Array).size() >= 2):
				t.next_stop = 0; _plan(t)
		"BLOCKED":
			t.timer -= dt
			if t.timer <= 0.0:
				t.timer = RETRY_TIME
				if t.line_id < 0 or not lines.has(t.line_id): _send_home(t)
				else: _plan(t)
		"DWELL":
			t.timer -= dt
			# v16.8: Mitfahrer mit [W] fährt vorzeitig ab (Pfeifen, dann geht's los).
			# is_action_pressed wie im Lokführer-Modus (gedrückthalten MUSS wirken).
			if RailSys.riding == t and Input.is_action_pressed("move_up") and t.timer > 0.05:
				SoundSys.play_train_whistle()
				t.timer = 0.0
			if t.timer <= 0.0:
				t.speed = 0.0
				t.next_stop += 1
				_plan(t)
		"MOVING":
			_move(t, dt)

# ── v16.8: Lokführer-Eingaben des Mitfahrers ─────────────────────────────────
## Wird einmal pro Frame für den Zug aufgerufen, in dem der Spieler sitzt.
## W oder S schaltet zum ersten Mal auf Handsteuerung; [T] toggelt zwischen
## Handsteuerung und Automatik (Kanten-Erkennung über _t_key_prev, weil es für
## rohe Tasten kein is_action_just_pressed gibt und is_key_pressed so
## testbar/stabil bleibt).
var _t_key_prev: bool = false

func _driver_input(t: TrainEntity) -> void:
	# Gehaltenes W/S = Lokführung übernehmen ("is_action_pressed" statt
	# "just_pressed": gedrückthalten muss immer wirken, das ist robuster und
	# auch headless-testbar).
	if not t.manual and (Input.is_action_pressed("move_up") or Input.is_action_pressed("move_down")):
		t.manual = true
		t.speed = TRAIN_SPEED * 0.5   # Sanfter Übergang: Automatik gab 100 %, Lokführer startet gemütlich
		GameState.notify("🚂 Lokführer-Modus: [W] Gas · [S] Bremse · [T] Automatik", Color(0.45, 0.8, 0.5))
	var t_now: bool = Input.is_physical_key_pressed(KEY_T)
	if t_now and not _t_key_prev:
		t.manual = not t.manual
		if t.manual:
			t.speed = TRAIN_SPEED * 0.5
			GameState.notify("🚂 Du übernimmst die Steuerung: [W] Gas · [S] Bremse", Color(0.45, 0.8, 0.5))
		else:
			GameState.notify("⚙️ Automatik fährt wieder selbst.", Color(0.45, 0.8, 0.5))
	_t_key_prev = t_now

func _move(t: TrainEntity, dt: float) -> void:
	# v16.8: mit Lokführer gilt sein Tempo (Gas/Bremse), sonst konstantes Streckentempo.
	var speed: float = TRAIN_SPEED
	if RailSys.riding != null and RailSys.riding == t and t.manual:
		var gas: bool = Input.is_action_pressed("move_up")
		var brk: bool = Input.is_action_pressed("move_down")
		if gas and not brk: t.speed = minf(t.speed + MANUAL_ACCEL * dt, TRAIN_SPEED)
		elif brk: t.speed = maxf(t.speed - MANUAL_BRAKE * dt, 0.0)
		speed = t.speed
	else:
		t.speed = TRAIN_SPEED
	var left: float = speed * dt
	while left > 0.0 and t.state == "MOVING":
		if t.path_i >= t.path.size():
			_arrive(t); return
		var tv: Vector2i = key_vec(int(t.path[t.path_i]))
		if not is_node(tv.x, tv.y):
			t.state = "BLOCKED"; t.timer = 0.0; return    # Gleis wurde entfernt -> neu planen
		var target: Vector2 = Vector2(float(tv.x), float(tv.y))
		var to_target: Vector2 = target - t.head
		var dist: float = to_target.length()
		if dist <= left:
			if dist > 0.0001: t.heading = to_target / dist
			t.head = target; left -= dist; t.path_i += 1
		else:
			t.heading = to_target / dist
			t.head += t.heading * left; left = 0.0
		if t.trail.is_empty() or (t.trail[0] as Vector2).distance_to(t.head) >= 0.2:
			t.trail.push_front(t.head)
			if t.trail.size() > 40: t.trail.resize(40)
	if t.state == "MOVING" and t.path_i >= t.path.size(): _arrive(t)

func _arrive(t: TrainEntity) -> void:
	var stops: Array = ((lines.get(t.line_id, {}) as Dictionary).get("stops", []) as Array)
	if stops.is_empty(): t.state = "BLOCKED"; t.timer = RETRY_TIME; return
	# v16.8: Lokführer-Boni. "Pünktlich" = am Halt nicht abgebremst haben
	# (Anfahrt mit >= 60 % Streckentempo) -> halbe Haltezeit. Selbst gefahrene
	# Halte zählen für den Erfolg "Lokführer".
	var driver: bool = RailSys.riding != null and RailSys.riding == t
	var punctual: bool = driver and t.manual and t.speed >= TRAIN_SPEED * PUNCTUAL_SPEED_FRAC
	var rep_bonus: float = DRIVER_REP_BONUS if driver else 1.0
	_exchange(t, t.next_stop % stops.size(), rep_bonus)
	t.trips += 1
	if driver:
		t.manual_stops += 1
		AchievementSys.report_manual_stop()
		if punctual:
			GameState.notify("⚡ Pünktlich angefahren! Kurzer Stopp in %s." % _stop_name(t, t.next_stop % stops.size()), Color(0.95, 0.80, 0.25))
			SoundSys.play_station_bell()
		else:
			SoundSys.play_station_bell()
	t.state = "DWELL"
	t.timer = DWELL_TIME * (PUNCTUAL_DWELL_FACTOR if punctual else 1.0)
	t.path = []; t.path_i = 0

## Name der Haltestelle an einem Stops-Index (für Meldungen).
func _stop_name(t: TrainEntity, stop_idx: int) -> String:
	var stops: Array = ((lines.get(t.line_id, {}) as Dictionary).get("stops", []) as Array)
	if stops.is_empty(): return "?"
	var sb = station_at_key(int(stops[stop_idx]))
	if sb == null: return "?"
	return get_station_name(sb as BuildingEntity)

## Entladen (was hier hingehört) und danach beladen (was hier abfährt) - jeweils
## gegen den Pool der Kolonie des Bahnhofs.
## v16.8: `driver_bonus` > 1, wenn der Spieler den Zug selbst gefahren hat -
## Ablieferungen am Nachbar-Bahnhof bringen dann mehr Ruf.
func _exchange(t: TrainEntity, stop_idx: int, driver_bonus: float = 1.0) -> void:
	var ln: Dictionary = lines.get(t.line_id, {}) as Dictionary
	var stops: Array = ln.get("stops", []) as Array
	var sb = station_at_key(int(stops[stop_idx]))
	if sb == null: return
	var prev: int = ResourceSys.current_colony
	ResourceSys.use_colony((sb as BuildingEntity).colony_id)
	var ships: Array = ln.get("shipments", []) as Array
	for sh in ships:
		var s: Dictionary = sh
		if int(s["to"]) != stop_idx: continue
		var res: String = str(s["res"])
		var amt: float = float(t.cargo.get(res, 0.0))
		if amt <= 0.0: continue
		var added: float = ResourceSys.add(res, amt)
		if added > 0.0 and ColonySys.is_npc((sb as BuildingEntity).colony_id):
			NeighborSys.on_delivery((sb as BuildingEntity).colony_id, res, added, driver_bonus)   # v16.7: Ruf beim Nachbarn; v16.8: Bonus selbst gefahren
		ln["delivered"] = float(ln.get("delivered", 0.0)) + added
		var rest: float = amt - added
		if rest <= 0.01: t.cargo.erase(res)
		else:
			t.cargo[res] = rest
			# Lager am Ziel voll: Fracht bleibt an Bord (einmal pro Tag melden)
			if t.full_day != DayNight.day_count:
				t.full_day = DayNight.day_count
				GameState.notify("🚂 Zug %d: Das Lager in %s ist voll - %s bleibt an Bord." % [t.id, ColonySys.get_name_of((sb as BuildingEntity).colony_id), res], Color(0.85, 0.55, 0.15))
	var loads: Array = []
	for sh in ships:
		var s2: Dictionary = sh
		if int(s2["from"]) == stop_idx and int(s2["to"]) != stop_idx: loads.append(s2)
	if not loads.is_empty():
		var share: float = floorf(maxf(0.0, t.capacity() - t.cargo_total()) / float(loads.size()))
		for s3 in loads:
			var res3: String = str((s3 as Dictionary)["res"])
			var take: float = floorf(minf(share, float(ResourceSys.resources.get(res3, 0.0))))
			var npc_station: bool = ColonySys.is_npc((sb as BuildingEntity).colony_id)
			if npc_station: take = floorf(NeighborSys.limit_take((sb as BuildingEntity).colony_id, res3, take))   # v16.7: Ruf-Kredit
			if take >= 1.0 and ResourceSys.remove(res3, take):
				t.cargo[res3] = float(t.cargo.get(res3, 0.0)) + take
				if npc_station: NeighborSys.on_take((sb as BuildingEntity).colony_id, res3, take)
	ResourceSys.use_colony(prev)

## Feature (v16.4): freie Kachel neben dem Zug zum Aussteigen (Bahnsteig). Bevorzugt die
## 4 direkten Nachbarn der Zugkachel, dann die Diagonalen; nie Gleis/Gebäude/Wasser.
func exit_tile(t: TrainEntity) -> Vector2i:
	var hx: int = roundi(t.head.x); var hy: int = roundi(t.head.y)
	var cand: Array = []
	for d in DIRS: cand.append(Vector2i(hx, hy) + (d as Vector2i))
	for d2 in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		cand.append(Vector2i(hx, hy) + (d2 as Vector2i))
	for c in cand:
		var v: Vector2i = c
		if not _in_bounds(v.x, v.y): continue
		var tile: Dictionary = (world[v.x] as Array)[v.y] as Dictionary
		if rails.has(key(v.x, v.y)) or tile.get("building") != null: continue
		if str(tile.get("biome", "")) == "WATER": continue
		return v
	return Vector2i(hx, hy)

# ── Speichern ────────────────────────────────────────────────────────────────
func serialize() -> Dictionary:
	var rl: Array = []
	for k in rails: rl.append(int(k))
	var ls: Dictionary = {}
	for id in lines: ls[str(id)] = (lines[id] as Dictionary).duplicate(true)
	var tl: Array = []
	for t in trains: tl.append((t as TrainEntity).serialize())
	var sn: Dictionary = {}
	for k in station_names: sn[str(k)] = station_names[k]
	return {"rails": rl, "lines": ls, "trains": tl, "station_names": sn,
		"next_line_id": next_line_id, "next_train_id": next_train_id}

func deserialize(data) -> void:
	init()
	if not (data is Dictionary): return
	var d: Dictionary = data as Dictionary
	for k in (d.get("rails", []) as Array): rails[int(k)] = true
	var raw_lines: Dictionary = d.get("lines", {}) as Dictionary
	for k in raw_lines:
		var ln: Dictionary = (raw_lines[k] as Dictionary).duplicate(true)
		var stops: Array = []
		for s in (ln.get("stops", []) as Array): stops.append(int(s))
		ln["stops"] = stops
		var ships: Array = []
		for sh in (ln.get("shipments", []) as Array):
			var sd: Dictionary = sh
			ships.append({"res": str(sd.get("res", "")), "from": int(sd.get("from", 0)), "to": int(sd.get("to", 0))})
		ln["shipments"] = ships
		ln["delivered"] = float(ln.get("delivered", 0.0))
		lines[int(k)] = ln
	for td in (d.get("trains", []) as Array):
		trains.append(TrainEntity.deserialize(td as Dictionary))
	var sn: Dictionary = d.get("station_names", {}) as Dictionary
	for k in sn: station_names[int(k)] = str(sn[k])
	next_line_id = int(d.get("next_line_id", lines.size() + 1))
	next_train_id = int(d.get("next_train_id", trains.size() + 1))
	all_dirty = true
	_rails_version += 1
	_graph_sig = "#"
