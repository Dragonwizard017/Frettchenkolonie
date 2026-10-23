## BuildingEntity.gd
class_name BuildingEntity
extends RefCounted

var id: String = ""
var name: String = ""
var btype: String = ""
var epoch: int = 1
var icon: String = ""
var tile_x: int = 0
var tile_y: int = 0
var costs: Dictionary = {}
var is_under_construction: bool = true
var construction_progress: float = 0.0
var construction_work_needed: float = 30.0
var assigned_builder = null
var placed_day: int = 0
var max_workers: int = 0
var assigned_workers: Array = []
## Feature: manuelle Arbeiter-Begrenzung über die Gebäude-UI. -1 = kein
## manuelles Limit (= max_workers gilt). Wird über set_worker_cap() gesetzt.
var worker_cap: int = -1
var work_priority: int = 3
var storage_capacity: float = 0.0
var water_capacity: float = 0.0
var max_residents: int = 0
var residents: Array = []
var production_speed: float = 1.0
var production_progress: float = 0.0
var produces: String = ""
var needs_input: bool = false
var input_resources: Array = []
var recipes: Array = []
var collects_resource: String = ""
var collection_radius: int = 6
# Bug-Fix (v10.14): "Försterei freigeschaltet, hat aber keine Funktion" -
# planting_radius wurde aus BuildingData.gd gelesen, aber nie irgendwo
# gespeichert/genutzt. Siehe _plant_trees() weiter unten.
var planting_radius: int = 8
var _plant_timer: float = 0.0
## Feature (v14.5, Timberborn-Feld-System): Timer für den Bauernhof - siehe
## _farmhouse() weiter unten, analog zu _plant_timer bei der Försterei.
var _farmhouse_timer: float = 0.0
## Verhindert Spam derselben "keine Felder zugewiesen"-Meldung jeden Tick -
## siehe _farmhouse(). Wird zurückgesetzt, sobald wieder ein Feld im Bezirk
## existiert.
var _warned_no_fields: bool = false
var happiness_bonus: float = 0.0
var happiness_radius: float = 8.0
var boost_radius: float = 10.0
var boost_factor: float = 0.5
var waterwheel_boost: float = 0.0
var level: int = 1
## Feature (v16.6, Erkundung): Radius (Kacheln), den diese Erkundungsstation bereits aufgedeckt hat.
var explore_radius_now: float = 0.0
var _explore_last_r: float = -1.0
var _explore_done_notified: bool = false
var is_active: bool = false
var dynamite_placed: bool = false

# ── Feature (v11.0, Timberborn-Lagersystem) ──────────────────────────────────
# Produktionsgebäude (COLLECTOR/PROCESSOR/MULTIPROCESSOR/HUNTER/FARM, ausser
# reinen Wasser-Sammlern) haben jetzt ein eigenes, kleines lokales Lager für
# die SELBST produzierte Ressource. Ist es voll, kann das Gebäude nicht mehr
# produzieren, bis ein Frettchen den Bestand zu einem Lagergebäude trägt
# (siehe FerretEntity._update_haul_work). local_storage_capacity = 0 bedeutet
# "dieses Gebäude hat kein lokales Lager" (z.B. Lagerhäuser selbst, Häuser,
# Wasser-Sammler - deren Fördermenge fliesst weiterhin direkt in den globalen
# Wassertank).
const LOCAL_STORAGE_CAPACITY: float = 50.0
var local_storage: Dictionary = {}
var local_storage_capacity: float = 0.0

# Baustellen-Logistik: Baumaterial muss jetzt erst von Frettchen zur Baustelle
# getragen werden, bevor überhaupt Bau-Fortschritt entsteht. delivered_resources
# zählt pro Ressourcentyp, wie viel von "costs" bereits angeliefert wurde.
var delivered_resources: Dictionary = {}

# Feature (v11.1, Logistik-Feinschliff): Lagerhaus-Spezialisierung. "" = nimmt
# alles an (Standard). Gesetzt = dieses Lagerhaus nimmt NUR noch diese eine
# Ressource von Haulern/Lagerarbeitern an (siehe accepts_resource()). Hat nur
# für STORAGE-Gebäude mit storage_capacity > 0 eine Wirkung.
var storage_filter: String = ""

# ── Feature (Tech Tree): Gebäude-Umbau ──────────────────────────────────────
# Ein per Tech-Tree freigeschaltetes Upgrade kann ein bestehendes Gebäude
# "umbauen": is_under_construction wird während des Umbaus wiederverwendet
# (identische Baustellen-Logistik wie bei einem Neubau - Material muss
# angeliefert werden, das Gebäude produziert in der Zeit nichts, siehe
# start_rebuild()/finish_rebuild() unten sowie GameController._process_construction()).
# is_rebuild unterscheidet "wird gerade umgebaut" von "wird gerade neu gebaut".
var is_rebuild: bool = false
var rebuild_target_id: String = ""

