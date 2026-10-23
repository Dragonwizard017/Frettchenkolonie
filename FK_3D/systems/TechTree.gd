## TechTree.gd
## Tech Tree v2 (Feature-Anfrage: Upgrades gleichmässig über die 4 Epochen
## verteilt, pro Knoten fest einer Epoche zugeordnet - man kann einen Knoten NUR
## erforschen, wenn seine Epoche bereits freigeschaltet ist (siehe can_unlock_node()).
## Die nächste Epoche wird käuflich, sobald ca. 80% der Knoten DER AKTUELLEN
## Epoche bereits erforscht sind (siehe epoch_requirement_met()) - zusätzlich zu den
## Wissenspunkte-Kosten der Epoche selbst. Titel/Beschreibung jedes Knotens passen
## zur Epoche, in der er freigeschaltet wird (Steinzeit/Mittelalter/Industrialisierung/
## Moderne).
extends Node

## Alle Themenbereiche (Abschnitte) des Tech Trees - dienen nur noch der optischen
## Gruppierung/Einfärbung innerhalb einer Epoche, NICHT mehr der Freischalt-Logik
## für Epochen (siehe epoch_requirement_met()).
const SECTIONS: Dictionary = {
	"FORESTRY": {"name": "Holzwirtschaft", "icon": "🪓"},
	"MINING": {"name": "Bergbau & Steinwirtschaft", "icon": "⛏️"},
	"WATER": {"name": "Wasserwirtschaft", "icon": "💧"},
	"FARMING": {"name": "Landwirtschaft & Ernährung", "icon": "🌾"},
	"BREEDING": {"name": "Zucht & Bevölkerung", "icon": "🐾"},
	"LOGISTICS": {"name": "Bauwesen & Logistik", "icon": "🏗️"},
}

const SECTION_ORDER: Array = ["FORESTRY", "MINING", "WATER", "FARMING", "BREEDING", "LOGISTICS"]

## Hinweis: die Anzahl Knoten pro Epoche wird für die 80%-Aufstiegsschwelle
## und die UI-Fortschrittsanzeige immer LIVE über get_node_ids_for_epoch()
## ermittelt (Epoche 1-3 haben je 15 Knoten, Epoche 4 seit v14.2 durch die
## 6 neuen Minispiel-Kür-Knoten 21) - es gibt bewusst keine feste "Knoten
## pro Epoche"-Konstante mehr, die mit den echten Daten hier auseinanderlaufen
## könnte.

