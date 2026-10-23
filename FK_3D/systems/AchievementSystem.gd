## AchievementSystem.gd
## Feature (v11.8, Achievement-System - Phase 1 des Langzeit-Content-Pakets).
## Architektur bewusst analog zu TechTree.gd: const-Datendictionary (hier
## ACHIEVEMENTS statt NODES), ein "unlocked"-Array, serialize()/deserialize()
## für SaveSystem.gd. Anders als TechTree.gd gibt es hier keine Kosten/
## Freischalt-Buttons - Achievements schalten sich automatisch frei, sobald
## ihre Bedingung erfüllt ist.
##
## WICHTIG (Performance-Vorgabe): Prüfung ist EVENT-GETRIEBEN, nicht per
## Frame-Polling. Es gibt bewusst KEINEN _process()-Tick - alle Bedingungen
## werden ausschliesslich in den GameState-Signal-Handlern unten geprüft,
## jeweils nur für die Achievement-Kategorien, die durch das jeweilige
## Signal überhaupt betroffen sein können.
extends Node

const CATEGORIES: Dictionary = {
	"POPULATION":  {"name": "Bevölkerung", "icon": "🐾"},
	"ECONOMY":     {"name": "Wirtschaft",  "icon": "📦"},
	"SURVIVAL":    {"name": "Überleben",   "icon": "❤️"},
	"EXPLORATION": {"name": "Erkundung",   "icon": "🗺️"},
	"TECH":        {"name": "Tech",        "icon": "🔬"},
	# Feature (v12.2, Phase 4 - Frettchen-Ich-Anpassung): eigene Kategorie
	# fürs Spieler-Frettchen. Anders als alle anderen Kategorien schaltet
	# jeder dieser 10 Erfolge zusätzlich ein Accessoire fürs Frettchen-Ich
	# frei (siehe "unlocks_accessory"-Feld unten sowie systems/
	# PlayerAccessories.gd) - einzige Kategorie mit spielrelevantem statt rein
	# kosmetischem Nutzen, da explizit vom Nutzer so gewünscht.
	"SPIELER":     {"name": "Frettchen-Ich", "icon": "🎯"},
}
const CATEGORY_ORDER: Array = ["POPULATION", "ECONOMY", "SURVIVAL", "EXPLORATION", "TECH", "SPIELER"]