## Feature (v11.11, Distrikt-System): jedes Gebäude gehört zu genau einem
## Bezirk (siehe DistrictSystem.gd). Wird bei der Platzierung automatisch
## zugewiesen (BuildingSystem.build() -> DistrictSys.assign_district()) -
## näher am nächsten Bauhof/Grossen Bauhof gebaute Gebäude übernehmen
## dessen Bezirk, ein NEU gebauter Bauhof gründet (ausser dem allerersten)
## automatisch einen neuen Bezirk.
var district_id: int = 0
## Feature (v16.0, Kolonie-Fundament): zu welcher Kolonie das Gebäude gehört
## (siehe ColonySystem.gd). Alte Saves: Standard 0 = Hauptkolonie.
var colony_id: int = 0

func accepts_resource(res: String) -> bool:
	return storage_filter == "" or storage_filter == res

static func from_type(building_id: String, tx: int, ty: int) -> BuildingEntity:
	var all_buildings: Dictionary = BuildingData.BUILDINGS
	if not all_buildings.has(building_id):
		return null
	var data: Dictionary = all_buildings[building_id]
	var b := BuildingEntity.new()
	b.id = building_id
	b.name = str(data.get("name", building_id))
	b.btype = str(data.get("type", ""))
	b.epoch = int(data.get("epoch", 1))
	b.icon = str(data.get("icon", "?"))
	b.tile_x = tx
	b.tile_y = ty
	b.costs = (data.get("costs", {}) as Dictionary).duplicate()
	b.max_workers = int(data.get("max_workers", 0))
	b.production_speed = float(data.get("production_speed", 1.0))
	b.produces = str(data.get("produces", ""))
	b.needs_input = bool(data.get("needs_input", false))
	var ir = data.get("input_resources", [])
	b.input_resources = (ir as Array).duplicate()
	var rec = data.get("recipes", [])
	b.recipes = (rec as Array).duplicate()
	b.collects_resource = str(data.get("collects_resource", ""))
	b.collection_radius = int(data.get("collection_radius", 6))
	b.planting_radius = int(data.get("planting_radius", 8))
	b.storage_capacity = float(data.get("storage_capacity", 0.0))
	b.water_capacity = float(data.get("water_capacity", 0.0))
	b.max_residents = int(data.get("max_residents", 0))
	b.happiness_bonus = float(data.get("happiness_bonus", 0.0))
	b.happiness_radius = float(data.get("happiness_radius", 8.0))
	b.boost_radius = float(data.get("boost_radius", 10.0))
	b.boost_factor = float(data.get("boost_factor", 0.5))
	b.construction_work_needed = float(data.get("construction_work", 30.0))
	b.is_under_construction = true
	b.construction_progress = 0.0
	b.delivered_resources = {}
	# Lokales Lager nur für "echte" Produktionsgebäude, und nicht für
	# Wasser-Sammler (Brunnen/Wasserturm/Aquädukt/Bewässerungskanal) - deren
	# Fördermenge bleibt weiterhin direkt im globalen Wassertank, da Wasser
	# nicht per Frettchen getragen wird.
	if b.btype in ["COLLECTOR", "PROCESSOR", "MULTIPROCESSOR", "HUNTER", "FARM", "FARMHOUSE"] \
			and b.collects_resource != "WATER" and b.collects_resource != "SCIENCE":
		b.local_storage_capacity = LOCAL_STORAGE_CAPACITY
	# Feature (Tech Tree): wendet alle über den Tech Tree freigeschalteten
	# Gebäude-Stat-Boni (Produktionsgeschwindigkeit, Radius, Kapazitäten, ...)
	# für diesen Gebäudetyp auf die gerade gesetzten Basiswerte an.
	TechTreeSys.apply_building_bonuses(b)
	return b

func get_effective_worker_cap() -> int:
	return max_workers if worker_cap < 0 else mini(worker_cap, max_workers)

## Vom Spieler über die Gebäude-UI aufgerufen (+/- Buttons), um die Anzahl
## zugewiesener Frettchen direkt zu steuern. Werden mehr Arbeiter zugewiesen
## sein als das neue Limit erlaubt, werden überzählige sofort freigesetzt.
func set_worker_cap(n: int) -> void:
	worker_cap = clampi(n, 0, max_workers)
	while assigned_workers.size() > worker_cap:
		remove_worker(assigned_workers[assigned_workers.size() - 1])

func assign_worker(ferret) -> bool:
	if assigned_workers.size() < get_effective_worker_cap():
		assigned_workers.append(ferret)
		ferret.assigned_building = self
		return true
	return false