## Alle regulären Tech-Knoten (60, 15 je Epoche, gleichmässig verteilt). Jeder
## Knoten hat einen individuellen Namen + epochenpassende Beschreibung, gehört zu
## einer "section" (nur optische Gruppierung), hat eine "tier" (1-basiert INNERHALB
## seiner Sektion, Knoten N benötigt Knoten N-1 DERSELBEN Sektion, ausser tier 1),
## eine feste "epoch" (1-4, siehe can_unlock_node()), einen Wissenspunkte-"cost" und
## eine Liste "effects".
const NODES: Dictionary = {
	"FORESTRY_1": {
		"name": "Geschärfte Äxte", "icon": "🪓", "desc": "Nachgeschärfte Klingen für die Holzfäller-Äxte sorgen für deutlich mehr Holz pro Hieb.",
		"section": "FORESTRY", "tier": 1, "epoch": 1, "cost": 15, "requires_node": "",
		"effects": [{"type":"bstat","building":"LUMBERJACK","field":"production_speed","mode":"mult","value":0.15}]
	},
	"FORESTRY_2": {
		"name": "Effiziente Stämme", "icon": "🪵", "desc": "Die ersten Sägeblätter verarbeiten Stämme spürbar schneller zu Brettern.",
		"section": "FORESTRY", "tier": 2, "epoch": 1, "cost": 20, "requires_node": "FORESTRY_1",
		"effects": [{"type":"bstat","building":"SAWMILL","field":"production_speed","mode":"mult","value":0.15}]
	},
	"FORESTRY_3": {
		"name": "Dichte Pflanzung", "icon": "🌱", "desc": "Die Försterei pflanzt in einem größeren Radius neue Setzlinge und hält den Wald weiträumiger am Leben.",
		"section": "FORESTRY", "tier": 3, "epoch": 1, "cost": 25, "requires_node": "FORESTRY_2",
		"effects": [{"type":"bstat","building":"FORESTER","field":"planting_radius","mode":"add","value":3}]
	},
	"FORESTRY_4": {
		"name": "Schnellwachsende Setzlinge", "icon": "🌿", "desc": "Ausgewähltes Saatgut lässt abgeholzte Bäume merklich schneller nachwachsen.",
		"section": "FORESTRY", "tier": 4, "epoch": 2, "cost": 35, "requires_node": "FORESTRY_3",
		"effects": [{"type":"global","key":"wood_regen_speed","value":0.2}]
	},
	"FORESTRY_5": {
		"name": "Weitreichende Fällung", "icon": "🌲", "desc": "Holzfäller dürfen jetzt einen größeren Umkreis nach fällbaren Bäumen absuchen.",
		"section": "FORESTRY", "tier": 5, "epoch": 2, "cost": 45, "requires_node": "FORESTRY_4",
		"effects": [{"type":"bstat","building":"LUMBERJACK","field":"collection_radius","mode":"add","value":2}]
	},
	"FORESTRY_6": {
		"name": "Verstärkte Transportkisten", "icon": "📦", "desc": "Robustere Kisten am Sammelplatz erhöhen das lokale Zwischenlager aller Holz-Sammelgebäude.",
		"section": "FORESTRY", "tier": 6, "epoch": 2, "cost": 60, "requires_node": "FORESTRY_5",
		"effects": [{"type":"bstat","building":"LUMBERJACK","field":"local_storage_capacity","mode":"add","value":20}, {"type":"bstat","building":"FORESTER","field":"local_storage_capacity","mode":"add","value":20}]
	},
	"FORESTRY_7": {
		"name": "Dampfbetriebene Sägen", "icon": "⚙️", "desc": "Neue Dampfmaschinen im Sägewerk verarbeiten Stämme in einem ganz neuen Tempo.",
		"section": "FORESTRY", "tier": 7, "epoch": 3, "cost": 80, "requires_node": "FORESTRY_6",
		"effects": [{"type":"bstat","building":"SAWMILL","field":"production_speed","mode":"mult","value":0.25}]
	},
	"FORESTRY_8": {
		"name": "Forstamt-Planung", "icon": "📋", "desc": "Ein eigenes Forstamt erkennt kahle Stellen früher und lässt den Wald insgesamt schneller nachwachsen.",
		"section": "FORESTRY", "tier": 8, "epoch": 3, "cost": 105, "requires_node": "FORESTRY_7",
		"effects": [{"type":"global","key":"wood_regen_speed","value":0.15}]
	},
	"FORESTRY_9": {
		"name": "Automatisierte Werkstatt", "icon": "🏭", "desc": "Fließbänder und Maschinenkraft erlauben es, die Werkstatt zu einer modernen Großwerkstatt umzubauen.",
		"section": "FORESTRY", "tier": 9, "epoch": 4, "cost": 140, "requires_node": "FORESTRY_8",
		"effects": [{"type":"rebuild","building":"WORKSHOP"}]
	},
	"FORESTRY_10": {
		"name": "Meister der Forstwirtschaft", "icon": "🌳", "desc": "Nachhaltige Forstwirtschaft im industriellen Maßstab steigert die Leistung aller holzbezogenen Gebäude spürbar.",
		"section": "FORESTRY", "tier": 10, "epoch": 4, "cost": 185, "requires_node": "FORESTRY_9",
		"effects": [{"type":"bstat","building":"LUMBERJACK","field":"production_speed","mode":"mult","value":0.25}, {"type":"bstat","building":"SAWMILL","field":"production_speed","mode":"mult","value":0.25}, {"type":"bstat","building":"FORESTER","field":"planting_radius","mode":"add","value":2}]
	},
	"MINING_1": {
		"name": "Gehärtete Meißel", "icon": "⛏️", "desc": "Härtere Meißelspitzen lassen den Steinbruch spürbar mehr Stein pro Arbeitsgang fördern.",
		"section": "MINING", "tier": 1, "epoch": 1, "cost": 15, "requires_node": "",
		"effects": [{"type":"bstat","building":"QUARRY","field":"production_speed","mode":"mult","value":0.15}]
	},
	"MINING_2": {
		"name": "Größere Fördermenge", "icon": "🪨", "desc": "Der Steinbruch darf jetzt in einem größeren Umkreis nach Gestein suchen.",
		"section": "MINING", "tier": 2, "epoch": 1, "cost": 20, "requires_node": "MINING_1",
		"effects": [{"type":"bstat","building":"QUARRY","field":"collection_radius","mode":"add","value":2}]
	},
	"MINING_3": {
		"name": "Steinlager-Ausbau", "icon": "🧱", "desc": "Zusätzliche Förderkörbe vergrößern das lokale Zwischenlager des Steinbruchs.",
		"section": "MINING", "tier": 3, "epoch": 1, "cost": 25, "requires_node": "MINING_2",
		"effects": [{"type":"bstat","building":"QUARRY","field":"local_storage_capacity","mode":"add","value":20}]
	},
	"MINING_4": {
		"name": "Sprengtechnik", "icon": "💥", "desc": "Kontrollierte Sprengungen lockern das Gestein vor - der Steinbruch fördert dadurch noch mehr.",
		"section": "MINING", "tier": 4, "epoch": 2, "cost": 35, "requires_node": "MINING_3",
		"effects": [{"type":"bstat","building":"QUARRY","field":"production_speed","mode":"mult","value":0.2}]
	},
	"MINING_5": {
		"name": "Bergbau-Zunft", "icon": "🏅", "desc": "Eine organisierte Zunft mit festen Schichtplänen erlaubt es, den Steinbruch zu einem Großsteinbruch umzubauen.",
		"section": "MINING", "tier": 5, "epoch": 2, "cost": 45, "requires_node": "MINING_4",
		"effects": [{"type":"rebuild","building":"QUARRY"}]
	},
	"MINING_6": {
		"name": "Erfahrene Schürfer", "icon": "👷", "desc": "Jahrelange Erfahrung im Umgang mit Gestein steigert die Förderleistung des Steinbruchs weiter.",
		"section": "MINING", "tier": 6, "epoch": 2, "cost": 60, "requires_node": "MINING_5",
		"effects": [{"type":"bstat","building":"QUARRY","field":"production_speed","mode":"mult","value":0.15}]
	},
	"MINING_7": {
		"name": "Tiefenbohrung", "icon": "🕳️", "desc": "Neue Bohrtechnik erschließt reichhaltigere Erzadern in der Eisenmine.",
		"section": "MINING", "tier": 7, "epoch": 3, "cost": 80, "requires_node": "MINING_6",
		"effects": [{"type":"bstat","building":"IRON_MINE","field":"production_speed","mode":"mult","value":0.2}]
	},
	"MINING_8": {
		"name": "Kohleveredelung", "icon": "⚫", "desc": "Bessere Sortierung lässt die Kohlemine mehr brauchbare Kohle pro Schicht liefern.",
		"section": "MINING", "tier": 8, "epoch": 3, "cost": 105, "requires_node": "MINING_7",
		"effects": [{"type":"bstat","building":"COAL_MINE","field":"production_speed","mode":"mult","value":0.2}]
	},
	"MINING_9": {
		"name": "Hochofentechnik", "icon": "🔥", "desc": "Eine gleichmäßigere, hochmoderne Befeürung steigert die Ausbeute der Schmelze deutlich.",
		"section": "MINING", "tier": 9, "epoch": 4, "cost": 140, "requires_node": "MINING_8",
		"effects": [{"type":"bstat","building":"SMELTER","field":"production_speed","mode":"mult","value":0.25}]
	},
	"MINING_10": {
		"name": "Meister des Bergbaus", "icon": "💎", "desc": "Generationen von Bergleuten-Wissen steigert die Leistung aller Bergbau- und Schmelzgebäude spürbar.",
		"section": "MINING", "tier": 10, "epoch": 4, "cost": 185, "requires_node": "MINING_9",
		"effects": [{"type":"bstat","building":"QUARRY","field":"production_speed","mode":"mult","value":0.2}, {"type":"bstat","building":"IRON_MINE","field":"production_speed","mode":"mult","value":0.2}, {"type":"bstat","building":"COAL_MINE","field":"production_speed","mode":"mult","value":0.2}, {"type":"bstat","building":"SMELTER","field":"production_speed","mode":"mult","value":0.2}]
	},
	"WATER_1": {
		"name": "Tiefere Brunnen", "icon": "🪣", "desc": "Tiefer gegrabene Brunnenschächte erreichen ergiebigere Wasserschichten.",
		"section": "WATER", "tier": 1, "epoch": 1, "cost": 15, "requires_node": "",
		"effects": [{"type":"bstat","building":"WELL","field":"production_speed","mode":"mult","value":0.2}]
	},
	"WATER_2": {
		"name": "Verstärkte Dämme", "icon": "🛡️", "desc": "Zusätzliche Stützpfeiler lassen Dämme deutlich mehr Wasser zurückhalten.",
		"section": "WATER", "tier": 2, "epoch": 1, "cost": 20, "requires_node": "WATER_1",
		"effects": [{"type":"global","key":"dam_retention_bonus","value":0.05}]
	},
	"WATER_3": {
		"name": "Ausgeklügelte Schöpfwerke", "icon": "🔧", "desc": "Verbesserte Schöpfräder holen noch mehr Wasser aus dem Brunnen.",
		"section": "WATER", "tier": 3, "epoch": 1, "cost": 25, "requires_node": "WATER_2",
		"effects": [{"type":"bstat","building":"WELL","field":"production_speed","mode":"mult","value":0.15}]
	},
	"WATER_4": {
		"name": "Größere Wassertürme", "icon": "🗼", "desc": "Verstärkte Tankwände erhöhen das Fassungsvermögen des Wasserturms erheblich.",
		"section": "WATER", "tier": 4, "epoch": 2, "cost": 35, "requires_node": "WATER_3",
		"effects": [{"type":"bstat","building":"WATER_TOWER","field":"water_capacity","mode":"add","value":150}]
	},
	"WATER_5": {
		"name": "Wasserradoptimierung", "icon": "🔄", "desc": "Neu geformte Schaufeln lassen jedes Wasserrad einen spürbar stärkeren Produktionsschub geben.",
		"section": "WATER", "tier": 5, "epoch": 2, "cost": 45, "requires_node": "WATER_4",
		"effects": [{"type":"global","key":"waterwheel_boost_bonus","value":0.15}]
	},
	"WATER_6": {
		"name": "Reservoir-Ausbau", "icon": "🛢️", "desc": "Vertiefte Becken erhöhen das Fassungsvermögen des Wasserreservoirs deutlich.",
		"section": "WATER", "tier": 6, "epoch": 2, "cost": 60, "requires_node": "WATER_5",
		"effects": [{"type":"bstat","building":"RESERVOIR","field":"water_capacity","mode":"add","value":250}]
	},
	"WATER_7": {
		"name": "Aquädukt-Technik", "icon": "🌉", "desc": "Verbesserte Rinnen-Neigung lässt das Aquädukt spürbar mehr Wasser heranführen.",
		"section": "WATER", "tier": 7, "epoch": 3, "cost": 80, "requires_node": "WATER_6",
		"effects": [{"type":"bstat","building":"AQUEDUCT","field":"production_speed","mode":"mult","value":0.2}]
	},
	"WATER_8": {
		"name": "Bewässerungstechnik", "icon": "🚿", "desc": "Feinere Kanalführung steigert die Fördermenge des Bewässerungskanals.",
		"section": "WATER", "tier": 8, "epoch": 3, "cost": 105, "requires_node": "WATER_7",
		"effects": [{"type":"bstat","building":"IRRIGATION","field":"production_speed","mode":"mult","value":0.2}]
	},
	"WATER_9": {
		"name": "Schleusentechnik", "icon": "🚪", "desc": "Steuerbare Schleusentore erlauben es, den Damm zu einer modernen Schleuse mit deutlich mehr Rückhalt umzubauen.",
		"section": "WATER", "tier": 9, "epoch": 4, "cost": 140, "requires_node": "WATER_8",
		"effects": [{"type":"rebuild","building":"DAM"}]
	},
	"WATER_10": {
		"name": "Meister der Wasserwirtschaft", "icon": "🌊", "desc": "Jahrelange Erfahrung im Umgang mit Flüssen und Seen verbessert alle wasserbezogenen Gebäude und senkt die Verdunstung zusätzlich.",
		"section": "WATER", "tier": 10, "epoch": 4, "cost": 185, "requires_node": "WATER_9",
		"effects": [{"type":"bstat","building":"WELL","field":"production_speed","mode":"mult","value":0.2}, {"type":"bstat","building":"WATER_PUMP","field":"production_speed","mode":"mult","value":0.2}, {"type":"bstat","building":"AQUEDUCT","field":"production_speed","mode":"mult","value":0.2}, {"type":"global","key":"drought_evaporation_reduction","value":0.2}]
	},
	"FARMING_1": {
		"name": "Ausgewählte Beerensträucher", "icon": "🫐", "desc": "Sorgfältig ausgewählte Sträucher lassen den Beerensammler mehr Beeren pro Runde ernten.",
		"section": "FARMING", "tier": 1, "epoch": 1, "cost": 15, "requires_node": "",
		"effects": [{"type":"bstat","building":"BERRY_GATHERER","field":"production_speed","mode":"mult","value":0.15}]
	},
	"FARMING_2": {
		"name": "Größere Sammelkörbe", "icon": "🧺", "desc": "Größere Körbe erhöhen das lokale Zwischenlager des Beerensammlers.",
		"section": "FARMING", "tier": 2, "epoch": 1, "cost": 20, "requires_node": "FARMING_1",
		"effects": [{"type":"bstat","building":"BERRY_GATHERER","field":"local_storage_capacity","mode":"add","value":20}]
	},
	"FARMING_3": {
		"name": "Gewächshausplanung", "icon": "📐", "desc": "Durchdachtere Beetanlagen steigern den Ertrag des Gartens.",
		"section": "FARMING", "tier": 3, "epoch": 2, "cost": 25, "requires_node": "FARMING_2",
		"effects": [{"type":"bstat","building":"GARDEN","field":"production_speed","mode":"mult","value":0.15}]
	},
	"FARMING_4": {
		"name": "Jagdausrüstung", "icon": "🏹", "desc": "Bessere Bögen und Fallen erhöhen die Beute der Jäger-Hütte.",
		"section": "FARMING", "tier": 4, "epoch": 2, "cost": 35, "requires_node": "FARMING_3",
		"effects": [{"type":"bstat","building":"HUNTER_HUT","field":"production_speed","mode":"mult","value":0.2}]
	},
	"FARMING_5": {
		"name": "Fruchtbarer Boden", "icon": "🟫", "desc": "Kompost und Fruchtwechsel lassen die Bauernhof-Arbeiter Felder schneller bestellen.",
		"section": "FARMING", "tier": 5, "epoch": 3, "cost": 45, "requires_node": "FARMING_4",
		"effects": [{"type":"bstat","building":"FARMHOUSE","field":"production_speed","mode":"mult","value":0.2}]
	},
	"FARMING_6": {
		"name": "Kochkunst", "icon": "🍲", "desc": "Neue Rezepte und Küchengriffe beschleunigen die Zubereitung im Kochhaus.",
		"section": "FARMING", "tier": 6, "epoch": 3, "cost": 60, "requires_node": "FARMING_5",
		"effects": [{"type":"bstat","building":"COOKHOUSE","field":"production_speed","mode":"mult","value":0.2}]
	},
	"FARMING_7": {
		"name": "Vorratshaltung", "icon": "🥫", "desc": "Zusätzliche Regale erhöhen die Kapazität des Lebensmittellagers deutlich.",
		"section": "FARMING", "tier": 7, "epoch": 3, "cost": 80, "requires_node": "FARMING_6",
		"effects": [{"type":"bstat","building":"FOOD_STORE","field":"storage_capacity","mode":"add","value":150}]
	},
	"FARMING_8": {
		"name": "Erweiterte Felder", "icon": "🚜", "desc": "Zusätzlich gerodete Ackerflächen und eingespielte Handgriffe beschleunigen den Bauernhof weiter.",
		"section": "FARMING", "tier": 8, "epoch": 4, "cost": 105, "requires_node": "FARMING_7",
		"effects": [{"type":"bstat","building":"FARMHOUSE","field":"production_speed","mode":"mult","value":0.2}]
	},
	"FARMING_9": {
		"name": "Gewächshaustechnik", "icon": "🍅", "desc": "Ein verglastes Dach erlaubt es, den Garten zu einem modernen, wetterunabhängigen Gewächshaus umzubauen.",
		"section": "FARMING", "tier": 9, "epoch": 4, "cost": 140, "requires_node": "FARMING_8",
		"effects": [{"type":"rebuild","building":"GARDEN"}]
	},
	"FARMING_10": {
		"name": "Meister der Landwirtschaft", "icon": "🌾", "desc": "Generationen von Erfahrung in Anbau und Zubereitung steigern alle Nahrungsgebäude und senken den Grundhunger der Kolonie.",
		"section": "FARMING", "tier": 10, "epoch": 4, "cost": 185, "requires_node": "FARMING_9",
		"effects": [{"type":"bstat","building":"BERRY_GATHERER","field":"production_speed","mode":"mult","value":0.25}, {"type":"bstat","building":"GARDEN","field":"production_speed","mode":"mult","value":0.25}, {"type":"bstat","building":"FARMHOUSE","field":"production_speed","mode":"mult","value":0.25}, {"type":"global","key":"hunger_decay_reduction","value":0.1}]
	},
	"BREEDING_1": {
		"name": "Kuschelnester", "icon": "🪺", "desc": "Weichere Nester und bessere Raumaufteilung schaffen zusätzlichen Platz im Wohnhaus.",
		"section": "BREEDING", "tier": 1, "epoch": 1, "cost": 15, "requires_node": "",
		"effects": [{"type":"bstat","building":"HOUSE","field":"max_residents","mode":"add","value":1}]
	},
	"BREEDING_2": {
		"name": "Gesunde Wildkost", "icon": "🍎", "desc": "Ausgewogenere Wildkost lässt kranke und erschöpfte Frettchen sich schneller erholen.",
		"section": "BREEDING", "tier": 2, "epoch": 1, "cost": 20, "requires_node": "BREEDING_1",
		"effects": [{"type":"global","key":"health_regen_bonus","value":0.15}]
	},
	"BREEDING_3": {
		"name": "Familienplanung", "icon": "👨‍👩‍👧", "desc": "Bessere Organisation der Kolonie senkt die nötige Glücksschwelle für Nachwuchs leicht.",
		"section": "BREEDING", "tier": 3, "epoch": 2, "cost": 25, "requires_node": "BREEDING_2",
		"effects": [{"type":"global","key":"growth_happiness_threshold_reduction","value":5.0}]
	},
	"BREEDING_4": {
		"name": "Wärmende Decken", "icon": "🧶", "desc": "Zusätzliche Decken lindern den Unmut obdachloser Frettchen spürbar.",
		"section": "BREEDING", "tier": 4, "epoch": 2, "cost": 35, "requires_node": "BREEDING_3",
		"effects": [{"type":"global","key":"homeless_penalty_reduction","value":0.35}]
	},
	"BREEDING_5": {
		"name": "Ammenpflege", "icon": "🍼", "desc": "Erfahrene Ammen kümmern sich besonders sorgfältig um neugeborene Frettchen.",
		"section": "BREEDING", "tier": 5, "epoch": 3, "cost": 45, "requires_node": "BREEDING_4",
		"effects": [{"type":"global","key":"newborn_health_bonus","value":20.0}]
	},
	"BREEDING_6": {
		"name": "Größere Betten", "icon": "🛏️", "desc": "Zusätzliche Stockbetten erlauben es, ein Wohnhaus zu einem geräumigeren Großen Wohnhaus umzubauen.",
		"section": "BREEDING", "tier": 6, "epoch": 3, "cost": 60, "requires_node": "BREEDING_5",
		"effects": [{"type":"rebuild","building":"HOUSE"}]
	},
	"BREEDING_7": {
		"name": "Ausdauertraining", "icon": "💪", "desc": "Regelmäßiges Training lässt Hunger, Durst und Laune der Frettchen langsamer absinken.",
		"section": "BREEDING", "tier": 7, "epoch": 3, "cost": 80, "requires_node": "BREEDING_6",
		"effects": [{"type":"global","key":"needs_decay_reduction","value":0.1}]
	},
	"BREEDING_8": {
		"name": "Schichtplan-Optimierung", "icon": "🗓️", "desc": "Modern organisierte Schichten lassen Frettchen abends länger wach bleiben, bevor die Nachtruhe einsetzt.",
		"section": "BREEDING", "tier": 8, "epoch": 4, "cost": 105, "requires_node": "BREEDING_7",
		"effects": [{"type":"global","key":"day_length_extend","value":0.06}]
	},
	"BREEDING_9": {
		"name": "Kinderstube", "icon": "🧸", "desc": "Eine eigene Kinderstube kümmert sich um den Nachwuchs und hebt die Stimmung in der ganzen Kolonie.",
		"section": "BREEDING", "tier": 9, "epoch": 4, "cost": 140, "requires_node": "BREEDING_8",
		"effects": [{"type":"unlock","building":"NURSERY"}]
	},
	"BREEDING_10": {
		"name": "Meister der Zucht", "icon": "🐾", "desc": "Generationenlange Erfahrung in der Aufzucht steigert die Wachstumsrate der Kolonie deutlich und senkt die Sterblichkeit.",
		"section": "BREEDING", "tier": 10, "epoch": 4, "cost": 185, "requires_node": "BREEDING_9",
		"effects": [{"type":"global","key":"growth_rate_bonus","value":0.3}, {"type":"global","key":"mortality_reduction","value":0.2}]
	},
	"LOGISTICS_1": {
		"name": "Bessere Werkzeuge", "icon": "🔨", "desc": "Schärferes Werkzeug beschleunigt jede Baustelle spürbar.",
		"section": "LOGISTICS", "tier": 1, "epoch": 1, "cost": 15, "requires_node": "",
		"effects": [{"type":"global","key":"construction_speed_bonus","value":0.2}]
	},
	"LOGISTICS_2": {
		"name": "Lagerlogistik", "icon": "📊", "desc": "Bessere Organisation schafft einen zusätzlichen Arbeitsplatz im Lager.",
		"section": "LOGISTICS", "tier": 2, "epoch": 1, "cost": 20, "requires_node": "LOGISTICS_1",
		"effects": [{"type":"bstat","building":"STORAGE","field":"max_workers","mode":"add","value":1}]
	},
	"LOGISTICS_3": {
		"name": "Großlager-Planung", "icon": "🏬", "desc": "Zusätzliche Regalreihen erhöhen die Kapazität des Großen Lagers deutlich.",
		"section": "LOGISTICS", "tier": 3, "epoch": 2, "cost": 25, "requires_node": "LOGISTICS_2",
		"effects": [{"type":"bstat","building":"LARGE_STORAGE","field":"storage_capacity","mode":"add","value":150}]
	},
	"LOGISTICS_4": {
		"name": "Bauhof-Ausbau", "icon": "🚧", "desc": "Zusätzliche Werkbänke schaffen Platz für einen weiteren Bauarbeiter im Bauhof.",
		"section": "LOGISTICS", "tier": 4, "epoch": 2, "cost": 35, "requires_node": "LOGISTICS_3",
		"effects": [{"type":"bstat","building":"CONSTRUCTION_YARD_1","field":"max_workers","mode":"add","value":1}]
	},
	"LOGISTICS_5": {
		"name": "Vorfertigung", "icon": "🧩", "desc": "Vorgefertigte Bauteile verkürzen die benötigte Bauzeit weiter.",
		"section": "LOGISTICS", "tier": 5, "epoch": 3, "cost": 45, "requires_node": "LOGISTICS_4",
		"effects": [{"type":"global","key":"construction_speed_bonus","value":0.15}]
	},
	"LOGISTICS_6": {
		"name": "Kranbau", "icon": "🏗️", "desc": "Ein einfacher Baukran erlaubt es, den Bauhof zu einem Großbauhof umzubauen.",
		"section": "LOGISTICS", "tier": 6, "epoch": 3, "cost": 60, "requires_node": "LOGISTICS_5",
		"effects": [{"type":"rebuild","building":"CONSTRUCTION_YARD_1"}]
	},
	"LOGISTICS_7": {
		"name": "Lagerhaus-Erweiterung", "icon": "🗄️", "desc": "Ein zusätzliches Stockwerk erlaubt es, ein Lager zu einem Großlagerhaus umzubauen.",
		"section": "LOGISTICS", "tier": 7, "epoch": 3, "cost": 80, "requires_node": "LOGISTICS_6",
		"effects": [{"type":"rebuild","building":"STORAGE"}]
	},
	"LOGISTICS_8": {
		"name": "Schnelle Füße", "icon": "👟", "desc": "Leichteres, modernes Schuhwerk lässt alle Frettchen spürbar schneller laufen.",
		"section": "LOGISTICS", "tier": 8, "epoch": 4, "cost": 105, "requires_node": "LOGISTICS_7",
		"effects": [{"type":"global","key":"move_speed_bonus","value":0.1}]
	},
	"LOGISTICS_9": {
		"name": "Optimierte Routen", "icon": "🗺️", "desc": "Eingespielte Laufwege erlauben es Lagerarbeitern, in einem größeren Umkreis nach Aufgaben zu suchen.",
		"section": "LOGISTICS", "tier": 9, "epoch": 4, "cost": 140, "requires_node": "LOGISTICS_8",
		"effects": [{"type":"global","key":"warehouse_search_range_bonus","value":25.0}]
	},
	"LOGISTICS_10": {
		"name": "Meister der Logistik", "icon": "🚚", "desc": "Perfekt eingespielte, moderne Abläufe beschleunigen jede Baustelle zusätzlich und lassen Frettchen mehr tragen.",
		"section": "LOGISTICS", "tier": 10, "epoch": 4, "cost": 185, "requires_node": "LOGISTICS_9",
		"effects": [{"type":"global","key":"construction_speed_bonus","value":0.25}, {"type":"global","key":"carry_capacity_bonus","value":10.0}]
	},
	# ── Feature (v14.2, Nutzerwunsch "mehr Inhalt"): 6 neue Kür-Knoten
	# (Tier 11, jeweils Epoche 4, einer je Themenbereich), die erstmals die
	# Minispiele mit dem Tech Tree verknüpfen - vorher hatte Forschung
	# überhaupt keinen Effekt auf sie. Jeder gibt +15% Ertrag aus JEDEM
	# Minispiel (stapelt sich additiv, siehe get_global_bonus("minigame_
	# reward_mult") in MinigameOverlay._finish_current()); alle 6 zusammen
	# also +90% - ein spürbares Spätspiel-Ziel für Vielspieler.
	"FORESTRY_11": {
		"name": "Erfahrene Fäller-Hände", "icon": "🪚", "desc": "Jahrzehntelange Übung beim Holzfällen zahlt sich auch beim Sammeln per Hand aus - mehr Ertrag aus jedem Minispiel.",
		"section": "FORESTRY", "tier": 11, "epoch": 4, "cost": 210, "requires_node": "FORESTRY_10",
		"effects": [{"type":"global","key":"minigame_reward_mult","value":0.15}]
	},
	"MINING_11": {
		"name": "Geschickte Bergleute", "icon": "🥽", "desc": "Erfahrene Bergleute holen aus jedem Handgriff im Steinbruch spürbar mehr heraus - mehr Ertrag aus jedem Minispiel.",
		"section": "MINING", "tier": 11, "epoch": 4, "cost": 210, "requires_node": "MINING_10",
		"effects": [{"type":"global","key":"minigame_reward_mult","value":0.15}]
	},
	"WATER_11": {
		"name": "Wasserweisheit", "icon": "🌊", "desc": "Generationen von Brunnenmeistern wissen, wie man aus jedem Eimer das Beste holt - mehr Ertrag aus jedem Minispiel.",
		"section": "WATER", "tier": 11, "epoch": 4, "cost": 210, "requires_node": "WATER_10",
		"effects": [{"type":"global","key":"minigame_reward_mult","value":0.15}]
	},
	"FARMING_11": {
		"name": "Erntemeister", "icon": "🧺", "desc": "Wer weiß, wo die reifsten Früchte hängen, verliert beim Sammeln nichts - mehr Ertrag aus jedem Minispiel.",
		"section": "FARMING", "tier": 11, "epoch": 4, "cost": 210, "requires_node": "FARMING_10",
		"effects": [{"type":"global","key":"minigame_reward_mult","value":0.15}]
	},
	"BREEDING_11": {
		"name": "Geübte Hände", "icon": "🎓", "desc": "Eine gute Ausbildung von klein auf zahlt sich bei jeder Handarbeit aus - mehr Ertrag aus jedem Minispiel.",
		"section": "BREEDING", "tier": 11, "epoch": 4, "cost": 210, "requires_node": "BREEDING_10",
		"effects": [{"type":"global","key":"minigame_reward_mult","value":0.15}]
	},
	"LOGISTICS_11": {
		"name": "Effiziente Handgriffe", "icon": "🧰", "desc": "Optimierte Arbeitsabläufe helfen nicht nur beim Transport, sondern bei jeder Handarbeit - mehr Ertrag aus jedem Minispiel.",
		"section": "LOGISTICS", "tier": 11, "epoch": 4, "cost": 210, "requires_node": "LOGISTICS_10",
		"effects": [{"type":"global","key":"minigame_reward_mult","value":0.15}]
	},
}

