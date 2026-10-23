## FerretEntity.gd
class_name FerretEntity
extends RefCounted

const FIRST_NAMES: Array = ["Freddy","Fido","Fiona","Franz","Frieda","Felix","Frida","Frank","Finn","Flora","Frodo","Franzi","Filou","Feli","Fips"]
const LAST_NAMES: Array  = ["Frettchen","Pfote","Flausch","Fell","Schnüffel","Hüpfer","Schwanz","Nase","Kralle","Zahn"]

# ── Feature (v10.10): Frettchen gehen jetzt tatsächlich zu ihrem Arbeitsplatz
# bzw. zu einer Ressourcenülle, statt nur zufällig durch die Karte zu
# wandern. Bei Sammel-Gebäuden (COLLECTOR mit WOOD/STONE/BERRIES/IRON) pendeln
# sie zwischen Gebäude und einer konkreten, im Tile gespeicherten
# Resource-Node hin und her, "ernten" sie dort (sichtbar als kurze Pause +
# Wipp-Animation in WorldRenderer3D, siehe harvest_anim_t) und die Quelle
# verliert dabei "amount" - bis sie erschöpft ist und eine Zeit lang
# regenerieren muss (siehe WorldGenerator.tick_resource_nodes).
const NODE_RESOURCE_TYPES: Array = ["WOOD", "STONE", "BERRIES", "IRON"]
const HARVEST_DURATION: float = 3.0   # Sekunden pro Ernte-Aktion an einer Quelle
const HARVEST_AMOUNT:   float = 18.0  # wie viel "amount" eine Ernte-Aktion abbaut

var ferret_name: String = ""
## Feature (v16.0, Kolonie-Fundament): zu welcher Kolonie das Frettchen gehört
## (Arbeit, Wohnung, Versorgung und Lagersuche bleiben innerhalb der Kolonie).
var colony_id: int = 0
var health: float = 100.0
var needs: Dictionary = {"food": 80.0, "water": 80.0, "happiness": 75.0}
## Feature (v11.8, Frettchen-Persönlichkeiten): jedes Frettchen trägt genau
## einen Trait aus FerretTraits.TRAITS, zufällig zugewiesen bei der Geburt
## (siehe create_random()) mit Abwärtskompatibilitäts-Fallback beim Laden
## alter Saves (siehe deserialize()).
var trait_id: String = ""
var assigned_building = null
var current_construction_site = null
var home = null
var specialization: String = ""
var spec_days: float = 0.0
## Feature (v11.9, Legendäre Frettchen): siehe update() für die genaue
## Zähl-Logik. Schwellwert bewusst konservativ (Nutzer-Entscheidung:
## strenger als der ursprüngliche 30-Tage-Vorschlag) - realistisch nur
## 1-3 legendäre Frettchen pro Kolonie über eine sehr lange Spielzeit.
const LEGENDARY_THRESHOLD_DAYS: float = 50.0
var career_building_id: String = ""
var career_days: float = 0.0
var is_legendary: bool = false
var legendary_title: String = ""
## Array von Accessoire-IDs aus FerretAccessories.ACCESSORIES - individuell
## gewürfelt beim Legendär-Werden, siehe pick_random_set().
var legendary_accessories: Array = []
var age_days: float = 0.0
var is_alive: bool = true
var pos: Vector2 = Vector2.ZERO
var target_pos: Vector2 = Vector2.ZERO
var move_speed: float = 2.0   # Tiles pro Sekunde

# ── Arbeits-/Ernte-Zustand (nicht persistiert, baut sich nach dem Laden von
# selbst wieder auf, genau wie assigned_building) ────────────────────────────
var work_state: String = "IDLE"        # IDLE, TO_BUILDING, WORKING, TO_NODE, HARVESTING, RETURN
var harvest_tile: Vector2i = Vector2i(-1, -1)
var work_timer: float = 0.0
var harvest_anim_t: float = 0.0        # Lese-Flag für den Renderer (Wipp-Animation)
# Feature (v10.11): generische, kontinuierlich laufende "Arbeits-Uhr" -
# zählt während der gesamten Zeit am Gebäude (work_state == "WORKING")
# hoch, im Gegensatz zu harvest_anim_t, das nur während des Node-Pendelns
# (work_state == "HARVESTING") läuft. Wird z.B. von WaterCollectAnimation
# genutzt, da Wasser-Gebäude keine physischen Resource-Nodes zum Pendeln
# haben und stattdessen direkt am Gebäude "arbeiten".
var work_anim_t: float = 0.0

# ── Feature (v10.13): Schlafzyklus ───────────────────────────────────────────
# Nachts (DayNight.is_day == false) unterbrechen alle Frettchen ihre Arbeit
# und gehen schlafen: mit zugewiesenem Haus (siehe `home`) laufen sie dort
# hin, ohne Haus legen sie sich einfach dort hin, wo sie gerade stehen ("auf
# dem Boden schlafen"). is_sleeping wird true, sobald das Ziel erreicht ist;
# der Renderer nutzt das für eine liegende Pose + langsames Atem-Wippen.
var is_sleeping: bool = false
## v15.6: einmalige Reaktions-Animation (Streicheln -> "Pet"/"Jump_Joy", Geburt -> "Jump_Joy").
## Wird vom Renderer bis react_until (Sekunden, Time.get_ticks_msec()/1000) abgespielt.
var react_clip: String = ""
var react_until: float = 0.0
var sleep_anim_t: float = 0.0

