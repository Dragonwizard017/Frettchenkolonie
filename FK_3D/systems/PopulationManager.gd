## PopulationManager.gd
extends Node

var ferrets: Array = []
var dead_ferrets: Array = []
var total_happiness: float = 50.0
var growth_timer: float = 0.0
var _death_count: int = 0
var _last_death_count: int = 0
var _last_bed_hint_day: Dictionary = {}           # colony_id -> Tag (v16.0: Hinweise pro Kolonie)
var _last_growth_block_hint_day: Dictionary = {}
## Feature (v16.0, Kolonie-Fundament): Durchschnitts-Glück pro Kolonie. total_happiness
## (von StatsPanel u.a. gelesen) zeigt immer die der AKTIVEN Kolonie.
var colony_happiness: Dictionary = {}

func init(start_pop: int = 5) -> void:
	ferrets = []
	dead_ferrets = []
	total_happiness = 50.0
	growth_timer = 0.0
	_death_count = 0
	_last_death_count = 0
	colony_happiness = {}
	_last_bed_hint_day = {}
	_last_growth_block_hint_day = {}
	for _i in start_pop:
		var f: FerretEntity = FerretEntity.create_random()
		# Tile-Koordinaten: Kartenmitte = (30, 30)
		f.pos = Vector2(30.0 + randf_range(-4.0, 4.0), 30.0 + randf_range(-4.0, 4.0))
		f.target_pos = f.pos
		ferrets.append(f)

func update(dt: float, is_day: bool, world: Array = []) -> void:
	# Feature (v16.0, Kolonie-Fundament): die Frettchen-Liste `ferrets` bleibt EINE
	# Liste (der Renderer ordnet Knoten nach Listenindex zu), die Logik läuft aber
	# je Kolonie im Kontext von deren Ressourcen-Pool.
	var groups: Dictionary = _group_by_colony()
	for cid_v in groups.keys():
		ResourceSys.use_colony(int(cid_v))
		for f in (groups[cid_v] as Array):
			var fe: FerretEntity = f
			# Feature (v11.9, Legendäre Frettchen): Übergang false→true erkennen,
			# um GENAU einmal zu benachrichtigen (kein separates "announced"-Flag
			# nötig - is_legendary ist einmal wahr für immer wahr, siehe
			# FerretEntity.update()/deserialize()).
			var was_legendary: bool = fe.is_legendary
			fe.update(dt, world, is_day)
			if fe.is_legendary and not was_legendary:
				GameState.ferret_became_legendary.emit(fe)
	if not world.is_empty():
		WorldGenerator.tick_resource_nodes(world, dt)

	for cid_v in groups.keys():
		var cid: int = int(cid_v)
		ResourceSys.use_colony(cid)
		_update_colony(cid, groups[cid_v] as Array, dt, is_day)

	# Tote entfernen
	var prev_size: int = ferrets.size()
	var to_die: Array = []
	for f in ferrets:
		var fe: FerretEntity = f
		if fe.health <= 0.0: to_die.append(fe)
	for f in to_die:
		_kill_ferret(f, "Hunger/Durst")
	var alive: Array = []
	for f in ferrets:
		var fe: FerretEntity = f
		if fe.health > 0.0: alive.append(fe)
	ferrets = alive

	if ferrets.size() < prev_size:
		_death_count += prev_size - ferrets.size()
	if _death_count != _last_death_count:
		SoundSys.play_death()
		_last_death_count = _death_count

	growth_timer += dt
	# Feature (Tech Tree): "Meister der Zucht" (BREEDING) verkürzt das
	# Intervall zwischen zwei Wachstumsversuchen - die Kolonie wächst dadurch
	# spürbar schneller.
	var growth_interval: float = 90.0 / (1.0 + TechTreeSys.get_global_bonus("growth_rate_bonus"))
	if growth_timer > growth_interval and is_day:
		growth_timer = 0.0
		for cid_v in groups.keys():
			ResourceSys.use_colony(int(cid_v))
			_try_grow(int(cid_v))

	ResourceSys.use_colony(ColonySys.active_id)
	total_happiness = float(colony_happiness.get(ColonySys.active_id, 50.0))

	if ferrets.is_empty() and dead_ferrets.size() > 0:
		GameState.game_over_triggered.emit("Alle Frettchen sind gestorben!")

