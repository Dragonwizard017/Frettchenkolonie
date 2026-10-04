## FerretAccessories.gd
## Feature (v11.9, Legendäre Frettchen - Accessoires). Reine Datenülle nach
## demselben Muster wie FerretTraits.gd: const-Dictionary + statische
## Hilfsfunktionen, kein Autoload nötig (kein Laufzeit-Zustand).
##
## 10 Accessoires (siehe assets/accessories/*.glb, generiert per trimesh -
## Details siehe General.md) verteilt auf 4 Slots (HEAD/NECK/FACE/BACK).
## "Kombinierbar" heisst hier: pro Slot maximal EIN Accessoire (sonst würden
## sich z.B. zwei Kopfbedeckungen visuell überlagern), aber die Slots werden
## unabhängig voneinander gewürfelt - ein legendäres Frettchen kann also
## z.B. gleichzeitig Krone (HEAD) + Schal (NECK) + Monokel (FACE) + Umhang
## (BACK) tragen. Siehe pick_random_set() für die Zusammenstellung.
extends RefCounted
class_name FerretAccessories

const SLOTS: Array = ["HEAD", "NECK", "FACE", "BACK"]

## "offset"/"rot_y" sind lokale Transform-Werte relativ zum Frettchen-Root
## selbst (siehe WorldRenderer3D._attach_ferret_accessories() - Accessoires
## hängen DIREKT am Frettchen, OHNE Gegen-Skalierung, und erben dadurch
## ganz normal dieselbe FERRET_MODEL_SCALE-Vergrösserung wie jeder andere
## Teil des Frettchen-Meshes auch). Diese Werte gelten deshalb in denselben
## UNSKALIERTEN Einheiten wie ferret.glb selbst - tatsächlich vermessen
## (trimesh, ausserhalb von Godot, siehe General.md für die Rohdaten):
## Füsse bei Y=0, Rücken/Schultern bei Y≈0.27, Kopfmitte Y≈0.24 Z≈0.27,
## Ohren-Oberkante Y≈0.30-0.33, Nasenspitze Z≈0.34, Augen bei X≈±0.034
## Y≈0.25 Z≈0.30.
##
## Bug-Fix (v11.23): CAPE.offset.y stand fälschlich auf 0.31 (seit v11.21,
## in dem Versuch, das Cape "ausserhalb" des Körper-Hauptvolumens zu
## platzieren) - das liegt aber OBERHALB des oben dokumentierten
## Rücken/Schultern-Werts (Y≈0.27) und nahe an der Kopf/Hut-Höhe
## (CROWN/TOP_HAT bei Y=0.33, WIZARD_HAT bei 0.31) - das Cape "schwebte"
## dadurch auf Kopfhöhe statt am Rücken zu hängen (vom Nutzer als
## "steht senkrecht im Frettchen" beschrieben, per Nahaufnahme-Screenshot
## bestätigt). Zurückgesetzt auf den in diesem Kommentar bereits
## dokumentierten, gemessenen Rücken/Schultern-Wert Y=0.27.
##
## Bug-Fix (v11.24, exakte trimesh-Vermessung von ferret.glb statt
## Schätzwerten - siehe WorldRenderer3D._attach_ferret_accessories() für
## die vollen Messdaten): NECK-Slot (BOWTIE/SCARF/MEDAL) lag bei Z≈0.18-0.19
## - numerisch bestätigt INNERHALB der massiven Body_mesh-Box (Body reicht
## bis Z=0.21) - daher unsichtbar (Nutzer-Report: "Fliege sieht man gar
## nicht"). Neue Werte liegen in der tatsächlich leeren "Kehlnische"
## (Y<0.19, Z>0.21 - dort existiert weder Body- noch Head-Geometrie), pro
## Mesh-Grösse einzeln durchgerechnet. CAPE.offset.z auf 0.15 verschoben
## (vormals -0.06) UND neues Feld "rot_x": PI/2 ergänzt - dreht das Cape von
## einer hängenden, durch den Körper clippenden Flagge zu einem dünnen,
## waagerecht auf der Rücken-Oberfläche (Y=0.27) aufliegenden Umhang, der
## von der Schulter (Z=0.15) bis zur Rücken-Mitte (Z=0.03) reicht.
##
## Neuvermessung (v15.2, neues Block-Frettchen mit Felltextur statt altem
## ferret.glb - Masse in Blender verifiziert, Render-Kontrolle pro Slot):
## Füsse Y=0, Rücken Y≈0.235, Kopfmitte Y≈0.235 Z≈0.26, Ohren-Oberkante Y≈0.33,
## Nasenspitze Z≈0.348, Augen bei X≈±0.040 Y≈0.25 Z≈0.318. Kehlnische jetzt
## Y<0.175 und Z>0.18. Angepasst: BOWTIE (0.0,0.10,0.23, sitzt auf dem Latz),
## SCARF (0.0,0.12,0.30, Ring frei unter der Schnauze), CAPE (0.0,0.24,0.10,
## liegt flach hinter dem Nacken), MONOCLE/EYEPATCH X auf ±0.04 (Augenlinie).
## Alle 10 Accessoire-Meshes neu gebaut (Blender, gleiche Filenames).
const ACCESSORIES: Dictionary = {
	"CROWN":     {"name": "Krone",         "slot": "HEAD", "glb": "res://assets/accessories/crown.glb",      "offset": Vector3(0.0, 0.33, 0.24), "rot_y": 0.0},
	"TOP_HAT":   {"name": "Zylinder",      "slot": "HEAD", "glb": "res://assets/accessories/top_hat.glb",    "offset": Vector3(0.0, 0.33, 0.24), "rot_y": 0.0},
	"WIZARD_HAT":{"name": "Zauberhut",     "slot": "HEAD", "glb": "res://assets/accessories/wizard_hat.glb", "offset": Vector3(0.0, 0.31, 0.24), "rot_y": 0.0},
	"BANDANA":   {"name": "Bandana",       "slot": "HEAD", "glb": "res://assets/accessories/bandana.glb",    "offset": Vector3(0.0, 0.29, 0.26), "rot_y": 0.0},
	"BOWTIE":    {"name": "Fliege",        "slot": "NECK", "glb": "res://assets/accessories/bowtie.glb",     "offset": Vector3(0.0, 0.10, 0.23), "rot_y": 0.0},
	"SCARF":     {"name": "Schal",         "slot": "NECK", "glb": "res://assets/accessories/scarf.glb",      "offset": Vector3(0.0, 0.12, 0.30), "rot_y": 0.0},
	"MEDAL":     {"name": "Medaille",      "slot": "NECK", "glb": "res://assets/accessories/medal.glb",      "offset": Vector3(0.0, 0.13, 0.26), "rot_y": 0.0},
	"MONOCLE":   {"name": "Monokel",       "slot": "FACE", "glb": "res://assets/accessories/monocle.glb",    "offset": Vector3(0.04, 0.25, 0.33), "rot_y": 0.0},
	"EYEPATCH":  {"name": "Augenklappe",   "slot": "FACE", "glb": "res://assets/accessories/eyepatch.glb",   "offset": Vector3(-0.04, 0.25, 0.33), "rot_y": 0.0},
	"CAPE":      {"name": "Umhang",        "slot": "BACK", "glb": "res://assets/accessories/cape.glb",       "offset": Vector3(0.0, 0.24, 0.10), "rot_x": PI/2, "rot_y": 0.0},
}

