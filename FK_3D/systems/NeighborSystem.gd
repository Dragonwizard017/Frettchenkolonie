## NeighborSystem.gd
## Feature (v16.7, Logistik-Update Phase 5): Nachbarkolonien auf Entdeckerkarten. Jeder Nachbar ist eine
## ECHTE Kolonie in ColonySys (Flag npc) mit eigenem Ressourcen-Pool, Rathaus, Bahnhof, Lager und zwei Häusern -
## deshalb funktioniert der Handel über die normale Bahn (RailSystem._exchange) ohne Sonderlogik für Gleise.
##
## Wirtschaft ("Ruf" als Währung):
##  - Waren, die ein Zug am Nachbar-Bahnhof ABLIEFERT, steigern den Ruf (gewünschte Waren doppelt, andere
##    weniger): gain = Menge * Wert * (2.0 | 0.4) / 25.
##  - Waren, die ein Zug dort LÄDT, kosten etwas Ruf: cost = Menge * Wert * 0.3 / 25 (Kredit bis -30).
##  - Der Nachbar produziert täglich seine "offers" in seinen Lagerpool (begrenzt durch sein Lager).
##  - Aufträge: der Nachbar bittet um eine bestimmte Menge einer Ware bis zu einem Tag -> Ruf + Belohnung.
##  - Ab Ruf 80 und Bahnanschluss kann man den Nachbarn ANNEKTIEREN (Kosten: ANNEX_COSTS): er wird eine
##    eigene Kolonie (Bauhof + Siedler kommen dazu). Kein Krieg - alles friedlich.
## Nur auf Entdeckerkarten (Nebel): dort liegen die Nachbarn außerhalb des Heimatbereichs und werden
## entdeckt, sobald ihre Kachel aufgedeckt wird.
extends Node

signal neighbor_discovered(cid: int)
signal neighbors_changed

const COUNT: int = 4
const REP_MIN: float = -30.0
const REP_MAX: float = 100.0
const ANNEX_REP: float = 80.0
const WANT_MULT: float = 2.0
const OTHER_MULT: float = 0.4
const TAKE_MULT: float = 0.3
const ANNEX_COSTS: Dictionary = {"PLANKS": 120, "TOOLS": 40, "FOOD": 100}

## Wert je Ware (für Ruf-Rechnung und Auftragsbelohnung)
const VALUE: Dictionary = {
	"WOOD": 1.0, "STONE": 1.0, "BERRIES": 1.0, "WHEAT": 1.0, "PLANKS": 2.0, "FOOD": 2.0, "MEAT": 2.0,
	"IRON": 3.0, "COAL": 3.0, "COOKED_MEAT": 3.0, "BREAD": 3.0, "TOOLS": 4.0, "STEW": 4.0, "IRON_BARS": 5.0,
	"DYNAMITE": 6.0, "STEEL": 8.0, "MACHINES": 12.0,
}

## Charakter der Nachbarn: was sie täglich herstellen (offers, Menge/Tag) und was sie brauchen (wants)
const PROFILES: Dictionary = {
	"MINE":   {"title": "Bergbaudorf",    "icon": "⛏️", "offers": {"IRON": 8.0, "COAL": 6.0, "STONE": 4.0}, "wants": ["PLANKS", "FOOD", "TOOLS"]},
	"FARM":   {"title": "Bauerndorf",     "icon": "🌾", "offers": {"WHEAT": 8.0, "BREAD": 4.0, "BERRIES": 6.0}, "wants": ["WOOD", "TOOLS", "PLANKS"]},
	"WOOD":   {"title": "Holzfällerdorf", "icon": "🪓", "offers": {"WOOD": 10.0, "PLANKS": 5.0, "STONE": 4.0}, "wants": ["IRON_BARS", "FOOD", "TOOLS"]},
	"HARBOR": {"title": "Fischerhafen",   "icon": "🐟", "offers": {"FOOD": 8.0, "MEAT": 5.0}, "wants": ["TOOLS", "PLANKS", "STONE"]},
	"FORGE":  {"title": "Schmiedestadt",  "icon": "🔥", "offers": {"IRON_BARS": 4.0, "TOOLS": 3.0, "STEEL": 2.0}, "wants": ["IRON", "COAL", "FOOD"]},
}
const NAMES: Array = ["Ferrum", "Moosbach", "Weizenau", "Salzhafen", "Glutheim", "Eisenfels", "Nebelburg", "Kupferbach"]

