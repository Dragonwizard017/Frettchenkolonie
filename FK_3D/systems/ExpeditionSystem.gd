## ExpeditionSystem.gd
extends Node

class Expedition extends RefCounted:
	var ferrets: Array = []
	var days_total: float = 0.0
	var days_elapsed: float = 0.0
	var exp_name: String = ""
	var colony_id: int = 0   # v16.0: Kolonie, die die Expedition losgeschickt hat (Beute geht dorthin)

	func update(dt: float) -> bool:
		days_elapsed += dt / 60.0
		return days_elapsed >= days_total

	func get_rewards() -> Dictionary:
		var diff: float = days_total / 12.0
		var r: Dictionary = {}
		r["WOOD"] = randi_range(5, 20)
		r["STONE"] = randi_range(3, 15)
		r["BERRIES"] = randi_range(5, 25)
		if diff > 0.4:
			r["TOOLS"] = randi_range(0, 3)
			r["IRON"] = randi_range(0, 8)
		if diff > 0.7:
			r["IRON_BARS"] = randi_range(0, 3)
			r["COAL"] = randi_range(0, 5)
		return r

	# Bug-Fix (v10.14): "Expeditionen werden nicht gespeichert" - bisher gab
	# es für eine einzelne Expedition gar keine Serialisierung, und die
	# mitgereisten Frettchen (die zu diesem Zeitpunkt NICHT mehr in
	# PopMgr.ferrets stehen, siehe send()) wären beim Speichern schlicht
	# verschwunden.
	func serialize() -> Dictionary:
		var f_data: Array = []
		for f in ferrets:
			f_data.append((f as FerretEntity).serialize())
		return {
			"exp_name": exp_name, "days_total": days_total,
			"days_elapsed": days_elapsed, "ferrets": f_data, "colony_id": colony_id
		}

	static func deserialize(data: Dictionary) -> Expedition:
		var e := Expedition.new()
		e.exp_name = str(data.get("exp_name", "Expedition"))
		e.days_total = float(data.get("days_total", 5.0))
		e.days_elapsed = float(data.get("days_elapsed", 0.0))
		e.colony_id = int(data.get("colony_id", 0))
		for fd in (data.get("ferrets", []) as Array):
			e.ferrets.append(FerretEntity.deserialize(fd as Dictionary))
		return e

var active_expeditions: Array = []

func init() -> void:
	active_expeditions = []

func can_send() -> bool:
	# v16.0: das Expeditionslager muss in der AKTIVEN Kolonie stehen.
	for b in BuildingSys.buildings:
		var be: BuildingEntity = b
		if be.btype == "EXPEDITION" and not be.is_under_construction and be.colony_id == ColonySys.active_id:
			return true
	return false

func send(ferret_count: int, days: float) -> bool:
	if not can_send(): return false
	if PopMgr.get_count(ColonySys.active_id) < ferret_count + 2:
		GameState.notify("Nicht genug Frettchen!"); return false
	if not ResourceSys.has("TOOLS", 2):
		GameState.notify("Brauche 2 Werkzeuge für Expedition!"); return false
	ResourceSys.remove("TOOLS", 2)
	var expd := Expedition.new()
	expd.days_total = days
	expd.exp_name = "Expedition %d" % (active_expeditions.size() + 1)
	expd.colony_id = ColonySys.active_id
	# v16.0: es ziehen nur Frettchen der aktiven Kolonie mit (von hinten, wie bisher).
	for _i in ferret_count:
		var f: FerretEntity = null
		for k in range(PopMgr.ferrets.size() - 1, -1, -1):
			if (PopMgr.ferrets[k] as FerretEntity).colony_id == ColonySys.active_id:
				f = PopMgr.ferrets[k] as FerretEntity
				PopMgr.ferrets.remove_at(k)
				break
		if f == null: break
		if f.assigned_building != null:
			var ab: BuildingEntity = f.assigned_building
			ab.remove_worker(f)
		expd.ferrets.append(f)
	active_expeditions.append(expd)
	GameState.notify("%s gestartet! (%d Frettchen, %d Tage)" % [expd.exp_name, ferret_count, int(days)])
	return true

func update(dt: float) -> void:
	var returned: Array = []
	for expd in active_expeditions:
		var e: Expedition = expd
		if e.update(dt): returned.append(e)
	for expd in returned:
		active_expeditions.erase(expd)
		_finish_expedition(expd as Expedition)

func _finish_expedition(expd: Expedition) -> void:
	for f in expd.ferrets:
		PopMgr.ferrets.append(f)
	var rewards: Dictionary = expd.get_rewards()
	# v16.0: Beute geht in den Pool der Kolonie, die die Expedition losgeschickt hat.
	var prev_colony: int = ResourceSys.current_colony
	ResourceSys.use_colony(expd.colony_id if ColonySys.has_colony(expd.colony_id) else 0)
	for res in rewards:
		ResourceSys.force_add(str(res), float(rewards[res]))
	ResourceSys.use_colony(prev_colony)
	GameState.expedition_returned.emit(rewards)
	GameState.notify("%s zurück! Beute erhalten!" % expd.exp_name)
	GameState.hud_update_requested.emit()

func serialize() -> Array:
	var result: Array = []
	for expd in active_expeditions:
		var e: Expedition = expd
		result.append(e.serialize())
	return result

func deserialize(data: Array) -> void:
	# Bug-Fix (v10.14): bisher hat deserialize() den Parameter komplett
	# ignoriert und IMMER auf eine leere Liste zurückgesetzt - laufende
	# Expeditionen (inkl. der Frettchen darin) gingen beim Laden verloren.
	# Jetzt werden sie inklusive ihrer Frettchen wiederhergestellt; diese
	# Frettchen dürfen NICHT zusätzlich in PopMgr.ferrets auftauchen (sie
	# waren beim Speichern bereits dort entfernt, siehe send()).
	active_expeditions = []
	for ed in data:
		active_expeditions.append(Expedition.deserialize(ed as Dictionary))