# ── Feature (v10.13): Bau-Frettchen gehen jetzt zur Baustelle ───────────────
# Frettchen, die einem BUILDER-Gebäude (Bauhof) zugewiesen sind, suchen sich
# eine aktive Baustelle im Umkreis (siehe BUILDER_SEARCH_RANGE) und laufen
# dort hin, statt nur am Bauhof zu stehen. construction_site zeigt auf die
# BuildingEntity, an der gerade gebaut wird - GameController._process_construction()
# zählt darüber pro Baustelle, wie viele Frettchen tatsächlich vor Ort
# sind, und skaliert den Baufortschritt entsprechend (siehe dort).
var construction_site = null
const BUILDER_SEARCH_RANGE: float = 50.0

# ── Feature (v11.0, Timberborn-Lagersystem) ─────────────────────────────────
# Jedes Frettchen hat jetzt ein simuliertes Inventar mit fester Tragekapazität
# (gleich für ALLE Frettchen, siehe Nutzeranfrage). Genutzt von drei Rollen:
#  1) Produktions-Arbeiter, die das volle lokale Lager ihres Gebäudes zu
#     einem Lagerhaus tragen (work_state HAUL_TO_WAREHOUSE/HAUL_RETURN)
#  2) Bau-Frettchen, die fehlendes Baumaterial vom nächsten Lagerhaus zur
#     Baustelle tragen (FETCH_TO_WAREHOUSE/FETCH_TO_SITE)
#  3) Lagerarbeiter (Frettchen in einem Lagerhaus-Gebäude), die proaktiv
#     Produktionsgebäude abklappern UND Material zu Baustellen liefern
#     (WH_TO_SOURCE/WH_TO_WAREHOUSE/WH_TO_SITE)
const CARRY_CAPACITY: float = 30.0
var carry_inventory: Dictionary = {}
var haul_target = null
const WAREHOUSE_SEARCH_RANGE: float = 70.0

# Feature (v11.1, Betten): Frettchen ohne eigenes Bett (home == null) werden
# zusätzlich zur normalen Abklingrate unglücklicher - macht ausreichenden
# Wohnraum zu einer echten strategischen Notwendigkeit statt nur einer netten
# Option für schnelleres Wachstum.
# Feature (v13.7, Nutzerwunsch "spürbar entspannter Einstieg"): von 0.3 auf
# 0.18 gesenkt - Obdachlosigkeit tut in den ersten Kolonie-Tagen (bevor genug
# Betten stehen) dadurch spürbar weniger weh.
const HOMELESS_HAPPINESS_PENALTY: float = 0.18

## Feature (Tech Tree): effektive Tragkraft/Suchradius inkl. globaler Boni aus
## dem Themenbereich "Bauwesen & Logistik" (siehe TechTree.gd). Ersetzt die
## direkte Verwendung der CARRY_CAPACITY/WAREHOUSE_SEARCH_RANGE Konstanten an
## allen Stellen unten.
func get_carry_capacity() -> float:
	return CARRY_CAPACITY + TechTreeSys.get_global_bonus("carry_capacity_bonus")

func get_warehouse_search_range() -> float:
	return WAREHOUSE_SEARCH_RANGE + TechTreeSys.get_global_bonus("warehouse_search_range_bonus")

## Feature (Tech Tree): "Schnelle Füsse" (LOGISTICS) erhöht das Lauftempo
## aller Frettchen global.
func get_effective_move_speed() -> float:
	return move_speed * (1.0 + TechTreeSys.get_global_bonus("move_speed_bonus"))

## Feature (v11.8, Frettchen-Persönlichkeiten): wie stark ein Glücklichkeits-
## Gebäude bei DIESEM Frettchen wirkt - "Glückspilz" profitiert deutlich
## mehr, "Eigenbrötler" deutlich weniger (siehe PopulationManager.
## _apply_happiness_bonuses()).
func get_happiness_bonus_multiplier() -> float:
	match trait_id:
		"LUCKY": return 1.6
		"LONER": return 0.6
		_: return 1.0

func get_trait_data() -> Dictionary:
	return FerretTraits.get_trait(trait_id)

static func create_random() -> FerretEntity:
	var f := FerretEntity.new()
	f.ferret_name = FIRST_NAMES[randi() % FIRST_NAMES.size()] + " " + LAST_NAMES[randi() % LAST_NAMES.size()]
	f.health = randf_range(80.0, 100.0)
	f.move_speed = randf_range(1.5, 2.8)
	f.trait_id = FerretTraits.pick_random_trait_id()
	f.needs = {
		"food": randf_range(50.0, 80.0),
		"water": randf_range(50.0, 80.0),
		"happiness": randf_range(40.0, 70.0)
	}
	# Startposition: isometrische Weltkoordinaten nahe Karte-Mitte (Tile 30,30)
	# tile_to_world(30,30) = (0, 2880) — wir randomisieren etwas drumherum
	f.pos = Vector2(30.0 + randf_range(-4.0, 4.0), 30.0 + randf_range(-4.0, 4.0))
	f.target_pos = f.pos
	return f