## Frettchen nach Kolonie gruppiert (jede bekannte Kolonie ist enthalten, auch
## ohne Frettchen - dort kann trotzdem Nachwuchs entstehen, wie bisher).
func _group_by_colony() -> Dictionary:
	var groups: Dictionary = {}
	for cid in ColonySys.ids():
		if ColonySys.is_npc(int(cid)): continue   # v16.7: Nachbarn haben keine simulierten Frettchen
		groups[int(cid)] = []
	for f in ferrets:
		var fe: FerretEntity = f
		if not groups.has(fe.colony_id): fe.colony_id = 0 if not ColonySys.is_npc(fe.colony_id) else ColonySys.player_ids()[0]
		(groups[fe.colony_id] as Array).append(fe)
	return groups

## Versorgung (Essen/Wasser), Glück, Arbeits- und Wohnungsvergabe EINER Kolonie.
## `cf` = die Frettchen dieser Kolonie; der Ressourcen-Kontext ist bereits gesetzt.
func _update_colony(cid: int, cf: Array, dt: float, is_day: bool) -> void:
	# Nahrung konsumieren
	# Bug-Fix (Frettchen sterben viel zu schnell): FerretEntity.update() lässt
	# needs["food"] mit -0.8/Sek und needs["water"] mit -1.1/Sek verfallen.
	# Die bisherigen Konsum-Konstanten (0.01 bzw. 0.018) ergaben selbst mit
	# vollen Lagern nur ca. +0.05-0.08 Nahrung/Sek und +0.07 Wasser/Sek -
	# zehn- bis fünfzehnmal zu wenig, um den Verfall jemals auszugleichen.
	# Frettchen sind dadurch unabhängig vom Spielerverhalten innerhalb
	# weniger Minuten verhungert/verdurstet. Jetzt großzügig genug bemessen,
	# damit ausreichende Produktion den Bedarf tatsächlich decken kann.
	# Bug-Fix (v14.6, intensives Bugfixing): der Verbrauch war bisher vom
	# tatsächlichen Bedarf entkoppelt - JEDES Frettchen "trank/ass" mit voller
	# Maximalrate (0.6 Wasser/s bzw. 0.4 Nahrung/s), auch wenn sein Bedürfnis-
	# Balken schon bei 100 stand (der Überschuss verpuffte). Gemessen: 5
	# Frettchen verbrauchten ~3 Wasser/s bei einem echten Bedarf von ~0.5/s
	# (Zerfall 0.43/s ÷ Effizienz 4) - Brunnen konnten das nie decken.
	# Jetzt nimmt jedes Frettchen höchstens so viel auf, wie ihm bis 100 fehlt;
	# die MAXIMALE Aufnahmerate pro Sekunde bleibt unverändert.
	if not cf.is_empty():
		var eat_options: Array = [
			{"r": "STEW",        "eff": 8.0},
			{"r": "COOKED_MEAT", "eff": 6.0},
			{"r": "BREAD",       "eff": 5.0},
			{"r": "FOOD",        "eff": 5.0},
			{"r": "BERRIES",     "eff": 3.0},
			{"r": "MEAT",        "eff": 2.0}
		]
		for opt in eat_options:
			var opt_d: Dictionary = opt
			var res: String = str(opt_d["r"])
			var eff: float = float(opt_d["eff"])
			var avail: float = float(ResourceSys.resources.get(res, 0.0))
			if avail < 0.5: continue
			var max_gain: float = 0.4 * dt * eff   # max. Bedürfnispunkte je Frettchen in diesem Tick
			var total_gain: float = 0.0
			for fv in cf:
				var fe: FerretEntity = fv
				total_gain += minf(max_gain, maxf(0.0, 100.0 - float(fe.needs["food"])))
			if total_gain <= 0.0:
				break   # alle satt - nichts verbrauchen
			var units: float = minf(avail, total_gain / eff)
			var scale: float = (units * eff) / total_gain
			ResourceSys.remove(res, units)
			for fv in cf:
				var fe: FerretEntity = fv
				var gain: float = minf(max_gain, maxf(0.0, 100.0 - float(fe.needs["food"]))) * scale
				fe.needs["food"] = minf(100.0, float(fe.needs["food"]) + gain)
			break

		# Wasser (gleiches Prinzip: nur so viel trinken, wie bis 100 fehlt)
		var w_avail: float = ResourceSys.water
		if w_avail > 0.0:
			const WATER_EFF: float = 4.0
			var w_max_gain: float = 0.6 * dt * WATER_EFF
			var w_total_gain: float = 0.0
			for fv in cf:
				var fe: FerretEntity = fv
				w_total_gain += minf(w_max_gain, maxf(0.0, 100.0 - float(fe.needs["water"])))
			if w_total_gain > 0.0:
				var w_units: float = minf(w_avail, w_total_gain / WATER_EFF)
				var w_scale: float = (w_units * WATER_EFF) / w_total_gain
				ResourceSys.remove_water(w_units)
				for fv in cf:
					var fe: FerretEntity = fv
					var w_gain: float = minf(w_max_gain, maxf(0.0, 100.0 - float(fe.needs["water"]))) * w_scale
					fe.needs["water"] = minf(100.0, float(fe.needs["water"]) + w_gain)

	_apply_happiness_bonuses(cid, cf, dt)
	colony_happiness[cid] = _calculate_happiness(cf)
	if is_day:
		_assign_work(cid, cf)
	_assign_homes(cid, cf)

