## PlayerAccessories.gd
## Feature (v12.2, Phase 4 - Frettchen-Ich-Anpassung).
## Verwaltet Ausrüstung (equipped) und Boosts fürs Frettchen-Ich. Die
## "Freischaltung" selbst (welches Accessoire überhaupt ausgerüstet werden
## darf) lebt bewusst NICHT hier als eigener Zustand, sondern wird direkt aus
## AchievementSys.unlocked abgeleitet (is_unlocked()) - Single Source of
## Truth, keine doppelt gehaltenen/potenziell inkonsistenten Freischalt-Daten.
## Nutzt dieselben 10 Accessoire-Definitionen (Meshes, Slots) wie
## FerretAccessories.gd (Legendäre Frettchen) - siehe ACCESSORIES dort.
extends Node

## Feature (v12.2, Phase 4): wird bei jeder erfolgreichen equip()/
## unequip_slot()-Änderung UND nach deserialize() (Spielstand laden)
## ausgelöst - PlayerController.gd hängt sich hier ein, um die
## 3D-Accessoire-Modelle am Frettchen-Ich-Sichtmodell zu aktualisieren, ohne
## dass die UI direkt eine Referenz auf PlayerController braucht.
signal equipment_changed

## Reverse-Lookup Accessoire-ID -> Achievement-ID, aus
## AchievementSys.ACHIEVEMENTS["unlocks_accessory"] abgeleitet (einmalig in
## _ready() aufgebaut, s.u.) - vermeidet eine zweite, separat zu pflegende
## Zuordnungstabelle.
var _achievement_for_accessory: Dictionary = {}

## Ausgerüstetes Accessoire pro Slot ("" = leer). Slots identisch zu
## FerretAccessories.ACCESSORIES[aid]["slot"]: HEAD, NECK, FACE, BACK.
var equipped: Dictionary = {"HEAD": "", "NECK": "", "FACE": "", "BACK": ""}

## Boost-Werte pro Accessoire-ID. "mult"-Schlüssel werden bei mehreren
## gleichzeitig aktiven Boosts MULTIPLIKATIV verknüpft (kompatibel mit
## "Boosts sollen parallel aktiv sein" - macht bei gleichzeitig 4 Slots ohne
## Powercreep-Explosion auch rechnerisch Sinn), "flat"-Schlüssel werden
## SUMMIERT. Boost-Zuordnung wie im Vorschlag mit dem Nutzer abgestimmt.
const BOOSTS: Dictionary = {
	"TOP_HAT":  {"move_speed_mult": 1.20},
	"WIZARD_HAT": {"minigame_reward_mult": 1.25},
	"CROWN":    {"interact_range_mult": 1.35},
	"BANDANA":  {"minigame_ease_mult": 0.7},     # <1.0 = Zielzonen/Toleranzen breiter, Anforderungen kleiner
	"BOWTIE":   {"jump_height_mult": 1.3},
	"SCARF":    {"winter_immunity_flat": 1.0},   # >0 = kein Winter-Tempo-Malus
	"MEDAL":    {"minigame_flat_bonus": 1.0},
	"MONOCLE":  {"interact_range_mult": 1.20},   # stackt multiplikativ mit CROWN (beide erhöhen dieselbe Reichweite)
	"EYEPATCH": {"minigame_duration_mult": 0.75},# <1.0 = weniger Treffer/kürzere Dauer nötig
	"CAPE":     {"soft_landing_flat": 1.0},      # >0 = keine harte-Landung-Verlangsamung
}

func _ready() -> void:
	for aid in AchievementSys.ACHIEVEMENTS:
		var ad: Dictionary = AchievementSys.ACHIEVEMENTS[aid]
		var acc_id: String = str(ad.get("unlocks_accessory", ""))
		if acc_id != "":
			_achievement_for_accessory[acc_id] = aid

func init() -> void:
	equipped = {"HEAD": "", "NECK": "", "FACE": "", "BACK": ""}
	equipment_changed.emit()

## Wird von AchievementSys._unlock() aufgerufen, sobald das zugehörige
## Achievement erreicht wird - rein informativ (löst eine eigene
## Benachrichtigung aus, damit klar wird, DASS jetzt auch ein Accessoire zur
## Verfügung steht, nicht nur der Erfolg selbst).
func notify_unlocked(acc_id: String) -> void:
	var ad: Dictionary = FerretAccessories.get_accessory(acc_id)
	if ad.is_empty(): return
	GameState.notify("👒 Neues Accessoire fürs Frettchen-Ich: " + str(ad.get("name", acc_id)) +
		" (im Pause-Menü ausrüstbar)", Color(0.25, 0.5, 0.85, 0.92))

func is_unlocked(acc_id: String) -> bool:
	if not _achievement_for_accessory.has(acc_id): return false
	return AchievementSys.is_unlocked(str(_achievement_for_accessory[acc_id]))

func is_equipped(acc_id: String) -> bool:
	var ad: Dictionary = FerretAccessories.get_accessory(acc_id)
	if ad.is_empty(): return false
	return str(equipped.get(str(ad.get("slot", "")), "")) == acc_id

## Rüstet "acc_id" im passenden Slot aus (verdrängt ein evtl. dort bereits
## ausgerüstetes Accessoire). Schlägt fehl (gibt false zurück, kein
## Zustandswechsel), wenn das Accessoire noch nicht freigeschaltet ist.
func equip(acc_id: String) -> bool:
	if not is_unlocked(acc_id): return false
	var ad: Dictionary = FerretAccessories.get_accessory(acc_id)
	if ad.is_empty(): return false
	equipped[str(ad.get("slot", ""))] = acc_id
	equipment_changed.emit()
	return true

func unequip_slot(slot: String) -> void:
	if equipped.has(slot):
		equipped[slot] = ""
		equipment_changed.emit()

## Multiplikativer Boost über alle ausgerüsteten Accessoires (Basis 1.0,
## jeder Treffer wird einmal hineinmultipliziert). Für Slots ohne
## Ausrüstung bleibt der Basiswert unverändert.
func get_boost_mult(key: String, base_value: float = 1.0) -> float:
	var result: float = base_value
	for slot in equipped:
		var aid: String = str(equipped[slot])
		if aid == "": continue
		var b: Dictionary = BOOSTS.get(aid, {})
		if b.has(key): result *= float(b[key])
	return result

## Additiver Boost über alle ausgerüsteten Accessoires (Basis 0.0).
func get_boost_flat(key: String, base_value: float = 0.0) -> float:
	var result: float = base_value
	for slot in equipped:
		var aid: String = str(equipped[slot])
		if aid == "": continue
		var b: Dictionary = BOOSTS.get(aid, {})
		if b.has(key): result += float(b[key])
	return result

func serialize() -> Dictionary:
	return {"equipped": equipped.duplicate()}

func deserialize(data) -> void:
	if not (data is Dictionary):
		init(); equipment_changed.emit(); return
	var d: Dictionary = data as Dictionary
	var eq: Dictionary = d.get("equipped", {}) as Dictionary
	equipped = {"HEAD": "", "NECK": "", "FACE": "", "BACK": ""}
	for slot in equipped.keys():
		var aid: String = str(eq.get(slot, ""))
		# Sicherheitsnetz: nur übernehmen, wenn tatsächlich noch freigeschaltet
		# (z.B. falls sich Erfolgsbedingungen je zwischen Versionen ändern sollten).
		if aid != "" and is_unlocked(aid):
			equipped[slot] = aid
	equipment_changed.emit()