func update(dt: float, world: Array = [], is_day: bool = true) -> void:
	age_days += dt / 60.0
	# Feature (Tech Tree): "Ausdauertraining" (BREEDING) lässt die Grund-
	# bedürfnisse global langsamer absinken.
	var decay_mult: float = 1.0 - clampf(TechTreeSys.get_global_bonus("needs_decay_reduction"), 0.0, 0.9)
	# Feature (v11.8, Frettchen-Persönlichkeiten): "Fleissig" (DILIGENT)
	# arbeitet mehr, dafür sinken die eigenen Grundbedürfnisse etwas
	# schneller (+15%) - kleiner Ausgleich für den Produktions-Bonus in
	# BuildingEntity.get_worker_trait_bonus().
	if trait_id == "DILIGENT": decay_mult *= 1.15
	# Feature (Tech Tree, Bugfix): "hunger_decay_reduction" (Landwirtschaft-
	# Kapstein) wurde bisher in TechTree.gd definiert, aber nirgends
	# abgefragt - der Bonus tat nichts. Wirkt zusätzlich zu decay_mult
	# NUR auf den Hunger-Bedarf, nicht auf Durst/Glücklichkeit.
	var hunger_mult: float = 1.0 - clampf(TechTreeSys.get_global_bonus("hunger_decay_reduction"), 0.0, 0.9)
	# Feature (v13.0, Anfänger-Freundlichkeit): Hunger-/Durst-Verschleiß
	# bereits um 35% reduziert.
	# Feature (v13.7, Nutzerwunsch "spürbar entspannter Einstieg"): nochmal
	# deutlich weiter gesenkt (Hunger/Durst zusätzlich ca. -40%, Glück -35%),
	# damit Kolonien auch bei nicht optimal getimtem Ausbau nicht mehr so
	# leicht wegsterben. Die Werte fühlen sich dadurch insgesamt gut halb so
	# schnell fallend an wie im ursprünglichen v10-Release.
	needs["food"] = maxf(0.0, float(needs["food"]) - dt * 0.31 * decay_mult * hunger_mult)
	needs["water"] = maxf(0.0, float(needs["water"]) - dt * 0.43 * decay_mult)
	needs["happiness"] = maxf(0.0, float(needs["happiness"]) - dt * 0.26 * decay_mult)
	# Feature (v11.1, Betten): kein eigenes Bett -> zusätzlicher Glücksverlust.
	# Schläft ein Frettchen "auf dem Boden" (siehe _update_sleep()), spürt es
	# das stärker als eines mit eigenem Bett im Wohnhaus.
	if home == null:
		# Feature (Tech Tree): "Wärmende Decken" (BREEDING) lindert diesen
		# Zusatzverlust.
		var penalty_mult: float = 1.0 - clampf(TechTreeSys.get_global_bonus("homeless_penalty_reduction"), 0.0, 0.9)
		needs["happiness"] = maxf(0.0, float(needs["happiness"]) - dt * HOMELESS_HAPPINESS_PENALTY * penalty_mult)
	var avg: float = (float(needs["food"]) + float(needs["water"])) / 2.0
	# Feature (v10.13): "zumindest am Anfang nicht so schnell sterben" - am
	# allerersten Tag (DayNight.day_count == 0) verursachen Hunger/Durst noch
	# KEINEN Gesundheitsschaden. Die Bedürfnis-Werte selbst sinken weiterhin
	# normal (sichtbar in der UI, motiviert schnell zu bauen), aber die
	# Kolonie bekommt einen vollen Tag Vorlauf, um die erste Nahrungs-/
	# Wasserproduktion aufzubauen, bevor das erste Frettchen sterben kann.
	# Feature (Tech Tree): "Gesunde Ernährung"/"Meister der Zucht" (BREEDING)
	# beschleunigen die Erholung bzw. verlangsamen den Gesundheitsverfall.
	var regen_bonus: float = TechTreeSys.get_global_bonus("health_regen_bonus")
	var mortality_mult: float = 1.0 - clampf(TechTreeSys.get_global_bonus("mortality_reduction"), 0.0, 0.9)
	# Feature (v11.8, Frettchen-Persönlichkeiten): "Zäh" (TOUGH) verliert bei
	# Hunger/Durst 30% langsamer Gesundheit als andere Frettchen.
	if trait_id == "TOUGH": mortality_mult *= 0.7
	# Feature (v13.0, Anfänger-Freundlichkeit): erste 2 Tage kein Hunger-Schaden.
	# Feature (v13.7, Nutzerwunsch "spürbar entspannter Einstieg"): Schonfrist
	# auf 4 Tage verdoppelt (mehr Zeit, die erste Versorgung aufzubauen), die
	# Schadensschwelle von "avg < 20" auf "avg < 12" gesenkt (Frettchen halten
	# spürbar länger durch, bevor überhaupt Gesundheit sinkt) und der
	# Schadensfaktor selbst von 0.1 auf 0.05 halbiert. Die Erholungsschwelle
	# wurde von "avg > 60" auf "avg > 45" gesenkt, damit sich Frettchen schon
	# bei mittelmässiger statt nur guter Versorgung wieder erholen.
	if DayNight.day_count > 4:
		if avg < 12.0:
			health = maxf(0.0, health - dt * (12.0 - avg) * 0.05 * mortality_mult)
		elif avg > 45.0:
			health = minf(100.0, health + dt * (0.7 + regen_bonus))
	elif avg > 45.0:
		health = minf(100.0, health + dt * (0.7 + regen_bonus))

	if not is_day:
		_update_sleep(dt)
		return
	is_sleeping = false
	sleep_anim_t = 0.0

	if assigned_building != null:
		var ab: BuildingEntity = assigned_building
		if not ab.is_under_construction:
			spec_days += dt / 60.0
			# Feature (v11.8, Frettchen-Persönlichkeiten): "Naturtalent"
			# (TALENTED) überspringt die übliche 5-Tage-Wartezeit komplett
			# und wird an jedem neuen Arbeitsplatz sofort zum Experten.
			var spec_threshold: float = 0.0 if trait_id == "TALENTED" else 5.0
			if spec_days >= spec_threshold and specialization != ab.btype:
				specialization = ab.btype
			# Feature (v11.9, Legendäre Frettchen): eigener, präziserer
			# Zähler als spec_days - trackt Tage im SELBEN konkreten Gebäude
			# (ab.id, z.B. "SMELTER"), nicht nur derselben Gebäude-Kategorie
			# (ab.btype). Wird bei Job-Wechsel (anderes Gebäude) zurückgesetzt,
			# NICHT bei kurzer Abwesenheit (siehe "else"-Zweig unten) - eine
			# 50-Tage-Legendären-Karriere soll nicht durch eine einzelne
			# Umverteilung des Arbeiters zunichte gemacht werden.
			if ab.id != career_building_id:
				career_building_id = ab.id
				career_days = 0.0
			else:
				career_days += dt / 60.0
			if not is_legendary and career_days >= LEGENDARY_THRESHOLD_DAYS:
				is_legendary = true
				legendary_title = "%s-Legende" % ab.name
				legendary_accessories = FerretAccessories.pick_random_set()
	else:
		spec_days = 0.0
	_update_work(dt, world)

