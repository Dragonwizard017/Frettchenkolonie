## BuildingSystem.gd
extends Node

var buildings: Array = []
var _warn_full: Dictionary = {}   # colony_id -> bool (v16.0: Lager-voll-Warnung pro Kolonie)
var _warn_timer: float = 0.0

# Feature (v14.1, Nutzerwunsch "Warum passiert nichts?"-Hinweise): erkennt
# Baustellen, die seit einer Weile keinen Fortschritt mehr machen UND noch
# nicht voll beliefert sind (typischste Ursache: kein Sammler/Lager mit den
# fehlenden Materialien in Reichweite, oder alle Frettchen anderweitig
# beschäftigt) - statt dass die Baustelle einfach stumm ewig herumsteht.
var _stall_track: Dictionary = {}      # "tx,ty" -> {"progress": float, "ticks": int}
var _stall_notified: Dictionary = {}   # "tx,ty" -> bool (schon gemeldet, nicht wiederholen)

func init() -> void:
	buildings = []
	_warn_full = {}
	_warn_timer = 0.0
	_stall_track = {}
	_stall_notified = {}

## Feature (v16.0, Kolonie-Fundament): alle Gebäude EINER Kolonie. Mit nur einer
## Kolonie (Normalfall) wird die Liste ohne Kopie zurückgegeben.
func get_colony_buildings(cid: int) -> Array:
	if ColonySys.count() <= 1: return buildings
	var out: Array = []
	for b in buildings:
		if (b as BuildingEntity).colony_id == cid: out.append(b)
	return out

func update(dt: float, is_day: bool, world: Array) -> void:
	# Jede Kolonie wird im Kontext IHRES Ressourcen-Pools simuliert.
	for cid_v in ColonySys.ids():
		var cid: int = int(cid_v)
		ResourceSys.use_colony(cid)
		if ColonySys.is_npc(cid):
			# v16.7: Nachbarkolonien werden nicht simuliert (ihre Wirtschaft macht NeighborSys); nur das Lager-Limit zählt
			ResourceSys.update_capacity(get_colony_buildings(cid))
			continue
		_update_colony(get_colony_buildings(cid), dt, is_day, world)
	ResourceSys.use_colony(ColonySys.active_id)

	_warn_timer += dt
	if _warn_timer > 10.0:
		_warn_timer = 0.0
		for cid_v in ColonySys.ids():
			var cid2: int = int(cid_v)
			if ColonySys.is_npc(cid2): continue
			ResourceSys.use_colony(cid2)
			var pct: float = ResourceSys.get_total_stored() / maxf(1.0, ResourceSys.storage_capacity)
			var was_full: bool = bool(_warn_full.get(cid2, false))
			if pct > 0.95 and not was_full:
				_warn_full[cid2] = true
				var who: String = "" if ColonySys.count() <= 1 else " (%s)" % ColonySys.get_name_of(cid2)
				GameState.notify("Lager voll%s! Ressourcen gehen verloren. Baue mehr Lager!" % who, Color(0.8, 0.3, 0.1))
			elif pct < 0.8:
				_warn_full[cid2] = false
		ResourceSys.use_colony(ColonySys.active_id)
		_check_stalled_construction()

