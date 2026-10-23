## BerryHarvestAnimation.gd
##
## Prozedurale Ersatz-Animation für die Beeren-Ernte, da ferret.glb nur eine
## einzige "Run"-Animation besitzt (siehe Projektnotizen v10.10). Ersetzt den
## bisherigen generischen Sinus-Bob für den Fall BERRIES.
##
## Bewegungsidee: Statt einem gleichmäßigen Wippen simuliert dies mehrere
## kurze, schnelle "Pflück"-Aktionen während der Erntezeit (HARVEST_DURATION,
## Standard 3.0s) - das Frettchen duckt sich kurz nach vorn/unten in den
## Busch, lehnt dabei abwechselnd leicht nach links/rechts (als würde es an
## verschiedenen Stellen pflücken) und richtet sich zwischen den Pflück-
## Aktionen kurz wieder auf.
##
## Seit v10.11 in rendering/WorldRenderer3D.gd (update_ferrets()) eingebunden:
## fe.assigned_building.collects_resource == "BERRIES" -> compute() steuert
## bob_y/rotation.x/rotation.z während work_state == "HARVESTING".
class_name BerryHarvestAnimation
extends RefCounted

## Anzahl der "Pflück"-Aktionen, die über die gesamte Erntezeit verteilt
## stattfinden. 4 Pflück-Aktionen in 3 Sekunden = knackig-schnelles Pflücken.
const PICK_COUNT: int = 4

## Berechnet die Pose für einen Frame während des Beeren-Erntens.
##
## @param t         Sekunden seit Erntebeginn (= FerretEntity.harvest_anim_t)
## @param duration  Gesamtdauer einer Ernte-Aktion (= HARVEST_DURATION, 3.0s)
## @return Dictionary mit:
##   "bob_y"  : float - vertikaler Versatz (negativ = nach unten/Ducken)
##   "rot_x"  : float - Nickwinkel (Vorlehnen in den Busch), Radiant
##   "rot_z"  : float - Rollwinkel (seitliches Lehnen beim Pflücken), Radiant
static func compute(t: float, duration: float) -> Dictionary:
	var pick_dur: float = duration / float(PICK_COUNT)
	if pick_dur <= 0.0:
		return {"bob_y": 0.0, "rot_x": 0.0, "rot_z": 0.0}

	var local_t: float = fmod(t, pick_dur)
	var phase: float = local_t / pick_dur  # 0..1 innerhalb einer Pflück-Aktion

	# Welche Pflück-Aktion (0,1,2,3...) - bestimmt die Seite (links/rechts).
	var pick_index: int = int(floor(t / pick_dur))
	var side: float = -1.0 if pick_index % 2 == 0 else 1.0

	# Schnelles Runter-Hoch (Pflücken): 0 -> 1 -> 0 über die Pick-Dauer,
	# aber asymmetrisch - schnelles Reingreifen, etwas langsameres Zurückziehen.
	var dip: float
	if phase < 0.4:
		dip = ease_in(phase / 0.4)
	else:
		dip = 1.0 - ease_out((phase - 0.4) / 0.6)

	var bob_y: float = -dip * 0.10
	var rot_x: float = dip * 0.30  # nach vorn ins Gebüsch lehnen
	var rot_z: float = side * dip * 0.12  # seitlich zur jeweiligen Beere lehnen

	return {"bob_y": bob_y, "rot_x": rot_x, "rot_z": rot_z}


static func ease_in(p: float) -> float:
	p = clampf(p, 0.0, 1.0)
	return p * p


static func ease_out(p: float) -> float:
	p = clampf(p, 0.0, 1.0)
	return 1.0 - (1.0 - p) * (1.0 - p)


# ─────────────────────────────────────────────────────────────────────────
# Integration (v10.11): rendering/WorldRenderer3D.gd, update_ferrets(), Block
# is_harvesting -> match fe.assigned_building.collects_resource -> "BERRIES".
# ─────────────────────────────────────────────────────────────────────────