## Epochen-Aufstiege. Kosten weiterhin AUSSCHLIESSLICH Wissenspunkte. Die
## Voraussetzung ist jetzt NICHT mehr statisch hinterlegt, sondern wird dynamisch
## berechnet (siehe epoch_requirement_met()): ca. 80% der Knoten DER AKTUELLEN Epoche
## müssen bereits erforscht sein, bevor die nächste Epoche überhaupt käuflich wird.
const EPOCHS: Dictionary = {
	"EPOCH_1": {
		"name": "Steinzeit", "epoch": 1, "cost": 0, "requires": [],
		"unlocks": ["CONSTRUCTION_YARD_1","LUMBERJACK","QUARRY","BERRY_GATHERER",
			"WELL","DAM","STORAGE","HOUSE","GATHERING_PLACE","FORESTER","GRAVEYARD",
			"DECO_FLOWERS","DECO_MUSHROOM","DECO_STONES","DECO_BUSH",
			"SAWMILL","WORKSHOP","RESEARCH_HUT"]
	},
	"EPOCH_2": {
		"name": "Mittelalter", "epoch": 2, "cost": 150, "requires": ["EPOCH_1"],
		"unlocks": ["CONSTRUCTION_YARD_2", "WATER_TOWER", "TAVERN", "GARDEN", "LARGE_STORAGE", "FARMHOUSE", "WATER_PUMP", "RESERVOIR", "FOOD_STORE", "WATERWHEEL", "BATHHOUSE", "EXPEDITION_CAMP", "COOKHOUSE", "DYNAMITE_WORKSHOP", "HUNTER_HUT", "DECO_LANTERN", "DISTRICT_GATE", "TOWN_HALL"]
	},
	"EPOCH_3": {
		"name": "Industrialisierung", "epoch": 3, "cost": 400, "requires": ["EPOCH_2"],
		"unlocks": ["ENGINEERS_GUILD", "IRON_MINE", "COAL_MINE", "SMELTER", "AQUEDUCT", "THEATER", "WAREHOUSE", "IRRIGATION"]
	},
	"EPOCH_4": {
		"name": "Moderne", "epoch": 4, "cost": 900, "requires": ["EPOCH_3"],
		"unlocks": ["CONSTRUCTION_OFFICE", "MACHINE_FACTORY", "BLAST_FURNACE", "STATUE"]
	},
	# Feature (v16.6, Logistik-Update Phase 4): "Eisenbahnzeit" - das Spätspiel: Schiene (Bahnhof, Depot, Gleise)
	# und Erkundung (Erkundungsstation löst auf Entdeckerkarten den Nebel auf). Bahnhof/Depot waren in v16.2-16.5
	# noch in Epoche 4; bestehende Bauten bleiben natürlich stehen.
	"EPOCH_5": {
		"name": "Eisenbahnzeit", "epoch": 5, "cost": 1500, "requires": ["EPOCH_4"],
		"unlocks": ["STATION", "DEPOT", "OBSERVATORY"]
	},
}
# ══════════════════════════════════════════════════════════════════════════════
# LAUFZEIT-ZUSTAND
# ══════════════════════════════════════════════════════════════════════════════
## Freigeschaltete Tech-Knoten-IDs (OHNE Epochen, siehe unlocked_epochs).
var unlocked: Array = []
## Freigeschaltete Epochen-IDs ("EPOCH_1".."EPOCH_5").
var unlocked_epochs: Array = []
## Wie viele Wissenspunkte insgesamt bereits in Tech-Knoten UND Epochen
## investiert wurden - rein informativ (z.B. für eine Fortschrittsanzeige).
var total_spent: float = 0.0