func remove_worker(ferret) -> void:
	assigned_workers.erase(ferret)
	if ferret.assigned_building == self:
		ferret.assigned_building = null
	# Bug-Fix (v11.11, Distrikt-System): ein Bezirkstor verbindet laut Design
	# NUR, solange es besetzt ist (siehe DistrictSystem.gd) - bisher wurde die
	# Verknüpfung aber nur beim VERKAUF entfernt (BuildingSystem.sell()), nicht
	# wenn der letzte Arbeiter es aus anderen Gründen verlässt (Um-Zuweisung,
	# Tod). Ohne diesen Fix blieb ein Bezirk fälschlich dauerhaft verlinkt,
	# obwohl das Tor längst leer stand.
	if btype == "DISTRICT_GATE" and assigned_workers.is_empty():
		DistrictSys.remove_gate_link(self)

func remove_all_workers() -> void:
	for w in assigned_workers.duplicate():
		remove_worker(w)

# ── Lokales Lager (v11.0) ────────────────────────────────────────────────────
func get_local_storage_total() -> float:
	var total: float = 0.0
	for k in local_storage:
		total += float(local_storage[k])
	return total

func get_local_free_space() -> float:
	return maxf(0.0, local_storage_capacity - get_local_storage_total())

func is_local_storage_full() -> bool:
	return local_storage_capacity > 0.0 and get_local_free_space() <= 0.5

## Fügt so viel wie möglich (begrenzt durch das freie lokale Lager) hinzu
## und gibt zurück, wie viel tatsächlich aufgenommen wurde.
func local_add(res: String, amount: float) -> float:
	var free: float = get_local_free_space()
	var to_add: float = minf(amount, free)
	if to_add > 0.0:
		local_storage[res] = float(local_storage.get(res, 0.0)) + to_add
	return to_add

## Ist gerade eines der zugewiesenen Frettchen damit beschäftigt, das lokale
## Lager dieses Gebäudes zu einem Lagerhaus zu tragen? Während das läuft,
## zählt dieses Frettchen nicht zur aktiven Produktions-Belegschaft (siehe
## get_active_worker_count()) - "produziert nichts, während es trägt".
func has_hauler() -> bool:
	for w in assigned_workers:
		var fe = w
		if fe.work_state == "HAUL_TO_WAREHOUSE" or fe.work_state == "HAUL_RETURN":
			return true
	return false

## Effektive Arbeiterzahl für die Produktionsformeln: alle zugewiesenen
## Arbeiter minus dem einen, der gerade Ressourcen ins Lagerhaus trägt (siehe
## Anfrage: "bei 2 Arbeitern, wenn einer weg ist, wird produziert als wäre
## nur einer da").
func get_active_worker_count() -> int:
	var n: int = assigned_workers.size()
	if has_hauler(): n -= 1
	return maxi(0, n)

# ── Baustellen-Material-Logistik (v11.0) ─────────────────────────────────────
func get_missing_amount(res: String) -> float:
	return maxf(0.0, float(costs.get(res, 0.0)) - float(delivered_resources.get(res, 0.0)))

func is_fully_supplied() -> bool:
	for res in costs:
		if get_missing_amount(res) > 0.01:
			return false
	return true

## Liefert eine Ressource an diese Baustelle. Überschuss (mehr getragen als
## noch gebraucht) geht zurück in den globalen Lagerpool statt verloren zu
## gehen.
func deliver_resource(res: String, amount: float) -> void:
	var need: float = get_missing_amount(res)
	var use: float = minf(amount, need)
	if use > 0.0:
		delivered_resources[res] = float(delivered_resources.get(res, 0.0)) + use
	var leftover: float = amount - use
	if leftover > 0.0:
		ResourceSys.add(res, leftover)

## Feature (Tech Tree): startet den Umbau dieses Gebäudes zu rebuild_id
## (muss ein Eintrag in BuildingData.REBUILDS[self.id] sein). Nutzt exakt
## dieselben Baustellen-Felder wie ein Neubau (costs/delivered_resources/
## construction_progress/construction_work_needed/is_under_construction) -
## Bau-Frettchen und Lagerarbeiter behandeln diese Baustelle dadurch
## automatisch genauso wie einen Neubau (siehe GameController._process_construction(),
## FerretEntity._update_builder_work()). Während is_under_construction == true
## produziert das Gebäude nichts (siehe update() oben).
func start_rebuild(rebuild_id: String, rebuild_costs: Dictionary, work_needed: float) -> void:
	rebuild_target_id = rebuild_id
	is_rebuild = true
	is_under_construction = true
	costs = rebuild_costs.duplicate()
	delivered_resources = {}
	construction_progress = 0.0
	construction_work_needed = work_needed
	assigned_builder = null