## Bug-Fix (v10.16): "Frettchen vermehren sich nicht" - Gebäude mit
## happiness_bonus/happiness_radius (Versammlungsplatz, Taverne, Wohnhaus,
## Statue, etc.) lasen ihre Werte zwar aus BuildingData.gd in BuildingEntity
## ein, wurden aber NIRGENDS tatsächlich auf needs["happiness"] angewendet.
## Dieser Bedarf sank seit Spielstart nur noch (-0.4/Sek, FerretEntity.gd)
## und erreichte nach 100-175 Sek. dauerhaft 0, ohne je wieder zu steigen.
## Da total_happiness der Durchschnitt aus food/water/happiness ist
## (_calculate_happiness), blieb die Kolonie dadurch praktisch immer unter
## der 50%-Wachstumsschwelle in _try_grow() - die Bevölkerung konnte kaum
## je wachsen, unabhängig von Nahrungsversorgung. Jetzt erhalten Frettchen
## im happiness_radius eines fertigen Gebäudes kontinuierlich
## happiness_bonus * 0.08 Punkte/Sek (z.B. Wohnhaus mit Bonus 5: +0.4/Sek,
## gleicht die Abklingrate genau aus; Versammlungsplatz/Taverne mit
## Bonus 8-15: deutlicher Überschuss in ihrer Reichweite).
func _apply_happiness_bonuses(cid: int, cf: Array, dt: float) -> void:
	for f in cf:
		var fe: FerretEntity = f
		for b in BuildingSys.buildings:
			var be: BuildingEntity = b
			if be.is_under_construction or be.happiness_bonus <= 0.0: continue
			if be.colony_id != cid: continue
			var dx: float = fe.pos.x - float(be.tile_x)
			var dy: float = fe.pos.y - float(be.tile_y)
			if dx * dx + dy * dy <= be.happiness_radius * be.happiness_radius:
				# Feature (v11.8, Frettchen-Persönlichkeiten): "Glückspilz"
				# profitiert deutlich mehr von Glücklichkeits-Gebäuden,
				# "Eigenbrötler" deutlich weniger (siehe FerretEntity.
				# get_happiness_bonus_multiplier()).
				var trait_mult: float = fe.get_happiness_bonus_multiplier()
				fe.needs["happiness"] = minf(100.0, float(fe.needs["happiness"]) + be.happiness_bonus * 0.08 * dt * trait_mult)

## Feature (v10.13): bisher bekamen NUR neu geborene Frettchen (_try_grow())
## ein Haus zugewiesen. Die Start-Population (und Frettchen, deren Haus
## abgerissen/verkauft wurde) blieb dauerhaft heimatlos und musste laut
## Spielwunsch dann nächtlich "auf dem Boden schlafen" - das ist als
## Fallback so gewollt, aber sobald ein freies Bett verfügbar ist, soll es
## auch tatsächlich vergeben werden. Wird jeden Frame aufgerufen, ist aber
## für Frettchen mit Haus ein reines No-Op (continue sofort).
func _assign_homes(cid: int, cf: Array) -> void:
	for f in cf:
		var fe: FerretEntity = f
		if fe.home != null: continue
		for b in BuildingSys.buildings:
			var be: BuildingEntity = b
			if be.btype != "HOUSING" or be.is_under_construction: continue
			if be.colony_id != cid: continue
			if be.residents.size() < be.max_residents:
				be.residents.append(fe)
				fe.home = be
				break