func init() -> void:
	unlocked = []
	unlocked_epochs = ["EPOCH_1"]
	total_spent = 0.0

# ══════════════════════════════════════════════════════════════════════════════
# TECH-KNOTEN FREISCHALTEN
# ══════════════════════════════════════════════════════════════════════════════
func can_unlock_node(tid: String) -> bool:
	if tid in unlocked: return false
	if not NODES.has(tid): return false
	var nd: Dictionary = NODES[tid]
	# Feature (Epochen-Verteilung): ein Knoten ist erst erforschbar, wenn seine
	# eigene Epoche bereits freigeschaltet wurde - unabhängig vom Themenbereich.
	if int(nd.get("epoch", 1)) > get_epoch(): return false
	var req: String = str(nd.get("requires_node", ""))
	if req != "" and not (req in unlocked): return false
	return ResourceSys.has_science(float(nd.get("cost", 0.0)))

func unlock_node(tid: String) -> bool:
	if not can_unlock_node(tid): return false
	var nd: Dictionary = NODES[tid]
	var cost: float = float(nd.get("cost", 0.0))
	if not ResourceSys.spend_science(cost): return false
	unlocked.append(tid)
	total_spent += cost
	# Feature (Tech Tree, Bugfix): wendet den gerade erforschten Bonus sofort
	# auf alle bereits bestehenden Gebäude an (nicht nur auf zukünftig neu
	# gebaute) - siehe BuildingSystem.recalculate_all_bonuses().
	BuildingSys.recalculate_all_bonuses()
	GameState.tech_unlocked.emit(tid)
	GameState.notify("Erforscht: " + str(nd.get("name", tid)))
	GameState.build_menu_update_requested.emit()
	return true