## "reward" ist IMMER rein kosmetisch (Statue-Skin-Bezeichnung o.ä.) oder
## leer - bewusst KEINE Ressourcen-/Produktionsboni, um Powercreep zu
## vermeiden (siehe Nutzeranfrage).
const ACHIEVEMENTS: Dictionary = {
	"FIRST_STEPS": {
		"name": "Erste Schritte", "desc": "10 lebende Frettchen gleichzeitig in der Kolonie.",
		"icon": "🐣", "category": "POPULATION", "condition_type": "stat_threshold", "reward": ""
	},
	"GROWING_COLONY": {
		"name": "Wachsende Kolonie", "desc": "25 lebende Frettchen gleichzeitig in der Kolonie.",
		"icon": "🏘️", "category": "POPULATION", "condition_type": "stat_threshold", "reward": ""
	},
	"CENTURY": {
		"name": "Erste 100 Frettchen", "desc": "Insgesamt 100 Frettchen wurden im Laufe der Kolonie-Geschichte geboren.",
		"icon": "💯", "category": "POPULATION", "condition_type": "stat_threshold", "reward": ""
	},
	"FULL_HOUSES": {
		"name": "Alle Betten belegt", "desc": "Mindestens 10 Betten vorhanden, alle gleichzeitig belegt.",
		"icon": "🛏️", "category": "POPULATION", "condition_type": "stat_threshold", "reward": ""
	},
	"NO_LOSSES": {
		"name": "50 Tage ohne Verlust", "desc": "50 Tage am Stück ohne einen einzigen Frettchen-Tod.",
		"icon": "🕊️", "category": "POPULATION", "condition_type": "stat_threshold", "reward": ""
	},
	"FULL_STORAGE": {
		"name": "Gut versorgt", "desc": "500 Einheiten einer einzelnen Ressource gleichzeitig gelagert.",
		"icon": "📦", "category": "ECONOMY", "condition_type": "stat_threshold", "reward": ""
	},
	"BIG_BUILDER": {
		"name": "Baumeister", "desc": "20 Gebäude gleichzeitig auf der Karte.",
		"icon": "🏗️", "category": "ECONOMY", "condition_type": "stat_threshold", "reward": ""
	},
	"TEN_REBUILDS": {
		"name": "Modernisierer", "desc": "10 Gebäude-Umbauten abgeschlossen.",
		"icon": "🔧", "category": "ECONOMY", "condition_type": "event_flag", "reward": ""
	},
	"SCIENCE_500": {
		"name": "Gelehrte Kolonie", "desc": "Insgesamt 500 Wissenspunkte in Forschung investiert.",
		"icon": "📚", "category": "ECONOMY", "condition_type": "tech_progress", "reward": ""
	},
	"DROUGHT_SURVIVOR": {
		"name": "Dürre überstanden", "desc": "Eine komplette Dürre ohne einen einzigen Todesfall überstehen.",
		"icon": "🌵", "category": "SURVIVAL", "condition_type": "survive_disaster", "reward": ""
	},
	"WINTER_SURVIVOR": {
		"name": "Erster Winter", "desc": "Die erste Wintersaison erleben.",
		"icon": "❄️", "category": "SURVIVAL", "condition_type": "event_flag", "reward": ""
	},
	"OLD_TIMER": {
		"name": "Methusalem", "desc": "Ein Frettchen erreicht ein Alter von 60 Tagen.",
		"icon": "🦴", "category": "SURVIVAL", "condition_type": "stat_threshold", "reward": ""
	},
	"EPOCH_4": {
		"name": "Moderne Zeitalter", "desc": "Epoche 4 (Moderne) erreicht.",
		"icon": "🏭", "category": "SURVIVAL", "condition_type": "tech_progress", "reward": ""
	},
	"FIRST_EXPEDITION": {
		"name": "Aufbruch", "desc": "Die erste Expedition erfolgreich abgeschlossen.",
		"icon": "🧭", "category": "EXPLORATION", "condition_type": "event_flag", "reward": ""
	},
	"FIVE_EXPEDITIONS": {
		"name": "Vielgereist", "desc": "5 Expeditionen erfolgreich abgeschlossen.",
		"icon": "🗺️", "category": "EXPLORATION", "condition_type": "event_flag", "reward": ""
	},
	"FIRST_TECH": {
		"name": "Forschergeist", "desc": "Den ersten Tech-Knoten erforscht.",
		"icon": "🔬", "category": "TECH", "condition_type": "tech_progress", "reward": ""
	},
	"ALL_SECTIONS": {
		"name": "Universalgelehrte", "desc": "Alle 6 Themenbereiche des Tech Trees zu 100% erforscht.",
		"icon": "🎓", "category": "TECH", "condition_type": "tech_progress", "reward": ""
	},
	"FULL_TECH_TREE": {
		"name": "Meister aller Zünfte", "desc": "Alle 60 Tech-Knoten erforscht.",
		"icon": "👑", "category": "TECH", "condition_type": "tech_progress", "reward": ""
	},
	# ── Feature (v12.2, Phase 4): 10 Frettchen-Ich-Erfolge - jeder schaltet
	# genau ein Accessoire fürs Frettchen-Ich frei (siehe
	# "unlocks_accessory", ausgewertet in _unlock() unten UND in
	# systems/PlayerAccessories.gd). Anders als alle anderen Achievements
	# HIER bewusst mit spielrelevantem Nutzen (Boosts NUR fürs Frettchen-Ich,
	# siehe PlayerAccessories.BOOSTS) - explizite Nutzeranfrage, keine
	# versehentliche Abweichung vom "reward ist rein kosmetisch"-Prinzip der
	# übrigen Kategorien.
	"PLAYER_DISTANCE": {
		"name": "Weitgereist", "desc": "1000 Welteinheiten im Frettchenmodus zurückgelegt.",
		"icon": "🥾", "category": "SPIELER", "condition_type": "stat_threshold", "reward": "",
		"unlocks_accessory": "TOP_HAT"
	},
	"PLAYER_MINIGAMES_50": {
		"name": "Sammelprofi", "desc": "50 Minispiele im Frettchenmodus erfolgreich abgeschlossen.",
		"icon": "🎪", "category": "SPIELER", "condition_type": "stat_threshold", "reward": "",
		"unlocks_accessory": "WIZARD_HAT"
	},
	"PLAYER_PLAYTIME": {
		"name": "Kolonieoberhaupt", "desc": "Insgesamt 1 Stunde im Frettchenmodus verbracht.",
		"icon": "⏱️", "category": "SPIELER", "condition_type": "stat_threshold", "reward": "",
		"unlocks_accessory": "CROWN"
	},
	"PLAYER_RESOURCES_500": {
		"name": "Vielsammler", "desc": "500 Ressourcen über Minispiele im Frettchenmodus gesammelt.",
		"icon": "🧺", "category": "SPIELER", "condition_type": "stat_threshold", "reward": "",
		"unlocks_accessory": "BANDANA"
	},
	"PLAYER_TRAIN_RIDE": {
		"name": "Fahrgast", "desc": "Im Frettchenmodus zum ersten Mal in einem Zug mitgefahren.",
		"icon": "🚂", "category": "SPIELER", "condition_type": "event_flag", "reward": ""
	},
	"NEIGHBOR_FOUND": {
		"name": "Entdecker", "desc": "Eine fremde Kolonie im Nebel entdeckt.",
		"icon": "🔭", "category": "SPIELER", "condition_type": "event_flag", "reward": ""
	},
	"NEIGHBOR_ANNEXED": {
		"name": "Gute Nachbarschaft", "desc": "Eine Nachbarkolonie friedlich in deine Kolonie aufgenommen.",
		"icon": "🤝", "category": "SPIELER", "condition_type": "event_flag", "reward": ""
	},
	# ── Feature (v16.8, Lokführer-Modus): selbst gefahrene Halte.
	"PLAYER_LOCO_25": {
		"name": "Lokführer", "desc": "25 Halte im Zug selbst ans Gas/Bremse geführt.",
		"icon": "🧑‍✈️", "category": "SPIELER", "condition_type": "stat_threshold", "reward": ""
	},
	"PLAYER_JUMPS_100": {
		"name": "Hüpfburg", "desc": "100 Sprünge im Frettchenmodus.",
		"icon": "🦘", "category": "SPIELER", "condition_type": "stat_threshold", "reward": "",
		"unlocks_accessory": "BOWTIE"
	},
	"PLAYER_WINTER_RESOURCES": {
		"name": "Wintertrotz", "desc": "100 Ressourcen im Winter über Minispiele gesammelt.",
		"icon": "🥶", "category": "SPIELER", "condition_type": "stat_threshold", "reward": "",
		"unlocks_accessory": "SCARF"
	},
	"PLAYER_NODES_DEPLETED": {
		"name": "Erntemeister", "desc": "20 Ressourcenknoten im Frettchenmodus komplett geleert.",
		"icon": "🌾", "category": "SPIELER", "condition_type": "stat_threshold", "reward": "",
		"unlocks_accessory": "MEDAL"
	},
	"PLAYER_TILES_EXPLORED": {
		"name": "Entdecker", "desc": "200 verschiedene Kacheln im Frettchenmodus betreten.",
		"icon": "🧭", "category": "SPIELER", "condition_type": "stat_threshold", "reward": "",
		"unlocks_accessory": "MONOCLE"
	},
	"PLAYER_PERFECT_20": {
		"name": "Perfektionist", "desc": "20 Minispiele mit dem bestmöglichen Ergebnis abgeschlossen.",
		"icon": "✨", "category": "SPIELER", "condition_type": "stat_threshold", "reward": "",
		"unlocks_accessory": "EYEPATCH"
	},
	"PLAYER_HARD_LANDINGS_10": {
		"name": "Klippenspringer", "desc": "10 harte Landungen im Frettchenmodus überstanden.",
		"icon": "🪂", "category": "SPIELER", "condition_type": "stat_threshold", "reward": "",
		"unlocks_accessory": "CAPE"
	},
}