## cid (int) -> {"profile": String, "discovered": bool, "rep": float, "request": Dictionary, "next_request_day": int,
##               "delivered_total": float, "annexed": bool}
var neighbors: Dictionary = {}
var _check_timer: float = 0.0

func _ready() -> void:
	GameState.day_changed.connect(_on_day_changed)

func reset() -> void:
	neighbors = {}

func has_neighbor(cid: int) -> bool: return neighbors.has(cid)
func cids() -> Array:
	var r: Array = neighbors.keys(); r.sort(); return r
func profile_of(cid: int) -> Dictionary:
	return PROFILES.get(str((neighbors.get(cid, {}) as Dictionary).get("profile", "")), {}) as Dictionary
func rep_of(cid: int) -> float: return float((neighbors.get(cid, {}) as Dictionary).get("rep", 0.0))
func is_discovered(cid: int) -> bool: return bool((neighbors.get(cid, {}) as Dictionary).get("discovered", false))

func status_of(cid: int) -> String:
	if bool((neighbors.get(cid, {}) as Dictionary).get("annexed", false)): return "Teil deiner Kolonie"
	var r: float = rep_of(cid)
	if r < 0.0: return "Misstrauisch"
	if r < 20.0: return "Fremd"
	if r < 50.0: return "Handelspartner"
	if r < ANNEX_REP: return "Freund"
	return "Verbündeter"

# ── Erzeugen (Weltstart auf Entdeckerkarten) ─────────────────────────────────
## Setzt COUNT Nachbarn an feste, aus dem Welt-Seed abgeleitete Stellen außerhalb des Heimatbereichs.
func spawn(gc: Node) -> void:
	reset()
	var wgen = gc.world_gen
	var rng := RandomNumberGenerator.new()
	rng.seed = int(wgen.seed_val) + 7717
	var center := Vector2(float(wgen.w) * 0.5, float(wgen.h) * 0.5)
	var profile_ids: Array = PROFILES.keys()
	# Bergbaudorf ist garantiert (Eisen!), der Rest wird gemischt
	var order: Array = ["MINE"]
	var rest: Array = profile_ids.duplicate(); rest.erase("MINE")
	for i in range(rest.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i); var tmp = rest[i]; rest[i] = rest[j]; rest[j] = tmp
	order.append_array(rest)
	var names: Array = NAMES.duplicate()
	for i in range(names.size() - 1, 0, -1):
		var j2: int = rng.randi_range(0, i); var t2 = names[i]; names[i] = names[j2]; names[j2] = t2
	var halls: Array = [Vector2i(int(center.x), int(center.y))]
	var base_angle: float = rng.randf() * TAU
	var placed: int = 0
	for k in COUNT:
		var site := Vector2i(-1, -1)
		for attempt in 40:
			var ang: float = base_angle + TAU * float(k) / float(COUNT) + rng.randf_range(-0.35, 0.35)
			var dist: float = rng.randf_range(36.0, 50.0)
			var c := Vector2i(int(center.x + cos(ang) * dist), int(center.y + sin(ang) * dist))
			if c.x < 8 or c.y < 8 or c.x >= wgen.w - 8 or c.y >= wgen.h - 8: continue
			var too_close := false
			for h in halls:
				if Vector2(c).distance_to(Vector2(h as Vector2i)) < 22.0: too_close = true
			if too_close: continue
			if _site_ok(gc.world, c): site = c; break
		if site.x < 0: continue
		halls.append(site)
		_build_town(gc, site, str(order[placed % order.size()]), str(names[placed % names.size()]))
		placed += 1
	neighbors_changed.emit()

func _site_ok(world: Array, c: Vector2i) -> bool:
	for dx in range(-5, 6):
		for dy in range(-5, 6):
			var t: Dictionary = (world[c.x + dx] as Array)[c.y + dy] as Dictionary
			var bi: String = str(t.get("biome", ""))
			if bi == "WATER" or bi == "MOUNTAIN": return false
			if t.get("building") != null: return false
	return true

