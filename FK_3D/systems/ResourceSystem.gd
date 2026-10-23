## ResourceSystem.gd
extends Node

# Bug-Fix (v10.10): BASE_STORAGE_CAPACITY war 80.0, obwohl die Start-
# Ressourcen (WOOD 50 + STONE 30 + BERRIES 20 = 100) das bereits überschreiten.
# get_free_space() = max(0, capacity - total_stored) war dadurch von Anfang an
# IMMER 0 - jede Produktion (add()) lief seither komplett leer, bis genug
# STORAGE-Gebäude gebaut waren, um die Kapazität über 100 zu heben. Das war
# der Hauptgrund für "Gebäude gebaut, aber keine Ressourcen produziert".
# Jetzt mit spürbarem Puffer über den Startressourcen.
const BASE_STORAGE_CAPACITY: float = 150.0

var resources: Dictionary = {}
var water: float = 20.0
var water_capacity: float = 50.0
var storage_capacity: float = BASE_STORAGE_CAPACITY

## Feature (Tech Tree): Wissenspunkte. Bewusst analog zu "water" ein eigenes,
## UNGEDECKELTES Feld ausserhalb von "resources" - Wissenspunkte werden nicht
## von Frettchen durchs Lagernetzwerk getragen (siehe RESEARCH_HUT in
## BuildingEntity._collect(), collects_resource == "SCIENCE"), sondern fliessen
## direkt in diesen globalen Pool, aus dem der Tech Tree Knoten und Epochen
## bezahlt (siehe TechTree.gd).
var science: float = 0.0

## Feature (v16.0, Kolonie-Fundament): jede Kolonie hat einen eigenen Ressourcen-Pool.
## Die Felder resources / water / water_capacity / storage_capacity oben sind
## IMMER der Pool der Kolonie `current_colony` - so funktionieren alle ~25
## bestehenden Zugriffe (HUD, Frettchen, Gebäude, ...) unverändert. use_colony()
## tauscht die Felder aus (resources ist ein Dictionary = nur ein Zeiger-Tausch,
## die drei Floats werden zurückgeschrieben). Wissenspunkte (science) bleiben
## bewusst GLOBAL: ein Forschungsstand für alle Kolonien.
## Konvention: Simulationsschleifen setzen den Kontext je Kolonie und stellen
## am Ende immer die AKTIVE Kolonie (ColonySys.active_id) wieder her.
var pools: Dictionary = {}          # colony_id (int) -> {"resources","water","water_capacity","storage_capacity"}
var current_colony: int = 0

func _save_current() -> void:
	pools[current_colony] = {
		"resources": resources, "water": water,
		"water_capacity": water_capacity, "storage_capacity": storage_capacity
	}

static func _new_pool() -> Dictionary:
	return {
		"resources": _default_resources(), "water": 20.0,
		"water_capacity": 50.0, "storage_capacity": BASE_STORAGE_CAPACITY
	}

## Legt den (leeren) Pool einer neuen Kolonie an, optional mit Startbestand.
func create_pool(id: int, start_resources: Dictionary = {}, start_water: float = 20.0) -> void:
	if id == current_colony: _save_current()
	var p: Dictionary = _new_pool()
	var res: Dictionary = p["resources"] as Dictionary
	for k in start_resources:
		if res.has(k): res[k] = float(start_resources[k])
	p["water"] = start_water
	pools[id] = p
	if id == current_colony: use_colony(id, true)

## Macht den Pool der Kolonie `id` zum "aktuellen" (siehe Kopfkommentar).
func use_colony(id: int, force: bool = false) -> void:
	if not force and id == current_colony and pools.has(id): return
	_save_current()
	if not pools.has(id): pools[id] = _new_pool()
	var p: Dictionary = pools[id] as Dictionary
	current_colony = id
	resources = p["resources"] as Dictionary
	water = float(p["water"])
	water_capacity = float(p["water_capacity"])
	storage_capacity = float(p["storage_capacity"])

## Kurzübersicht eines Pools, OHNE den Kontext zu wechseln (für Kolonie-Panel).
func pool_info(id: int) -> Dictionary:
	var res: Dictionary = resources
	var w: float = water; var wc: float = water_capacity; var sc: float = storage_capacity
	if id != current_colony:
		if not pools.has(id): return {"stored": 0.0, "capacity": BASE_STORAGE_CAPACITY, "water": 0.0, "water_capacity": 50.0}
		var p: Dictionary = pools[id] as Dictionary
		res = p["resources"] as Dictionary
		w = float(p["water"]); wc = float(p["water_capacity"]); sc = float(p["storage_capacity"])
	var total: float = 0.0
	for k in res: total += float(res[k])
	return {"stored": total, "capacity": sc, "water": w, "water_capacity": wc}