signal achievement_unlocked_toast(id: String)

var unlocked: Array = []

# ── interne Zähler/Snapshots (nicht Teil der ACHIEVEMENTS-Daten, aber Teil
# des Speicherstands - siehe serialize()/deserialize()) ─────────────────────
var lifetime_births: int = 0
var rebuilds_completed: int = 0
var expeditions_completed: int = 0
var last_death_day: int = 0
var drought_death_snapshot: int = -1
var seen_winter: bool = false

# ── Feature (v12.2, Phase 4): Frettchen-Ich-Zähler. Bewusste Ausnahme vom
# "kein Frame-Polling"-Prinzip (siehe Datei-Kopfkommentar) NUR für
# player_dist_walked/player_playtime_sec/player_tiles_visited - diese
# können prinzipbedingt nicht event-getrieben erfasst werden (kontinuierliche
# Bewegung/Zeit). Eingeschränkt auf report_player_tick(), das NUR während
# eines aktiven Frettchenmodus-Aufenthalts pro Physik-Frame aufgerufen wird
# (siehe PlayerController.gd) - kein Dauerlast-Polling der Kolonie-Simulation.
var player_dist_walked: float = 0.0
var player_minigames_completed: int = 0
var player_playtime_sec: float = 0.0
var player_resources_collected: float = 0.0
var player_jumps: int = 0
var player_winter_resources: float = 0.0
var player_nodes_depleted: int = 0
var player_tiles_visited: Dictionary = {}   # Set: "tx,ty" -> true
var player_minigames_perfect: int = 0
var player_hard_landings: int = 0
var manual_driver_stops: int = 0   # v16.8: eigene Halte im Zug (Erfolg "Lokführer")