func _kill_ferret(f: FerretEntity, cause: String) -> void:
	f.is_alive = false
	if f.assigned_building != null:
		var ab: BuildingEntity = f.assigned_building
		ab.remove_worker(f)
	if f.home != null:
		var hb: BuildingEntity = f.home
		hb.residents.erase(f)
	var entry: Dictionary = {
		"name": f.ferret_name, "cause": cause,
		"day": DayNight.day_count, "age": int(f.age_days)
	}
	# Feature (v11.9, Legendäre Frettchen): prominenterer Eintrag mit
	# Titel + kurzer Karriere-Zusammenfassung statt nur Name/Tag/Ursache.
	if f.is_legendary:
		entry["is_legendary"] = true
		entry["legendary_title"] = f.legendary_title
		entry["career_days"] = int(f.career_days)
	dead_ferrets.append(entry)
	GameState.ferret_died.emit(f, cause)

func _calculate_happiness(cf: Array) -> float:
	if cf.is_empty(): return 50.0
	var base: float = 0.0
	for f in cf:
		var fe: FerretEntity = f
		base += (float(fe.needs["food"]) + float(fe.needs["water"]) + float(fe.needs["happiness"])) / 3.0
	return base / float(cf.size())

## Vom Spieler über die Gebäude-UI ("+"-Button) aufgerufen: weist sofort ein
## freies Frettchen der Kolonie diesem Gebäude zu, falls eines verfügbar ist
## und noch ein Arbeitsplatz frei ist.
func try_fill_building(b: BuildingEntity) -> bool:
	if b.assigned_workers.size() >= b.get_effective_worker_cap(): return false
	for f in ferrets:
		var fe: FerretEntity = f
		if fe.colony_id != b.colony_id: continue   # v16.0: nur Frettchen der eigenen Kolonie
		if fe.assigned_building == null and fe.current_construction_site == null:
			return b.assign_worker(fe)
	return false

func _assign_work(cid: int, cf: Array) -> void:
	for f in cf:
		var fe: FerretEntity = f
		if fe.assigned_building != null: continue
		if fe.current_construction_site != null: continue
		var best: BuildingEntity = null
		var best_pri: int = -1
		for b in BuildingSys.buildings:
			var be: BuildingEntity = b
			if be.is_under_construction: continue
			if be.colony_id != cid: continue
			if be.btype in ["STORAGE","HAPPINESS","DECO","GRAVEYARD","HOUSING"]: continue
			if be.assigned_workers.size() >= be.get_effective_worker_cap(): continue
			if be.work_priority > best_pri:
				best_pri = be.work_priority
				best = be
		if best != null:
			best.assign_worker(fe)