## Alle bekannten Ressourcen-Keys mit Default-Wert 0 - einzige Quelle der
## Wahrheit für init() UND deserialize() (siehe dort), damit beide niemals
## auseinanderlaufen können.
static func _default_resources() -> Dictionary:
	return {
		"WOOD": 0.0, "STONE": 0.0, "BERRIES": 0.0,
		"PLANKS": 0.0, "TOOLS": 0.0, "FOOD": 0.0,
		"IRON": 0.0, "IRON_BARS": 0.0, "MACHINES": 0.0,
		"COAL": 0.0, "STEEL": 0.0, "MEAT": 0.0,
		"DYNAMITE": 0.0, "WHEAT": 0.0, "COOKED_MEAT": 0.0,
		"BREAD": 0.0, "STEW": 0.0
	}

func init() -> void:
	pools = {}
	current_colony = 0
	resources = _default_resources()
	resources["WOOD"] = 50.0
	resources["STONE"] = 30.0
	resources["BERRIES"] = 20.0
	water = 20.0
	water_capacity = 50.0
	storage_capacity = BASE_STORAGE_CAPACITY
	science = 0.0

func add_science(amount: float) -> void:
	science = maxf(0.0, science + amount)
	GameState.hud_update_requested.emit()

func spend_science(amount: float) -> bool:
	if science < amount: return false
	science -= amount
	GameState.hud_update_requested.emit()
	return true

func has_science(amount: float) -> bool:
	return science >= amount

func add_water(amount: float) -> void:
	water = minf(water_capacity, water + amount)

func remove_water(amount: float) -> float:
	var actual: float = minf(water, amount)
	water = maxf(0.0, water - actual)
	return actual

func has_water(amount: float) -> bool:
	return water >= amount

func update_water_capacity(buildings: Array) -> void:
	var cap: float = 50.0
	for b in buildings:
		var be: BuildingEntity = b
		if not be.is_under_construction:
			cap += be.water_capacity
	water_capacity = cap

func get_total_stored() -> float:
	var total: float = 0.0
	for key in resources:
		total += float(resources[key])
	return total

func get_free_space() -> float:
	return maxf(0.0, storage_capacity - get_total_stored())

func update_capacity(buildings: Array) -> void:
	var cap: float = BASE_STORAGE_CAPACITY
	for b in buildings:
		var be: BuildingEntity = b
		if not be.is_under_construction:
			cap += be.storage_capacity
	storage_capacity = cap

func add(res_type: String, amount: float) -> float:
	if not resources.has(res_type):
		return 0.0
	var free: float = INF if GameState.dev_unlimited_storage else get_free_space()
	var to_add: float = minf(amount, free)
	if to_add > 0.0:
		resources[res_type] = float(resources[res_type]) + to_add
		GameState.resource_changed.emit(res_type, float(resources[res_type]))
	return to_add

func force_add(res_type: String, amount: float) -> void:
	if resources.has(res_type):
		resources[res_type] = float(resources[res_type]) + amount

func remove(res_type: String, amount: float) -> bool:
	if has(res_type, amount):
		resources[res_type] = float(resources[res_type]) - amount
		GameState.resource_changed.emit(res_type, float(resources[res_type]))
		return true
	return false

func has(res_type: String, amount: float) -> bool:
	return float(resources.get(res_type, 0.0)) >= amount

func can_afford(costs: Dictionary) -> bool:
	for res in costs:
		if res == "WATER":
			if not has_water(float(costs[res])): return false
		elif not has(res, float(costs[res])): return false
	return true

func spend(costs: Dictionary) -> bool:
	if not can_afford(costs): return false
	for res in costs:
		if res == "WATER": remove_water(float(costs[res]))
		else: remove(res, float(costs[res]))
	return true

func can_produce(output: String) -> bool:
	var chains: Dictionary = BuildingData.PRODUCTION_CHAINS
	if not chains.has(output): return false
	var chain: Dictionary = chains[output]
	var inputs: Dictionary = chain["inputs"]
	for res in inputs:
		if not has(res, float(inputs[res])): return false
	return true