func _update_colony(blist: Array, dt: float, is_day: bool, world: Array) -> void:
	ResourceSys.update_capacity(blist)
	ResourceSys.update_water_capacity(blist)

	# Wasserrad-Boosts zurücksetzen
	for b in blist:
		var be: BuildingEntity = b
		be.waterwheel_boost = 0.0

	# Wasserrad-Boosts berechnen
	for b in blist:
		var ww: BuildingEntity = b
		if ww.btype != "WATERWHEEL" or ww.is_under_construction or ww.assigned_workers.is_empty():
			continue
		var has_water_near: bool = false
		for dx in range(-3, 4):
			for dy in range(-3, 4):
				var wx: int = ww.tile_x + dx
				var wy: int = ww.tile_y + dy
				if wx < 0 or wy < 0 or wx >= world.size(): continue
				var col: Array = world[wx]
				if wy >= col.size(): continue
				var tile: Dictionary = col[wy]
				# Feature (Wasserphysik): Wasserrad braucht jetzt TATSAECHLICH
				# fliessendes/stehendes Wasser (water_level), nicht nur die
				# statische WATER-Biom-Zugehörigkeit - trocknet der Fluss in
				# einer Dürre komplett aus, steht das Wasserrad still, genau
				# wie eine Wassermühle in Timberborn ohne Wasserzufluss.
				if float(tile.get("water_level", 0.0)) > 0.15:
					has_water_near = true; break
			if has_water_near: break
		if not has_water_near: continue
		# Feature (Tech Tree): "Wasserradoptimierung" erhöht den Boost-Faktor
		# jedes Wasserrads global (siehe TechTree.gd, Themenbereich WATER).
		var effective_boost: float = ww.boost_factor + TechTreeSys.get_global_bonus("waterwheel_boost_bonus")
		for other in blist:
			var ob: BuildingEntity = other
			if ob.is_under_construction: continue
			var dist: int = abs(ob.tile_x - ww.tile_x) + abs(ob.tile_y - ww.tile_y)
			if dist <= int(ww.boost_radius):
				ob.waterwheel_boost += effective_boost

	for b in blist:
		var be: BuildingEntity = b
		be.update(dt, is_day, world)

## Feature (v14.1): läuft alle 10s mit. Eine Baustelle gilt als "hängt fest",
## wenn sich ihr Baufortschritt seit dem letzten Check nicht bewegt hat UND
## sie noch nicht voll mit Material beliefert ist - nach 3 solchen Checks
## in Folge (~30s) kommt EINMALIG ein Hinweis mit den konkret fehlenden
## Ressourcen, statt dass der Spieler nur rätselt, warum nichts vorangeht.
func _check_stalled_construction() -> void:
	var still_active: Dictionary = {}
	for site_any in get_construction_sites():
		var site: BuildingEntity = site_any
		var key: String = "%d,%d" % [site.tile_x, site.tile_y]
		still_active[key] = true
		if site.is_fully_supplied():
			_stall_track.erase(key); _stall_notified.erase(key)
			continue
		var prev: Dictionary = _stall_track.get(key, {"progress": -1.0, "ticks": 0})
		var prev_progress: float = float(prev.get("progress", -1.0))
		if absf(site.construction_progress - prev_progress) < 0.01:
			var ticks: int = int(prev.get("ticks", 0)) + 1
			_stall_track[key] = {"progress": site.construction_progress, "ticks": ticks}
			if ticks == 3 and not bool(_stall_notified.get(key, false)):
				_stall_notified[key] = true
				var missing: Array = []
				for res in site.costs:
					var m: float = site.get_missing_amount(str(res))
					if m > 0.01:
						missing.append("%s×%d" % [str(BuildingData.RESOURCE_ICONS.get(str(res), str(res))), int(ceil(m))])
				var missing_txt: String = ""
				for i in missing.size():
					missing_txt += str(missing[i])
					if i < missing.size() - 1: missing_txt += ", "
				GameState.notify(
					"Baustelle '%s' bekommt keine Lieferung (fehlt: %s) - baue Sammler/Lager näher dran oder weise mehr Frettchen zu!" % [site.name, missing_txt],
					Color(0.85, 0.55, 0.15)
				)
		else:
			_stall_track[key] = {"progress": site.construction_progress, "ticks": 0}
			_stall_notified.erase(key)
	# aufgeräumte/fertige Baustellen aus der Verfolgung entfernen
	for key in _stall_track.keys().duplicate():
		if not still_active.has(key):
			_stall_track.erase(key); _stall_notified.erase(key)