func _try_grow(cid: int) -> void:
	var free_beds: int = BuildingSys.get_total_beds(cid) - BuildingSys.get_occupied_beds(cid)
	var who: String = "" if ColonySys.player_count() <= 1 else " in %s" % ColonySys.get_name_of(cid)
	if free_beds <= 0:
		# Feature (v13.7, gemeldet: "verstehe nicht, wieso keine neuen
		# Frettchen kommen"): Nachwuchs braucht IMMER ein freies Bett - das
		# stand bisher nirgends klar sichtbar, wenn es der einzige blockierende
		# Grund war. Einmal pro Tag (nicht öfter, sonst nervt es) ein
		# Hinweis, statt dass die Kolonie einfach stillschweigend nicht wächst.
		if DayNight.day_count != int(_last_bed_hint_day.get(cid, -1)):
			_last_bed_hint_day[cid] = DayNight.day_count
			GameState.notify("Kein Nachwuchs%s möglich: alle Betten belegt. Baue ein weiteres Wohnhaus!" % who)
		return
	var has_food: bool = (
		float(ResourceSys.resources.get("FOOD", 0.0)) > 5.0 or
		float(ResourceSys.resources.get("BERRIES", 0.0)) > 15.0 or
		float(ResourceSys.resources.get("STEW", 0.0)) > 2.0 or
		float(ResourceSys.resources.get("BREAD", 0.0)) > 3.0 or
		float(ResourceSys.resources.get("COOKED_MEAT", 0.0)) > 3.0
	)
	if not has_food:
		if DayNight.day_count != int(_last_growth_block_hint_day.get(cid, -1)):
			_last_growth_block_hint_day[cid] = DayNight.day_count
			GameState.notify("Kein Nachwuchs%s möglich: zu wenig Nahrung im Lager." % who)
		return
	# Feature (Tech Tree): "Familienplanung" (BREEDING) senkt die nötige
	# Glückschwelle für Nachwuchs; "Meister der Zucht" beschleunigt das
	# Wachstum zusätzlich per Wahrscheinlichkeits-Bonus pro Aufruf.
	var threshold: float = 50.0 - TechTreeSys.get_global_bonus("growth_happiness_threshold_reduction")
	if float(colony_happiness.get(cid, 50.0)) < threshold:
		if DayNight.day_count != int(_last_growth_block_hint_day.get(cid, -1)):
			_last_growth_block_hint_day[cid] = DayNight.day_count
			GameState.notify("Kein Nachwuchs%s möglich: Glück zu niedrig (mind. %d%% nötig)." % [who, int(threshold)])
		return
	var f: FerretEntity = FerretEntity.create_random()
	f.colony_id = cid
	# Neugeborene starten bei ihrem Wohnhaus (Kolonie-Gebiet), nicht in der Kartenmitte.
	var hall_tile: Vector2i = ColonySys.get_hall_tile(cid)
	if hall_tile.x >= 0:
		f.pos = Vector2(float(hall_tile.x) + randf_range(-2.0, 2.0), float(hall_tile.y) + randf_range(-2.0, 2.0))
		f.target_pos = f.pos
	# Feature (Tech Tree): "Ammenpflege" (BREEDING) gibt neugeborenen
	# Frettchen einen Gesundheits-Vorsprung.
	f.health = minf(100.0, f.health + TechTreeSys.get_global_bonus("newborn_health_bonus"))
	for b in BuildingSys.buildings:
		var be: BuildingEntity = b
		if be.colony_id != cid: continue
		if be.btype == "HOUSING" and not be.is_under_construction:
			if be.residents.size() < be.max_residents:
				be.residents.append(f)
				f.home = be; break
	ferrets.append(f)
	GameState.ferret_born.emit(f)
	SoundSys.play_born()
	GameState.notify("Ein neues Frettchen ist geboren!")

## cid < 0 = alle Kolonien (bisheriges Verhalten), sonst nur diese Kolonie.
func get_count(cid: int = -1) -> int:
	if cid < 0: return ferrets.size()
	var n: int = 0
	for f in ferrets:
		if (f as FerretEntity).colony_id == cid: n += 1
	return n

func ferrets_of(cid: int) -> Array:
	var out: Array = []
	for f in ferrets:
		if (f as FerretEntity).colony_id == cid: out.append(f)
	return out

## Feature (v16.0, Kolonie-Gründung): schickt `count` Siedler von Kolonie `from_id`
## nach `to_id` an die Kachel `dest` (Tile-Koordinaten). Bevorzugt Frettchen ohne
## Arbeit/Baustelle. Löst Arbeit, Wohnung und Trageauftrag sauber. Gibt zurück,
## wie viele tatsächlich umgezogen sind.
func transfer_ferrets(from_id: int, to_id: int, count: int, dest: Vector2) -> int:
	var picked: Array = []
	for pass_idx in 2:
		for f in ferrets:
			if picked.size() >= count: break
			var fe: FerretEntity = f
			if fe.colony_id != from_id or picked.has(fe): continue
			var idle: bool = fe.assigned_building == null and fe.current_construction_site == null
			if pass_idx == 0 and not idle: continue
			picked.append(fe)
	for f in picked:
		var fe2: FerretEntity = f
		if fe2.assigned_building != null:
			(fe2.assigned_building as BuildingEntity).remove_worker(fe2)
		fe2.assigned_building = null
		if fe2.home != null:
			(fe2.home as BuildingEntity).residents.erase(fe2)
		fe2.home = null
		fe2.current_construction_site = null
		fe2.construction_site = null
		fe2.haul_target = null
		fe2.carry_inventory.clear()
		fe2.work_state = "IDLE"
		fe2.colony_id = to_id
		fe2.pos = dest + Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
		fe2.target_pos = fe2.pos
	return picked.size()

func serialize() -> Dictionary:
	var f_data: Array = []
	for f in ferrets:
		var fe: FerretEntity = f
		f_data.append(fe.serialize())
	return {"ferrets": f_data, "dead": dead_ferrets.duplicate(true)}

func deserialize(data: Dictionary) -> void:
	ferrets = []
	var dead = data.get("dead", [])
	dead_ferrets = (dead as Array).duplicate(true)
	var flist = data.get("ferrets", [])
	for fd in flist:
		ferrets.append(FerretEntity.deserialize(fd as Dictionary))