## Würfelt pro Slot unabhängig (70% Chance auf ein Accessoire in diesem
## Slot, davon gleichverteilt eines der Slot-Optionen) - liefert ein
## individuelles Set (Array von Accessoire-IDs) für ein neu legendär
## gewordenes Frettchen. Mindestens 1 Accessoire garantiert, damit kein
## legendäres Frettchen komplett "leer" bleibt.
static func pick_random_set() -> Array:
	var by_slot: Dictionary = {}
	for aid in ACCESSORIES:
		var slot: String = str((ACCESSORIES[aid] as Dictionary).get("slot", ""))
		if not by_slot.has(slot): by_slot[slot] = []
		(by_slot[slot] as Array).append(aid)

	var result: Array = []
	for slot in SLOTS:
		if randf() < 0.7:
			var options: Array = by_slot.get(slot, [])
			if not options.is_empty():
				result.append(options[randi() % options.size()])

	if result.is_empty():
		var all_slots: Array = SLOTS.duplicate()
		all_slots.shuffle()
		var fallback: Array = by_slot.get(all_slots[0], [])
		if not fallback.is_empty(): result.append(fallback[randi() % fallback.size()])
	return result

static func get_accessory(aid: String) -> Dictionary:
	return ACCESSORIES.get(aid, {})