func init() -> void:
	unlocked = []
	lifetime_births = 0
	rebuilds_completed = 0
	expeditions_completed = 0
	last_death_day = 0
	drought_death_snapshot = -1
	seen_winter = false
	player_dist_walked = 0.0
	player_minigames_completed = 0
	player_playtime_sec = 0.0
	player_resources_collected = 0.0
	player_jumps = 0
	player_winter_resources = 0.0
	player_nodes_depleted = 0
	player_tiles_visited = {}
	player_minigames_perfect = 0
	player_hard_landings = 0
	manual_driver_stops = 0

func _ready() -> void:
	GameState.ferret_born.connect(_on_ferret_born)
	GameState.ferret_died.connect(_on_ferret_died)
	GameState.day_changed.connect(_on_day_changed)
	GameState.tech_unlocked.connect(_on_tech_unlocked)
	GameState.drought_started.connect(_on_drought_started)
	GameState.drought_ended.connect(_on_drought_ended)
	GameState.expedition_returned.connect(_on_expedition_returned)
	GameState.building_placed.connect(_on_building_placed)
	GameState.building_rebuilt.connect(_on_building_rebuilt)
	GameState.resource_changed.connect(_on_resource_changed)
	GameState.season_changed.connect(_on_season_changed)

# ══════════════════════════════════════════════════════════════════════════
# FREISCHALTUNG
# ══════════════════════════════════════════════════════════════════════════
## Bug-Fix (v12.4): öffentlicher Wrapper für Dev-Mode/Debug-Zwecke, der
## IMMER über den regulären _unlock()-Pfad läuft (statt "unlocked" direkt
## zu manipulieren). Der bisherige Dev-Tools-Button "Alle Achievements
## freischalten" hängte IDs direkt an "unlocked" an - dadurch feuerte NIE
## das achievement_unlocked_toast-Signal, an das sich reaktive UI-Panels
## (u.a. der neue Charakter-Editor über PlayerAccessories) hängen. Ergebnis:
## per Dev-Mode "freigeschaltete" Accessoires liessen sich zwar technisch
## equippen (is_unlocked() prüfte weiterhin korrekt "unlocked"), aber KEIN
## Panel wusste davon, solange es nicht ohnehin neu geöffnet wurde - wirkte
## für den Nutzer wie "gar nicht freigeschaltet".
func debug_force_unlock(id: String) -> void:
	_unlock(id)

