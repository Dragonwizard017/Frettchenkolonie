## DistrictSystem.gd
## Feature (v11.11, Distrikt-System - erstes Timberborn-Kernmechanik-Paket
## nach der Achievements/Traits/Legendäre-Frettchen-Reihe). Architektur
## bewusst simpel gehalten - KEINE echte Pfad-/Konnektivitäts-Analyse (dafür
## gibt es in diesem Projekt kein Pathfinding-Graph-System), sondern ein
## distanzbasiertes, automatisches Zuordnungsschema:
##
## - Jeder Bauhof/Grosse Bauhof (btype "BUILDER") gründet beim Bauen einen
##   NEUEN Bezirk - AUSSER dem allerersten Bauhof der Kolonie, der den
##   "Hauptbezirk" (district_id 0) bekommt.
## - Jedes andere Gebäude wird bei Platzierung automatisch dem Bezirk des
##   NAECHSTGELEGENEN Bauhofs zugeordnet (siehe assign_district()).
## - Lagerhaus-Suche (siehe FerretEntity._find_nearest_storage_building())
##   berücksichtigt nur Lagerhäuser im SELBEN Bezirk ODER in einem per
##   Bezirkstor (DISTRICT_GATE) verbundenen Bezirk (siehe are_linked()).
## - Ein Bezirkstor verbindet, SOLANGE es mit einem Frettchen besetzt ist
##   (siehe BuildingEntity.update()), alle Bezirke in seiner Reichweite
##   (collection_radius) paarweise miteinander (siehe update_gate_link()).
##   Wird es verkauft/leer, fällt NUR seine eigene Verbindung weg - andere
##   Tore, die zufällig dieselben zwei Bezirke verbinden, bleiben aktiv
##   (siehe active_links, Schlüssel = Gate-ID, nicht globale Paarliste).
extends Node

var districts: Dictionary = {}      # district_id (int) -> {"name": String, "color": Array[float*3]}
var next_district_id: int = 1
## Schlüssel: eindeutige Gate-Instanz-ID (siehe _gate_key()), Wert: [district_a, district_b].
## Ein Bezirkstor trägt selbst KEINE eigene "id"-Instanzkennung (BuildingEntity.id ist der
## GebäudeTYP, z.B. "DISTRICT_GATE" - bei mehreren Toren also nicht eindeutig!), daher wird
## hier stattdessen die Tile-Position als Schlüssel verwendet (pro Tile kann ohnehin nur ein
## Gebäude stehen).
var active_links: Dictionary = {}

func init() -> void:
	districts = {0: {"name": "Hauptbezirk", "color": [0.35, 0.65, 0.95], "colony_id": 0}}
	next_district_id = 1
	active_links = {}

## Wird beim Platzieren JEDES Gebäudes aufgerufen (siehe BuildingSystem.build()).
## "all_buildings" = BuildingSys.buildings NACH dem Anhängen von b selbst.
func assign_district(b, all_buildings: Array) -> void:
	# Feature (v16.0, Kolonie-Fundament): Bauhöfe und Bezirke zählen PRO KOLONIE.
	if b.btype == "BUILDER":
		var other_builders: int = 0
		for ob in all_buildings:
			if ob != b and ob.btype == "BUILDER" and ob.colony_id == b.colony_id: other_builders += 1
		if other_builders == 0:
			if int(b.colony_id) == 0:
				b.district_id = 0  # allererster Bauhof der Hauptkolonie -> Hauptbezirk
			else:
				b.district_id = _create_district(int(b.colony_id), "Hauptbezirk " + ColonySys.get_name_of(int(b.colony_id)))
		else:
			b.district_id = _create_district(int(b.colony_id))
		return
	# Alle anderen Gebäude: Bezirk des nächstgelegenen Bauhofs DERSELBEN Kolonie
	# (Fallback: nächster Bauhof überhaupt).
	var best_builder = null
	var best_d: float = INF
	for ob in all_buildings:
		if ob == b or ob.btype != "BUILDER" or ob.colony_id != b.colony_id: continue
		var d: float = Vector2(float(ob.tile_x), float(ob.tile_y)).distance_to(Vector2(float(b.tile_x), float(b.tile_y)))
		if d < best_d: best_d = d; best_builder = ob
	if best_builder == null:
		for ob in all_buildings:
			if ob == b or ob.btype != "BUILDER": continue
			var d2: float = Vector2(float(ob.tile_x), float(ob.tile_y)).distance_to(Vector2(float(b.tile_x), float(b.tile_y)))
			if d2 < best_d: best_d = d2; best_builder = ob
	b.district_id = (best_builder.district_id if best_builder != null else 0)

## Feature (Timberborn-Feld-System): ermittelt den Bezirk einer BLOSSEN
## Kachel-Position (kein Gebäude) nach demselben "nächstgelegener Bauhof"-
## Schema wie assign_district() oben - wird beim Anlegen einer Feld-Kachel
## durch den Spieler gebraucht (siehe GameController._place_field()), da
## Felder selbst keine Gebäude sind und deshalb nicht über assign_district()
## laufen.
func get_district_for_tile(tx: int, ty: int) -> int:
	var cid: int = ColonySys.colony_of_tile(tx, ty)
	if cid < 0: cid = ColonySys.active_id
	var best_builder = null
	var best_d: float = INF
	for pass_idx in 2:   # 1. Durchlauf: nur Bauhöfe der Kolonie; 2.: Fallback alle
		for ob in BuildingSys.buildings:
			if ob.btype != "BUILDER": continue
			if pass_idx == 0 and ob.colony_id != cid: continue
			var d: float = Vector2(float(ob.tile_x), float(ob.tile_y)).distance_to(Vector2(float(tx), float(ty)))
			if d < best_d: best_d = d; best_builder = ob
		if best_builder != null: break
	return (best_builder.district_id if best_builder != null else 0)

