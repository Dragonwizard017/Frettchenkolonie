## FerretTraits.gd
## Feature (v11.8, Frettchen-Persönlichkeiten - Phase 1 des Langzeit-Content-
## Pakets): jedes neu erzeugte Frettchen bekommt bei der Geburt zufällig
## (GEWICHTET, nicht gleichverteilt - siehe "weight") genau einen Trait
## zugewiesen. Angewendet in FerretEntity.create_random()/deserialize()
## (Abwärtskompatibilität für alte Saves ohne trait_id).
##
## Balance-Leitplanke (Nutzeranfrage): Effekte sollen spürbar, aber klein
## genug sein, dass sie kein Muss-Optimierungsproblem erzeugen - eher ein
## Grund, sich für einzelne Frettchen zu interessieren. Die eigentlichen
## mechanischen Effekte sitzen NICHT hier, sondern an den jeweils passenden
## Stellen in FerretEntity.gd (Bedürfnis-/Gesundheitsverfall, Spezialisierung),
## BuildingEntity.gd (Produktions-Bonus der zugewiesenen Arbeiter) und
## PopulationManager.gd (Glücklichkeits-Gebäude-Wirkung) - diese Datei ist
## nur die reine Datenülle + Zufallsauswahl, analog zu TechTree.NODES.
extends RefCounted
class_name FerretTraits

const TRAITS: Dictionary = {
	"DILIGENT": {
		"name": "Fleißig", "icon": "💪", "weight": 3,
		"desc": "Produziert am eigenen Arbeitsplatz spürbar mehr (+10% je Fleißigem im Gebäude), dafür sinken die eigenen Bedürfnisse etwas schneller."
	},
	"LUCKY": {
		"name": "Glückspilz", "icon": "🍀", "weight": 2,
		"desc": "Erholt sich in der Nähe von Glücklichkeits-Gebäuden deutlich schneller als andere Frettchen."
	},
	"TALENTED": {
		"name": "Naturtalent", "icon": "⭐", "weight": 1,
		"desc": "Wird an jedem neuen Arbeitsplatz sofort zum Experten, ohne die übliche Wartezeit von 5 Tagen."
	},
	"LONER": {
		"name": "Eigenbrötler", "icon": "🌙", "weight": 2,
		"desc": "Profitiert deutlich weniger von der Nähe zu Glücklichkeits-Gebäuden, braucht sie aber im Gegenzug auch seltener."
	},
	"TOUGH": {
		"name": "Zäh", "icon": "🛡️", "weight": 3,
		"desc": "Gesundheit verfällt bei Hunger oder Durst spürbar langsamer als bei anderen Frettchen."
	},
}

## Wählt gewichtet-zufällig genau eine Trait-ID aus TRAITS. Höhere "weight"
## Werte werden entsprechend häufiger gezogen (TALENTED ist bewusst am
## seltensten, da sein Effekt am stärksten spürbar ist).
static func pick_random_trait_id() -> String:
	var total_weight: int = 0
	for tid in TRAITS:
		total_weight += int((TRAITS[tid] as Dictionary).get("weight", 1))
	var roll: int = randi() % maxi(1, total_weight)
	var acc: int = 0
	for tid in TRAITS:
		acc += int((TRAITS[tid] as Dictionary).get("weight", 1))
		if roll < acc:
			return tid
	return TRAITS.keys()[0]

static func get_trait(tid: String) -> Dictionary:
	return TRAITS.get(tid, {})