func _unlock(id: String) -> void:
	if id in unlocked: return
	if not ACHIEVEMENTS.has(id): return
	unlocked.append(id)
	var ad: Dictionary = ACHIEVEMENTS[id]
	# Feature: normale, unauffällige Notification-Zeile UND zusätzlich ein
	# eigenes Signal für einen auffälligeren Toast/Popup-Effekt (siehe
	# AchievementToast.gd) - beide Kanäle wie in der Anfrage gefordert.
	GameState.notify("🏆 Erfolg freigeschaltet: " + str(ad.get("name", id)), Color(0.55, 0.42, 0.08, 0.92))
	achievement_unlocked_toast.emit(id)
	# Feature (v12.2, Phase 4): SPIELER-Erfolge schalten zusätzlich ein
	# Accessoire fürs Frettchen-Ich frei (siehe "unlocks_accessory"-Feld).
	var acc_id: String = str(ad.get("unlocks_accessory", ""))
	if acc_id != "":
		PlayerAccessories.notify_unlocked(acc_id)

func is_unlocked(id: String) -> bool:
	return id in unlocked

func get_progress_count() -> int:
	return unlocked.size()

func get_total_count() -> int:
	return ACHIEVEMENTS.size()

func get_achievements_by_category(category: String) -> Array:
	var result: Array = []
	for aid in ACHIEVEMENTS:
		if str((ACHIEVEMENTS[aid] as Dictionary).get("category", "")) == category:
			result.append(aid)
	return result

# ══════════════════════════════════════════════════════════════════════════
# SIGNAL-HANDLER (jeweils nur die dadurch potenziell betroffenen Achievements)
# ══════════════════════════════════════════════════════════════════════════
func _on_ferret_born(_f) -> void:
	lifetime_births += 1
	if lifetime_births >= 100: _unlock("CENTURY")
	if PopMgr.ferrets.size() >= 10: _unlock("FIRST_STEPS")
	if PopMgr.ferrets.size() >= 25: _unlock("GROWING_COLONY")
	_check_full_houses()

func _on_ferret_died(_f, _cause: String) -> void:
	last_death_day = DayNight.day_count

func _on_day_changed(day: int) -> void:
	# "50 Tage am Stück ohne Frettchen-Tod" - Streak seit dem letzten Tod
	# (bzw. seit Kolonie-Start, falls noch niemand gestorben ist).
	if day - last_death_day >= 50:
		_unlock("NO_LOSSES")
	# "Methusalem" - günstig genug, um einmal pro Spieltag über alle
	# lebenden Frettchen zu iterieren (kein Frame-Polling).
	for f in PopMgr.ferrets:
		var fe: FerretEntity = f
		if float(fe.age_days) >= 60.0:
			_unlock("OLD_TIMER")
			break

func _on_tech_unlocked(tid: String) -> void:
	if not str(tid).begins_with("EPOCH_"):
		_unlock("FIRST_TECH")
	if TechTreeSys.get_epoch() >= 4:
		_unlock("EPOCH_4")
	if TechTreeSys.total_spent >= 500.0:
		_unlock("SCIENCE_500")
	var all_sections_done: bool = true
	for sec in TechTreeSys.SECTION_ORDER:
		if TechTreeSys.get_section_progress(sec) < 10:
			all_sections_done = false
			break
	if all_sections_done: _unlock("ALL_SECTIONS")
	var node_count: int = 0
	for u in TechTreeSys.unlocked:
		if not str(u).begins_with("EPOCH_"): node_count += 1
	if node_count >= 60: _unlock("FULL_TECH_TREE")