## Wird von GameController._process_construction() aufgerufen, sobald der
## Umbau-Baufortschritt abgeschlossen ist. Übernimmt alle Basiswerte des
## Zielgebäudetyps (inkl. eventueller Tech-Tree-Boni, siehe from_type()) in
## dieses bestehende BuildingEntity, behält aber Position, Bewohner
## (z.B. beim Wohnhaus-Umbau) und zugewiesene Arbeiter so weit wie möglich.
## Das lokale Lager wird bewusst geleert - während des Umbaus wurde ohnehin
## nicht produziert, und die neue lokale Lagerkapazität kann sich geändert
## haben.
func finish_rebuild() -> void:
	var target_id: String = rebuild_target_id
	var kept_residents: Array = residents.duplicate()
	var kept_workers: Array = assigned_workers.duplicate()
	var kept_placed_day: int = placed_day
	var new_b: BuildingEntity = BuildingEntity.from_type(target_id, tile_x, tile_y)
	is_rebuild = false
	rebuild_target_id = ""
	is_under_construction = false
	construction_progress = 0.0
	assigned_builder = null
	local_storage = {}
	if new_b == null:
		delivered_resources = {}
		return
	id = new_b.id; name = new_b.name; btype = new_b.btype; epoch = new_b.epoch; icon = new_b.icon
	costs = new_b.costs
	# Bugfix: ein fertiges Gebäude hält normalerweise delivered_resources ==
	# costs (siehe BuildingSystem.sell(), das die Verkaufserstattung darauf
	# stützt). Würde man delivered_resources hier auf {} zurücksetzen,
	# könnte ein umgebautes Gebäude nie wieder mit Erstattung verkauft
	# werden. Stattdessen wird es auf die neuen (Ziel-)Kosten gesetzt, exakt
	# wie bei einem ganz normal fertiggestellten Neubau.
	delivered_resources = new_b.costs.duplicate()
	max_workers = new_b.max_workers
	production_speed = new_b.production_speed
	produces = new_b.produces
	needs_input = new_b.needs_input
	input_resources = new_b.input_resources
	recipes = new_b.recipes
	collects_resource = new_b.collects_resource
	collection_radius = new_b.collection_radius
	planting_radius = new_b.planting_radius
	storage_capacity = new_b.storage_capacity
	water_capacity = new_b.water_capacity
	max_residents = new_b.max_residents
	happiness_bonus = new_b.happiness_bonus
	happiness_radius = new_b.happiness_radius
	boost_radius = new_b.boost_radius
	boost_factor = new_b.boost_factor
	local_storage_capacity = new_b.local_storage_capacity
	construction_work_needed = new_b.construction_work_needed
	placed_day = kept_placed_day
	worker_cap = -1
	residents = kept_residents
	if residents.size() > max_residents:
		for i in range(max_residents, residents.size()):
			var extra = residents[i]
			extra.home = null
		residents = residents.slice(0, max_residents)
	assigned_workers = kept_workers
	while assigned_workers.size() > max_workers:
		remove_worker(assigned_workers[assigned_workers.size() - 1])
	# Feature (v11.8, Achievement-System): "Modernisierer"-Achievement muss
	# abgeschlossene Umbauten zählen können - vorher gab es dafür kein
	# Signal, AchievementSystem.gd hängt sich hier ein (siehe GameState.gd).
	GameState.building_rebuilt.emit(self)

func update(dt: float, is_day: bool, world: Array) -> void:
	if is_under_construction:
		return
	is_active = false
	if btype == "DECO" or btype == "GRAVEYARD" or btype == "STORAGE" or btype == "DAM":
		is_active = true
		return
	if not is_day and btype != "HAPPINESS" and btype != "BUILDER" and btype != "STORAGE" and btype != "DECO" and btype != "DISTRICT_GATE":
		return
	if assigned_workers.is_empty() and max_workers > 0:
		return
	is_active = true
	match btype:
		"COLLECTOR":      _collect(dt, world)
		"PROCESSOR":      _process(dt)
		"MULTIPROCESSOR": _multi_process(dt)
		"HUNTER":         _hunt(dt)
		"FARMHOUSE":      _farmhouse(dt)
		"FORESTER":       _plant_trees(dt, world)
		"EXPLORER":       _explore(dt)
		# Feature (v11.11, Distrikt-System): ein Bezirkstor verbindet die
		# Distrikte in seiner Reichweite, SOLANGE es mit mind. 1 Frettchen
		# besetzt ist (das erzwingt bereits die Bedingung oben, "braucht
		# eigene Frettchen" laut Nutzeranfrage). Tagsuber UND nachts aktiv
		# (siehe Ausnahme oben) - eine Bezirksverbindung soll nicht jede
		# Nacht abreissen.
		"DISTRICT_GATE":  DistrictSys.update_gate_link(self)