func build(building_id: String, tx: int, ty: int, world: Array, free: bool = false, colony_override: int = -1) -> BuildingEntity:
	var all_buildings: Dictionary = BuildingData.BUILDINGS
	if not all_buildings.has(building_id): return null
	var data: Dictionary = all_buildings[building_id]
	# Feature (v16.2, Schiene): auf einer Gleiskachel darf nichts stehen - ausser Bahnhof/Depot,
	# die das Gleis ersetzen und selbst Knoten des Netzes werden.
	if RailSys.has_rail(tx, ty):
		if building_id == "STATION" or building_id == "DEPOT": RailSys.remove_rail(tx, ty)
		else: return null
	if not free:
		var costs: Dictionary = data.get("costs", {}) as Dictionary
		# Feature (v11.0, Lagersystem): Baukosten werden NICHT mehr sofort
		# beim Platzieren abgezogen - der can_afford()-Check bleibt als grobes
		# Gate ("ist überhaupt genug im Lagernetzwerk vorhanden"), aber das
		# tatsächliche Verbrauchen passiert jetzt Stück für Stück, wenn
		# Bau-/Lagerfrettchen die Materialien physisch zur Baustelle tragen
		# (siehe BuildingEntity.deliver_resource(), FerretEntity._update_builder_work()).
		if not ResourceSys.can_afford(costs): return null
	var b: BuildingEntity = BuildingEntity.from_type(building_id, tx, ty)
	if b == null: return null
	if free:
		b.delivered_resources = b.costs.duplicate()
	if tx < world.size():
		var col: Array = world[tx]
		if ty < col.size():
			col[ty]["building"] = b
	# Feature (v16.0, Kolonie-Fundament): Kolonie = Gebiet, in dem die Kachel liegt
	# (im Niemandsland - nur Dev-Modus - die aktive Kolonie).
	if colony_override >= 0:
		b.colony_id = colony_override
	else:
		var tile_colony: int = ColonySys.colony_of_tile(tx, ty)
		b.colony_id = tile_colony if tile_colony >= 0 else ColonySys.active_id
	buildings.append(b)
	# Feature (v11.11, Distrikt-System): Zuweisung NACH dem Anhängen an
	# "buildings", da assign_district() bei Bauhof-Gebäuden die restliche
	# Liste nach bereits vorhandenen Bauhöfen durchsucht.
	DistrictSys.assign_district(b, buildings)
	GameState.building_placed.emit(b)
	GameState.hud_update_requested.emit()
	GameState.build_menu_update_requested.emit()
	return b

func build_free(building_id: String, tx: int, ty: int, world: Array, colony_override: int = -1) -> BuildingEntity:
	var b: BuildingEntity = build(building_id, tx, ty, world, true, colony_override)
	if b != null:
		b.is_under_construction = false
		b.construction_progress = b.construction_work_needed
	return b

## Feature (Tech Tree): startet den Umbau eines bereits fertigen Gebäudes,
## sofern BuildingData.REBUILDS einen Eintrag dafür hat und der nötige
## Tech-Knoten bereits freigeschaltet ist (siehe TechTreeSys.can_rebuild()).
## Es gilt bewusst dasselbe can_afford()-Gate wie bei build() - die
## tatsächlichen Kosten werden erst Stück für Stück angeliefert.
func start_rebuild(b: BuildingEntity) -> bool:
	if b == null or b.is_under_construction: return false
	var rd: Dictionary = BuildingData.REBUILDS.get(b.id, {})
	if rd.is_empty(): return false
	if not TechTreeSys.can_rebuild(b.id): return false
	var rc: Dictionary = rd.get("costs", {}) as Dictionary
	if not ResourceSys.can_afford(rc): return false
	b.start_rebuild(str(rd.get("target", "")), rc, float(rd.get("construction_work", 30.0)))
	GameState.hud_update_requested.emit()
	GameState.build_menu_update_requested.emit()
	return true