## Nachts: zum zugewiesenen Haus laufen und dort schlafen, oder - falls kein
## Haus zugewiesen ist - einfach an der aktuellen Position liegen bleiben.
func _update_sleep(dt: float) -> void:
	work_state = "SLEEPING"
	harvest_anim_t = 0.0
	work_anim_t = 0.0
	var target: Vector2 = pos
	if home != null:
		var hb: BuildingEntity = home
		target = Vector2(float(hb.tile_x) + 0.5, float(hb.tile_y) + 0.5)
	if is_sleeping:
		sleep_anim_t += dt
		return
	if _move_toward(target, dt):
		is_sleeping = true
		sleep_anim_t = 0.0

## Bewegt pos einen Schritt Richtung target und hält target_pos synchron, da
## WorldRenderer3D daraus die Blickrichtung des Frettchens berechnet
## (fe.target_pos - fe.pos).
func _move_toward(target: Vector2, dt: float) -> bool:
	target_pos = target
	var diff: Vector2 = target - pos
	if diff.length() < 0.08:
		pos = target
		return true
	pos += diff.normalized() * get_effective_move_speed() * dt
	return false

func _wander(dt: float) -> void:
	var diff: Vector2 = target_pos - pos
	if diff.length() < 0.15:
		target_pos = pos + Vector2(randf_range(-3.5, 3.5), randf_range(-3.5, 3.5))
	else:
		pos += diff.normalized() * get_effective_move_speed() * dt

func _update_work(dt: float, world: Array) -> void:
	harvest_anim_t = 0.0
	if assigned_building == null:
		work_state = "IDLE"
		harvest_tile = Vector2i(-1, -1)
		work_anim_t = 0.0
		construction_site = null
		_wander(dt)
		return
	var ab: BuildingEntity = assigned_building
	if ab.is_under_construction:
		work_anim_t = 0.0
		construction_site = null
		_wander(dt)
		return

	var building_pos: Vector2 = Vector2(float(ab.tile_x) + 0.5, float(ab.tile_y) + 0.5)

	if ab.btype == "BUILDER":
		_update_builder_work(dt, building_pos)
		return

	# Feature (v11.0): Frettchen in einem Lagerhaus ("Lagerarbeiter") holen
	# proaktiv Ressourcen aus nahen Produktionsgebäuden und liefern Material
	# an Baustellen - komplett eigene Logik, siehe _update_warehouse_work().
	if ab.btype == "STORAGE" and ab.storage_capacity > 0.0:
		_update_warehouse_work(dt, ab, building_pos)
		return

	# Feature (v11.0): ist das lokale Lager dieses Produktionsgebäudes voll
	# und trägt noch kein anderes zugewiesenes Frettchen gerade ab, wird
	# DIESES Frettchen zum Träger - es produziert in der Zeit nichts (siehe
	# BuildingEntity.get_active_worker_count()).
	if work_state == "HAUL_TO_WAREHOUSE" or work_state == "HAUL_RETURN":
		_update_haul_work(dt, ab, building_pos)
		return
	if work_state == "WORKING" and ab.local_storage_capacity > 0.0 \
			and ab.is_local_storage_full() and not ab.has_hauler():
		var haul_res: String = "" if ab.local_storage.is_empty() else str(ab.local_storage.keys()[0])
		var wh: BuildingEntity = _find_nearest_storage_building(building_pos, haul_res, ab)
		if wh != null:
			haul_target = wh
			_pickup_from_building(ab, wh.storage_filter)
			work_state = "HAUL_TO_WAREHOUSE"
			_update_haul_work(dt, ab, building_pos)
			return

	var is_node_collector: bool = (ab.btype == "COLLECTOR"
		and ab.collects_resource in NODE_RESOURCE_TYPES)

	if not is_node_collector:
		# Einfacher Fall (Werkstätten, Bauernhöfe, Brunnen, ...): das
		# Frettchen geht ins/zum Gebäude und bleibt dort "drinnen" stehen,
		# während die eigentliche Produktion über den Gebäude-Timer läuft.
		if work_state != "WORKING" and work_state != "TO_BUILDING":
			work_state = "TO_BUILDING"
		if _move_toward(building_pos, dt):
			work_state = "WORKING"
			work_anim_t += dt
		else:
			work_anim_t = 0.0
		return

	# Sammel-Gebäude mit physischen Ressourcen-Quellen im Terrain: zwischen
	# Gebäude und Quelle hin- und herpendeln.
	match work_state:
		"TO_NODE":
			var target: Vector2 = Vector2(float(harvest_tile.x) + 0.5, float(harvest_tile.y) + 0.5)
			if _node_still_valid(world):
				if _move_toward(target, dt):
					work_state = "HARVESTING"
					work_timer = 0.0
			else:
				work_state = "WORKING"
		"HARVESTING":
			work_timer += dt
			harvest_anim_t = work_timer
			if work_timer >= HARVEST_DURATION:
				_finish_harvest(world)
				work_state = "RETURN"
		"RETURN":
			if _move_toward(building_pos, dt):
				work_state = "WORKING"
		_:
			var node_tile: Vector2i = _find_harvestable_node(world, ab)
			if node_tile.x >= 0:
				harvest_tile = node_tile
				work_state = "TO_NODE"
			else:
				# Keine erntbare Quelle in der Nähe (alle gerade erschöpft) -
				# am Gebäude warten, bis wieder eine verfügbar ist.
				work_state = "WORKING"
				_move_toward(building_pos, dt)