## Bug-Fix (v10.14): FORESTER hatte im match-Block oben gar keinen Fall und
## tat dadurch buchstäblich nichts - Spieler konnten eine Försterei bauen
## und Arbeiter zuweisen, ohne jeden Effekt. Die Försterei sammelt selbst
## kein Holz (das macht der Holzfäller), sondern "pflanzt" regelmässig neue
## WOOD-Resource-Nodes auf FOREST-Tiles in ihrem planting_radius, die
## aktuell keine (oder eine komplett erschöpfte) Quelle haben - sie hält den
## Wald langfristig am Leben/dicht, statt selbst zu ernten. Die zugehörige
## 3D-Baum-Visualisierung entsteht automatisch über
## WorldRenderer3D.refresh_vegetation() (erkennt neue Resource-Nodes ohne
## Modell und spawnt nachträglich einen Baum).
func _plant_trees(dt: float, world: Array) -> void:
	if assigned_workers.is_empty(): return
	_plant_timer += dt
	var interval: float = 9.0 / maxf(1.0, float(assigned_workers.size()))
	if _plant_timer < interval: return
	_plant_timer = 0.0
	var r: int = planting_radius
	var ww: int = world.size()
	var candidates: Array = []
	for dx in range(-r, r + 1):
		var tx: int = tile_x + dx
		if tx < 0 or tx >= ww: continue
		var col: Array = world[tx]
		var hh: int = col.size()
		for dy in range(-r, r + 1):
			var ty: int = tile_y + dy
			if ty < 0 or ty >= hh: continue
			var tile: Dictionary = col[ty]
			if str(tile.get("biome", "")) != "FOREST": continue
			if tile.get("building") != null: continue
			var node_data = tile.get("resource_node")
			if node_data != null and (node_data is Dictionary):
				if float((node_data as Dictionary).get("amount", 0.0)) > 1.0:
					continue  # hier wächst schon etwas
			candidates.append(tile)
	if candidates.is_empty(): return
	var tile: Dictionary = candidates[randi() % candidates.size()]
	var start_amount: float = randf_range(60.0, 140.0)
	tile["resource_node"] = {
		"type": "WOOD", "amount": start_amount, "max_amount": start_amount,
		"regen_timer": 0.0, "depleted": false
	}

## Feature (v11.8, Frettchen-Persönlichkeiten): durchschnittlicher
## Produktions-Bonus aus den Traits der hier zugewiesenen Arbeiter (aktuell
## nur "Fleissig"/DILIGENT, +10% je Fleissigem, gemittelt über ALLE
## zugewiesenen Arbeiter - nicht nur die aktiven, analog zu max_workers-
## basierten Boni). Wird in allen Produktions-Funktionen unten als
## zusätzlicher Multiplikator angewendet, siehe FerretTraits.gd.
func get_worker_trait_bonus() -> float:
	if assigned_workers.is_empty(): return 0.0
	var total: float = 0.0
	for w in assigned_workers:
		var fe: FerretEntity = w
		if fe.trait_id == "DILIGENT":
			total += 0.10
	return total / float(assigned_workers.size())

