## WaterCollectAnimation.gd
##
## Prozedurale Ersatz-Animation für das Wassersammeln (Brunnen, Wasserturm,
## Wasserpumpe etc.), da ferret.glb nur eine einzige "Run"-Animation besitzt
## (siehe Projektnotizen v10.10).
##
## Hinweis zur Einordnung: Wasser-Gebäude sind im aktuellen Code KEINE
## "Node-Collector" wie Holzfäller/Steinbruch/Beerensammler (ihr Output hängt
## vom WaterSystem-Pegel der Umgebung ab, nicht von einer physischen
## Resource-Node) - das Frettchen geht dort direkt in den einfachen
## work_state == "WORKING" über und steht am Gebäude, statt zu pendeln/zu
## ernten (siehe FerretEntity._update_work(), Zweig "not is_node_collector").
##
## Seit v10.11 angesteuert über FerretEntity.work_anim_t (eine generische,
## kontinuierlich laufende Uhr, die während der gesamten Arbeitszeit am
## Gebäude hochzählt - im Gegensatz zu harvest_anim_t, das nur während
## des Node-Pendelns läuft). rendering/WorldRenderer3D.gd ruft für
## collects_resource == "WATER" + work_state == "WORKING" compute() auf.
##
## Bewegungsidee: Langsames, ruhiges Herunterbeugen (Eimer/Pfoten ins Wasser
## senken), kurzes Halten am tiefsten Punkt (Schöpfen/Füllen), dann
## gleichmäßiges Aufrichten - ein voller Zyklus pro Erntedauer, deutlich
## ruhiger und "schwerer" als das Beeren-Pflücken.
class_name WaterCollectAnimation
extends RefCounted

## Anteil des Zyklus für das Herunterbeugen (0..HOLD_START).
const BEND_DOWN_END: float = 0.35
## Anteil des Zyklus, an dem das Halten/Schöpfen endet und das Aufrichten beginnt.
const HOLD_END: float = 0.65

## Berechnet die Pose für einen Frame während des Wassersammelns.
##
## @param t         Sekunden seit Zyklusbeginn (z.B. eine eigene laufende Uhr)
## @param duration  Dauer eines vollen Schöpf-Zyklus (z.B. 3.0s, analog HARVEST_DURATION)
## @return Dictionary mit:
##   "bob_y"  : float - vertikaler Versatz (negativ = Herunterbeugen)
##   "rot_x"  : float - Nickwinkel (Vorbeugen zum Wasser hin)
##   "rot_z"  : float - Rollwinkel (hier ungenutzt, für Konsistenz vorhanden)
static func compute(t: float, duration: float) -> Dictionary:
	if duration <= 0.0:
		return {"bob_y": 0.0, "rot_x": 0.0, "rot_z": 0.0}

	var phase: float = fmod(t, duration) / duration  # 0..1 über den vollen Zyklus

	var bend: float
	if phase < BEND_DOWN_END:
		# Herunterbeugen: ruhig und gleichmäßig (smoothstep), 0 -> 1.
		bend = smooth(phase / BEND_DOWN_END)
	elif phase < HOLD_END:
		# Halten am tiefsten Punkt (Schöpfen/Eimer füllen).
		bend = 1.0
	else:
		# Aufrichten: ruhig zurück, 1 -> 0.
		var p: float = (phase - HOLD_END) / (1.0 - HOLD_END)
		bend = 1.0 - smooth(p)

	var bob_y: float = -bend * 0.16  # tiefer als beim Pflücken, da ganzer Körper sich beugt
	var rot_x: float = bend * 0.35
	var rot_z: float = 0.0

	return {"bob_y": bob_y, "rot_x": rot_x, "rot_z": rot_z}


## Smoothstep-artige Ease-Funktion für ruhige, organische Übergänge.
static func smooth(p: float) -> float:
	p = clampf(p, 0.0, 1.0)
	return p * p * (3.0 - 2.0 * p)


# ─────────────────────────────────────────────────────────────────────────
# Integration (v10.11): FerretEntity.work_anim_t läuft kontinuierlich
# während work_state == "WORKING"; WorldRenderer3D.update_ferrets() ruft
# für collects_resource == "WATER" entsprechend
# WaterCollectAnimation.compute(fe.work_anim_t, 3.0) auf.
# ─────────────────────────────────────────────────────────────────────────
