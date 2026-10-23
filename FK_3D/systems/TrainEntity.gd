class_name TrainEntity
extends RefCounted
## Feature (v16.2, Logistik-Update Phase 2): ein Güterzug (Lok + Waggons).
## Reine Daten + Serialisierung; die Bewegung/Logik steckt in RailSys.gd, die
## Darstellung in rendering/RailRenderer.gd.

var id: int = 0
var line_id: int = -1            # -1 = keiner Linie zugewiesen (steht im Depot)
var depot_key: int = -1          # Gleis-/Gebäude-Schlüssel des Heimat-Depots
var colony_id: int = 0           # Kolonie des Depots
var state: String = "DEPOT"      # DEPOT | MOVING | DWELL | BLOCKED
var head: Vector2 = Vector2.ZERO # Lok-Position in Kachelkoordinaten (ganzzahlig = Kachelmitte)
var heading: Vector2 = Vector2(1, 0)
var path: Array = []             # Gleis-Schlüssel (siehe RailSys.key()) bis zum nächsten Halt
var path_i: int = 0              # Index der Kachel, auf die die Lok gerade zufährt
var next_stop: int = 0           # Index in line.stops, den der Zug als nächstes ansteuert
var timer: float = 0.0           # Haltezeit / Wartezeit bei BLOCKED
var cargo: Dictionary = {}       # Ressource -> Menge
var wagons: int = 2
var trail: Array = []            # letzte Kopf-Positionen (neueste zuerst) für die Waggons
var blocked_day: int = -1        # an welchem Tag zuletzt "Strecke blockiert" gemeldet wurde
var full_day: int = -1           # an welchem Tag zuletzt "Lager voll" gemeldet wurde
var trips: int = 0               # abgeschlossene Halte (Statistik)

# Feature (v16.8, Lokführer-Modus): der mitfahrende Spieler kann das Tempolenkr
# (Gas [W] / Bremse [S]) selbst in der Hand halten - `manual` schaltet um,
# `speed` ist das aktuelle Tempo in Kacheln/s (ohne Lokführer fährt der Zug
# konstant TRAIN_SPEED). Geschwindigkeit selbst wird NICHT gespeichert:
# nach dem Laden ist `RailSys.riding` ohnehin null und der Zug fährt automatisch.
var manual: bool = false
var speed: float = 0.0
var manual_stops: int = 0        # Halte, die der Spieler selbst angefahren hat (Erfolg "Lokführer")

func capacity() -> float:
	return RailSys.TRAIN_CAPACITY_PER_WAGON * float(wagons)

func cargo_total() -> float:
	var t: float = 0.0
	for k in cargo: t += float(cargo[k])
	return t

func serialize() -> Dictionary:
	return {
		"id": id, "line_id": line_id, "depot_key": depot_key, "colony_id": colony_id,
		"state": state, "head": [head.x, head.y], "next_stop": next_stop,
		"cargo": cargo.duplicate(), "wagons": wagons, "trips": trips,
		"manual_stops": manual_stops   # v16.8: Fortschritt "Lokführer" bleibt erhalten
	}

static func deserialize(d: Dictionary) -> TrainEntity:
	var t := TrainEntity.new()
	t.id = int(d.get("id", 0)); t.line_id = int(d.get("line_id", -1))
	t.depot_key = int(d.get("depot_key", -1)); t.colony_id = int(d.get("colony_id", 0))
	var h: Array = d.get("head", [0, 0]) as Array
	t.head = Vector2(float(h[0]), float(h[1]))
	t.next_stop = int(d.get("next_stop", 0))
	var c: Dictionary = d.get("cargo", {}) as Dictionary
	for k in c: t.cargo[str(k)] = float(c[k])
	t.wagons = int(d.get("wagons", 2)); t.trips = int(d.get("trips", 0))
	t.manual_stops = int(d.get("manual_stops", 0))   # v16.8; fehlt in alten Saves = 0
	# Nach dem Laden wird die Strecke neu geplant (Pfad wird nicht gespeichert).
	var st: String = str(d.get("state", "DEPOT"))
	t.state = "DEPOT" if (st == "DEPOT" or t.line_id < 0) else "BLOCKED"
	t.timer = 0.0
	t.trail = [t.head]
	return t