func produce(output: String) -> bool:
	if not can_produce(output): return false
	var chain: Dictionary = BuildingData.PRODUCTION_CHAINS[output]
	var inputs: Dictionary = chain["inputs"]
	for res in inputs:
		remove(res, float(inputs[res]))
	add(output, float(chain["output"]))
	return true

## Feature (v11.0, Lagersystem): Gegenstück zu produce(), das NUR die
## Input-Ressourcen verbraucht und KEINEN Output addiert. Produktionsgebäude
## haben jetzt ein eigenes, begrenztes lokales Lager (siehe BuildingEntity.
## local_storage) - der Output landet dort statt direkt im globalen Pool, die
## Inputs (Rohstoffe aus dem Lagernetzwerk) werden aber weiterhin hier global
## entnommen, da sie bereits per Frettchen-Logistik bis zum globalen Pool
## transportiert worden sein müssen, bevor ein Gebäude sie verarbeiten kann.
func consume_inputs(output: String) -> bool:
	if not can_produce(output): return false
	var chain: Dictionary = BuildingData.PRODUCTION_CHAINS[output]
	var inputs: Dictionary = chain["inputs"]
	for res in inputs:
		remove(res, float(inputs[res]))
	return true

func serialize() -> Dictionary:
	_save_current()
	var pools_out: Dictionary = {}
	for id in pools:
		var p: Dictionary = pools[id] as Dictionary
		pools_out[str(id)] = {
			"resources": (p["resources"] as Dictionary).duplicate(),
			"water": float(p["water"]), "water_capacity": float(p["water_capacity"]),
			"storage_capacity": float(p["storage_capacity"])
		}
	# Top-Level-Felder = Pool der Kolonie 0 (so liest auch jeder ältere Code den Save).
	var base: Dictionary = pools_out.get("0", {}) as Dictionary
	return {
		"resources": (base.get("resources", resources) as Dictionary).duplicate(),
		"water": float(base.get("water", water)),
		"water_capacity": float(base.get("water_capacity", water_capacity)),
		"storage_capacity": float(base.get("storage_capacity", storage_capacity)),
		"science": science,
		"pools": pools_out
	}

func deserialize(data: Dictionary) -> void:
	# Bug-Fix (v10.14): "Alte Saves können Ressourcen-Schlüssel verlieren".
	# resources wurde bisher komplett durch das gespeicherte Dictionary
	# ERSETZT. Ein Save aus einer älteren Version (z.B. noch ohne WHEAT,
	# COOKED_MEAT, BREAD, STEW oder DYNAMITE) hatte diese Keys schlicht
	# nicht - add() schlägt für unbekannte Keys aber leise fehl
	# (resources.has(res_type) == false), das jeweilige Gebäude hätte dann
	# für IMMER nichts mehr produziert, ohne jede Fehlermeldung. Jetzt wird
	# mit dem aktuellen Default-Set (alle Keys = 0) gestartet und nur mit
	# den im Save vorhandenen Werten überschrieben - fehlende Keys bleiben
	# einfach bei 0, statt komplett zu fehlen.
	var defaults: Dictionary = _default_resources()
	var saved: Dictionary = data.get("resources", {}) as Dictionary
	for res in saved:
		defaults[res] = float(saved[res])
	resources = defaults
	water = float(data.get("water", 20.0))
	water_capacity = float(data.get("water_capacity", 50.0))
	storage_capacity = float(data.get("storage_capacity", BASE_STORAGE_CAPACITY))
	science = float(data.get("science", 0.0))
	# Feature (v16.0, Kolonie-Fundament): Top-Level-Felder oben = Kolonie 0 (so
	# lesen sich auch Saves von vor v16.0). Weitere Kolonien stehen in "pools".
	pools = {}
	current_colony = 0
	_save_current()
	var saved_pools: Dictionary = data.get("pools", {}) as Dictionary
	for k in saved_pools:
		var id: int = int(k)
		if id == 0: continue
		var sp: Dictionary = saved_pools[k] as Dictionary
		var pres: Dictionary = _default_resources()
		var sres: Dictionary = sp.get("resources", {}) as Dictionary
		for rk in sres: pres[rk] = float(sres[rk])
		pools[id] = {
			"resources": pres, "water": float(sp.get("water", 20.0)),
			"water_capacity": float(sp.get("water_capacity", 50.0)),
			"storage_capacity": float(sp.get("storage_capacity", BASE_STORAGE_CAPACITY))
		}