func _build_town(gc: Node, c: Vector2i, profile: String, nm: String) -> void:
	var world: Array = gc.world
	# Plateau 9x9: Höhe der Mitte, Vorkommen und Wege weg
	var h0: float = float(((world[c.x] as Array)[c.y] as Dictionary).get("height", 0.0))
	for dx in range(-4, 5):
		for dy in range(-4, 5):
			var t: Dictionary = (world[c.x + dx] as Array)[c.y + dy] as Dictionary
			t["height"] = h0; t["resource_node"] = null; t["path"] = null
	var cid: int = ColonySys.register_colony(nm, c.x, c.y, 0, true)
	var start: Dictionary = {}
	for res in (PROFILES[profile] as Dictionary)["offers"]: start[res] = 60.0
	ResourceSys.create_pool(cid, start, 30.0)
	var did: int = DistrictSys._create_district(cid, "Dorf " + nm)
	var plan: Array = [["TOWN_HALL", 0, 0], ["STATION", 3, 0], ["STORAGE", -3, 0], ["HOUSE", 0, 3], ["HOUSE", 0, -3]]
	for p in plan:
		var b: BuildingEntity = BuildingSys.build_free(str(p[0]), c.x + int(p[1]), c.y + int(p[2]), world, cid)
		if b != null:
			b.district_id = did
			b.placed_day = 0
	neighbors[cid] = {"profile": profile, "discovered": false, "rep": 0.0, "request": {}, "next_request_day": 2,
		"delivered_total": 0.0, "annexed": false}

# ── Entdecken ────────────────────────────────────────────────────────────────
## Vom GameController gedrosselt aufgerufen (~1x/s): Nachbar entdeckt, sobald sein Rathaus-Feld aufgedeckt ist.
func check_discovery(delta: float) -> void:
	_check_timer += delta
	if _check_timer < 1.0: return
	_check_timer = 0.0
	for cid in neighbors:
		var nb: Dictionary = neighbors[cid] as Dictionary
		if bool(nb["discovered"]): continue
		var hall: Vector2i = ColonySys.get_hall_tile(int(cid))
		if hall.x >= 0 and ExploreSys.is_revealed(hall.x, hall.y):
			nb["discovered"] = true
			ExploreSys.reveal_circle(hall.x, hall.y, 8.0)   # das Dorf soll sichtbar sein
			var pf: Dictionary = profile_of(int(cid))
			GameState.notify("%s Neue Kolonie entdeckt: %s (%s)! Mit einem Bahnhof und Gleisen kannst du mit ihr handeln." % [str(pf.get("icon", "🏘️")), ColonySys.get_name_of(int(cid)), str(pf.get("title", ""))], Color(0.7, 0.6, 0.95))
			AchievementSys.report_neighbor_found()
			neighbor_discovered.emit(int(cid))
			neighbors_changed.emit()

# ── täglich: produzieren, Aufträge ───────────────────────────────────────────
func _on_day_changed(day: int) -> void:
	var prev: int = ResourceSys.current_colony
	for cid in neighbors:
		var nb: Dictionary = neighbors[cid] as Dictionary
		if bool(nb["annexed"]): continue
		ResourceSys.use_colony(int(cid))
		var pf: Dictionary = profile_of(int(cid))
		for res in (pf.get("offers", {}) as Dictionary):
			ResourceSys.add(str(res), float((pf["offers"] as Dictionary)[res]))
		ResourceSys.use_colony(prev)
		if not bool(nb["discovered"]): continue
		var rq: Dictionary = nb["request"] as Dictionary
		if not rq.is_empty() and day > int(rq["deadline"]):
			nb["rep"] = maxf(REP_MIN, float(nb["rep"]) - 4.0)
			GameState.notify("⌛ %s: Auftrag nicht rechtzeitig erfüllt (-4 Ruf)." % ColonySys.get_name_of(int(cid)), Color(0.85, 0.55, 0.15))
			nb["request"] = {}; nb["next_request_day"] = day + 3
			neighbors_changed.emit()
		elif rq.is_empty() and day >= int(nb["next_request_day"]):
			_new_request(int(cid), day)
	ResourceSys.use_colony(ColonySys.active_id)