func is_node_unlocked(tid: String) -> bool:
	return tid in unlocked

## Wie viele Knoten eines Themenbereichs sind bereits freigeschaltet (= höchster
## erreichter Tier). Rein informativ für die UI (Fortschrittsanzeige je Reiter).
func get_section_progress(section: String) -> int:
	var best: int = 0
	for tid in unlocked:
		if not NODES.has(tid): continue
		var nd: Dictionary = NODES[tid]
		if str(nd.get("section", "")) != section: continue
		var tier: int = int(nd.get("tier", 0))
		if tier > best: best = tier
	return best

## Alle Knoten-IDs, die zu einer bestimmten Epoche (1-4) gehören.
func get_node_ids_for_epoch(epoch_num: int) -> Array:
	var result: Array = []
	for tid in NODES:
		if int((NODES[tid] as Dictionary).get("epoch", 1)) == epoch_num:
			result.append(tid)
	return result

## Wie viele der Knoten einer Epoche sind bereits erforscht.
func get_epoch_unlocked_count(epoch_num: int) -> int:
	var count: int = 0
	for tid in get_node_ids_for_epoch(epoch_num):
		if tid in unlocked: count += 1
	return count

# ══════════════════════════════════════════════════════════════════════════════
# EPOCHEN FREISCHALTEN (kosten nur noch Wissenspunkte + ca. 80% Knoten-Fortschritt
# der AKTUELLEN Epoche)
# ══════════════════════════════════════════════════════════════════════════════
func get_next_epoch_id() -> String:
	for eid in ["EPOCH_1","EPOCH_2","EPOCH_3","EPOCH_4","EPOCH_5"]:
		if eid in unlocked_epochs: continue
		return eid
	return ""

