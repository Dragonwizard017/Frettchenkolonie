class_name FerretAnimUtil
extends RefCounted
## Setzt die Loop-Modi der Frettchen-Animationen (v15.4).
##
## Das animierte ferret.glb (v15.2) wird von Godot mit Loop = AUS importiert
## (der Importer loopt nur Clips mit "loop"-Namensteil). Ohne diese Funktion
## spielt "Run" einmal (0.88 s) und das Frettchen erstarrt in Laufpose.
## Dauer-Clips loopen, Gesten (Tod, Streicheln, Freudensprung ...) bleiben einmalig.
## Die Animation-Ressourcen sind zwischen allen Instanzen geteilt -> einmal reicht,
## mehrfaches Aufrufen schadet nicht.

const LOOPING: PackedStringArray = [
	"Run", "Idle", "Carry", "Work", "Build", "Harvest", "Drink", "Sleep", "Smash", "Mash_Shake", "Balance_Wobble"]

static func ensure_loops(ap: AnimationPlayer) -> void:
	if ap == null: return
	for n in LOOPING:
		if ap.has_animation(n):
			var a: Animation = ap.get_animation(n)
			if a != null and a.loop_mode != Animation.LOOP_LINEAR:
				a.loop_mode = Animation.LOOP_LINEAR
