## BuildingData.gd
## Alle Gebäudetypen-Definitionen (entspricht BT und PATH_TYPES im HTML).
extends Node

const BUILDINGS: Dictionary = {
	# ── Epoche 1 ──────────────────────────────────────────────────────────────
	"CONSTRUCTION_YARD_1": {
		"name": "Bauhof", "type": "BUILDER", "epoch": 1,
		"costs": {"WOOD": 20, "STONE": 10}, "max_workers": 3,
		"icon": "🏗️", "construction_work": 30,
		"desc": "Frettchen bauen hier Gebäude"
	},
	"LUMBERJACK": {
		"name": "Holzfäller", "type": "COLLECTOR", "epoch": 1,
		"costs": {"WOOD": 15}, "max_workers": 2,
		"collection_radius": 6, "collects_resource": "WOOD",
		"production_speed": 1.0, "icon": "🪓", "construction_work": 30
	},
	"QUARRY": {
		"name": "Steinbruch", "type": "COLLECTOR", "epoch": 1,
		"costs": {"WOOD": 10, "STONE": 5}, "max_workers": 2,
		"collection_radius": 5, "collects_resource": "STONE",
		"production_speed": 0.8, "icon": "⛏️", "construction_work": 40
	},
	"BERRY_GATHERER": {
		"name": "Beerensammler", "type": "COLLECTOR", "epoch": 1,
		"costs": {"WOOD": 8}, "max_workers": 2,
		"collection_radius": 7, "collects_resource": "BERRIES",
		# Bug-Fix (v10.13): production_speed war 1.2 - bei voller Besetzung
		# (2 Arbeiter) macht das mit der globalen 0.35x-Formel in
		# BuildingEntity._collect() nur ~0.84 BERRIES/Sek. Der Hunger-Verbrauch
		# der Kolonie (PopulationManager.update(), "BERRIES" als Nahrungs-
		# Fallback) kann aber bis zu ferrets.size()*0.4 BERRIES/Sek auffressen -
		# schon ab 3 Frettchen war der Verbrauch stärker als die Produktion,
		# das Lager blieb dadurch dauerhaft bei ~0 hängen ("produziert keine
		# Beeren"). production_speed jetzt so gewählt, dass ein voll
		# besetzter Beerensammler allein den Grundbedarf von ~6 Frettchen
		# decken kann.
		"production_speed": 3.5, "icon": "🫐", "construction_work": 20
	},
	"WELL": {
		"name": "Brunnen", "type": "COLLECTOR", "epoch": 1,
		"costs": {"WOOD": 10, "STONE": 15}, "max_workers": 1,
		"collection_radius": 6, "collects_resource": "WATER",
		"production_speed": 1.5, "water_capacity": 100,
		"happiness_bonus": 2, "icon": "🪣", "construction_work": 45
	},
	"DAM": {
		"name": "Damm", "type": "DAM", "epoch": 1,
		"costs": {"WOOD": 15, "STONE": 25}, "max_workers": 0,
		"icon": "🧱", "construction_work": 50,
		"desc": "Staut Wasser auf - hält Flüsse/Seen während einer Dürre länger gefüllt"
	},
	"STORAGE": {
		"name": "Lager", "type": "STORAGE", "epoch": 1,
		"costs": {"WOOD": 20}, "max_workers": 2,
		"storage_capacity": 120, "icon": "📦", "construction_work": 25
	},
	"HOUSE": {
		"name": "Wohnhaus", "type": "HOUSING", "epoch": 1,
		"costs": {"WOOD": 25, "STONE": 10}, "max_workers": 0,
		"max_residents": 3, "happiness_bonus": 5,
		"icon": "🏠", "construction_work": 50
	},
	"GATHERING_PLACE": {
		"name": "Versammlungsplatz", "type": "HAPPINESS", "epoch": 1,
		"costs": {"WOOD": 15, "STONE": 5}, "max_workers": 0,
		"happiness_bonus": 8, "happiness_radius": 8,
		"icon": "🎪", "construction_work": 35
	},
	"FORESTER": {
		"name": "Försterei", "type": "FORESTER", "epoch": 1,
		"costs": {"WOOD": 20, "STONE": 5}, "max_workers": 2,
		"planting_radius": 8, "icon": "🌲", "construction_work": 40
	},
	"GRAVEYARD": {
		"name": "Gedenkstätte", "type": "GRAVEYARD", "epoch": 1,
		"costs": {"STONE": 15}, "max_workers": 0,
		"happiness_bonus": 3, "icon": "🪦", "construction_work": 30
	},
	"DECO_FLOWERS": {
		"name": "Blumenbeet", "type": "DECO", "epoch": 1,
		"costs": {"WOOD": 5}, "max_workers": 0,
		"happiness_bonus": 3, "happiness_radius": 4,
		"icon": "🌸", "construction_work": 10
	},
	"DECO_MUSHROOM": {
		"name": "Pilzgarten", "type": "DECO", "epoch": 1,
		"costs": {"STONE": 5}, "max_workers": 0,
		"happiness_bonus": 2, "happiness_radius": 4,
		"icon": "🍄", "construction_work": 10
	},
	"DECO_STONES": {
		"name": "Steinkreis", "type": "DECO", "epoch": 1,
		"costs": {"STONE": 8}, "max_workers": 0,
		"happiness_bonus": 2, "happiness_radius": 5,
		"icon": "🪨", "construction_work": 10
	},
	"DECO_BUSH": {
		"name": "Zierstrauch", "type": "DECO", "epoch": 1,
		"costs": {"WOOD": 8}, "max_workers": 0,
		"happiness_bonus": 3, "happiness_radius": 4,
		"icon": "🌿", "construction_work": 10
	},
	# ── Epoche 2 ──────────────────────────────────────────────────────────────
	"CONSTRUCTION_YARD_2": {
		"name": "Großer Bauhof", "type": "BUILDER", "epoch": 2,
		"costs": {"PLANKS": 30, "STONE": 20}, "max_workers": 5,
		"icon": "🏗️", "construction_work": 60
	},
	"SAWMILL": {
		"name": "Sägewerk", "type": "PROCESSOR", "epoch": 1,
		# Bug-Fix (v10.19): kostete bisher PLANKS - aber das Sägewerk ist die
		# EINZIGE Quelle für PLANKS überhaupt. Mit PLANKS als eigenen
		# Baukosten wäre seine eigene Errichtung unmöglich gewesen
		# (0 PLANKS am Spielstart, keine andere Quelle). Jetzt reine
		# Rohmaterial-Kosten (WOOD/STONE), die mit Holzfäller/Steinbruch aus
		# Epoche 1 ohne Umwege erreichbar sind.
		"costs": {"WOOD": 35, "STONE": 10}, "max_workers": 2,
		"produces": "PLANKS", "production_speed": 1.5,
		"needs_input": true, "input_resources": ["WOOD"],
		"icon": "🪚", "construction_work": 60
	},
	"WORKSHOP": {
		"name": "Werkstatt", "type": "PROCESSOR", "epoch": 1,
		# Bug-Fix (v10.19): siehe SAWMILL - gleicher Deadlock mit TOOLS/PLANKS,
		# gleicher Fix (reine WOOD/STONE-Kosten).
		"costs": {"WOOD": 25, "STONE": 20}, "max_workers": 2,
		"produces": "TOOLS", "production_speed": 1.0,
		"needs_input": true, "input_resources": ["WOOD", "STONE"],
		"icon": "🔨", "construction_work": 70
	},
	"WATER_TOWER": {
		"name": "Wasserturm", "type": "COLLECTOR", "epoch": 2,
		"costs": {"PLANKS": 25, "STONE": 30}, "max_workers": 2,
		"collection_radius": 10, "collects_resource": "WATER",
		"production_speed": 3.5, "water_capacity": 300,
		"happiness_bonus": 4, "icon": "⛲", "construction_work": 85
	},
	"TAVERN": {
		"name": "Taverne", "type": "HAPPINESS", "epoch": 2,
		"costs": {"PLANKS": 30, "STONE": 20}, "max_workers": 2,
		"happiness_bonus": 12, "happiness_radius": 10,
		"icon": "🍺", "construction_work": 80
	},
	"GARDEN": {
		"name": "Garten", "type": "COLLECTOR", "epoch": 2,
		"costs": {"PLANKS": 15, "STONE": 5}, "max_workers": 2,
		"collection_radius": 5, "collects_resource": "BERRIES",
		# Bug-Fix (v10.13): proportional zum BERRY_GATHERER-Fix angehoben
		# (siehe dort) - der Garten ist die Epoche-2-Aufwertung und sollte
		# spürbar besser sein als der einfache Beerensammler.
		"production_speed": 5.0, "happiness_bonus": 5,
		"icon": "🌻", "construction_work": 45
	},
	"LARGE_STORAGE": {
		"name": "Großes Lager", "type": "STORAGE", "epoch": 2,
		"costs": {"PLANKS": 35, "STONE": 20}, "max_workers": 3,
		"storage_capacity": 250, "icon": "🏪", "construction_work": 50
	},
	# Feature (v11.11, Distrikt-System): verbindet die Lager-Netzwerke zweier
	# (oder mehrerer) Bezirke in seiner collection_radius, SOLANGE es mit
	# mindestens einem Frettchen besetzt ist (siehe DistrictSystem.gd,
	# BuildingEntity.update()). Ohne Verbindung holen Lagerarbeiter/Bau-
	# Frettchen NUR innerhalb ihres eigenen Bezirks Material - genau wie in
	# Timberborn, wo getrennte Landmassen eigene Bezirke bilden und erst eine
	# "District Crossing" sie verbindet.
	# Feature (v16.0, Kolonie-Fundament): das Rathaus MACHT eine Kolonie aus. Die
	# Startkolonie bekommt es gratis; ab Epoche 2 gründet jedes weitere Rathaus
	# (in mind. 20 Kacheln Abstand zu jedem anderen) eine NEUE Kolonie. Die
	# "Kosten" sind das Gründungspaket: sie werden der Gründerkolonie abgezogen
	# und wandern als Startbestand in den Pool der neuen Kolonie. Dazu gibt es
	# gratis Bauhof + Lager und 3 Siedler-Frettchen (siehe GameController._found_colony()).
	"TOWN_HALL": {
		"name": "Rathaus", "type": "TOWN_HALL", "epoch": 2,
		"costs": {"WOOD": 80, "STONE": 50, "PLANKS": 20, "TOOLS": 5, "BERRIES": 20},
		"max_workers": 0, "territory_radius": 16, "icon": "🏛️", "construction_work": 10,
		"desc": "Gründet eine neue Kolonie: Gebiet, eigene Lager und Bevölkerung"
	},
	# Feature (v16.2, Logistik-Update Phase 2): Schiene. Beide Gebäude sind Knoten des
	# Gleisnetzes (siehe RailSystem.gd); sie stehen im Gebiet einer Kolonie, die Gleise
	# dazwischen dürfen auch durch Niemandsland führen.
	"STATION": {
		"name": "Bahnhof", "type": "STATION", "epoch": 5,
		"costs": {"PLANKS": 40, "STONE": 30, "TOOLS": 6},
		"max_workers": 0, "icon": "🚉", "construction_work": 12,
		"desc": "Halt der Güterzüge: tauscht Waren mit dem Lager der Kolonie"
	},
	# Feature (v16.6, Erkundung): die Erkundungsstation deckt auf Entdeckerkarten (Nebel) nach und nach
	# einen Kreis um sich herum auf, solange sie besetzt ist (siehe BuildingEntity._explore()). Radius =
	# collection_radius, +50% je Upgrade-Stufe (14 -> 21 -> 28). In klassischen Welten ohne Nebel nutzlos
	# (das Baumenü blendet sie dort aus).
	"OBSERVATORY": {
		"name": "Erkundungsstation", "type": "EXPLORER", "epoch": 5,
		"costs": {"PLANKS": 80, "STONE": 60, "TOOLS": 15, "IRON_BARS": 10},
		"max_workers": 2, "collection_radius": 14, "icon": "🔭", "construction_work": 16,
		"desc": "Deckt den Nebel um sich herum nach und nach auf"
	},
	"DEPOT": {
		"name": "Depot", "type": "DEPOT", "epoch": 5,
		"costs": {"PLANKS": 50, "STONE": 30, "IRON_BARS": 10, "TOOLS": 8},
		"max_workers": 0, "icon": "🚂", "construction_work": 14,
		"desc": "Hier stehen und starten deine Züge"
	},
	"DISTRICT_GATE": {
		"name": "Bezirkstor", "type": "DISTRICT_GATE", "epoch": 2,
		"costs": {"PLANKS": 30, "STONE": 25}, "max_workers": 1,
		"collection_radius": 5, "icon": "🚧", "construction_work": 45,
		"desc": "Verbindet Lager-Netzwerke benachbarter Bezirke, solange ein Frettchen hier arbeitet"
	},
	# Feature (v14.5, Timberborn-Feld-System): ersetzt die früheren CROP_FIELD
	# ("Getreidefeld") und WHEAT_FARM ("Getreidefarm") - beide produzierten
	# WHEAT rein anhand der Arbeiterzahl, ohne jedes Feld-Konzept. Der
	# Bauernhof selbst baut nichts an - er weist Arbeiter zu, die vom Spieler
	# frei im Bezirk gesetzte Feld-Kacheln bestellen (säen -> FarmFieldSystem
	# lässt wachsen -> ernten), siehe FarmFieldSystem.gd und
	# BuildingEntity._farmhouse(). "Feld setzen/entfernen" ist ein eigenes,
	# kostenloses Terrain-Werkzeug (siehe BuildMenu.gd "Landwirtschaft").
	"FARMHOUSE": {
		"name": "Bauernhof", "type": "FARMHOUSE", "epoch": 2,
		"costs": {"PLANKS": 25, "STONE": 10}, "max_workers": 4,
		"collects_resource": "WHEAT",
		"icon": "🚜", "production_speed": 1.0, "construction_work": 50,
		"desc": "Arbeiter bestellen vom Spieler gesetzte Feld-Kacheln im selben Bezirk (Saat -> Wachstum -> Ernte) - Reichweite ist bezirksweit unbegrenzt."
	},
	"WATER_PUMP": {
		"name": "Wasserpumpe", "type": "COLLECTOR", "epoch": 2,
		"costs": {"PLANKS": 30, "STONE": 20}, "max_workers": 2,
		"collection_radius": 8, "collects_resource": "WATER",
		"production_speed": 5.0, "water_capacity": 200,
		"icon": "🚿", "construction_work": 70
	},
	"RESERVOIR": {
		"name": "Wasserreservoir", "type": "STORAGE", "epoch": 2,
		"costs": {"STONE": 40, "PLANKS": 20}, "max_workers": 0,
		"water_capacity": 500, "icon": "🏗️", "construction_work": 90
	},
	"FOOD_STORE": {
		"name": "Lebensmittellager", "type": "STORAGE", "epoch": 2,
		"costs": {"PLANKS": 30, "STONE": 15}, "max_workers": 2,
		"storage_capacity": 200, "icon": "🍱", "construction_work": 55
	},
	"WATERWHEEL": {
		"name": "Wasserrad", "type": "WATERWHEEL", "epoch": 2,
		"costs": {"PLANKS": 40, "STONE": 20}, "max_workers": 1,
		"boost_radius": 10, "boost_factor": 0.5,
		"icon": "⚙️", "construction_work": 100
	},
	"BATHHOUSE": {
		"name": "Badehaus", "type": "HAPPINESS", "epoch": 2,
		"costs": {"PLANKS": 35, "STONE": 30}, "max_workers": 2,
		"happiness_bonus": 15, "happiness_radius": 12,
		"icon": "🛁", "construction_work": 90
	},
	"EXPEDITION_CAMP": {
		"name": "Expeditionslager", "type": "EXPEDITION", "epoch": 2,
		"costs": {"PLANKS": 25, "TOOLS": 5}, "max_workers": 0,
		"icon": "🗺️", "construction_work": 70,
		"desc": "Schicke Frettchen auf Erkundungstouren"
	},
	"COOKHOUSE": {
		"name": "Kochhaus", "type": "MULTIPROCESSOR", "epoch": 2,
		"costs": {"WOOD": 30, "STONE": 15}, "max_workers": 2,
		"recipes": ["FOOD", "COOKED_MEAT", "BREAD", "STEW"],
		"production_speed": 1.2, "icon": "🍲", "construction_work": 50
	},
	"HUNTER_HUT": {
		"name": "Jäger-Hütte", "type": "HUNTER", "epoch": 2,
		"costs": {"WOOD": 20, "STONE": 10}, "max_workers": 2,
		"production_speed": 0.8, "collection_radius": 10,
		"icon": "🏹", "construction_work": 55
	},
	"DYNAMITE_WORKSHOP": {
		"name": "Sprengstoffwerk", "type": "PROCESSOR", "epoch": 2,
		"costs": {"PLANKS": 30, "STONE": 20}, "max_workers": 2,
		"produces": "DYNAMITE", "production_speed": 1.0,
		"needs_input": true, "input_resources": ["COAL", "IRON"],
		"icon": "🧨", "construction_work": 60
	},
	"DECO_LANTERN": {
		"name": "Laterne", "type": "DECO", "epoch": 2,
		"costs": {"IRON": 3, "WOOD": 2}, "max_workers": 0,
		"happiness_bonus": 4, "happiness_radius": 6,
		"icon": "🪔", "construction_work": 15
	},
	# ── Epoche 3 ──────────────────────────────────────────────────────────────
	"ENGINEERS_GUILD": {
		"name": "Ingenieursgilde", "type": "BUILDER", "epoch": 3,
		"costs": {"PLANKS": 50, "STONE": 40, "TOOLS": 10}, "max_workers": 6,
		"icon": "🏛️", "construction_work": 120
	},
	"IRON_MINE": {
		"name": "Eisenmine", "type": "COLLECTOR", "epoch": 3,
		"costs": {"PLANKS": 40, "STONE": 30}, "max_workers": 3,
		"collection_radius": 6, "collects_resource": "IRON",
		"production_speed": 1.0, "icon": "⛏️", "construction_work": 110
	},
	"COAL_MINE": {
		"name": "Kohlemine", "type": "COLLECTOR", "epoch": 3,
		"costs": {"PLANKS": 35, "STONE": 25}, "max_workers": 3,
		"collection_radius": 6, "collects_resource": "COAL",
		"production_speed": 1.0, "icon": "⚫", "construction_work": 100
	},
	"SMELTER": {
		"name": "Schmelze", "type": "PROCESSOR", "epoch": 3,
		"costs": {"STONE": 50, "PLANKS": 30}, "max_workers": 3,
		"produces": "IRON_BARS", "production_speed": 0.8,
		"needs_input": true, "input_resources": ["IRON", "WOOD"],
		"icon": "🔥", "construction_work": 140
	},
	"AQUEDUCT": {
		"name": "Aquädukt", "type": "COLLECTOR", "epoch": 3,
		"costs": {"STONE": 80, "PLANKS": 40}, "max_workers": 3,
		"collection_radius": 14, "collects_resource": "WATER",
		"production_speed": 6.0, "water_capacity": 800,
		"happiness_bonus": 6, "icon": "🌊", "construction_work": 160
	},
	"THEATER": {
		"name": "Theater", "type": "HAPPINESS", "epoch": 3,
		"costs": {"PLANKS": 60, "STONE": 50, "IRON_BARS": 10}, "max_workers": 3,
		"happiness_bonus": 20, "happiness_radius": 15,
		"icon": "🎭", "construction_work": 160
	},
	"WAREHOUSE": {
		"name": "Warenlager", "type": "STORAGE", "epoch": 3,
		"costs": {"PLANKS": 60, "STONE": 40, "IRON_BARS": 5}, "max_workers": 4,
		"storage_capacity": 500, "icon": "🏭", "construction_work": 100
	},
	"IRRIGATION": {
		"name": "Bewässerungskanal", "type": "COLLECTOR", "epoch": 3,
		"costs": {"STONE": 60, "PLANKS": 30}, "max_workers": 2,
		"collection_radius": 12, "collects_resource": "WATER",
		"production_speed": 4.0, "water_capacity": 400,
		"icon": "💧", "construction_work": 130
	},
	# ── Epoche 4 ──────────────────────────────────────────────────────────────
	"CONSTRUCTION_OFFICE": {
		"name": "Konstruktionsamt", "type": "BUILDER", "epoch": 4,
		"costs": {"PLANKS": 80, "STONE": 60, "IRON_BARS": 20}, "max_workers": 8,
		"icon": "🏢", "construction_work": 200
	},
	"MACHINE_FACTORY": {
		"name": "Maschinenfabrik", "type": "PROCESSOR", "epoch": 4,
		"costs": {"IRON_BARS": 30, "STONE": 50, "PLANKS": 40}, "max_workers": 4,
		"produces": "MACHINES", "production_speed": 0.5,
		"needs_input": true, "input_resources": ["IRON_BARS", "TOOLS"],
		"icon": "🤖", "construction_work": 250
	},
	"BLAST_FURNACE": {
		"name": "Hochofen", "type": "PROCESSOR", "epoch": 4,
		"costs": {"STONE": 80, "IRON_BARS": 20, "PLANKS": 30}, "max_workers": 4,
		"produces": "STEEL", "production_speed": 0.6,
		"needs_input": true, "input_resources": ["IRON_BARS", "COAL"],
		"icon": "🔥", "construction_work": 280
	},
	"STATUE": {
		"name": "Statue", "type": "HAPPINESS", "epoch": 4,
		"costs": {"STONE": 100, "IRON_BARS": 30, "MACHINES": 5}, "max_workers": 0,
		"happiness_bonus": 30, "happiness_radius": 20,
		"icon": "🗿", "construction_work": 200
	},
	# ── Feature (Tech Tree): Forschungsstube – produziert Wissenspunkte ──────
	"RESEARCH_HUT": {
		"name": "Forschungsstube", "type": "COLLECTOR", "epoch": 1,
		"costs": {"WOOD": 25, "STONE": 15}, "max_workers": 2,
		# Bug-Fix (v14.2, gemeldet: "Forschung fühlt sich zu schnell an"):
		# production_speed war 2.0 - doppelt so hoch wie der Holzfäller (1.0)
		# und mehr als doppelt so hoch wie der Steinbruch (0.8), obwohl
		# Wissenspunkte KEIN Lager/Kapazitätslimit haben (sie fliessen direkt
		# in einen globalen Pool, siehe _collect() unten) - eine voll besetzte
		# Forschungsstube hat dadurch spürbar schneller durch den ganzen
		# Tech Tree geschaltet, als neue Inhalte/Gebäude nachkommen konnten.
		# Jetzt auf Höhe der anderen Basis-Sammelgebäude.
		"collects_resource": "SCIENCE", "production_speed": 1.0,
		"icon": "🔬", "construction_work": 50,
		"desc": "Produziert Wissenspunkte für den Tech Tree."
	},
	# ── Feature (Tech Tree): Kinderstube – über BREEDING_9 freigeschaltet ───
	"NURSERY": {
		"name": "Kinderstube", "type": "HAPPINESS", "epoch": 4,
		"costs": {"PLANKS": 25, "STONE": 15}, "max_workers": 1,
		"happiness_bonus": 8, "happiness_radius": 8,
		"icon": "🍼", "construction_work": 55,
		"desc": "Kümmert sich um den Nachwuchs und hebt die Stimmung der Kolonie."
	},
	# ── Feature (Tech Tree): Umbau-Ziel-Gebäude. Diese Einträge sind absichtlich
	# in KEINER Epochen-"unlocks"-Liste enthalten (erscheinen also nie im
	# normalen Baumenü) - sie sind ausschliesslich über den "Umbauen"-Button
	# im Gebäude-Infopanel erreichbar, siehe BuildingData.REBUILDS und
	# BuildingEntity.start_rebuild()/finish_rebuild().
	"WORKSHOP_ADV": {
		"name": "Großwerkstatt", "type": "PROCESSOR", "epoch": 1,
		"costs": {"WOOD": 25, "STONE": 20}, "max_workers": 3,
		"produces": "TOOLS", "production_speed": 1.5,
		"needs_input": true, "input_resources": ["WOOD", "STONE"],
		"icon": "🏭", "construction_work": 70
	},
	"QUARRY_ADV": {
		"name": "Großsteinbruch", "type": "COLLECTOR", "epoch": 1,
		"costs": {"WOOD": 20, "STONE": 10}, "max_workers": 4,
		"collection_radius": 8, "collects_resource": "STONE",
		"production_speed": 1.6, "icon": "⛏️", "construction_work": 60
	},
	"DAM_ADV": {
		"name": "Schleuse", "type": "DAM", "epoch": 2,
		"costs": {"STONE": 30, "PLANKS": 20}, "max_workers": 0,
		"icon": "🚧", "construction_work": 60
	},
	"GARDEN_ADV": {
		"name": "Gewächshaus", "type": "COLLECTOR", "epoch": 2,
		"costs": {"PLANKS": 15, "STONE": 5}, "max_workers": 2,
		"collection_radius": 5, "collects_resource": "BERRIES",
		"production_speed": 6.5, "happiness_bonus": 5,
		"icon": "🏡", "construction_work": 45
	},
	"HOUSE_ADV": {
		"name": "Großes Wohnhaus", "type": "HOUSING", "epoch": 1,
		"costs": {"WOOD": 20, "STONE": 5}, "max_workers": 0,
		"max_residents": 6, "happiness_bonus": 2, "happiness_radius": 5,
		"icon": "🏘️", "construction_work": 40
	},
	"CONSTRUCTION_YARD_1_ADV": {
		"name": "Großbauhof", "type": "BUILDER", "epoch": 1,
		"costs": {"WOOD": 30, "STONE": 15}, "max_workers": 4,
		"icon": "🏗️", "construction_work": 45
	},
	"STORAGE_ADV": {
		"name": "Großlagerhaus", "type": "STORAGE", "epoch": 1,
		"costs": {"WOOD": 20}, "max_workers": 3,
		"storage_capacity": 150, "icon": "🏬", "construction_work": 30
	}
}