## Feature (v10.13): Frettchen, die einem Bauhof (btype "BUILDER") zugewiesen
## sind, suchen sich eine aktive Baustelle im Umkreis und laufen dorthin,
## statt nur am Bauhof zu stehen. Die tatsächliche Fortschritts-Berechnung
## (abhängig davon, wie viele Frettchen GERADE an einer Baustelle stehen)
## passiert zentral in GameController._process_construction(), die dafür
## über alle Frettchen mit work_state == "BUILDING" iteriert.
##
## Feature (v11.0, Lagersystem): bevor überhaupt gebaut werden kann, muss das
## komplette Baumaterial an der Baustelle liegen (siehe BuildingEntity.
## is_fully_supplied()). Fehlt noch etwas, holt das Bau-Frettchen es zuerst
## vom nächsten Lagerhaus (FETCH_TO_WAREHOUSE/FETCH_TO_SITE), bevor es
## überhaupt in den eigentlichen "BUILDING"-Zustand wechselt.
func _update_builder_work(dt: float, yard_pos: Vector2) -> void:
	match work_state:
		"TO_SITE":
			if construction_site == null or not is_instance_valid(construction_site) or not (construction_site as BuildingEntity).is_under_construction:
				construction_site = null
				work_state = "WORKING"
				return
			var site: BuildingEntity = construction_site
			var target: Vector2 = Vector2(float(site.tile_x) + 0.5, float(site.tile_y) + 0.5)
			if site.is_fully_supplied():
				if _move_toward(target, dt):
					work_state = "BUILDING"
					work_anim_t = 0.0
			else:
				_try_start_material_fetch(dt, site, target)
		"FETCH_TO_WAREHOUSE":
			if haul_target == null or not is_instance_valid(haul_target) or construction_site == null or not is_instance_valid(construction_site):
				haul_target = null; work_state = "TO_SITE"; return
			var wh: BuildingEntity = haul_target
			if _move_toward(Vector2(float(wh.tile_x) + 0.5, float(wh.tile_y) + 0.5), dt):
				_pickup_resource_for_site(wh, construction_site)
				work_state = "FETCH_TO_SITE"
		"FETCH_TO_SITE":
			if construction_site == null or not is_instance_valid(construction_site):
				_deposit_inventory_to_resourcesys()
				work_state = "WORKING"; return
			var site3: BuildingEntity = construction_site
			if _move_toward(Vector2(float(site3.tile_x) + 0.5, float(site3.tile_y) + 0.5), dt):
				_deliver_inventory_to_site(site3)
				work_state = "TO_SITE"
		"BUILDING":
			if construction_site == null or not is_instance_valid(construction_site) or not (construction_site as BuildingEntity).is_under_construction:
				construction_site = null
				work_state = "WORKING"
			else:
				work_anim_t += dt
		_:
			construction_site = null
			var site2: BuildingEntity = _find_construction_site(yard_pos)
			if site2 != null:
				construction_site = site2
				work_state = "TO_SITE"
			else:
				# Kein aktives Bauprojekt - am Bauhof warten
				work_state = "WORKING"
				_move_toward(yard_pos, dt)

## Sucht eine zufällige, aktuell im Bau befindliche Baustelle im Umkreis von
## BUILDER_SEARCH_RANGE Tiles um den Bauhof.
func _find_construction_site(yard_pos: Vector2) -> BuildingEntity:
	var candidates: Array = []
	for b in BuildingSys.buildings:
		var be: BuildingEntity = b
		if not be.is_under_construction: continue
		if be.colony_id != colony_id: continue
		var d: float = yard_pos.distance_to(Vector2(float(be.tile_x), float(be.tile_y)))
		if d <= BUILDER_SEARCH_RANGE:
			candidates.append(be)
	if candidates.is_empty(): return null
	return candidates[randi() % candidates.size()]