## Wie viele Knoten der aktuellen Epoche müssen erforscht sein, damit die
## nächste Epoche überhaupt käuflich wird (aufgerundete 80%-Schwelle).
func get_epoch_unlock_requirement(epoch_num: int) -> int:
	var total: int = get_node_ids_for_epoch(epoch_num).size()
	return int(ceil(float(total) * 0.8))

## Ist die Voraussetzung ("~80% der Knoten der aktuellen Epoche erforscht") für
## die nächste Epoche bereits erfüllt - unabhängig davon, ob man sich die
## Wissenspunkte-Kosten selbst schon leisten kann?
func epoch_requirement_met(eid: String) -> bool:
	if not EPOCHS.has(eid): return false
	var target_epoch: int = int((EPOCHS[eid] as Dictionary).get("epoch", 1))
	var current_epoch: int = target_epoch - 1
	if current_epoch < 1: return true
	var required: int = get_epoch_unlock_requirement(current_epoch)
	return get_epoch_unlocked_count(current_epoch) >= required

func can_unlock_epoch(eid: String) -> bool:
	if eid in unlocked_epochs: return false
	if not EPOCHS.has(eid): return false
	var ed: Dictionary = EPOCHS[eid]
	for req in ed.get("requires", []):
		if not (str(req) in unlocked_epochs): return false
	if not epoch_requirement_met(eid): return false
	return ResourceSys.has_science(float(ed.get("cost", 0.0)))