## Feature (Tech Tree): Gebäude-Umbau. Ordnet einer bereits gebauten
## Gebäude-ID (Schlüssel) das Umbau-Ziel zu: welches BUILDINGS-Eintrag es
## danach wird ("target"), welcher Tech-Knoten dafür freigeschaltet sein muss
## ("requires_tech"), Anzeigename/-beschreibung für den Button, sowie eigene
## Umbau-Kosten und Bauzeit (bewusst GUENSTIGER/kürzer als ein Neubau - es
## handelt sich ja um eine Erweiterung eines bestehenden Gebäudes). Während
## des Umbaus gelten dieselben Baustellen-Prinzipien wie bei einem Neubau
## (siehe BuildingEntity.start_rebuild()) - das Gebäude produziert in dieser
## Zeit nichts.
const REBUILDS: Dictionary = {
	"WORKSHOP": {
		"target": "WORKSHOP_ADV", "requires_tech": "FORESTRY_9",
		"name": "Großwerkstatt", "desc": "Mehr Arbeiterplätze und schnellere Werkzeugproduktion.",
		"costs": {"WOOD": 30, "STONE": 15, "TOOLS": 5}, "construction_work": 55
	},
	"QUARRY": {
		"target": "QUARRY_ADV", "requires_tech": "MINING_5",
		"name": "Großsteinbruch", "desc": "Größerer Sammelradius und mehr Arbeiterplätze.",
		"costs": {"WOOD": 25, "STONE": 15, "TOOLS": 5}, "construction_work": 55
	},
	"DAM": {
		"target": "DAM_ADV", "requires_tech": "WATER_9",
		"name": "Schleuse", "desc": "Hält deutlich mehr Wasser zurück als ein einfacher Damm.",
		"costs": {"STONE": 25, "PLANKS": 15}, "construction_work": 45
	},
	"GARDEN": {
		"target": "GARDEN_ADV", "requires_tech": "FARMING_9",
		"name": "Gewächshaus", "desc": "Mehr Ertrag, unabhängig von der Jahreszeit.",
		"costs": {"PLANKS": 20, "STONE": 10}, "construction_work": 45
	},
	"HOUSE": {
		"target": "HOUSE_ADV", "requires_tech": "BREEDING_6",
		"name": "Großes Wohnhaus", "desc": "Zwei zusätzliche Schlafplätze und etwas mehr Wohnkomfort.",
		"costs": {"WOOD": 25, "STONE": 10}, "construction_work": 40
	},
	"CONSTRUCTION_YARD_1": {
		"target": "CONSTRUCTION_YARD_1_ADV", "requires_tech": "LOGISTICS_6",
		"name": "Großbauhof", "desc": "Mehr Arbeiterplätze für schnelleren Baufortschritt.",
		"costs": {"WOOD": 30, "STONE": 15}, "construction_work": 50
	},
	"STORAGE": {
		"target": "STORAGE_ADV", "requires_tech": "LOGISTICS_7",
		"name": "Großlagerhaus", "desc": "Deutlich mehr Lagerkapazität und ein weiterer Arbeiterplatz.",
		"costs": {"WOOD": 25, "STONE": 5}, "construction_work": 35
	}
}

