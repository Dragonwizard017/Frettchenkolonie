class_name FerretAnimDirector
extends RefCounted
## Wählt pro Frettchen den passenden Animations-Clip des ferret.glb (v15.6).
##
## Clips (aus dem Modell): Idle, Run, Carry, Work, Build, Harvest, Smash, Drink, Mash_Shake,
## Sleep_LieDown, Sleep, Death, Pet, Jump_Joy, Nod, Balance_Wobble.
##
## Reine Entscheidungslogik ohne Szenen-Zugriff -> headless testbar (tools/AnimDirectorCheck).
## Prioritäten (oben gewinnt):
##   1. Schlafen        Sleep_LieDown (einmal) -> Sleep (Loop)
##   2. Reaktion        fe.react_clip bis fe.react_until (Streicheln: Pet / Jump_Joy, Geburt: Jump_Joy)
##   3. Arbeit          Ernten/Arbeiten/Bauen je nach Ressource bzw. Gebäude
##   4. Bewegung        Balance_Wobble (geschwächt) / Carry (trägt Ware) / Run
##   5. sonst           Idle
##
## Alte Modelle ohne diese Clips: Aufrufer prüft `AnimationPlayer.has_animation()` und fällt auf
## die prozeduralen Posen zurück.

const LIE_DOWN_TIME: float = 1.0          # Länge von Sleep_LieDown (1.04 s) knapp unterschritten
const WEAK_HEALTH: float = 35.0           # darunter: wackeliger Gang

## Welcher Arbeits-Clip passt zur gesammelten Ressource?
const HARVEST_CLIPS: Dictionary = {
	"BERRIES": "Harvest", "WHEAT": "Harvest", "FOOD": "Harvest", "MEAT": "Harvest",
	"WOOD": "Smash", "STONE": "Smash", "IRON": "Smash", "COAL": "Smash",
	"WATER": "Drink",
}
## Gebäude, in denen "gekocht/gerührt" wird.
const COOKING_HINTS: PackedStringArray = ["COOK", "BAKE", "KITCHEN", "TAVERN"]

## prev_clip = zuletzt gespielter Clip, clip_elapsed = Sekunden seit dessen Start,
## moving = bewegt sich zum Ziel, now = Time.get_ticks_msec()/1000 (für Reaktionen).
static func pick(fe: FerretEntity, moving: bool, prev_clip: String, clip_elapsed: float, now: float) -> String:
	# 1. Schlafen
	if fe.is_sleeping:
		if prev_clip == "Sleep": return "Sleep"
		if prev_clip == "Sleep_LieDown" and clip_elapsed >= LIE_DOWN_TIME: return "Sleep"
		return "Sleep_LieDown"
	# 2. Reaktionen (einmalige Clips)
	if fe.react_clip != "" and now < fe.react_until:
		return fe.react_clip
	# 3. Arbeit
	var ab_res: String = ""
	var ab_id: String = ""
	if fe.assigned_building != null:
		var b: BuildingEntity = fe.assigned_building as BuildingEntity
		if b != null:
			ab_res = b.collects_resource
			ab_id = str(b.id)
	match fe.work_state:
		"HARVESTING":
			return str(HARVEST_CLIPS.get(ab_res, "Smash"))
		"BUILDING":
			return "Build"
		"WORKING":
			for h in COOKING_HINTS:
				if ab_id.contains(h): return "Mash_Shake"
			return "Work"
	# 4. Bewegung
	if moving:
		if fe.health < WEAK_HEALTH: return "Balance_Wobble"
		if _carries(fe): return "Carry"
		return "Run"
	# 5. Stillstand
	return "Idle"

## Gibt an, ob dieser Clip nach Ablauf stehen bleibt (einmalig) - dann nicht neu starten.
static func is_one_shot(clip: String) -> bool:
	return clip in ["Sleep_LieDown", "Death", "Pet", "Jump_Joy", "Nod"]

static func _carries(fe: FerretEntity) -> bool:
	var total: float = 0.0
	for k in fe.carry_inventory:
		total += float(fe.carry_inventory[k])
	return total > 0.5