@warning_ignore("unused_parameter")
func _collect(dt: float, world: Array) -> void:
	if collects_resource == "": return
	# Feature (v11.0): aktive Arbeiterzahl statt Rohzahl - ein Frettchen, das
	# gerade Ressourcen zum Lagerhaus trägt, produziert in der Zeit nichts.
	var workers: int = get_active_worker_count()
	if workers == 0: return
	var level_bonus: float = float(level - 1) * 0.35
	var base_rate: float = production_speed * dt * float(workers) * 0.35 * (1.0 + get_worker_trait_bonus())
	if collects_resource == "WATER":
		# Bug-Fix/Feature (Wasserphysik): Fördermenge hängt jetzt vom
		# TATSAECHLICHEN, simulierten Wasserstand in der Umgebung ab
		# (WaterSystem.gd) statt nur von der statischen Biom-Zugehörigkeit.
		# Trocknet der nahe Fluss/See während einer Dürre aus, sinkt die
		# Förderleistung entsprechend - genau das macht Dämme strategisch
		# wertvoll, da sie den lokalen Pegel länger hochhalten.
		# Bug-Fix (v14.6): Bonus aus dem Wasservolumen in Reichweite (siehe
		# WaterSys.get_water_volume_near()) - ~3 Pegel-Einheiten = voller Bonus.
		var avg_level: float = minf(1.0, WaterSys.get_water_volume_near(tile_x, tile_y, collection_radius) / 3.0)
		# Bug-Fix (v13.7, gemeldet: "Wasserbeschaffung noch verbuggt"): war
		# vorher clampf(avg_level, 0.0, 1.5) - lag ein Brunnen auch nur knapp
		# ausserhalb des collection_radius zu jeder Wasserkachel, war
		# avg_level exakt 0.0 und der Brunnen produzierte für immer NULL
		# Wasser, ohne dass das irgendwo sichtbar war (kein Warnhinweis, kein
		# Fehler - er stand einfach nur permanent bei 0/Kapazität). Jetzt
		# gibt es einen kleinen garantierten Sockel (0.22 statt 0.0 als
		# Minimum) - ein Brunnen fördert immer wenigstens ein bisschen
		# Grundwasser, auch fernab von sichtbarem Oberflächenwasser. Nähe zu
		# einem See/Fluss bleibt weiterhin deutlich effizienter, und eine
		# Dürre senkt die Förderung immer noch stark (siehe DroughtSystem) -
		# nur eben nie mehr auf hart Null für immer.
		var level_factor: float = clampf(0.22 + avg_level / 1.0, 0.22, 1.5)
		ResourceSys.add_water(base_rate * level_factor * (1.0 + level_bonus + waterwheel_boost))
	elif collects_resource == "SCIENCE":
		# Feature (Tech Tree): Wissenspunkte fliessen wie Wasser direkt in
		# einen globalen Pool statt in ein lokales Lager - sie werden nicht
		# von Frettchen zu einem Lagerhaus getragen (siehe ResourceSystem.science).
		ResourceSys.add_science(base_rate * (1.0 + level_bonus + waterwheel_boost))
	else:
		# Feature (v11.0): ist das lokale Lager voll, kann das Gebäude die
		# Ernte nirgends mehr ablegen - die Produktion stoppt komplett, bis es
		# wieder Platz hat (siehe Anfrage: "Produktion stoppt immer, wenn das
		# interne Lager voll ist").
		if is_local_storage_full(): return
		var rate: float = base_rate * (1.0 + waterwheel_boost + level_bonus)
		# Feature (v10.10): die Fördermenge hängt jetzt auch davon ab, ob
		# überhaupt eine erntbare Quelle (WOOD/STONE/BERRIES/IRON) in
		# Reichweite liegt - sind alle Quellen gerade erschöpft (siehe
		# FerretEntity-Ernte-Logik), fällt die Ausbeute deutlich ab statt
		# unbeeindruckt weiterzulaufen.
		if collects_resource in ["WOOD", "STONE", "BERRIES", "IRON"] and not _has_nearby_node(world):
			rate *= 0.35
		local_add(collects_resource, rate)

## Prüft, ob im Sammelradius mindestens eine aktuell erntbare Resource-Node
## des passenden Typs liegt (siehe FerretEntity._find_harvestable_node, hier
## bewusst dieselbe Logik in kompakter Form, da BuildingEntity nicht von
## FerretEntity abhängen soll).
func _has_nearby_node(world: Array) -> bool:
	if collects_resource == "": return false
	var r: int = collection_radius
	var ww: int = world.size()
	for dx in range(-r, r + 1):
		var tx: int = tile_x + dx
		if tx < 0 or tx >= ww: continue
		var col: Array = world[tx]
		var hh: int = col.size()
		for dy in range(-r, r + 1):
			var ty: int = tile_y + dy
			if ty < 0 or ty >= hh: continue
			var node_data = (col[ty] as Dictionary).get("resource_node")
			if node_data == null or not (node_data is Dictionary): continue
			var nd: Dictionary = node_data
			if str(nd.get("type", "")) != collects_resource: continue
			if bool(nd.get("depleted", false)): continue
			if float(nd.get("amount", 0.0)) > 1.0: return true
	return false

func _process(dt: float) -> void:
	if produces == "": return
	var chains: Dictionary = BuildingData.PRODUCTION_CHAINS
	if not chains.has(produces): return
	var workers: int = get_active_worker_count()
	if workers == 0: return
	if is_local_storage_full(): return
	if needs_input and not ResourceSys.can_produce(produces): return
	var bonus: float = float(workers) / maxf(1.0, float(max_workers))
	production_progress += dt * production_speed * bonus * (1.0 + waterwheel_boost) * (1.0 + get_worker_trait_bonus())
	var chain: Dictionary = chains[produces]
	var chain_time: float = float(chain.get("time", 5.0))
	if production_progress >= chain_time:
		production_progress = 0.0
		# Feature (v11.0): Inputs kommen weiterhin aus dem globalen Lagerpool,
		# der Output landet aber im lokalen Lager dieses Gebäudes statt
		# direkt global - muss erst per Frettchen ins Lagerhaus getragen
		# werden, bevor er für Baukosten o.ä. verfügbar ist.
		if needs_input:
			if not ResourceSys.consume_inputs(produces): return
		local_add(produces, float(chain.get("output", 1.0)))