## Feature (v11.0): entscheidet, ob ein Bau-Frettchen jetzt los soll, um
## fehlendes Material vom nächsten Lagerhaus zu holen, oder ob es lieber an
## der Baustelle wartet (kein Lagerhaus vorhanden, oder die fehlende
## Ressource ist nirgends im Lagernetzwerk verfügbar - sinnloses Hin- und
## Herlaufen wäre sonst die Folge).
func _try_start_material_fetch(dt: float, site: BuildingEntity, site_target: Vector2) -> void:
	var res: String = _pick_missing_resource(site)
	if res == "":
		_move_toward(site_target, dt)
		return
	var avail: float = float(ResourceSys.resources.get(res, 0.0))
	if avail <= 0.01:
		_move_toward(site_target, dt)
		return
	var wh: BuildingEntity = _find_nearest_storage_building(site_target, res, site)
	if wh == null:
		_move_toward(site_target, dt)
		return
	haul_target = wh
	work_state = "FETCH_TO_WAREHOUSE"

## Erstes noch fehlendes Material einer Baustelle (Reihenfolge der costs-Keys).
func _pick_missing_resource(site: BuildingEntity) -> String:
	for res in site.costs:
		if site.get_missing_amount(str(res)) > 0.01:
			return str(res)
	return ""

@warning_ignore("unused_parameter")
func _pickup_resource_for_site(wh: BuildingEntity, site: BuildingEntity) -> void:
	var res: String = _pick_missing_resource(site)
	if res == "": return
	var need: float = site.get_missing_amount(res)
	var avail: float = float(ResourceSys.resources.get(res, 0.0))
	var take: float = minf(get_carry_capacity(), minf(need, avail))
	if take > 0.0:
		ResourceSys.remove(res, take)
		carry_inventory[res] = float(carry_inventory.get(res, 0.0)) + take

func _deliver_inventory_to_site(site: BuildingEntity) -> void:
	for res in carry_inventory.keys().duplicate():
		site.deliver_resource(str(res), float(carry_inventory[res]))
	carry_inventory.clear()

func _deposit_inventory_to_resourcesys() -> void:
	for res in carry_inventory.keys().duplicate():
		ResourceSys.add(str(res), float(carry_inventory[res]))
	carry_inventory.clear()

## Nimmt bis zu CARRY_CAPACITY aus dem lokalen Lager eines Gebäudes auf
## (genutzt sowohl vom selbst-abtragenden Produktions-Arbeiter als auch vom
## Lagerarbeiter, der fremde Gebäude abklappert). Optionaler filter_res
## (v11.1, Lagerhaus-Spezialisierung): ist er gesetzt, wird NUR diese eine
## Ressource aufgenommen - relevant, wenn das Zieleagerhaus auf einen
## bestimmten Rohstoff spezialisiert ist und andere im lokalen Lager liegende
## Resten nicht mitgenommen werden sollen.
func _pickup_from_building(src: BuildingEntity, filter_res: String = "") -> void:
	var amt_taken: float = 0.0
	for res in src.local_storage.keys().duplicate():
		if amt_taken >= get_carry_capacity(): break
		if filter_res != "" and str(res) != filter_res: continue
		var avail: float = float(src.local_storage[res])
		var take: float = minf(avail, get_carry_capacity() - amt_taken)
		if take > 0.0:
			carry_inventory[res] = float(carry_inventory.get(res, 0.0)) + take
			src.local_storage[res] = avail - take
			if float(src.local_storage[res]) <= 0.001:
				src.local_storage.erase(res)
			amt_taken += take

## Feature (v11.1, Logistik-Feinschliff): "res" optional - wird ein
## Ressourcentyp angegeben, werden Lagerhäuser mit einer Spezialisierung auf
## eine ANDERE Ressource (storage_filter) übersprungen (siehe
## BuildingEntity.accepts_resource()). Ohne Angabe (res == "") zählt nur die
## Distanz, wie bisher.
## Feature (v11.11, Distrikt-System): "from_building" optional - wird es
## angegeben, werden nur Lagerhäuser im SELBEN Bezirk ODER einem per
## Bezirkstor verbundenen Bezirk berücksichtigt (siehe DistrictSys.are_linked()).
## Ohne Angabe (from_building == null) gilt weiterhin nur die Distanz, wie bisher
## (z.B. für Aufrufstellen, die keinen sinnvollen "Herkunfts-Bezirk" haben).
func _find_nearest_storage_building(from_pos: Vector2, res: String = "", from_building: BuildingEntity = null) -> BuildingEntity:
	var best: BuildingEntity = null
	var best_d: float = INF
	for b in BuildingSys.buildings:
		var be: BuildingEntity = b
		if be.btype != "STORAGE" or be.is_under_construction or be.storage_capacity <= 0.0: continue
		if be.colony_id != colony_id: continue
		if res != "" and not be.accepts_resource(res): continue
		if from_building != null and not DistrictSys.are_linked(from_building.district_id, be.district_id): continue
		var d: float = from_pos.distance_to(Vector2(float(be.tile_x), float(be.tile_y)))
		if d < best_d:
			best_d = d; best = be
	return best

## Feature (v11.0): ein Produktions-Arbeiter, dessen Gebäude-Lager voll ist,
## trägt es selbst zum nächsten Lagerhaus - währenddessen produziert er
## nichts (siehe BuildingEntity.get_active_worker_count()).
@warning_ignore("unused_parameter")
func _update_haul_work(dt: float, ab: BuildingEntity, building_pos: Vector2) -> void:
	if haul_target == null or not is_instance_valid(haul_target):
		carry_inventory.clear(); haul_target = null; work_state = "WORKING"; return
	work_anim_t += dt
	var wh: BuildingEntity = haul_target
	match work_state:
		"HAUL_TO_WAREHOUSE":
			if _move_toward(Vector2(float(wh.tile_x) + 0.5, float(wh.tile_y) + 0.5), dt):
				_deposit_inventory_to_resourcesys()
				work_state = "HAUL_RETURN"
		"HAUL_RETURN":
			if _move_toward(building_pos, dt):
				haul_target = null
				work_state = "WORKING"