func _on_drought_started() -> void:
	drought_death_snapshot = PopMgr.dead_ferrets.size()

func _on_drought_ended() -> void:
	if drought_death_snapshot >= 0 and PopMgr.dead_ferrets.size() == drought_death_snapshot:
		_unlock("DROUGHT_SURVIVOR")
	drought_death_snapshot = -1

func _on_expedition_returned(_result: Dictionary) -> void:
	expeditions_completed += 1
	if expeditions_completed >= 1: _unlock("FIRST_EXPEDITION")
	if expeditions_completed >= 5: _unlock("FIVE_EXPEDITIONS")

func _on_building_placed(_b) -> void:
	if BuildingSys.buildings.size() >= 20: _unlock("BIG_BUILDER")
	_check_full_houses()

func _on_building_rebuilt(_b) -> void:
	rebuilds_completed += 1
	if rebuilds_completed >= 10: _unlock("TEN_REBUILDS")

func _on_resource_changed(_resource: String, amount: float) -> void:
	if amount >= 500.0: _unlock("FULL_STORAGE")

func _on_season_changed(season: String) -> void:
	if season == "Winter" and not seen_winter:
		seen_winter = true
		_unlock("WINTER_SURVIVOR")

func _check_full_houses() -> void:
	var total_beds: int = BuildingSys.get_total_beds()
	if total_beds >= 10 and BuildingSys.get_occupied_beds() >= total_beds:
		_unlock("FULL_HOUSES")

# ══════════════════════════════════════════════════════════════════════════
# FRETTCHEN-ICH-ZAEHLER (Feature v12.2, Phase 4) - aufgerufen von
# PlayerController.gd bzw. GameController.gd, NICHT von GameState-Signalen
# (Spieler-Aktionen sind kein Kolonie-Zustand).
# ══════════════════════════════════════════════════════════════════════════

## Pro Physik-Frame während eines aktiven Frettchenmodus-Aufenthalts
## aufgerufen (siehe Kommentar bei den var-Deklarationen oben zur bewussten
## Ausnahme vom Nicht-Polling-Prinzip).
func report_player_tick(delta: float, dist_moved: float, tile: Vector2i) -> void:
	player_playtime_sec += delta
	player_dist_walked += dist_moved
	var key: String = "%d,%d" % [tile.x, tile.y]
	if not player_tiles_visited.has(key):
		player_tiles_visited[key] = true
		if player_tiles_visited.size() >= 200: _unlock("PLAYER_TILES_EXPLORED")
	if player_dist_walked >= 1000.0: _unlock("PLAYER_DISTANCE")
	if player_playtime_sec >= 3600.0: _unlock("PLAYER_PLAYTIME")

func report_player_jump() -> void:
	player_jumps += 1
	if player_jumps >= 100: _unlock("PLAYER_JUMPS_100")

## v16.4: erste Zugfahrt in Ich-Perspektive.
func report_train_ride() -> void:
	_unlock("PLAYER_TRAIN_RIDE")

## v16.7: Nachbarkolonien.
func report_neighbor_found() -> void:
	_unlock("NEIGHBOR_FOUND")

func report_neighbor_annexed() -> void:
	_unlock("NEIGHBOR_ANNEXED")

func report_player_hard_landing() -> void:
	player_hard_landings += 1
	if player_hard_landings >= 10: _unlock("PLAYER_HARD_LANDINGS_10")

## v16.8: der mitfahrende Spieler hat einen Halt absolut selbst angefahren
## (RailSys._arrive, nur wenn RailSys.riding == Zug). Kleines Bonbon: pünktliche
## Anfahrt verkürzt dort den Stopp (siehe RailSys.PUNCTUAL_*).
func report_manual_stop() -> void:
	manual_driver_stops += 1
	if manual_driver_stops >= 25: _unlock("PLAYER_LOCO_25")

