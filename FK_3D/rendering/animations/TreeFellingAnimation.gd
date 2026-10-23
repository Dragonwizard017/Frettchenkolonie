## TreeFellingAnimation.gd
##
## Prozedurale Ersatz-Animation für das Baumfällen (Holzfäller, Ressource
## WOOD), da ferret.glb nur eine einzige "Run"-Animation besitzt (siehe
## Projektnotizen v10.10). Ersetzt den bisherigen generischen Sinus-Bob für
## den Fall WOOD.
##
## Bewegungsidee: Ein Hack-Zyklus mit Ausholbewegung (langsam, nach hinten/
## oben) gefolgt von einem schnellen Schlag (nach vorn/unten, simuliert den
## Axthieb). Beim "Treffer" gibt es einen kurzen, stärkeren Einduck-Impuls
## (bob_y), der den Aufprall andeutet. Mehrere solcher Hiebe pro Ernte-Aktion,
## deutlich langsamer und kraftvoller als das Beeren-Pflücken.
##
## Seit v10.11 in rendering/WorldRenderer3D.gd (update_ferrets()) eingebunden,
## für fe.assigned_building.collects_resource == "WOOD".
class_name TreeFellingAnimation
extends RefCounted

## Anzahl der Axthiebe über die gesamte Erntezeit (HARVEST_DURATION, 3.0s).
## 3 kräftige Hiebe wirken glaubwürdiger als viele schnelle.
const CHOP_COUNT: int = 3

## Anteil der Hieb-Phase, der auf das langsame Ausholen entfällt (Rest = Schlag).
const WINDUP_FRACTION: float = 0.65

## Berechnet die Pose für einen Frame während des Baumfällens.
##
## @param t         Sekunden seit Erntebeginn (= FerretEntity.harvest_anim_t)
## @param duration  Gesamtdauer einer Ernte-Aktion (= HARVEST_DURATION, 3.0s)
## @return Dictionary mit:
##   "bob_y"  : float - vertikaler Versatz (negativ = Eintauchen beim Treffer)
##   "rot_x"  : float - Nickwinkel (Ausholen nach hinten / Schlag nach vorn)
##   "rot_z"  : float - Rollwinkel (hier ungenutzt, für Konsistenz vorhanden)
static func compute(t: float, duration: float) -> Dictionary:
	var chop_dur: float = duration / float(CHOP_COUNT)
	if chop_dur <= 0.0:
		return {"bob_y": 0.0, "rot_x": 0.0, "rot_z": 0.0}

	var local_t: float = fmod(t, chop_dur)
	var phase: float = local_t / chop_dur  # 0..1 innerhalb eines Hiebs

	var swing: float
	var impact: float = 0.0

	if phase < WINDUP_FRACTION:
		# Ausholen: langsam von 0 nach hinten/oben (negativer Nickwinkel).
		var p: float = phase / WINDUP_FRACTION
		swing = -ease_out(p)
	else:
		# Schlag: schnell von "hinten" nach vorn durchschwingen (Treffer am Ende).
		var p: float = (phase - WINDUP_FRACTION) / (1.0 - WINDUP_FRACTION)
		swing = -1.0 + 2.0 * ease_in(p)
		swing = clampf(swing, -1.0, 1.0)
		# Impact-Impuls kurz vor/am Ende des Schlags (Aufprall auf den Baum).
		impact = ease_in(p) * ease_in(p)

	var rot_x: float = swing * 0.55  # großer Ausschlag = deutlich erkennbarer Hieb
	var bob_y: float = -impact * 0.06  # kurzes Eintauchen beim Treffer
	var rot_z: float = 0.0

	return {"bob_y": bob_y, "rot_x": rot_x, "rot_z": rot_z}


static func ease_in(p: float) -> float:
	p = clampf(p, 0.0, 1.0)
	return p * p


static func ease_out(p: float) -> float:
	p = clampf(p, 0.0, 1.0)
	return 1.0 - (1.0 - p) * (1.0 - p)


# ─────────────────────────────────────────────────────────────────────────
# Integration (v10.11): siehe BerryHarvestAnimation.gd - gleiches Schema im
# match-Block in WorldRenderer3D.gd, Fall "WOOD".
#
# Bonus-Idee (nicht umgesetzt): Beim Erreichen von impact ≈ 1.0 könnte
# zusätzlich GameState ein Signal "tree_chop_hit" emittieren, an das später
# ein Holzspan-Partikeleffekt oder ein Hieb-Sound gekoppelt werden könnte.
# ─────────────────────────────────────────────────────────────────────────