func sell(b: BuildingEntity, world: Array) -> void:
	if b == null: return
	# Feature (v16.0): ein Rathaus hält die Kolonie zusammen - nicht verkaufbar.
	if b.btype == "TOWN_HALL":
		GameState.notify("Das Rathaus kann nicht verkauft werden.", Color(0.8, 0.3, 0.1))
		return
	if ColonySys.is_npc(b.colony_id):
		GameState.notify("Das gehört einer fremden Kolonie.", Color(0.8, 0.3, 0.1))
		return
	b.remove_all_workers()
	# Crash-Fix: assigned_builder ist eine BuildingEntity (RefCounted) und hat
	# kein current_construction_site-Feld (das gibt es nur auf FerretEntity).
	# Schreiben auf eine nicht deklarierte Property eines RefCounted-Objekts
	# wirft in GDScript 4 einen Laufzeitfehler -> Absturz, sobald dieses Feld
	# jemals belegt wird. Einfach zurücksetzen reicht hier aus.
	b.assigned_builder = null
	for r in b.residents.duplicate():
		var ferret = r
		ferret.home = null
	b.residents = []
	# Feature (v11.0): erstattet wird, was tatsächlich angeliefert wurde
	# (delivered_resources), nicht mehr pauschal die vollen Baukosten - bei
	# einer frisch platzierten, noch unbelieferten Baustelle wäre sonst
	# Material aus dem Nichts erstattet worden, das nie wirklich verbraucht
	# wurde. Für fertige Gebäude ist delivered_resources == costs, das
	# Ergebnis bleibt also wie zuvor.
	# Erstattung in den Pool der Kolonie, zu der das Gebäude gehört (v16.0).
	var prev_colony: int = ResourceSys.current_colony
	ResourceSys.use_colony(b.colony_id)
	for res in b.delivered_resources:
		ResourceSys.force_add(res, floorf(float(b.delivered_resources[res]) * 0.7))
	ResourceSys.use_colony(prev_colony)
	# Feature (v11.11, Distrikt-System): verkauftes Bezirkstor darf keine
	# "geisterhaft" fortbestehende Verbindung hinterlassen.
	if b.btype == "DISTRICT_GATE":
		DistrictSys.remove_gate_link(b)
	if b.tile_x < world.size():
		var col: Array = world[b.tile_x]
		if b.tile_y < col.size():
			col[b.tile_y]["building"] = null
	buildings.erase(b)
	GameState.building_sold.emit(b)
	GameState.hud_update_requested.emit()
	GameState.build_menu_update_requested.emit()

func can_build(building_id: String) -> bool:
	var all_buildings: Dictionary = BuildingData.BUILDINGS
	if not all_buildings.has(building_id): return false
	var data: Dictionary = all_buildings[building_id]
	return ResourceSys.can_afford(data.get("costs", {}) as Dictionary)

func get_construction_sites() -> Array:
	var result: Array = []
	for b in buildings:
		var be: BuildingEntity = b
		if be.is_under_construction: result.append(be)
	return result

func get_buildings_of_type(btype: String) -> Array:
	var result: Array = []
	for b in buildings:
		var be: BuildingEntity = b
		if be.btype == btype and not be.is_under_construction: result.append(be)
	return result

func get_builders() -> Array:
	var result: Array = []
	for b in buildings:
		var be: BuildingEntity = b
		if be.btype in ["BUILDER", "ENGINEERS_GUILD", "CONSTRUCTION_OFFICE"] and \
		   not be.is_under_construction and not be.assigned_workers.is_empty():
			result.append(be)
	return result

func get_total_beds(cid: int = -1) -> int:
	var total: int = 0
	for b in buildings:
		var be: BuildingEntity = b
		if cid >= 0 and be.colony_id != cid: continue
		if be.btype == "HOUSING" and not be.is_under_construction:
			total += be.max_residents
	return total

func get_occupied_beds(cid: int = -1) -> int:
	var total: int = 0
	for b in buildings:
		var be: BuildingEntity = b
		if cid >= 0 and be.colony_id != cid: continue
		if be.btype == "HOUSING" and not be.is_under_construction:
			total += be.residents.size()
	return total

## Feature (Tech Tree, Bugfix): ohne diesen Aufruf wirkten neu erforschte
## Produktions-/Kapazitäts-Boni (TechTree.apply_building_bonuses()) nur auf
## Gebäude, die NACH der Forschung neu gebaut wurden - bereits bestehende
## Gebäude blieben auf ihrem alten Stand eingefroren. Wird von
## TechTree.unlock_node() nach jedem erfolgreichen Knoten-Unlock für alle
## betroffenen Gebäudetypen aufgerufen.
func recalculate_all_bonuses() -> void:
	for b in buildings:
		if b.is_under_construction: continue
		TechTreeSys.apply_building_bonuses(b)

func serialize() -> Array:
	var result: Array = []
	for b in buildings:
		var be: BuildingEntity = b
		result.append(be.serialize())
	return result

func deserialize(data: Array, world: Array) -> void:
	buildings = []
	for bd in data:
		var b: BuildingEntity = BuildingEntity.deserialize(bd as Dictionary)
		if b == null: continue
		if b.tile_x < world.size():
			var col: Array = world[b.tile_x]
			if b.tile_y < col.size():
				col[b.tile_y]["building"] = b
		buildings.append(b)