func _multi_process(dt: float) -> void:
	if recipes.is_empty() or assigned_workers.is_empty(): return
	var workers: int = get_active_worker_count()
	if workers == 0: return
	if is_local_storage_full(): return
	var bonus: float = float(workers) / maxf(1.0, float(max_workers))
	production_progress += dt * production_speed * bonus * (1.0 + get_worker_trait_bonus())
	var priority: Array = ["STEW", "COOKED_MEAT", "BREAD", "FOOD"]
	var chosen: String = ""
	for r in priority:
		if r in recipes and ResourceSys.can_produce(r):
			chosen = r; break
	if chosen == "":
		production_progress = 0.0; return
	var chains: Dictionary = BuildingData.PRODUCTION_CHAINS
	var chain: Dictionary = chains[chosen]
	if production_progress >= float(chain.get("time", 5.0)):
		production_progress = 0.0
		if not ResourceSys.consume_inputs(chosen): return
		local_add(chosen, float(chain.get("output", 1.0)))

func _hunt(dt: float) -> void:
	var workers: int = get_active_worker_count()
	if workers == 0: return
	if is_local_storage_full(): return
	var rate: float = production_speed * dt * maxf(1.0, float(workers)) * 0.04 * (1.0 + get_worker_trait_bonus())
	local_add("MEAT", rate)

## Feature (v14.5, Timberborn-Feld-System): ersetzt die alte, rein
## arbeiterzahl-basierte _farm()-Formel (früher CROP_FIELD/WHEAT_FARM).
## Der Bauernhof selbst erzeugt KEIN WHEAT direkt - er lässt seine aktiven
## Arbeiter EIN vom Spieler gesetztes Feld (FarmFieldSystem.gd) im eigenen
## Bezirk bestellen: zuerst ein READY-Feld ernten (falls vorhanden und
## lokales Lager nicht voll), sonst ein EMPTY-Feld besäen. Das eigentliche
## Wachstum (GROWING -> READY) läuft unabhängig davon zentral in
## FarmFieldSystem.update(). Mehr Arbeiter/höherer production_speed (Tech-
## Tree) verkürzen das Intervall zwischen zwei Aktionen - analog zum
## Intervall-Muster von _plant_trees() bei der Försterei.
const FARMHOUSE_BASE_INTERVAL: float = 5.0
const FARMHOUSE_HARVEST_YIELD: float = 12.0

func _farmhouse(dt: float) -> void:
	var workers: int = get_active_worker_count()
	if workers == 0: return
	_farmhouse_timer += dt
	var interval: float = FARMHOUSE_BASE_INTERVAL / (float(workers) * production_speed * (1.0 + get_worker_trait_bonus()))
	if _farmhouse_timer < interval: return
	_farmhouse_timer = 0.0
	if FarmSys.count_in_district(district_id) == 0:
		# Sichtbarkeit von Ursache/Wirkung (siehe Projektprinzipien): ohne
		# zugewiesene Feld-Kacheln haben die Arbeiter schlicht nichts zu
		# tun - das soll sich nicht wie ein stummer Bug anfühlen. Nur EINMAL
		# melden, nicht jedes Intervall erneut.
		if not _warned_no_fields:
			_warned_no_fields = true
			GameState.notify(name + ": keine Feld-Kacheln im Bezirk zugewiesen!", Color(0.55, 0.4, 0.1, 0.92))
		return
	_warned_no_fields = false
	if not is_local_storage_full():
		var ready_field = FarmSys.find_field(district_id, "READY")
		if ready_field != null:
			ready_field["state"] = "EMPTY"
			ready_field["growth"] = 0.0
			local_add(collects_resource if collects_resource != "" else "WHEAT",
				FARMHOUSE_HARVEST_YIELD * (1.0 + get_worker_trait_bonus()))
			return
	var empty_field = FarmSys.find_field(district_id, "EMPTY")
	if empty_field != null:
		empty_field["state"] = "GROWING"
		empty_field["growth"] = 0.0

func get_upgrade_costs() -> Dictionary:
	if level >= 3: return {}
	var result: Dictionary = {}
	for res in costs:
		result[res] = int(float(costs[res]) * (1.0 + float(level) * 0.5))
	return result

## Feature (v16.6, Erkundung): wächst der aufgedeckte Radius mit der Arbeit der Besatzung bis zum Maximum
## (collection_radius, +50% je Level). Die Fläche wird nur bei sichtbarer Änderung neu aufgedeckt.
func get_max_explore_radius() -> float:
	return float(collection_radius) * (1.0 + 0.5 * float(level - 1))