func _new_request(cid: int, day: int) -> void:
	var nb: Dictionary = neighbors[cid] as Dictionary
	var wants: Array = (profile_of(cid).get("wants", []) as Array)
	if wants.is_empty(): return
	var res: String = str(wants[randi() % wants.size()])
	var value: float = float(VALUE.get(res, 1.0))
	var amount: int = int(clampf(round(120.0 / value / 10.0) * 10.0, 20.0, 120.0))
	nb["request"] = {"res": res, "amount": amount, "delivered": 0.0, "deadline": day + 10, "reward_rep": 12.0}
	GameState.notify("📜 %s bittet um %d × %s (bis Tag %d)." % [ColonySys.get_name_of(cid), amount, res, day + 10], Color(0.7, 0.6, 0.95))
	neighbors_changed.emit()

# ── Handel (vom RailSystem aufgerufen) ───────────────────────────────────────
## Ein Zug hat `amount` von `res` am Bahnhof des Nachbarn abgeliefert.
## v16.8: `rep_bonus` > 1, wenn der Spieler den Zug selbst gefahren hat
## (Lokführer-Bonus, RailSys.DRIVER_REP_BONUS).
func on_delivery(cid: int, res: String, amount: float, rep_bonus: float = 1.0) -> void:
	if not neighbors.has(cid) or amount <= 0.0: return
	var nb: Dictionary = neighbors[cid] as Dictionary
	var wants: Array = profile_of(cid).get("wants", []) as Array
	var mult: float = WANT_MULT if (res in wants) else OTHER_MULT
	nb["rep"] = minf(REP_MAX, float(nb["rep"]) + amount * float(VALUE.get(res, 1.0)) * mult * rep_bonus / 25.0)
	nb["delivered_total"] = float(nb["delivered_total"]) + amount
	var rq: Dictionary = nb["request"] as Dictionary
	if not rq.is_empty() and str(rq["res"]) == res:
		rq["delivered"] = float(rq["delivered"]) + amount
		if float(rq["delivered"]) >= float(rq["amount"]):
			nb["rep"] = minf(REP_MAX, float(nb["rep"]) + float(rq["reward_rep"]))
			var prev: int = ResourceSys.current_colony
			ResourceSys.use_colony(ColonySys.active_id)
			ResourceSys.force_add("TOOLS", 10.0 + float(rq["amount"]) * 0.1)
			ResourceSys.use_colony(prev)
			GameState.notify("✅ %s: Auftrag erfüllt! +%d Ruf und eine Lieferung Werkzeug als Dank." % [ColonySys.get_name_of(cid), int(rq["reward_rep"])], Color(0.45, 0.85, 0.5))
			nb["request"] = {}; nb["next_request_day"] = DayNight.day_count + 2
	neighbors_changed.emit()

## Wie viel von `res` darf ein Zug am Nachbar-Bahnhof laden (begrenzt durch den Ruf-Kredit)?
func limit_take(cid: int, res: String, amount: float) -> float:
	if not neighbors.has(cid): return amount
	var per_unit: float = float(VALUE.get(res, 1.0)) * TAKE_MULT / 25.0
	if per_unit <= 0.0: return amount
	var headroom: float = rep_of(cid) - REP_MIN
	return minf(amount, floorf(headroom / per_unit))

func on_take(cid: int, res: String, amount: float) -> void:
	if not neighbors.has(cid) or amount <= 0.0: return
	var nb: Dictionary = neighbors[cid] as Dictionary
	nb["rep"] = maxf(REP_MIN, float(nb["rep"]) - amount * float(VALUE.get(res, 1.0)) * TAKE_MULT / 25.0)
	neighbors_changed.emit()