const PATH_TYPES: Dictionary = {
	"DIRT": {
		"name": "Weg", "costs": {"WOOD": 1},
		"color": Color(0.56, 0.42, 0.28), "icon": "🟫"
	},
	"STONE": {
		"name": "Steinweg", "costs": {"STONE": 1},
		"color": Color(0.58, 0.58, 0.60), "icon": "⬜"
	},
	"PLANKS": {
		"name": "Holzplankenweg", "costs": {"PLANKS": 1},
		"color": Color(0.72, 0.56, 0.35), "icon": "🟧"
	}
}

const RESOURCE_ICONS: Dictionary = {
	"WOOD": "🪵", "STONE": "🪨", "BERRIES": "🫐", "WATER": "💧",
	# Bug-Fix (v14.0, gemeldet: "Zeichen von verarbeitetem Holz soll anders
	# aussehen als unverarbeitetes"): PLANKS nutzte bisher DASSELBE Icon "🪵"
	# wie rohes WOOD - im Lager/HUD/an Gebäuden war ein Stapel Bretter optisch
	# nicht von einem Stapel Rohholz zu unterscheiden. Jetzt eigenes Icon.
	"PLANKS": "🟫", "TOOLS": "🔨", "FOOD": "🍱", "IRON": "🔩",
	"IRON_BARS": "⚙️", "MACHINES": "🤖", "COAL": "⚫", "STEEL": "🔵",
	"MEAT": "🥩", "WHEAT": "🌾", "COOKED_MEAT": "🍗",
	"BREAD": "🍞", "STEW": "🍲", "DYNAMITE": "🧨", "SCIENCE": "🔬"
}

