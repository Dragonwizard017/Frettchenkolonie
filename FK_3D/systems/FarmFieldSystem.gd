## FarmFieldSystem.gd
## Feature (v14.5, Timberborn-Feld-System): ersetzt die bisherigen passiven
## Getreide-Gebäude (CROP_FIELD, WHEAT_FARM - beide produzierten WHEAT rein
## anhand der Arbeiterzahl, ohne jedes Feld-Konzept) durch echte, vom Spieler
## frei im Bezirk platzierte Feld-Kacheln mit Wachstumszyklus:
##
##   EMPTY (frisch angelegt/abgeerntet) -> GROWING (wächst von selbst,
##   unabhängig von Arbeitern) -> READY (erntereif) -> zurück zu EMPTY.
##
## Architektur bewusst als EIGENES, schlankes Kachel-Register (statt dass
## jeder Bauernhof (btype FARMHOUSE) bei jedem Tick das komplette Kachelraster
## nach Feldern absucht) - analog zum Bezirks-Register in DistrictSystem.gd.
## Das WACHSTUM läuft hier zentral für ALLE Felder (update(), unabhängig von
## Arbeitern - die Pflanze wächst auch, während gerade kein Frettchen auf dem
## Acker ist). Das SÄEN/ERNTEN selbst übernimmt weiterhin die einzelne
## BuildingEntity (siehe BuildingEntity._farmhouse()) - jeder Bauernhof mit
## freien Arbeitern darf ein beliebiges EMPTY/READY-Feld SEINES Bezirks
## bearbeiten (kein Feld "gehört" einem bestimmten Bauernhof), genau wie in
## Timberborn mehrere Farmhäuser gemeinsam denselben Ackerpool bewirtschaften.
extends Node

## Sekunden bis ein Feld bei production_speed=1.0 und ohne Dürre von GROWING
## auf READY wächst. Die tatsächliche Wachstumsgeschwindigkeit hängt NICHT
## vom production_speed einzelner Bauernhöfe ab (ein Feld ist keinem
## bestimmten Gebäude zugeordnet) - Tech-Tree-Boni auf FARMHOUSE wirken
## stattdessen auf die Säe-/Ernte-Geschwindigkeit der Arbeiter (siehe
## BuildingEntity._farmhouse()).
const GROWTH_TIME: float = 200.0
## Bug-Fix (v14.6): Wasserkosten je Feld und SEKUNDE (vorher je Frame, also
## framerate-abhängig: bei 60 FPS ~1.2 Wasser/s pro Feld).
const DROUGHT_WATER_COST: float = 0.02

var fields: Dictionary = {}  # "x_y" (String) -> {tile_x,tile_y,state,growth,district_id}

func init() -> void:
	fields = {}

func _key(tx: int, ty: int) -> String:
	return "%d_%d" % [tx, ty]

func has_field(tx: int, ty: int) -> bool:
	return fields.has(_key(tx, ty))

func get_field(tx: int, ty: int):
	return fields.get(_key(tx, ty))

## Legt eine neue Feld-Kachel an (Zustand EMPTY). Gibt false zurück, wenn
## dort schon ein Feld existiert (Aufrufer prüft davor bereits Biom/
## Gebäude/Weg-Bedingungen, siehe GameController._place_field()).
func register_field(tx: int, ty: int, district_id: int) -> bool:
	var k: String = _key(tx, ty)
	if fields.has(k): return false
	fields[k] = {"tile_x": tx, "tile_y": ty, "state": "EMPTY", "growth": 0.0, "district_id": district_id}
	return true

func remove_field(tx: int, ty: int) -> void:
	fields.erase(_key(tx, ty))

func count_in_district(did: int) -> int:
	var n: int = 0
	for k in fields:
		if int((fields[k] as Dictionary).get("district_id", 0)) == did: n += 1
	return n

## Für die Bauernhof-Statuszeile (siehe BuildingInfo.gd) - Aufschlüsselung
## nach Zustand, damit sichtbar wird, WARUM gerade nichts geerntet wird
## (z.B. "3 Felder, alle wachsen noch" statt nur einer nackten Zahl).
func get_district_stats(did: int) -> Dictionary:
	var stats: Dictionary = {"total": 0, "empty": 0, "growing": 0, "ready": 0}
	for k in fields:
		var f: Dictionary = fields[k]
		if int(f.get("district_id", 0)) != did: continue
		stats["total"] = int(stats["total"]) + 1
		var st: String = str(f.get("state", "EMPTY"))
		match st:
			"EMPTY":   stats["empty"]   = int(stats["empty"]) + 1
			"GROWING": stats["growing"] = int(stats["growing"]) + 1
			"READY":   stats["ready"]   = int(stats["ready"]) + 1
	return stats

func has_growing_fields() -> bool:
	for k in fields:
		if str((fields[k] as Dictionary).get("state", "")) == "GROWING": return true
	return false

## Zentrales Wachstum ALLER gerade wachsenden Felder - läuft jeden Frame vom
## GameController aus (siehe GameController._process()), TAGS UND NACHTS
## (Pflanzen wachsen schliesslich auch nachts weiter), unabhängig von
## zugewiesenen Bauernhof-Arbeitern. Dürre verlangsamt das Wachstum spürbar,
## statt es (wie früher bei CROP_FIELD) hart zu blockieren.
func update(dt: float) -> void:
	if fields.is_empty(): return
	var drought: bool = DroughtSys.is_drought
	for k in fields:
		var f: Dictionary = fields[k]
		if str(f.get("state", "")) != "GROWING": continue
		var factor: float = 1.0
		if drought:
			var w_cost: float = DROUGHT_WATER_COST * dt
			# v16.0: das Wasser kommt aus dem Tank der Kolonie, zu der der Bezirk des Feldes gehört.
			var prev_colony: int = ResourceSys.current_colony
			ResourceSys.use_colony(DistrictSys.district_colony(int(f.get("district_id", 0))))
			if ResourceSys.has_water(w_cost):
				ResourceSys.remove_water(w_cost)
				factor = 0.5
			else:
				factor = 0.15
			ResourceSys.use_colony(prev_colony)
		var g: float = minf(1.0, float(f.get("growth", 0.0)) + dt * factor / GROWTH_TIME)
		f["growth"] = g
		if g >= 1.0:
			f["state"] = "READY"

## Sucht ein bearbeitbares Feld im gegebenen Bezirk. want_state = "EMPTY"
## (braucht Aussaat) oder "READY" (kann geerntet werden). Gibt die
## Feld-Dictionary-Referenz zurück (Godot-Dictionaries sind Referenztypen -
## Mutation über die Rückgabe wirkt direkt im Register) oder null.
func find_field(district_id: int, want_state: String):
	for k in fields:
		var f: Dictionary = fields[k]
		if int(f.get("district_id", 0)) == district_id and str(f.get("state", "")) == want_state:
			return f
	return null

func serialize() -> Dictionary:
	return {"fields": fields.duplicate(true)}

func deserialize(data) -> void:
	if not (data is Dictionary):
		fields = {}; return
	fields = ((data as Dictionary).get("fields", {}) as Dictionary).duplicate(true)
	# JSON kennt nur String-Keys für Werte, aber tile_x/tile_y/district_id
	# selbst sind schon als int in der Feld-Dictionary gespeichert - JSON
	# wandelt Zahlen beim Parsen zuverlässig zurück in int/float, hier ist
	# (anders als bei DistrictSystem.districts) keine Schlüssel-Rückkonvertierung
	# nötig, da _key() ohnehin Strings liefert und auch als Strings genutzt wird.