## Feature (v11.0): Frettchen, die einem Lagerhaus zugewiesen sind
## ("Lagerarbeiter"). Zwei Aufgaben, geprüft in dieser Reihenfolge:
##  1) liegt eine Baustelle mit fehlendem, im Lagernetzwerk verfügbarem
##     Material in Reichweite - Material direkt vom Lager zur Baustelle tragen
##  2) sonst: nahes Produktionsgebäude mit gefülltem lokalem Lager abklappern
##     und dessen Bestand ins Lagerhaus bringen
func _update_warehouse_work(dt: float, wh: BuildingEntity, wh_pos: Vector2) -> void:
	match work_state:
		"WH_TO_SOURCE":
			if haul_target == null or not is_instance_valid(haul_target) \
					or (haul_target as BuildingEntity).get_local_storage_total() <= 0.0:
				haul_target = null; work_state = "WORKING"; return
			var src: BuildingEntity = haul_target
			work_anim_t += dt
			if _move_toward(Vector2(float(src.tile_x) + 0.5, float(src.tile_y) + 0.5), dt):
				_pickup_from_building(src, wh.storage_filter)
				work_state = "WH_TO_WAREHOUSE"
		"WH_TO_WAREHOUSE":
			work_anim_t += dt
			if _move_toward(wh_pos, dt):
				_deposit_inventory_to_resourcesys()
				haul_target = null
				work_state = "WORKING"
		"WH_TO_SITE":
			if haul_target == null or not is_instance_valid(haul_target) \
					or not (haul_target as BuildingEntity).is_under_construction:
				_deposit_inventory_to_resourcesys()
				haul_target = null; work_state = "WORKING"; return
			var site: BuildingEntity = haul_target
			work_anim_t += dt
			if _move_toward(Vector2(float(site.tile_x) + 0.5, float(site.tile_y) + 0.5), dt):
				_deliver_inventory_to_site(site)
				haul_target = null
				work_state = "WORKING"
		_:
			work_anim_t = 0.0
			_move_toward(wh_pos, dt)
			if not carry_inventory.is_empty(): return
			var site_needs: BuildingEntity = _find_site_needing_materials(wh_pos, wh)
			if site_needs != null:
				var res: String = _pick_missing_resource(site_needs)
				# Feature (v11.1): ein spezialisiertes Lagerhaus liefert nur
				# noch die Ressource, auf die es spezialisiert ist.
				if res != "" and wh.accepts_resource(res):
					var need: float = site_needs.get_missing_amount(res)
					var avail: float = float(ResourceSys.resources.get(res, 0.0))
					var take: float = minf(get_carry_capacity(), minf(need, avail))
					if take > 0.0:
						ResourceSys.remove(res, take)
						carry_inventory[res] = take
						haul_target = site_needs
						work_state = "WH_TO_SITE"
						return
			var src2: BuildingEntity = _find_building_to_collect(wh_pos, wh)
			if src2 != null:
				haul_target = src2
				work_state = "WH_TO_SOURCE"

## Feature (v11.11, Distrikt-System): "wh" (das Lagerhaus, dem dieser
## Lagerarbeiter zugeordnet ist) liefert jetzt NUR NOCH an Baustellen im
## selben oder einem per Bezirkstor verbundenen Bezirk - "Lagerarbeiter holen
## nur innerhalb ihres Bezirks ab" (Nutzeranfrage), analog zu Timberborns
## getrennten Lager-Netzwerken pro Distrikt.
func _find_site_needing_materials(from_pos: Vector2, wh: BuildingEntity) -> BuildingEntity:
	var best: BuildingEntity = null
	var best_d: float = INF
	for b in BuildingSys.get_construction_sites():
		var be: BuildingEntity = b
		if be.is_fully_supplied(): continue
		if not DistrictSys.are_linked(wh.district_id, be.district_id): continue
		var d: float = from_pos.distance_to(Vector2(float(be.tile_x), float(be.tile_y)))
		if d <= get_warehouse_search_range() and d < best_d:
			best_d = d; best = be
	return best

## Feature (v11.1, Logistik-Feinschliff): ist das Lagerhaus "wh" auf eine
## Ressource spezialisiert, werden Produktionsgebäude übersprungen, deren
## lokales Lager NICHTS von dieser Ressource enthält - sonst würde der
## Lagerarbeiter dort sinnlos ankommen und nichts mitnehmen können.
## Feature (v11.11, Distrikt-System): zusätzlich auf denselben/verbundenen
## Bezirk eingeschränkt (siehe _find_site_needing_materials() oben).
func _find_building_to_collect(from_pos: Vector2, wh: BuildingEntity) -> BuildingEntity:
	var best: BuildingEntity = null
	var best_d: float = INF
	for b in BuildingSys.buildings:
		var be: BuildingEntity = b
		if be.is_under_construction or be.local_storage_capacity <= 0.0: continue
		if be.get_local_storage_total() <= 0.5: continue
		if wh.storage_filter != "" and not be.local_storage.has(wh.storage_filter): continue
		if not DistrictSys.are_linked(wh.district_id, be.district_id): continue
		var d: float = from_pos.distance_to(Vector2(float(be.tile_x), float(be.tile_y)))
		if d <= get_warehouse_search_range() and d < best_d:
			best_d = d; best = be
	return best