const PRODUCTION_CHAINS: Dictionary = {
	"PLANKS":      {"inputs": {"WOOD": 2},             "output": 1, "time": 3.0},
	"TOOLS":       {"inputs": {"WOOD": 1, "STONE": 2}, "output": 1, "time": 5.0},
	"FOOD":        {"inputs": {"BERRIES": 2},           "output": 2, "time": 4.0},
	"COOKED_MEAT": {"inputs": {"MEAT": 2},              "output": 3, "time": 5.0},
	"BREAD":       {"inputs": {"WHEAT": 3},             "output": 2, "time": 6.0},
	"STEW":        {"inputs": {"COOKED_MEAT": 1, "BERRIES": 1}, "output": 3, "time": 8.0},
	"IRON_BARS":   {"inputs": {"IRON": 2, "WOOD": 1},  "output": 1, "time": 6.0},
	"MACHINES":    {"inputs": {"IRON_BARS": 3, "TOOLS": 1}, "output": 1, "time": 10.0},
	"STEEL":       {"inputs": {"IRON_BARS": 2, "COAL": 1}, "output": 1, "time": 8.0},
	"DYNAMITE":    {"inputs": {"COAL": 3, "IRON": 2},  "output": 2, "time": 8.0}
}

## Feature (v11.1, Logistik-Feinschliff): wählbare Filter-Ressourcen für die
## Lagerhaus-Spezialisierung (BuildingEntity.storage_filter). Ein Lagerhaus
## mit gesetztem Filter nimmt nur noch diese eine Ressource von Haulern/
## Lagerarbeitern an - alle anderen Ressourcen werden zu einem anderen,
## unspezialisierten oder passend gefilterten Lagerhaus getragen. "" (leer)
## bedeutet "akzeptiert alles" und ist der Standard.
const STORAGE_FILTER_OPTIONS: Array[String] = [
	"WOOD", "STONE", "BERRIES", "IRON", "COAL",
	"PLANKS", "TOOLS", "MEAT", "WHEAT",
	"COOKED_MEAT", "BREAD", "STEW",
	"IRON_BARS", "MACHINES", "STEEL", "DYNAMITE"
]

static func get_building(id: String) -> Dictionary:
	return BUILDINGS.get(id, {})

static func get_building_names_by_epoch(epoch: int) -> Array[String]:
	var result: Array[String] = []
	for id in BUILDINGS:
		if BUILDINGS[id].get("epoch", 1) == epoch:
			result.append(id)
	return result