func _create_district(colony_id: int = 0, name_override: String = "") -> int:
	var did: int = next_district_id
	next_district_id += 1
	districts[did] = {
		"name": name_override if name_override != "" else "Bezirk %d" % (did + 1),
		"color": _random_color(), "colony_id": colony_id
	}
	return did

## Feature (v16.0, Kolonie-Fundament): zu welcher Kolonie gehört der Bezirk?
func district_colony(did: int) -> int:
	return int((districts.get(did, {}) as Dictionary).get("colony_id", 0))

func _random_color() -> Array:
	return [randf_range(0.3, 0.9), randf_range(0.3, 0.9), randf_range(0.3, 0.9)]

func get_district_name(did: int) -> String:
	return str((districts.get(did, {}) as Dictionary).get("name", "Unbekannt"))

## Feature (v11.11, Distrikt-System-UI): Umbenennen für DistrictPanel.gd.
## Leere/reine Leerzeichen-Namen werden ignoriert (Bezirk behält seinen
## bisherigen Namen), damit nie ein Bezirk ganz ohne Namen dasteht.
func rename_district(did: int, new_name: String) -> void:
	var trimmed: String = new_name.strip_edges()
	if trimmed == "" or not districts.has(did): return
	(districts[did] as Dictionary)["name"] = trimmed

## Feature (v11.11, Distrikt-System-UI): für DistrictPanel.gd - Anzahl
## Gebäude je Bezirk, ohne dass das Panel selbst durch BuildingSys.buildings
## iterieren und Feldnamen kennen muss.
func count_buildings_in_district(did: int) -> int:
	var n: int = 0
	for b in BuildingSys.buildings:
		if int(b.district_id) == did: n += 1
	return n

func are_linked(a: int, b: int) -> bool:
	if a == b: return true
	# Feature (v16.0): Bezirke verschiedener Kolonien sind NIE verbunden - die
	# Verbindung zwischen Kolonien läuft später über die Logistik (Züge).
	if district_colony(a) != district_colony(b): return false
	for key in active_links:
		var pair: Array = active_links[key]
		if (int(pair[0]) == a and int(pair[1]) == b) or (int(pair[0]) == b and int(pair[1]) == a):
			return true
	return false

func _gate_key(gate) -> String:
	return "%d_%d" % [gate.tile_x, gate.tile_y]

## Wird jeden Tick von einem besetzten (siehe Aufrufbedingung in
## BuildingEntity.update()) DISTRICT_GATE aufgerufen: findet alle
## unterschiedlichen Bezirke innerhalb collection_radius und verlinkt sie
## paarweise. Bei mehr als 2 gefundenen Bezirken werden ALLE Paare verlinkt
## (ein Tor an einer Dreifach-Kreuzung verbindet alle drei miteinander).
func update_gate_link(gate) -> void:
	var found: Dictionary = {}  # district_id -> true, Set-Simulation
	found[gate.district_id] = true
	for b in BuildingSys.buildings:
		if b == gate or b.is_under_construction: continue
		if b.colony_id != gate.colony_id: continue
		var d: float = Vector2(float(b.tile_x), float(b.tile_y)).distance_to(Vector2(float(gate.tile_x), float(gate.tile_y)))
		if d <= float(gate.collection_radius):
			found[b.district_id] = true
	var ids: Array = found.keys()
	if ids.size() < 2:
		active_links.erase(_gate_key(gate))
		return
	# Nur EIN Paar pro Tor gespeichert (a,b) - bei >2 gefundenen Bezirken wird
	# das nächste Paar genommen; für den Alltagsfall (ein Tor verbindet
	# genau zwei angrenzende Bezirke) reicht das. Ein Torbau an einer
	# echten Dreifach-Grenze ist ein Rand- statt Regelfall.
	active_links[_gate_key(gate)] = [ids[0], ids[1]]

func remove_gate_link(gate) -> void:
	active_links.erase(_gate_key(gate))

func serialize() -> Dictionary:
	return {
		"districts": districts.duplicate(true),
		"next_district_id": next_district_id,
		"active_links": active_links.duplicate(true)
	}

func deserialize(data) -> void:
	if not (data is Dictionary) or (data as Dictionary).is_empty():
		init(); return
	var d: Dictionary = data as Dictionary
	# Bug-Fix: JSON kennt nur String-Keys - beim Speichern via JSON.stringify()
	# werden die int-Keys von "districts" (0,1,2,...) automatisch zu "0","1","2"
	# (siehe SaveSystem.gd). Ohne Rückkonvertierung würde JEDE Suche nach
	# einer int-ID (z.B. get_district_name(0)) nach dem Laden ins Leere laufen.
	var raw_districts: Dictionary = d.get("districts", {}) as Dictionary
	districts = {}
	for k in raw_districts:
		districts[int(k)] = (raw_districts[k] as Dictionary).duplicate(true)
		(districts[int(k)] as Dictionary)["colony_id"] = int((districts[int(k)] as Dictionary).get("colony_id", 0))
	if districts.is_empty(): districts = {0: {"name": "Hauptbezirk", "color": [0.35, 0.65, 0.95], "colony_id": 0}}
	next_district_id = int(d.get("next_district_id", 1))
	active_links = (d.get("active_links", {}) as Dictionary).duplicate(true)