func unlock_epoch(eid: String) -> bool:
	if not can_unlock_epoch(eid): return false
	var ed: Dictionary = EPOCHS[eid]
	var cost: float = float(ed.get("cost", 0.0))
	if not ResourceSys.spend_science(cost): return false
	unlocked_epochs.append(eid)
	total_spent += cost
	GameState.tech_unlocked.emit(eid)
	GameState.notify("Epoche freigeschaltet: " + str(ed.get("name", eid)))
	GameState.build_menu_update_requested.emit()
	return true

func get_epoch() -> int:
	var max_e: int = 1
	for eid in unlocked_epochs:
		if not EPOCHS.has(eid): continue
		var e: int = int((EPOCHS[eid] as Dictionary).get("epoch", 1))
		if e > max_e: max_e = e
	return max_e

# ══════════════════════════════════════════════════════════════════════════════
# FREIGESCHALTETE Gebäude (Epochen-Unlocks + einzelne Tech-Knoten mit
# "unlock"-Effekt, z.B. die Kinderstube über BREEDING_9)
# ══════════════════════════════════════════════════════════════════════════════
func get_unlocked_buildings() -> Array:
	var result: Array = []
	for eid in unlocked_epochs:
		if not EPOCHS.has(eid): continue
		for bid in (EPOCHS[eid] as Dictionary).get("unlocks", []):
			result.append(str(bid))
	for tid in unlocked:
		if not NODES.has(tid): continue
		for eff in (NODES[tid] as Dictionary).get("effects", []):
			var e: Dictionary = eff
			if str(e.get("type","")) == "unlock":
				result.append(str(e.get("building","")))
	return result