func _explore(dt: float) -> void:
	if not ExploreSys.enabled: return
	var max_r: float = get_max_explore_radius()
	if explore_radius_now >= max_r:
		if not _explore_done_notified:
			_explore_done_notified = true
			GameState.notify("🔭 Erkundung abgeschlossen: Radius %d aufgedeckt. Ein Upgrade der Station deckt mehr auf." % int(max_r), Color(0.45, 0.8, 0.5))
		return
	_explore_done_notified = false
	explore_radius_now = minf(max_r, explore_radius_now + dt * 0.3 * float(assigned_workers.size()) * production_speed)
	if floorf(explore_radius_now * 2.0) != floorf(_explore_last_r * 2.0):
		_explore_last_r = explore_radius_now
		ExploreSys.reveal_circle(tile_x, tile_y, explore_radius_now)

func upgrade() -> bool:
	if level >= 3: return false
	var up_costs: Dictionary = get_upgrade_costs()
	if not ResourceSys.can_afford(up_costs): return false
	ResourceSys.spend(up_costs)
	level += 1
	production_speed *= 1.35
	if max_workers > 0: max_workers += 1
	return true

func serialize() -> Dictionary:
	return {
		"id": id, "tile_x": tile_x, "tile_y": tile_y,
		"is_under_construction": is_under_construction,
		"construction_progress": construction_progress,
		"level": level, "production_progress": production_progress,
		"work_priority": work_priority, "placed_day": placed_day,
		"worker_cap": worker_cap,
		"local_storage": local_storage.duplicate(),
		"delivered_resources": delivered_resources.duplicate(),
		"storage_filter": storage_filter,
		"is_rebuild": is_rebuild,
		"rebuild_target_id": rebuild_target_id,
		"costs": costs.duplicate(),
		"district_id": district_id,
		"colony_id": colony_id,
		"explore_radius_now": explore_radius_now
	}

static func deserialize(data: Dictionary) -> BuildingEntity:
	var b: BuildingEntity = BuildingEntity.from_type(
		str(data.get("id", "")), int(data.get("tile_x", 0)), int(data.get("tile_y", 0)))
	if b == null: return null
	b.is_under_construction = bool(data.get("is_under_construction", false))
	b.construction_progress = float(data.get("construction_progress", b.construction_work_needed))
	b.level = int(data.get("level", 1))
	b.production_progress = float(data.get("production_progress", 0.0))
	b.work_priority = int(data.get("work_priority", 3))
	b.placed_day = int(data.get("placed_day", 0))
	b.worker_cap = int(data.get("worker_cap", -1))
	b.storage_filter = str(data.get("storage_filter", ""))
	b.is_rebuild = bool(data.get("is_rebuild", false))
	b.rebuild_target_id = str(data.get("rebuild_target_id", ""))
	# Feature (v11.11, Distrikt-System): fehlt bei alten Saves komplett -
	# Fallback 0 ("Hauptbezirk") ist bereits der Feld-Default.
	b.district_id = int(data.get("district_id", 0))
	b.colony_id = int(data.get("colony_id", 0))
	b.explore_radius_now = float(data.get("explore_radius_now", 0.0))
	# Feature (Tech Tree): während eines laufenden Umbaus (is_under_construction
	# UND is_rebuild) weichen die aktuellen Baustellen-Kosten von den normalen
	# Basiskosten des Gebäudetyps ab (siehe start_rebuild()) - die müssen aus
	# dem Save wiederhergestellt werden, sonst würde nach dem Laden plötzlich
	# wieder nach den vollen Neubau-Kosten verlangt.
	if b.is_under_construction and b.is_rebuild:
		var saved_costs = data.get("costs", {})
		if saved_costs is Dictionary and not (saved_costs as Dictionary).is_empty():
			var costs_clean: Dictionary = {}
			for k in (saved_costs as Dictionary):
				costs_clean[k] = float((saved_costs as Dictionary)[k])
			b.costs = costs_clean
	var ls = data.get("local_storage", {})
	if ls is Dictionary:
		var ls_clean: Dictionary = {}
		for k in (ls as Dictionary):
			ls_clean[k] = float((ls as Dictionary)[k])
		b.local_storage = ls_clean
	var dr = data.get("delivered_resources", {})
	if dr is Dictionary:
		var dr_clean: Dictionary = {}
		for k in (dr as Dictionary):
			dr_clean[k] = float((dr as Dictionary)[k])
		b.delivered_resources = dr_clean
	# Ältere Saves (vor v11.0) kennen kein delivered_resources/Materiallogistik
	# - bereits fertige Gebäude gelten automatisch als voll belieferter,
	# damit sie nicht plötzlich wieder "auf Material warten" müssen.
	if not b.is_under_construction and b.delivered_resources.is_empty():
		b.delivered_resources = b.costs.duplicate()
	return b