func _node_still_valid(world: Array) -> bool:
	var nd: Dictionary = _get_node_dict(world, harvest_tile)
	if nd.is_empty(): return false
	if bool(nd.get("depleted", false)): return false
	return float(nd.get("amount", 0.0)) > 0.5

func _get_node_dict(world: Array, t: Vector2i) -> Dictionary:
	if t.x < 0 or t.x >= world.size(): return {}
	var col: Array = world[t.x]
	if t.y < 0 or t.y >= col.size(): return {}
	var tile: Dictionary = col[t.y]
	var nd = tile.get("resource_node")
	if nd == null or not (nd is Dictionary): return {}
	return nd

## Sucht eine zufällige, aktuell erntbare Resource-Node desselben Typs wie
## `ab.collects_resource` im Sammelradius des Gebäudes.
func _find_harvestable_node(world: Array, ab: BuildingEntity) -> Vector2i:
	var candidates: Array = []
	var r: int = ab.collection_radius
	var bx: int = ab.tile_x
	var by: int = ab.tile_y
	var ww: int = world.size()
	for dx in range(-r, r + 1):
		var tx: int = bx + dx
		if tx < 0 or tx >= ww: continue
		var col: Array = world[tx]
		var hh: int = col.size()
		for dy in range(-r, r + 1):
			var ty: int = by + dy
			if ty < 0 or ty >= hh: continue
			var nd: Dictionary = _get_node_dict(world, Vector2i(tx, ty))
			if nd.is_empty(): continue
			if str(nd.get("type", "")) != ab.collects_resource: continue
			if bool(nd.get("depleted", false)): continue
			if float(nd.get("amount", 0.0)) <= 1.0: continue
			candidates.append(Vector2i(tx, ty))
	if candidates.is_empty(): return Vector2i(-1, -1)
	return candidates[randi() % candidates.size()]

## Baut die geerntete Quelle ab; wird sie leer, gilt sie als "depleted" und
## braucht danach Zeit zum Regenerieren (siehe WorldGenerator.tick_resource_nodes).
func _finish_harvest(world: Array) -> void:
	var nd: Dictionary = _get_node_dict(world, harvest_tile)
	if nd.is_empty(): return
	var amt: float = float(nd.get("amount", 0.0)) - HARVEST_AMOUNT
	if amt <= 0.0:
		nd["amount"] = 0.0
		nd["depleted"] = true
		nd["regen_timer"] = 0.0
	else:
		nd["amount"] = amt

func get_happiness() -> float:
	return float(needs["happiness"])

func serialize() -> Dictionary:
	return {
		"name": ferret_name, "health": health,
		"needs": needs.duplicate(), "age_days": age_days,
		"specialization": specialization, "spec_days": spec_days,
		"pos_x": pos.x, "pos_y": pos.y,
		"trait_id": trait_id,
		"colony_id": colony_id,
		# Feature (v11.9, Legendäre Frettchen):
		"career_building_id": career_building_id, "career_days": career_days,
		"is_legendary": is_legendary, "legendary_title": legendary_title,
		"legendary_accessories": legendary_accessories.duplicate()
	}

static func deserialize(data: Dictionary) -> FerretEntity:
	var f := FerretEntity.new()
	f.ferret_name = str(data.get("name", "Unbekannt"))
	f.health = float(data.get("health", 100.0))
	var n = data.get("needs", {"food": 60.0, "water": 60.0, "happiness": 60.0})
	f.needs = (n as Dictionary).duplicate()
	f.age_days = float(data.get("age_days", 0.0))
	f.specialization = str(data.get("specialization", ""))
	f.spec_days = float(data.get("spec_days", 0.0))
	# Feature (v11.8, Frettchen-Persönlichkeiten): Abwärtskompatibilität -
	# alte Saves (vor diesem Feature) haben kein "trait_id" Feld. Fallback:
	# nachträglich zufällig einen Trait zuweisen, statt das Frettchen ohne
	# Persönlichkeit zu lassen.
	f.trait_id = str(data.get("trait_id", ""))
	f.colony_id = int(data.get("colony_id", 0))
	if f.trait_id == "" or not FerretTraits.TRAITS.has(f.trait_id):
		f.trait_id = FerretTraits.pick_random_trait_id()
	# Feature (v11.9, Legendäre Frettchen): fehlt bei alten Saves komplett -
	# Standardwerte (nicht legendär, leere Karriere) sind bereits die
	# deklarierten Feld-Defaults, .get() mit Fallback reicht hier aus.
	f.career_building_id = str(data.get("career_building_id", ""))
	f.career_days = float(data.get("career_days", 0.0))
	f.is_legendary = bool(data.get("is_legendary", false))
	f.legendary_title = str(data.get("legendary_title", ""))
	f.legendary_accessories = (data.get("legendary_accessories", []) as Array).duplicate()
	# Pos: ältere Saves hatten Pixel-Koordinaten (~2880) – sicher auf Tile-Range clampen
	var raw_x: float = float(data.get("pos_x", 30.0))
	var raw_y: float = float(data.get("pos_y", 30.0))
	# Heuristik: Pixel-Koordinaten > 200 stammen aus altem Format
	if absf(raw_x) > 200.0 or absf(raw_y) > 200.0:
		raw_x = 30.0 + randf_range(-3.0, 3.0)
		raw_y = 30.0 + randf_range(-3.0, 3.0)
	f.pos = Vector2(raw_x, raw_y)
	f.target_pos = f.pos
	return f