## Wird von GameController._on_minigame_finished() nach jedem erfolgreich
## abgeschlossenen Minispiel aufgerufen. "reward" ist bereits inkl. evtl.
## Zauberhut-/Medaille-Boosts (Reihenfolge in GameController: erst Boosts auf
## reward anwenden, DANN hier melden - "gesammelte Ressourcen" soll den
## tatsächlich erhaltenen Betrag zählen). "is_perfect" = bestmögliches
## Ergebnis (reward nahe max_reward).
func report_player_minigame(reward: float, is_perfect: bool, is_winter: bool) -> void:
	player_minigames_completed += 1
	player_resources_collected += reward
	if is_winter: player_winter_resources += reward
	if is_perfect: player_minigames_perfect += 1
	if player_minigames_completed >= 50: _unlock("PLAYER_MINIGAMES_50")
	if player_resources_collected >= 500.0: _unlock("PLAYER_RESOURCES_500")
	if player_winter_resources >= 100.0: _unlock("PLAYER_WINTER_RESOURCES")
	if player_minigames_perfect >= 20: _unlock("PLAYER_PERFECT_20")

func report_player_node_depleted() -> void:
	player_nodes_depleted += 1
	if player_nodes_depleted >= 20: _unlock("PLAYER_NODES_DEPLETED")

# ══════════════════════════════════════════════════════════════════════════
# SPEICHERN / LADEN
# ══════════════════════════════════════════════════════════════════════════
func serialize() -> Dictionary:
	return {
		"unlocked": unlocked.duplicate(),
		"lifetime_births": lifetime_births,
		"rebuilds_completed": rebuilds_completed,
		"expeditions_completed": expeditions_completed,
		"last_death_day": last_death_day,
		"seen_winter": seen_winter,
		# Feature (v12.2, Phase 4):
		"player_dist_walked": player_dist_walked,
		"player_minigames_completed": player_minigames_completed,
		"player_playtime_sec": player_playtime_sec,
		"player_resources_collected": player_resources_collected,
		"player_jumps": player_jumps,
		"player_winter_resources": player_winter_resources,
		"player_nodes_depleted": player_nodes_depleted,
		"player_tiles_visited": player_tiles_visited.duplicate(),
		"player_minigames_perfect": player_minigames_perfect,
		"player_hard_landings": player_hard_landings,
		"manual_driver_stops": manual_driver_stops,   # v16.8
	}

func deserialize(data) -> void:
	if not (data is Dictionary):
		init(); return
	var d: Dictionary = data as Dictionary
	unlocked = (d.get("unlocked", []) as Array).duplicate()
	lifetime_births = int(d.get("lifetime_births", 0))
	rebuilds_completed = int(d.get("rebuilds_completed", 0))
	expeditions_completed = int(d.get("expeditions_completed", 0))
	last_death_day = int(d.get("last_death_day", 0))
	seen_winter = bool(d.get("seen_winter", false))
	drought_death_snapshot = -1
	# Feature (v12.2, Phase 4):
	player_dist_walked = float(d.get("player_dist_walked", 0.0))
	player_minigames_completed = int(d.get("player_minigames_completed", 0))
	player_playtime_sec = float(d.get("player_playtime_sec", 0.0))
	player_resources_collected = float(d.get("player_resources_collected", 0.0))
	player_jumps = int(d.get("player_jumps", 0))
	player_winter_resources = float(d.get("player_winter_resources", 0.0))
	player_nodes_depleted = int(d.get("player_nodes_depleted", 0))
	player_tiles_visited = (d.get("player_tiles_visited", {}) as Dictionary).duplicate()
	player_minigames_perfect = int(d.get("player_minigames_perfect", 0))
	player_hard_landings = int(d.get("player_hard_landings", 0))
	manual_driver_stops = int(d.get("manual_driver_stops", 0))   # v16.8; alte Saves = 0