# ══════════════════════════════════════════════════════════════════════════════
# Gebäude-STAT-BONI (angewendet in BuildingEntity.from_type()/finish_rebuild())
# ══════════════════════════════════════════════════════════════════════════════
## Wendet alle freigeschalteten "bstat"-Effekte für die Gebäude-ID von b auf
## dessen BASISWERTE an. WICHTIG: liest die Basiswerte bewusst frisch aus
## BuildingData.BUILDINGS[b.id] statt aus den aktuellen Feldern von b - sonst
## wäre die Funktion nicht idempotent (ein zweiter Aufruf würde bereits
## angewendete Mult-Boni erneut draufmultiplizieren). Dadurch kann diese
## Funktion jederzeit erneut aufgerufen werden, z.B. wenn NACH dem Bau eines
## Gebäudes ein weiterer Tech-Knoten erforscht wird (siehe unlock_node() unten,
## das dafür BuildingSys.recalculate_all_bonuses() aufruft) - vorher wirkten
## neu erforacht Boni nur auf danach NEU gebaute Gebäude, nicht auf bereits
## bestehende.
## "add" addiert direkt auf den Basiswert, "mult" addiert value auf einen
## laufenden Multiplikator (1.0 + summe), der am Ende auf den Basiswert
## angewendet wird - so stapeln sich mehrere "mult"-Boni additiv statt sich
## zu potenzieren (vorhersehbarer für die Balance).
func apply_building_bonuses(b) -> void:
	var base_data: Dictionary = BuildingData.BUILDINGS.get(b.id, {})
	if base_data.is_empty(): return
	# Basiswerte 1:1 wie in BuildingEntity.from_type() - muss synchron gehalten
	# werden, falls sich dort die Default-Werte je Feld ändern.
	var base_defaults: Dictionary = {
		"production_speed": float(base_data.get("production_speed", 1.0)),
		"collection_radius": int(base_data.get("collection_radius", 6)),
		"planting_radius": int(base_data.get("planting_radius", 8)),
		"storage_capacity": float(base_data.get("storage_capacity", 0.0)),
		"water_capacity": float(base_data.get("water_capacity", 0.0)),
		"max_residents": int(base_data.get("max_residents", 0)),
		"max_workers": int(base_data.get("max_workers", 0)),
		"local_storage_capacity": float(BuildingEntity.LOCAL_STORAGE_CAPACITY if base_data.get("type","") in \
			["COLLECTOR","PROCESSOR","MULTIPROCESSOR","HUNTER","FARM","FARMHOUSE"] and \
			str(base_data.get("collects_resource","")) not in ["WATER","SCIENCE"] else 0.0),
		"happiness_bonus": float(base_data.get("happiness_bonus", 0.0)),
	}
	var mult_sums: Dictionary = {}   # field -> summierter Multiplikator-Zuschlag
	var add_sums: Dictionary = {}    # field -> summierter Additions-Zuschlag
	for tid in unlocked:
		if not NODES.has(tid): continue
		for eff in (NODES[tid] as Dictionary).get("effects", []):
			var e: Dictionary = eff
			if str(e.get("type","")) != "bstat": continue
			if str(e.get("building","")) != b.id: continue
			var field: String = str(e.get("field",""))
			var mode: String = str(e.get("mode","add"))
			var value: float = float(e.get("value", 0.0))
			if mode == "mult":
				mult_sums[field] = float(mult_sums.get(field, 0.0)) + value
			else:
				add_sums[field] = float(add_sums.get(field, 0.0)) + value
	for field in base_defaults:
		var base_val: float = float(base_defaults[field])
		var new_val: float = base_val
		if mult_sums.has(field):
			new_val = base_val * (1.0 + float(mult_sums[field]))
		if add_sums.has(field):
			new_val += float(add_sums[field])
		if field in ["collection_radius","planting_radius","max_residents","max_workers"]:
			b.set(field, int(round(new_val)))
		else:
			b.set(field, new_val)

# ══════════════════════════════════════════════════════════════════════════════
# GLOBALE, PERMANENTE BONI (abgefragt von PopulationManager/FerretEntity/
# WaterSystem/DayNightSystem/GameController/BuildingSystem an der jeweiligen
# Wirkstelle). Bekannte Keys:
#   carry_capacity_bonus, move_speed_bonus, construction_speed_bonus,
#   needs_decay_reduction, hunger_decay_reduction, waterwheel_boost_bonus,
#   dam_retention_bonus, drought_evaporation_reduction, homeless_penalty_reduction,
#   growth_happiness_threshold_reduction, warehouse_search_range_bonus,
#   health_regen_bonus, growth_rate_bonus, mortality_reduction,
#   day_length_extend, wood_regen_speed, newborn_health_bonus,
#   minigame_reward_mult (v14.2, siehe MinigameOverlay._finish_current())
# ══════════════════════════════════════════════════════════════════════════════
func get_global_bonus(key: String) -> float:
	var total: float = 0.0
	for tid in unlocked:
		if not NODES.has(tid): continue
		for eff in (NODES[tid] as Dictionary).get("effects", []):
			var e: Dictionary = eff
			if str(e.get("type","")) == "global" and str(e.get("key","")) == key:
				total += float(e.get("value", 0.0))
	return total

# ══════════════════════════════════════════════════════════════════════════════
# Gebäude-UMBAU (Rebuild) - Nachschlagen, ob/wofür ein Gebäudetyp umgebaut
# werden kann. Die eigentlichen Umbau-Daten (Ziel-Gebäude, Kosten, Bauzeit)
# stehen in BuildingData.REBUILDS; hier wird nur geprüft, ob der dafür
# nötige Tech-Knoten bereits freigeschaltet ist.
# ══════════════════════════════════════════════════════════════════════════════
func can_rebuild(building_id: String) -> bool:
	var rd: Dictionary = BuildingData.REBUILDS.get(building_id, {})
	if rd.is_empty(): return false
	var req: String = str(rd.get("requires_tech", ""))
	return req == "" or (req in unlocked)

func get_rebuild_info(building_id: String) -> Dictionary:
	return BuildingData.REBUILDS.get(building_id, {})

# ══════════════════════════════════════════════════════════════════════════════
# SPEICHERN / LADEN
# ══════════════════════════════════════════════════════════════════════════════
func serialize() -> Dictionary:
	return {
		"unlocked": unlocked.duplicate(),
		"unlocked_epochs": unlocked_epochs.duplicate(),
		"total_spent": total_spent
	}

func deserialize(data) -> void:
	# Abwärtskompatibilität: alte Saves (vor diesem Feature) speicherten hier
	# ein einfaches Array aus Epochen-IDs statt eines Dictionarys.
	if data is Array:
		unlocked = []
		unlocked_epochs = []
		for tid in data:
			if str(tid).begins_with("EPOCH_"):
				unlocked_epochs.append(str(tid))
		if unlocked_epochs.is_empty(): unlocked_epochs = ["EPOCH_1"]
		total_spent = 0.0
		return
	var d: Dictionary = data as Dictionary
	unlocked = (d.get("unlocked", []) as Array).duplicate()
	unlocked_epochs = (d.get("unlocked_epochs", ["EPOCH_1"]) as Array).duplicate()
	if unlocked_epochs.is_empty(): unlocked_epochs = ["EPOCH_1"]
	total_spent = float(d.get("total_spent", 0.0))