# ── Annexion ─────────────────────────────────────────────────────────────────
## "" = möglich, sonst der Grund.
func annex_block_reason(cid: int) -> String:
	if not neighbors.has(cid): return "Unbekannte Kolonie."
	var nb: Dictionary = neighbors[cid] as Dictionary
	if bool(nb["annexed"]): return "Bereits Teil deiner Kolonie."
	if not bool(nb["discovered"]): return "Noch nicht entdeckt."
	if rep_of(cid) < ANNEX_REP and not GameState.dev_all_buildings:
		return "Ruf %d/%d - liefere gewünschte Waren und erfülle Aufträge." % [int(rep_of(cid)), int(ANNEX_REP)]
	var nb_station := _station_key_of(cid)
	if nb_station < 0: return "Die Kolonie hat keinen Bahnhof."
	var linked := false
	for sb in RailSys.get_buildings_of("STATION"):
		var be: BuildingEntity = sb
		if ColonySys.is_npc(be.colony_id): continue
		if not RailSys.find_path(RailSys.key(be.tile_x, be.tile_y), nb_station).is_empty(): linked = true; break
	if not linked: return "Kein Bahnanschluss: verbinde einen deiner Bahnhöfe per Gleis mit ihrem Bahnhof."
	if not GameState.dev_all_buildings and not ResourceSys.can_afford(ANNEX_COSTS):
		return "Es fehlen Ressourcen für die Annexion."
	return ""

func _station_key_of(cid: int) -> int:
	for sb in RailSys.get_buildings_of("STATION"):
		var be: BuildingEntity = sb
		if be.colony_id == cid: return RailSys.key(be.tile_x, be.tile_y)
	return -1

## Friedliche Annexion: die Nachbarkolonie wird eine eigene Kolonie (Bauhof + Siedler kommen dazu).
func annex(cid: int, gc: Node, force: bool = false) -> String:
	if force and not neighbors.has(cid): return "Unbekannte Kolonie."
	var why: String = "" if force else annex_block_reason(cid)
	if why != "": return why
	if not force and not GameState.dev_all_buildings: ResourceSys.spend(ANNEX_COSTS)
	var nb: Dictionary = neighbors[cid] as Dictionary
	nb["annexed"] = true
	ColonySys.set_npc(cid, false)
	var hall: Vector2i = ColonySys.get_hall_tile(cid)
	var yard_pos: Vector2i = gc.call("_find_free_tile_ring", hall.x, hall.y, gc.world, 2, 6)
	if yard_pos.x >= 0:
		var yb: BuildingEntity = BuildingSys.build_free("CONSTRUCTION_YARD_1", yard_pos.x, yard_pos.y, gc.world, cid)
		if yb != null:
			yb.placed_day = DayNight.day_count
			gc.renderer.add_building(yb)
	for i in 4:
		var f: FerretEntity = FerretEntity.create_random()
		f.colony_id = cid
		f.pos = Vector2(float(hall.x) + randf_range(-2.0, 2.0), float(hall.y) + randf_range(-2.0, 2.0)); f.target_pos = f.pos
		PopMgr.ferrets.append(f)
	AchievementSys.report_neighbor_annexed()
	GameState.notify("🤝 %s ist jetzt Teil deiner Kolonie! 4 Frettchen und ein Bauhof sind eingezogen." % ColonySys.get_name_of(cid), Color(0.45, 0.85, 0.5))
	neighbors_changed.emit()
	GameState.build_menu_update_requested.emit()
	return ""

# ── Speichern ────────────────────────────────────────────────────────────────
func serialize() -> Dictionary:
	var out: Dictionary = {}
	for cid in neighbors:
		out[str(cid)] = (neighbors[cid] as Dictionary).duplicate(true)
	return {"neighbors": out}

func deserialize(data) -> void:
	neighbors = {}
	if not (data is Dictionary): return
	var raw: Dictionary = (data as Dictionary).get("neighbors", {}) as Dictionary
	for k in raw:
		var nb: Dictionary = (raw[k] as Dictionary).duplicate(true)
		nb["discovered"] = bool(nb.get("discovered", false)); nb["annexed"] = bool(nb.get("annexed", false))
		nb["rep"] = float(nb.get("rep", 0.0)); nb["next_request_day"] = int(nb.get("next_request_day", 2))
		nb["delivered_total"] = float(nb.get("delivered_total", 0.0))
		var rq: Dictionary = nb.get("request", {}) as Dictionary
		if not rq.is_empty():
			rq["amount"] = int(rq.get("amount", 0)); rq["delivered"] = float(rq.get("delivered", 0.0))
			rq["deadline"] = int(rq.get("deadline", 0)); rq["reward_rep"] = float(rq.get("reward_rep", 10.0))
		nb["request"] = rq
		neighbors[int(k)] = nb
