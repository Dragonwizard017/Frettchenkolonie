## WorldRenderer3D.gd
## Rendert die Spielwelt vollständig in 3D.
## Terrain = ein zusammengesetztes ArrayMesh, pro Biom eine Oberseiten-
## Textur (copyright-freies isometrisches Tileset) + Vertex-Farbe als
## multiplikativer Tönungs-Layer (Dürre/Weg/austrocknendes Flussbett).
## Gebäude = individuelle StaticBody3D + BoxMesh + Label3D.
## Frettchen = SphereMesh die sich auf ihren Tile-Koordinaten bewegen.
class_name WorldRenderer3D
extends Node3D

# ── Konstanten ────────────────────────────────────────────────────────────────
const TILE_SIZE:    float = 2.0   # Welteinheiten pro Tile
const HEIGHT_SCALE: float = 1.2   # Tile-Höhe in Welteinheiten
const FERRET_Y:     float = 0.35  # Frettchen-Offset über Boden

# Baum-Modell: ersetzt die reine Forest-Einfärbung des Terrains durch echte
# 3D-Bäume auf jedem Tile mit einem Holz-Resource-Node.
const PINE_TREE_SCENE: PackedScene = preload("res://assets/pine_tree.glb")
const TREE_BASE_SCALE: float = 0.6  # Modell ist ~4.7 Welteinheiten hoch (roh)
# Beerenbusch-Modell: auf jedem Tile mit einem Beeren-Resource-Node.
const BUSH_SCENE: PackedScene = preload("res://assets/bush.glb")
const BUSH_BASE_SCALE: float = 0.46  # Modell ist ~1.27 Welteinheiten hoch (roh)
var _bushes_node: Node3D = null
# Bug-Fix (v14.3, gemeldet: "was ist Stein, wo ist Eisen"): STONE- und
# IRON-Resource-Nodes existierten in den Tile-Daten von Anfang an genauso
# wie WOOD/BERRIES, hatten aber - anders als Bäume (pine_tree.glb) und
# Büsche (bush.glb) - NIE ein eigenes 3D-Modell bekommen. Auf der Karte war
# dadurch komplett unsichtbar, wo überhaupt Stein/Eisen zu finden ist - nur
# Gras. Es gibt kein eigenes Fels-/Erz-Modell im Projekt, daher werden hier
# einfache, aber klar erkennbare prozedurale Felsbrocken-Cluster gebaut
# (STONE = grau, IRON = dunkler mit rostroten Erzadern) plus - für maximale
# Klarheit - ein schwebendes Icon darüber, genau wie bei Gebäuden/Fabriken.
var _rocks_node: Node3D = null
var _ore_node: Node3D = null
const ROCK_BASE_SCALE: float = 1.0

## Feature (v13.3, Performance): LOD-System - Frettchen die nicht sichtbar sind
## oder >20 Tiles entfernt nicht jeden Frame updaten (reduziert Rechenleistung)
var _ferret_lod_distance: float = 20.0
var _last_lod_update: float = 0.0
# Gebäude-Modell (v10.19): nutzt das "Building"-Asset (assets/building.glb)
# für ALLE fertig gebauten Gebäudetypen statt des in v10.16-v10.18
# verwendeten house.glb. Grund (Nutzer-Feedback): house.glb sollte nicht mehr
# als Gebäude-Darstellung dienen.
# v10.20: das Modell wurde durch eine Version mit 7 getrennten Material-
# Flächen ersetzt ("Dach", "Pfeiler_Holzbalken", "Wand", "Gras_Busch",
# "Fenster_Dunkel", "Schornstein", "Sockel_Stein" - gleiche Geometrie/
# Bounding-Box wie zuvor, nur die Zuordnung der Dreiecke zu Materialien ist
# neu). Dadurch färbt _tint_building_wall() jetzt gezielt NUR die
# "Wand"-Fläche in der jeweiligen BUILDING_VISUALS-Gebäudefarbe ein - Dach,
# Fensterrahmen, Schornstein, Sockel etc. behalten ihr Original-Material/
# -Aussehen bei, statt wie bisher (material_override auf der ganzen
# MeshInstance3D) komplett übermalt zu werden.
# Skalierung weiterhin pro Gebäude aus der individuellen Ziel-Höhe "bh"
# berechnet statt eines festen Werts (siehe BUILDING_MODEL_RAW_HEIGHT unten).
const BUILDING_SCENE: PackedScene = preload("res://assets/building.glb")
## Rohmodell-Bounding-Box (per Skript aus den Vertex-Positionen ermittelt):
## Y reicht von ca. -1.00 bis +0.995, d.h. roh ca. 1.995 hoch, mit dem
## Mesh-Ursprung in der MITTE des Modells (nicht am Boden!). Wird benutzt, um
## die Modell-Skalierung passend zur jeweiligen Gebäude-Zielhöhe "bh" zu
## berechnen (scale = bh / RAW_HEIGHT).
const BUILDING_MODEL_RAW_HEIGHT: float = 1.995
## Bug-Fix (v10.19, "Häuser stehen im Boden"): der Modell-Ursprung liegt in
## der Mitte statt am Boden des Mesh - ohne Korrektur ragt die untere Hälfte
## des Modells unter die Tile-Oberfläche. Dieser Wert ist der Abstand
## (in rohen, unskalierten Modell-Einheiten) vom Ursprung zur Unterkante des
## Mesh und wird nach dem Skalieren als Y-Offset auf das Modell angewendet,
## damit sein Boden exakt auf der Tile-Oberfläche (y=0 relativ zum
## Gebäude-Root) aufsteht statt zur Hälfte im Boden zu versinken.
const BUILDING_MODEL_BOTTOM_OFFSET: float = 1.0
## Globaler Korrekturfaktor zusätzlich zur Höhen-Skalierung, falls das
## Modell auf allen Gebäuden insgesamt zu klein/gross wirkt: hier anpassen.
const BUILDING_MODEL_SCALE_FACTOR: float = 1.15
## Falls das Modell nach dem Import seitlich verdreht steht: hier in
## 90°-Schritten (PI/2) anpassen (gleiches Muster wie FERRET_ROT_OFFSET).
const BUILDING_ROT_OFFSET: float = 0.0

# v12.8: eigene Modelle für Brunnen (WELL) und Lager (STORAGE) statt des
# generischen building.glb - per KI generiert (Fast3D.io) und anschliessend
# nachträglich in dieselben 4 Material-Flächen aufgeteilt/eingefärbt wie
# building.glb ("Sockel_Stein", "Wand", "Pfeiler_Holzbalken", "Dach"), damit
# _tint_building_wall() weiterhin nur die "Wand"-Fläche in der jeweiligen
# BUILDING_VISUALS-Farbe einfärbt. Rohmodell-Bounding-Box je Modell einzeln
# ermittelt (Ursprung jeweils in der Mitte, daher eigener BOTTOM_OFFSET).
const WELL_SCENE: PackedScene = preload("res://assets/well_building.glb")
const WELL_MODEL_RAW_HEIGHT: float = 1.99
const WELL_MODEL_BOTTOM_OFFSET: float = 0.995
const STORAGE_SCENE: PackedScene = preload("res://assets/storage_building.glb")
const STORAGE_MODEL_RAW_HEIGHT: float = 2.33
const STORAGE_MODEL_BOTTOM_OFFSET: float = 1.165
const WATER_TOWER_SCENE: PackedScene = preload("res://assets/water_tower.glb")
const WATER_TOWER_MODEL_RAW_HEIGHT: float = 4.0
const WATER_TOWER_MODEL_BOTTOM_OFFSET: float = 2.0
const STATUE_SCENE: PackedScene = preload("res://assets/statue.glb")
const STATUE_MODEL_RAW_HEIGHT: float = 3.355
const STATUE_MODEL_BOTTOM_OFFSET: float = 1.6775
## Ordnet einem Gebäudetyp (BuildingEntity.id) ein eigenes Modell zu, falls
## vorhanden. Gebäudetypen, die hier NICHT gelistet sind, nutzen weiterhin
## das generische BUILDING_SCENE (building.glb).
const BUILDING_MODEL_OVERRIDES: Dictionary = {
	"WELL":    {"scene": WELL_SCENE,    "raw_h": WELL_MODEL_RAW_HEIGHT,    "bottom_off": WELL_MODEL_BOTTOM_OFFSET},
	"STORAGE": {"scene": STORAGE_SCENE, "raw_h": STORAGE_MODEL_RAW_HEIGHT, "bottom_off": STORAGE_MODEL_BOTTOM_OFFSET},
	"WATER_TOWER": {"scene": WATER_TOWER_SCENE, "raw_h": WATER_TOWER_MODEL_RAW_HEIGHT, "bottom_off": WATER_TOWER_MODEL_BOTTOM_OFFSET},
	"STATUE": {"scene": STATUE_SCENE, "raw_h": STATUE_MODEL_RAW_HEIGHT, "bottom_off": STATUE_MODEL_BOTTOM_OFFSET},
}
# Frettchen-Modell: ersetzt die bisherige reine Platzhalter-Kugel.
const FERRET_SCENE: PackedScene = preload("res://assets/ferret.glb")
const FERRET_MODEL_SCALE: float = 2.2
## Feature (v11.9, Legendäre Frettchen): Accessoire-Modelle vorab geladen -
## Slot-/Offset-Daten stehen in FerretAccessories.gd (Datenülle), hier nur
## die tatsächlichen PackedScene-Referenzen zum Instanziieren.
const ACCESSORY_SCENES: Dictionary = {
	"CROWN": preload("res://assets/accessories/crown.glb"),
	"TOP_HAT": preload("res://assets/accessories/top_hat.glb"),
	"WIZARD_HAT": preload("res://assets/accessories/wizard_hat.glb"),
	"BANDANA": preload("res://assets/accessories/bandana.glb"),
	"BOWTIE": preload("res://assets/accessories/bowtie.glb"),
	"SCARF": preload("res://assets/accessories/scarf.glb"),
	"MEDAL": preload("res://assets/accessories/medal.glb"),
	"MONOCLE": preload("res://assets/accessories/monocle.glb"),
	"EYEPATCH": preload("res://assets/accessories/eyepatch.glb"),
	"CAPE": preload("res://assets/accessories/cape.glb"),
}
## Feature (v11.9, Frettchen-Klick-Interaktion): Frettchen haben keine
## Collision-Shapes (anders als Gebäude, siehe GameController._screen_to_tile()
## mit PhysicsRayQueryParameters3D) - Klick-Erkennung läuft stattdessen über
## Bildschirm-Projektion, siehe find_ferret_at_screen_pos() weiter unten.
const FERRET_CLICK_RADIUS_PX: float = 28.0
## Falls das Modell nach dem Import in die falsche Richtung schaut: hier in
## 90°-Schritten (PI/2) anpassen, z.B. PI für "schaut nach hinten".
const FERRET_ROT_OFFSET: float = 0.0
var _trees_node: Node3D = null
# Feature (v10.10): merkt sich Baum-/Busch-Node + ursprüngliche Skalierung
# pro Tile, damit refresh_vegetation() sie je nach Rest-Ressourcenmenge
# (resource_node.amount / max_amount) dynamisch verkleinern/vergrössern kann
# - sichtbares Abholzen/Abpflücken + Nachwachsen, ohne das Mesh neu bauen
# zu müssen.
var _tree_nodes: Dictionary = {}   # "tx,ty" -> {"node": Node3D, "base_scale": float}
var _bush_nodes: Dictionary = {}   # "tx,ty" -> {"node": Node3D, "base_scale": float}
var _rock_nodes: Dictionary = {}   # "tx,ty" -> {"node": Node3D, "base_scale": float} (STONE)
var _ore_nodes: Dictionary = {}    # "tx,ty" -> {"node": Node3D, "base_scale": float} (IRON)

# ── Terrain-Texturen (Tileset-Grafiktausch) ──────────────────────────────────
# Copyright-freies isometrisches Tileset (32x32 Pixelart, ein Tile pro Biom).
# Jede Biom-Oberseite bekommt ihre eigene Textur + eigenes Material/Surface;
# die Vertex-Farbe ist standardmässig WEISS (Textur unverändert sichtbar)
# und wird nur in Sonderfällen (Dürre/Weg/austrocknendes Flussbett) als
# multiplikativer Tönungs-Layer Richtung einer Zielfarbe gelerpt
# (siehe _build_terrain_mesh).
const TILE_TEXTURES: Dictionary = {
	"PLAINS":   preload("res://assets/tiles/plains.png"),
	"FOREST":   preload("res://assets/tiles/forest.png"),
	"BEACH":    preload("res://assets/tiles/beach.png"),
	"HILLS":    preload("res://assets/tiles/hills.png"),
	"MOUNTAIN": preload("res://assets/tiles/mountain.png"),
	"WATER":    preload("res://assets/tiles/water.png"),
}
# Feature (v11.2-Hotfix, Seiten-Texturen): eigene prozedurale Seiten-Texturen
# pro Biom (erzeugt via Python/Pillow in assets/tiles/*_side.png). Timberborn-
# Style: PLAINS/FOREST zeigen Grasboden-Erde-Schichten, BEACH hellen Sand,
# HILLS trockenen Lehm, MOUNTAIN Steinmauerwerk, WATER nasse dunkle Erde.
const TILE_SIDE_TEXTURES: Dictionary = {
	"PLAINS":   preload("res://assets/tiles/plains_side.png"),
	"FOREST":   preload("res://assets/tiles/forest_side.png"),
	"BEACH":    preload("res://assets/tiles/beach_side.png"),
	"HILLS":    preload("res://assets/tiles/hills_side.png"),
	"MOUNTAIN": preload("res://assets/tiles/mountain_side.png"),
	"WATER":    preload("res://assets/tiles/water_side.png"),
}
var _top_materials:  Dictionary = {} # Biom-Name -> StandardMaterial3D (Cache)
var _side_materials: Dictionary = {} # Biom-Name -> StandardMaterial3D (Cache)

# ── Biom-Farben ───────────────────────────────────────────────────────────────
# Seit dem Tileset-Grafiktausch liefert die Textur die Grundfarbe der
# Oberseite; BIOME_TOP wird daher nicht mehr aktiv genutzt (nur als
# Referenz/Fallback erhalten). BIOME_SIDE färbt weiterhin die meist
# verdeckten Seitenflächen der Klippen (keine Textur dort).
const BIOME_TOP: Dictionary = {
	"WATER":    Color(0.20, 0.48, 0.82),
	"BEACH":    Color(0.91, 0.86, 0.64),
	"PLAINS":   Color(0.42, 0.72, 0.32),
	"FOREST":   Color(0.24, 0.54, 0.22),
	"HILLS":    Color(0.58, 0.54, 0.40),
	"MOUNTAIN": Color(0.68, 0.65, 0.62),
}
const BIOME_SIDE: Dictionary = {
	"WATER":    Color(0.14, 0.35, 0.65),
	"BEACH":    Color(0.76, 0.72, 0.50),
	"PLAINS":   Color(0.30, 0.56, 0.22),
	"FOREST":   Color(0.16, 0.40, 0.14),
	"HILLS":    Color(0.44, 0.42, 0.30),
	"MOUNTAIN": Color(0.50, 0.48, 0.46),
}

# ── Gebäude-Visuals (Farbe + Höhe in Welteinheiten) ──────────────────────────
const BUILDING_VISUALS: Dictionary = {
	"CONSTRUCTION_YARD_1": {"color": Color(0.85,0.72,0.20), "h": 2.2},
	"CONSTRUCTION_YARD_2": {"color": Color(0.85,0.72,0.20), "h": 2.6},
	"ENGINEERS_GUILD":     {"color": Color(0.80,0.65,0.15), "h": 3.0},
	"CONSTRUCTION_OFFICE": {"color": Color(0.80,0.65,0.15), "h": 3.2},
	"LUMBERJACK":          {"color": Color(0.50,0.30,0.12), "h": 1.8},
	"QUARRY":              {"color": Color(0.62,0.60,0.55), "h": 1.2},
	"BERRY_GATHERER":      {"color": Color(0.65,0.25,0.45), "h": 1.5},
	"WELL":                {"color": Color(0.40,0.62,0.88), "h": 1.6},
	"WATER_TOWER":         {"color": Color(0.50,0.65,0.78), "h": 3.8},
	"WATER_PUMP":          {"color": Color(0.45,0.60,0.75), "h": 2.2},
	"AQUEDUCT":            {"color": Color(0.70,0.82,0.90), "h": 1.5},
	"RESERVOIR":           {"color": Color(0.30,0.55,0.80), "h": 1.2},
	"IRRIGATION":          {"color": Color(0.40,0.62,0.88), "h": 0.5},
	"STORAGE":             {"color": Color(0.88,0.68,0.32), "h": 2.2},
	"LARGE_STORAGE":       {"color": Color(0.82,0.60,0.28), "h": 2.8},
	"FOOD_STORE":          {"color": Color(0.75,0.88,0.50), "h": 2.4},
	"WAREHOUSE":           {"color": Color(0.80,0.65,0.30), "h": 3.0},
	"HOUSE":               {"color": Color(0.88,0.48,0.28), "h": 2.5},
	"GATHERING_PLACE":     {"color": Color(0.92,0.78,0.40), "h": 1.5},
	"TAVERN":              {"color": Color(0.80,0.35,0.18), "h": 2.8},
	"BATHHOUSE":           {"color": Color(0.62,0.72,0.88), "h": 2.6},
	"THEATER":             {"color": Color(0.72,0.30,0.62), "h": 3.5},
	"GARDEN":              {"color": Color(0.35,0.78,0.35), "h": 0.6},
	"FARMHOUSE":           {"color": Color(0.75,0.45,0.20), "h": 2.2},
	"FORESTER":            {"color": Color(0.20,0.55,0.20), "h": 1.8},
	"SAWMILL":             {"color": Color(0.55,0.35,0.15), "h": 2.0},
	"WORKSHOP":            {"color": Color(0.70,0.55,0.35), "h": 2.2},
	"COOKHOUSE":           {"color": Color(0.75,0.40,0.20), "h": 2.0},
	"HUNTER_HUT":          {"color": Color(0.45,0.30,0.18), "h": 1.8},
	"EXPEDITION_CAMP":     {"color": Color(0.60,0.55,0.38), "h": 1.5},
	"GRAVEYARD":           {"color": Color(0.40,0.42,0.42), "h": 0.8},
	"IRON_MINE":           {"color": Color(0.50,0.48,0.45), "h": 2.0},
	"COAL_MINE":           {"color": Color(0.25,0.25,0.28), "h": 1.8},
	"SMELTER":             {"color": Color(0.80,0.35,0.10), "h": 3.0},
	"BLAST_FURNACE":       {"color": Color(0.85,0.30,0.08), "h": 3.5},
	"MACHINE_FACTORY":     {"color": Color(0.40,0.40,0.50), "h": 3.8},
	"WATERWHEEL":          {"color": Color(0.55,0.42,0.22), "h": 2.5},
	"DAM":                 {"color": Color(0.52,0.48,0.42), "h": 1.6},
	"STATUE":              {"color": Color(0.85,0.82,0.72), "h": 4.0},
	"DYNAMITE_WORKSHOP":   {"color": Color(0.75,0.15,0.15), "h": 2.0},
	"DECO_FLOWERS":        {"color": Color(0.95,0.55,0.70), "h": 0.4},
	"DECO_MUSHROOM":       {"color": Color(0.85,0.30,0.20), "h": 0.6},
	"DECO_LANTERN":        {"color": Color(0.95,0.90,0.40), "h": 0.8},
	"DECO_STONES":         {"color": Color(0.60,0.58,0.55), "h": 0.5},
	"DECO_BUSH":           {"color": Color(0.30,0.65,0.25), "h": 0.7},
}

const BUILDING_EMOJIS: Dictionary = {
	"CONSTRUCTION_YARD_1":"🏗","CONSTRUCTION_YARD_2":"🏗",
	"ENGINEERS_GUILD":"🏗","CONSTRUCTION_OFFICE":"🏗",
	"LUMBERJACK":"🪓","QUARRY":"⛏","BERRY_GATHERER":"🫐",
	"WELL":"🪣","WATER_TOWER":"⛲","WATER_PUMP":"🚿",
	"AQUEDUCT":"🌊","IRRIGATION":"💧","RESERVOIR":"🏗",
	"STORAGE":"📦","LARGE_STORAGE":"📦","FOOD_STORE":"🍱",
	"WAREHOUSE":"📦","HOUSE":"🏠","GATHERING_PLACE":"🎪",
	"TAVERN":"🍺","BATHHOUSE":"🛁","THEATER":"🎭",
	"GARDEN":"🌻","FARMHOUSE":"🚜",
	"FORESTER":"🌲","SAWMILL":"🪚","WORKSHOP":"🔨",
	"COOKHOUSE":"🍲","HUNTER_HUT":"🏹","EXPEDITION_CAMP":"🗺",
	"GRAVEYARD":"🪦","IRON_MINE":"⛏","COAL_MINE":"⚫",
	"SMELTER":"🔥","BLAST_FURNACE":"🔥","MACHINE_FACTORY":"🤖",
	"WATERWHEEL":"⚙","STATUE":"🗿","DYNAMITE_WORKSHOP":"🧨",
	"DAM":"🧱",
	"DECO_FLOWERS":"🌸","DECO_MUSHROOM":"🍄","DECO_LANTERN":"🪔",
	"DECO_STONES":"🪨","DECO_BUSH":"🌿",
}

# ── State ─────────────────────────────────────────────────────────────────────
var world:    Array = []
var world_w:  int   = 60
var world_h:  int   = 60
var is_drought: bool = false

# Selektion / Ghost
var selected_tile:     Vector2i = Vector2i(-1, -1)
var selected_building: BuildingEntity = null

# ── Interne Nodes ─────────────────────────────────────────────────────────────
var _terrain_node:    MeshInstance3D = null
var _water_node:      MeshInstance3D = null
var _col_body:        StaticBody3D   = null
var _building_root:   Node3D         = null
var _building_nodes:  Dictionary     = {}   # "tx,ty" → StaticBody3D
# Feature (v11.0, Lagersystem): "tx,ty" → Label3D mit dem Füllstand des
# lokalen Lagers eines Produktionsgebäudes - separat von _building_nodes,
# damit refresh_storage_labels() den Text aktualisieren kann, ohne jedesmal
# das komplette Gebäude neu aufzubauen.
var _storage_labels:  Dictionary     = {}
# Feature (v11.1, Logistik-Feinschliff): ein einzelner ImmediateMesh-Node für
# alle aktuell aktiven Hauler-Linien (Pfeile/Linien zwischen Start und Ziel
# eines Transports) - wird periodisch komplett neu gezeichnet statt pro
# Linie einen eigenen Node zu verwalten, da sich die Anzahl aktiver Hauls
# ständig ändert.
var _haul_line_node:  MeshInstance3D  = null
var _haul_line_mesh:  ImmediateMesh   = null
# Feature (v11.1, Logistik-Feinschliff): zweites Overlay, gezeichnet nur beim
# Anklicken eines Gebäudes - zeigt die POTENZIELLE Lieferkette (Produktions-
# gebäude → Lagerhaus → Baustelle), nicht nur aktiv laufende Transporte.
var _chain_line_node: MeshInstance3D  = null
var _chain_line_mesh: ImmediateMesh   = null
var _ferret_root:     Node3D         = null
var _ferret_nodes:    Array          = []
var _highlight_node:  MeshInstance3D = null
var _ghost_node:      MeshInstance3D = null

# ── Materialien ───────────────────────────────────────────────────────────────
var _sel_mat:   StandardMaterial3D = null
var _ghost_mat: StandardMaterial3D = null

# ══════════════════════════════════════════════════════════════════════════════
func _ready() -> void:
	_building_root = Node3D.new(); _building_root.name = "Buildings"
	add_child(_building_root)
	_ferret_root = Node3D.new(); _ferret_root.name = "Ferrets"
	add_child(_ferret_root)
	_create_highlight()
	_create_ghost()
	_create_ghost_radius()
	_create_haul_lines()
	_create_chain_lines()
	_create_tutorial_marker()

# ── Koordinaten ───────────────────────────────────────────────────────────────
func tile_to_world3d(tx: int, ty: int) -> Vector3:
	if world.is_empty():
		return Vector3(float(tx) * TILE_SIZE + TILE_SIZE * 0.5, 0.0,
					   float(ty) * TILE_SIZE + TILE_SIZE * 0.5)
	if tx < 0 or ty < 0 or tx >= world_w or ty >= world_h:
		return Vector3(float(tx) * TILE_SIZE + TILE_SIZE * 0.5, 0.0,
					   float(ty) * TILE_SIZE + TILE_SIZE * 0.5)
	var tile: Dictionary = (world[tx] as Array)[ty] as Dictionary
	var h: float = float(tile.get("height", 0.0)) * HEIGHT_SCALE
	return Vector3(
		float(tx) * TILE_SIZE + TILE_SIZE * 0.5,
		h,
		float(ty) * TILE_SIZE + TILE_SIZE * 0.5
	)

func world3d_to_tile(pos: Vector3) -> Vector2i:
	return Vector2i(
		int(pos.x / TILE_SIZE),
		int(pos.z / TILE_SIZE)
	)

func map_center_3d() -> Vector3:
	@warning_ignore("integer_division")
	return tile_to_world3d(world_w / 2, world_h / 2)

# ══════════════════════════════════════════════════════════════════════════════
# WELT BAUEN
# ══════════════════════════════════════════════════════════════════════════════
func build_world() -> void:
	_clear_all()
	_build_terrain_mesh()
	_build_collision()
	_build_water_mesh(world)
	_rebuild_all_buildings()
	_place_trees()
	_place_bushes()
	_place_rocks()
	_place_ore_deposits()

func _clear_all() -> void:
	if _terrain_node: _terrain_node.queue_free(); _terrain_node = null
	if _water_node:   _water_node.queue_free();   _water_node   = null
	if _col_body:     _col_body.queue_free();     _col_body = null
	if _trees_node:   _trees_node.queue_free();   _trees_node = null
	if _rocks_node:   _rocks_node.queue_free();   _rocks_node = null
	if _ore_node:     _ore_node.queue_free();     _ore_node   = null
	for key in _building_nodes:
		(_building_nodes[key] as Node).queue_free()
	_building_nodes.clear()
	_storage_labels.clear()
	_clear_ferrets()

## Stellt echte 3D-Bäume (Kiefer, GLB-Modell) auf jedes Tile, das einen
## Holz-Resource-Node trägt (gesetzt vom WorldGenerator auf ~35% der
## FOREST-Tiles). Ersetzt die bisherige rein farbliche "Wald"-Darstellung.
func _place_trees() -> void:
	if _trees_node:
		_trees_node.queue_free()
		_trees_node = null
	_tree_nodes.clear()
	_trees_node = Node3D.new()
	_trees_node.name = "Trees"
	add_child(_trees_node)
	for x in world_w:
		var col: Array = world[x] as Array
		for y in world_h:
			var tile: Dictionary = col[y] as Dictionary
			if tile.get("building") != null: continue
			var node_data = tile.get("resource_node")
			if node_data == null or not (node_data is Dictionary): continue
			if str((node_data as Dictionary).get("type","")) != "WOOD": continue
			var tree := PINE_TREE_SCENE.instantiate() as Node3D
			var base_pos: Vector3 = tile_to_world3d(x, y)
			# leichter Zufalls-Versatz innerhalb des Tiles, sonst wirkt es zu gitterartig
			base_pos.x += randf_range(-TILE_SIZE*0.28, TILE_SIZE*0.28)
			base_pos.z += randf_range(-TILE_SIZE*0.28, TILE_SIZE*0.28)
			tree.position = base_pos
			tree.rotation.y = randf_range(0.0, TAU)
			# Deutlich sichtbare Grössen-/Höhenvarianz (vorher nur ±15%,
			# wirkte zu gleichförmig) - von kleinen Jungbäumen bis zu
			# grossen, alten Bäumen in derselben Waldfläche.
			var s: float = TREE_BASE_SCALE * randf_range(0.65, 1.45)
			tree.scale = Vector3(s, s, s)
			_trees_node.add_child(tree)
			_tree_nodes["%d,%d" % [x, y]] = {"node": tree, "base_scale": s}

func _place_bushes() -> void:
	if _bushes_node:
		_bushes_node.queue_free()
		_bushes_node = null
	_bush_nodes.clear()
	_bushes_node = Node3D.new()
	_bushes_node.name = "Bushes"
	add_child(_bushes_node)
	for x in world_w:
		var col: Array = world[x] as Array
		for y in world_h:
			var tile: Dictionary = col[y] as Dictionary
			if tile.get("building") != null: continue
			var node_data = tile.get("resource_node")
			if node_data == null or not (node_data is Dictionary): continue
			if str((node_data as Dictionary).get("type","")) != "BERRIES": continue
			var bush := BUSH_SCENE.instantiate() as Node3D
			var base_pos: Vector3 = tile_to_world3d(x, y)
			base_pos.x += randf_range(-TILE_SIZE*0.22, TILE_SIZE*0.22)
			base_pos.z += randf_range(-TILE_SIZE*0.22, TILE_SIZE*0.22)
			bush.position = base_pos
			bush.rotation.y = randf_range(0.0, TAU)
			var s: float = BUSH_BASE_SCALE * randf_range(0.75, 1.3)
			bush.scale = Vector3(s, s, s)
			_bushes_node.add_child(bush)
			_bush_nodes["%d,%d" % [x, y]] = {"node": bush, "base_scale": s}

## Baut einen kleinen, prozeduralen Felsbrocken-Cluster (2-3 unregelmässig
## rotierte/skalierte Boxen) - es gibt kein fertiges Fels-GLB im Projekt,
## das hier reicht aber für klare Erkennbarkeit locker aus. Bei Erz (IRON)
## zusätzlich rostrote/orange "Adern" als kleine Akzent-Boxen, damit Stein
## und Eisen sich auch farblich klar unterscheiden.
func _make_rock_cluster(is_ore: bool) -> Node3D:
	var root := Node3D.new()
	var base_color: Color = Color(0.42, 0.41, 0.40) if not is_ore else Color(0.30, 0.28, 0.27)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = base_color
	mat.roughness = 0.95
	var chunk_count: int = 2 + (1 if randf() < 0.5 else 0)
	for i in chunk_count:
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var w: float = randf_range(0.35, 0.6)
		bm.size = Vector3(w, w * randf_range(0.55, 0.85), w * randf_range(0.8, 1.1))
		box.mesh = bm
		box.material_override = mat
		box.position = Vector3(randf_range(-0.18, 0.18), bm.size.y * 0.5 * 0.8, randf_range(-0.18, 0.18))
		box.rotation = Vector3(randf_range(-0.15, 0.15), randf_range(0.0, TAU), randf_range(-0.15, 0.15))
		box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(box)
	if is_ore:
		var ore_mat := StandardMaterial3D.new()
		ore_mat.albedo_color = Color(0.72, 0.38, 0.18)
		ore_mat.emission_enabled = true
		ore_mat.emission = Color(0.55, 0.25, 0.08)
		ore_mat.emission_energy_multiplier = 0.35
		var vein_count: int = 2 + (1 if randf() < 0.5 else 0)
		for i in vein_count:
			var vein := MeshInstance3D.new()
			var vm := BoxMesh.new()
			vm.size = Vector3(0.14, 0.10, 0.14)
			vein.mesh = vm
			vein.material_override = ore_mat
			vein.position = Vector3(randf_range(-0.22, 0.22), randf_range(0.15, 0.35), randf_range(-0.22, 0.22))
			vein.rotation.y = randf_range(0.0, TAU)
			root.add_child(vein)
	return root

## Feature (v14.3): STONE-Resource-Nodes bekommen jetzt einen sichtbaren
## Felsbrocken-Cluster PLUS ein schwebendes "🪨"-Icon (dieselbe Technik wie
## bei den Gebäude-/Fabrik-Icons) - vorher komplett unsichtbares Gras.
func _place_rocks() -> void:
	if _rocks_node:
		_rocks_node.queue_free(); _rocks_node = null
	_rock_nodes.clear()
	_rocks_node = Node3D.new(); _rocks_node.name = "Rocks"
	add_child(_rocks_node)
	for x in world_w:
		var col: Array = world[x] as Array
		for y in world_h:
			var tile: Dictionary = col[y] as Dictionary
			if tile.get("building") != null: continue
			var node_data = tile.get("resource_node")
			if node_data == null or not (node_data is Dictionary): continue
			if str((node_data as Dictionary).get("type", "")) != "STONE": continue
			var rock := _make_rock_cluster(false)
			var base_pos: Vector3 = tile_to_world3d(x, y)
			rock.position = base_pos
			_rocks_node.add_child(rock)
			_rock_nodes["%d,%d" % [x, y]] = {"node": rock, "base_scale": ROCK_BASE_SCALE}
			var lbl := Label3D.new()
			lbl.text = "🪨"
			lbl.pixel_size = 0.006
			lbl.font_size = 46
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.no_depth_test = true
			lbl.modulate = Color(1.0, 1.0, 1.0, 0.85)
			lbl.position = base_pos + Vector3(0.0, 0.9, 0.0)
			_rocks_node.add_child(lbl)

## Feature (v14.3): dasselbe für IRON, mit dunklerem Gestein + rostroten
## Erzadern und einem "⛏️"-Icon statt "🪨" - auf einen Blick von Stein
## unterscheidbar.
func _place_ore_deposits() -> void:
	if _ore_node:
		_ore_node.queue_free(); _ore_node = null
	_ore_nodes.clear()
	_ore_node = Node3D.new(); _ore_node.name = "OreDeposits"
	add_child(_ore_node)
	for x in world_w:
		var col: Array = world[x] as Array
		for y in world_h:
			var tile: Dictionary = col[y] as Dictionary
			if tile.get("building") != null: continue
			var node_data = tile.get("resource_node")
			if node_data == null or not (node_data is Dictionary): continue
			if str((node_data as Dictionary).get("type", "")) != "IRON": continue
			var ore := _make_rock_cluster(true)
			var base_pos: Vector3 = tile_to_world3d(x, y)
			ore.position = base_pos
			_ore_node.add_child(ore)
			_ore_nodes["%d,%d" % [x, y]] = {"node": ore, "base_scale": ROCK_BASE_SCALE}
			var lbl := Label3D.new()
			lbl.text = "⛏️"
			lbl.pixel_size = 0.006
			lbl.font_size = 46
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.no_depth_test = true
			lbl.modulate = Color(1.0, 0.9, 0.75, 0.9)
			lbl.position = base_pos + Vector3(0.0, 0.9, 0.0)
			_ore_node.add_child(lbl)

## Feature (v10.10): wird periodisch (gedrosselt, siehe GameController) auf-
## gerufen, solange das Spiel läuft, und skaliert Bäume/Büsche je nach
## Rest-Ressourcenmenge der zugehörigen Tile (resource_node.amount /
## max_amount) - so sieht man Bäume beim Abholzen schrumpfen und Büsche
## "kahl" werden, und beide wachsen sichtbar wieder, sobald die Quelle
## regeneriert. Eine völlig erschöpfte Quelle bleibt als kleiner, fast
## verschwindender Rest (Stumpf/kahler Strauch) sichtbar statt komplett zu
## verschwinden.
const _MIN_VEGETATION_SCALE: float = 0.22

func refresh_vegetation() -> void:
	_refresh_vegetation_dict(_tree_nodes)
	_refresh_vegetation_dict(_bush_nodes)
	_refresh_vegetation_dict(_rock_nodes)
	_refresh_vegetation_dict(_ore_nodes)
	_spawn_missing_vegetation()

## Bug-Fix (v10.14): Baum-/Busch-Modelle entstehen normalerweise nur EINMAL
## beim initialen Terrain-Aufbau (_place_trees()/_place_bushes()). Neue
## Resource-Nodes, die erst während des Spiels entstehen (z.B. von der
## Försterei gepflanzt, siehe BuildingEntity._plant_trees()), hätten ohne
## diese Funktion KEIN sichtbares Modell - Holzfäller würden "unsichtbare"
## Bäume abholzen. Erkennt solche Fälle und spawnt nachträglich das
## passende Modell (klein startend, wächst dann über die normale
## amount/max_amount-Skalierung in _refresh_vegetation_dict() nach).
func _spawn_missing_vegetation() -> void:
	for x in world_w:
		var col: Array = world[x] as Array
		for y in world_h:
			var tile: Dictionary = col[y] as Dictionary
			if tile.get("building") != null: continue
			var node_data = tile.get("resource_node")
			if node_data == null or not (node_data is Dictionary): continue
			var nd: Dictionary = node_data
			var key: String = "%d,%d" % [x, y]
			var rtype: String = str(nd.get("type", ""))
			if rtype == "WOOD" and not _tree_nodes.has(key):
				var tree := PINE_TREE_SCENE.instantiate() as Node3D
				var base_pos: Vector3 = tile_to_world3d(x, y)
				base_pos.x += randf_range(-TILE_SIZE * 0.28, TILE_SIZE * 0.28)
				base_pos.z += randf_range(-TILE_SIZE * 0.28, TILE_SIZE * 0.28)
				tree.position = base_pos
				tree.rotation.y = randf_range(0.0, TAU)
				var s: float = TREE_BASE_SCALE * randf_range(0.65, 1.45)
				tree.scale = Vector3.ONE * s * _MIN_VEGETATION_SCALE
				_trees_node.add_child(tree)
				_tree_nodes[key] = {"node": tree, "base_scale": s}
			elif rtype == "BERRIES" and not _bush_nodes.has(key):
				var bush := BUSH_SCENE.instantiate() as Node3D
				var base_pos2: Vector3 = tile_to_world3d(x, y)
				base_pos2.x += randf_range(-TILE_SIZE * 0.22, TILE_SIZE * 0.22)
				base_pos2.z += randf_range(-TILE_SIZE * 0.22, TILE_SIZE * 0.22)
				bush.position = base_pos2
				bush.rotation.y = randf_range(0.0, TAU)
				var s2: float = BUSH_BASE_SCALE * randf_range(0.75, 1.3)
				bush.scale = Vector3.ONE * s2 * _MIN_VEGETATION_SCALE
				_bushes_node.add_child(bush)
				_bush_nodes[key] = {"node": bush, "base_scale": s2}
			elif rtype == "STONE" and not _rock_nodes.has(key):
				var rock := _make_rock_cluster(false)
				rock.position = tile_to_world3d(x, y)
				rock.scale = Vector3.ONE * _MIN_VEGETATION_SCALE
				_rocks_node.add_child(rock)
				_rock_nodes[key] = {"node": rock, "base_scale": ROCK_BASE_SCALE}
			elif rtype == "IRON" and not _ore_nodes.has(key):
				var ore := _make_rock_cluster(true)
				ore.position = tile_to_world3d(x, y)
				ore.scale = Vector3.ONE * _MIN_VEGETATION_SCALE
				_ore_node.add_child(ore)
				_ore_nodes[key] = {"node": ore, "base_scale": ROCK_BASE_SCALE}

func _refresh_vegetation_dict(nodes: Dictionary) -> void:
	for key in nodes.keys():
		var entry: Dictionary = nodes[key] as Dictionary
		var node: Node3D = entry.get("node") as Node3D
		if node == null or not is_instance_valid(node): continue
		var coords: PackedStringArray = (key as String).split(",")
		var tx: int = int(coords[0])
		var ty: int = int(coords[1])
		if tx < 0 or tx >= world_w or ty < 0 or ty >= world_h: continue
		var tile: Dictionary = (world[tx] as Array)[ty] as Dictionary
		var node_data = tile.get("resource_node")
		if node_data == null or not (node_data is Dictionary): continue
		var nd: Dictionary = node_data
		var max_amount: float = maxf(1.0, float(nd.get("max_amount", 100.0)))
		var frac: float = clampf(float(nd.get("amount", max_amount)) / max_amount, 0.0, 1.0)
		var base_scale: float = float(entry.get("base_scale", 1.0))
		var scale_mult: float = lerpf(_MIN_VEGETATION_SCALE, 1.0, frac)
		var s: float = base_scale * scale_mult
		node.scale = Vector3(s, s, s)

# ── Terrain-Mesh ──────────────────────────────────────────────────────────────
## Liefert (gecacht) das Textur-Material für ein Biom. Nearest-Filter hält
## den Pixelart-Look des Tilesets scharf statt ihn weichzuzeichnen.
func _get_top_material(biome: String) -> StandardMaterial3D:
	if _top_materials.has(biome):
		return _top_materials[biome]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = TILE_TEXTURES.get(biome, TILE_TEXTURES["PLAINS"]) as Texture2D
	mat.vertex_color_use_as_albedo = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 0.88
	mat.metallic  = 0.0
	_top_materials[biome] = mat
	return mat

func _get_side_material(biome: String) -> StandardMaterial3D:
	if _side_materials.has(biome):
		return _side_materials[biome]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = TILE_SIDE_TEXTURES.get(biome, TILE_SIDE_TEXTURES["PLAINS"]) as Texture2D
	mat.vertex_color_use_as_albedo = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 0.92
	mat.metallic  = 0.0
	# Bug-Fix (v11.3): CULL_DISABLED macht BEIDE Seiten jedes Quads sichtbar,
	# unabhängig von Winding-Order. Damit ist die "zur Kamera zeigende Seite
	# transparent"-Problem garantiert gelöst, auch wenn generate_normals()
	# die Normalen für Backface-Culling-Berechnung durch Averaging verfälscht
	# hätte.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_side_materials[biome] = mat
	return mat

func _build_terrain_mesh() -> void:
	if _terrain_node:
		_terrain_node.queue_free()
		_terrain_node = null

	# Pro Biom je ein SurfaceTool für Oberseiten UND Seitenflächen -
	# dadurch bekommt jede Seitenfläche das richtige Seiten-Material (z.B.
	# MOUNTAIN bekommt Steinmauerwerk-Seiten, PLAINS bekommt Erde-Seiten)
	# anstatt einer einzigen globalen Flat-Color-Seite wie bisher.
	var top_tools:  Dictionary = {}
	var side_tools: Dictionary = {}
	var top_counts:  Dictionary = {}
	var side_counts: Dictionary = {}
	for biome in TILE_TEXTURES.keys():
		var st_t := SurfaceTool.new()
		st_t.begin(Mesh.PRIMITIVE_TRIANGLES)
		st_t.set_material(_get_top_material(biome))
		top_tools[biome] = st_t
		var st_s := SurfaceTool.new()
		st_s.begin(Mesh.PRIMITIVE_TRIANGLES)
		st_s.set_material(_get_side_material(biome))
		side_tools[biome] = st_s
		top_counts[biome]  = 0
		side_counts[biome] = 0

	for x in world_w:
		for z in world_h:
			var tile: Dictionary = (world[x] as Array)[z] as Dictionary
			var biome: String    = str(tile.get("biome", "PLAINS"))
			if not top_tools.has(biome): biome = "PLAINS"
			var h: float         = float(tile.get("height", 0.0)) * HEIGHT_SCALE

			var top_c:  Color = Color.WHITE
			var side_c: Color = Color.WHITE

			if biome == "WATER":
				var wlvl: float = float(tile.get("water_level", 1.0))
				if wlvl < 0.4:
					var mud: Color = Color(0.42, 0.36, 0.24)
					var dry_t: float = 1.0 - clampf(wlvl / 0.4, 0.0, 1.0)
					top_c  = top_c.lerp(mud, dry_t)
					side_c = side_c.lerp(mud.darkened(0.18), dry_t)

			if is_drought and biome in ["PLAINS", "FOREST", "BEACH"]:
				top_c  = top_c.lerp(Color(0.72, 0.60, 0.28), 0.35)
				side_c = side_c.lerp(Color(0.60, 0.48, 0.20), 0.30)

			if tile.get("path") != null:
				top_c = top_c.lerp(Color(0.55, 0.50, 0.40), 0.45)

			# Feature (v14.5, Timberborn-Feld-System): vom Spieler gesetzte
			# Feld-Kacheln werden farblich nach Wachstumszustand eingefärbt -
			# frisch gepflügte Erde (EMPTY), die von Erde zu Grün übergehende
			# Saat (GROWING, siehe growth-Anteil) und reifes Gold (READY).
			# Macht den Feldzustand auf einen Blick sichtbar, ohne eine
			# eigene Vegetations-Mesh-Schicht für Getreide zu brauchen.
			var field = FarmSys.get_field(x, z)
			if field != null:
				var fstate: String = str(field.get("state", "EMPTY"))
				var soil: Color = Color(0.42, 0.32, 0.19)
				if fstate == "READY":
					top_c = top_c.lerp(Color(0.87, 0.71, 0.18), 0.65)
				elif fstate == "GROWING":
					var g: float = float(field.get("growth", 0.0))
					top_c = top_c.lerp(soil.lerp(Color(0.40, 0.62, 0.22), g), 0.60)
				else:
					top_c = top_c.lerp(soil, 0.60)

			_add_top_quad(top_tools[biome] as SurfaceTool, x, z, h, top_c)
			top_counts[biome] = int(top_counts[biome]) + 1
			if h > 0.05:
				_add_side_quads(side_tools[biome] as SurfaceTool, x, z, h, side_c)
				side_counts[biome] = int(side_counts[biome]) + 1

	var mesh := ArrayMesh.new()
	for biome in top_tools.keys():
		if int(top_counts[biome]) == 0: continue
		var st_t: SurfaceTool = top_tools[biome]
		st_t.generate_normals()
		mesh = st_t.commit(mesh)
	# Bug-Fix (v11.3): Side-SurfaceTools bekommen KEIN generate_normals() mehr.
	# generate_normals() würde die manuell gesetzten Normals (set_normal())
	# durch gemittelte Smooth-Normals ersetzen - bei geteilten Eckpunkten
	# zwischen verschiedenen Seiten-Quads könnte das eine komplett falsche
	# Normale ergeben. Da wir CULL_DISABLED nutzen, spielen Normals für das
	# Culling ohnehin keine Rolle mehr (nur noch für Beleuchtung).
	# Ausserdem: Surfaces mit 0 Vertices überspringen - ein leerer
	# SurfaceTool-Commit könnte den ArrayMesh beschädigen und damit
	# auch create_trimesh_shape() für die Kollision kaputt machen.
	for biome in side_tools.keys():
		if int(side_counts[biome]) == 0: continue
		var st_s: SurfaceTool = side_tools[biome]
		mesh = st_s.commit(mesh)

	_terrain_node = MeshInstance3D.new()
	_terrain_node.name = "Terrain"
	_terrain_node.mesh = mesh
	_terrain_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_terrain_node)

func _add_top_quad(st: SurfaceTool, tx: int, tz: int, h: float, color: Color) -> void:
	var x0: float = float(tx) * TILE_SIZE
	var x1: float = x0 + TILE_SIZE
	var z0: float = float(tz) * TILE_SIZE
	var z1: float = z0 + TILE_SIZE
	st.set_color(color)
	st.set_normal(Vector3.UP)
	# Deterministische Pseudo-Zufallsspiegelung der Textur pro Tile (U/V),
	# damit sich die Wiederholung der einzelnen Tile-Grafik nicht als
	# sichtbares Gitter-Muster abzeichnet. Hängt nur von der Tile-Position
	# ab, bleibt also bei jedem Mesh-Rebuild stabil (kein Flackern).
	var seed_val: int = (tx * 92821) ^ (tz * 689287)
	var flip_u: bool = (seed_val & 1) == 1
	var flip_v: bool = (seed_val & 2) == 2
	var u0: float = 1.0 if flip_u else 0.0
	var u1: float = 0.0 if flip_u else 1.0
	var v0: float = 1.0 if flip_v else 0.0
	var v1: float = 0.0 if flip_v else 1.0
	st.set_uv(Vector2(u0, v0)); st.add_vertex(Vector3(x0, h, z0))
	st.set_uv(Vector2(u1, v0)); st.add_vertex(Vector3(x1, h, z0))
	st.set_uv(Vector2(u1, v1)); st.add_vertex(Vector3(x1, h, z1))
	st.set_uv(Vector2(u0, v0)); st.add_vertex(Vector3(x0, h, z0))
	st.set_uv(Vector2(u1, v1)); st.add_vertex(Vector3(x1, h, z1))
	st.set_uv(Vector2(u0, v1)); st.add_vertex(Vector3(x0, h, z1))

func _add_side_quads(st: SurfaceTool, tx: int, tz: int, h: float, color: Color) -> void:
	var x0: float = float(tx) * TILE_SIZE
	var x1: float = x0 + TILE_SIZE
	var z0: float = float(tz) * TILE_SIZE
	var z1: float = z0 + TILE_SIZE
	# UV-V skaliert mit der Tile-Höhe damit die Texturschichten immer
	# gleich "dick" aussehen, egal wie hoch die Klippe ist - bei doppelter
	# Höhe werden die Schichten einfach zweimal wiederholt statt gestreckt.
	var v_repeat: float = h / HEIGHT_SCALE   # z.B. h=2.4, HEIGHT_SCALE=1.2 → 2.0 Wiederholungen
	var dark_front: Color = color.darkened(0.10)
	var dark_back:  Color = color.darkened(0.18)
	var dark_left:  Color = color.darkened(0.22)
	var dark_right: Color = color.darkened(0.14)

	# Seite Z- (Nord / Vorderseite)
	st.set_color(dark_front); st.set_normal(Vector3(0, 0, -1))
	st.set_uv(Vector2(0.0, 0.0));       st.add_vertex(Vector3(x0, h,   z0))
	st.set_uv(Vector2(1.0, 0.0));       st.add_vertex(Vector3(x1, h,   z0))
	st.set_uv(Vector2(1.0, v_repeat));  st.add_vertex(Vector3(x1, 0.0, z0))
	st.set_uv(Vector2(0.0, 0.0));       st.add_vertex(Vector3(x0, h,   z0))
	st.set_uv(Vector2(1.0, v_repeat));  st.add_vertex(Vector3(x1, 0.0, z0))
	st.set_uv(Vector2(0.0, v_repeat));  st.add_vertex(Vector3(x0, 0.0, z0))

	# Seite Z+ (Süd / Rückseite)
	st.set_color(dark_back); st.set_normal(Vector3(0, 0, 1))
	st.set_uv(Vector2(1.0, 0.0));       st.add_vertex(Vector3(x0, h,   z1))
	st.set_uv(Vector2(1.0, v_repeat));  st.add_vertex(Vector3(x0, 0.0, z1))
	st.set_uv(Vector2(0.0, v_repeat));  st.add_vertex(Vector3(x1, 0.0, z1))
	st.set_uv(Vector2(1.0, 0.0));       st.add_vertex(Vector3(x0, h,   z1))
	st.set_uv(Vector2(0.0, v_repeat));  st.add_vertex(Vector3(x1, 0.0, z1))
	st.set_uv(Vector2(0.0, 0.0));       st.add_vertex(Vector3(x1, h,   z1))

	# Seite X- (West)
	st.set_color(dark_left); st.set_normal(Vector3(-1, 0, 0))
	st.set_uv(Vector2(0.0, 0.0));       st.add_vertex(Vector3(x0, h,   z1))
	st.set_uv(Vector2(1.0, 0.0));       st.add_vertex(Vector3(x0, h,   z0))
	st.set_uv(Vector2(1.0, v_repeat));  st.add_vertex(Vector3(x0, 0.0, z0))
	st.set_uv(Vector2(0.0, 0.0));       st.add_vertex(Vector3(x0, h,   z1))
	st.set_uv(Vector2(1.0, v_repeat));  st.add_vertex(Vector3(x0, 0.0, z0))
	st.set_uv(Vector2(0.0, v_repeat));  st.add_vertex(Vector3(x0, 0.0, z1))

	# Seite X+ (Ost)
	st.set_color(dark_right); st.set_normal(Vector3(1, 0, 0))
	st.set_uv(Vector2(0.0, 0.0));       st.add_vertex(Vector3(x1, h,   z0))
	st.set_uv(Vector2(1.0, 0.0));       st.add_vertex(Vector3(x1, h,   z1))
	st.set_uv(Vector2(1.0, v_repeat));  st.add_vertex(Vector3(x1, 0.0, z1))
	st.set_uv(Vector2(0.0, 0.0));       st.add_vertex(Vector3(x1, h,   z0))
	st.set_uv(Vector2(1.0, v_repeat));  st.add_vertex(Vector3(x1, 0.0, z1))
	st.set_uv(Vector2(0.0, v_repeat));  st.add_vertex(Vector3(x1, 0.0, z0))

# ── Terrain-Kollision (für Raycast) ──────────────────────────────────────────
## Bug-Fix (Klick-Versatz): Die Kollision wurde bisher als FLACHE Box bei y=0
## gebaut, unabhängig von der tatsächlichen (variierenden) Tile-Höhe. Der
## Raycast traf also bei jedem nicht-flachen Tile (Hügel/Berge - praktisch
## überall, da WorldGenerator fast immer eine Höhe > 0 erzeugt) eine falsche
## Ebene, wodurch der getroffene Weltpunkt und damit das ausgewählte Tile
## gegenüber der echten Mausposition versetzt war. Fix: Kollisionsform wird
## jetzt direkt aus dem sichtbaren Terrain-Mesh erzeugt (Trimesh), sodass der
## Raycast exakt die gerenderte Oberfläche trifft.
func _build_collision() -> void:
	if _col_body:
		_col_body.queue_free()
		_col_body = null
	if _terrain_node == null or _terrain_node.mesh == null:
		return
	_col_body = StaticBody3D.new()
	_col_body.name = "TerrainCollider"
	_col_body.collision_layer = 1
	_col_body.collision_mask  = 0

	# Kollisionsstrategie (v11.3):
	# TOP-Fläche: Trimesh des sichtbaren Meshes - erlaubt präzises Klick-
	#   Raycasting und glattes Laufen über Hügel/Steigungen.
	# SEITEN: Pro erhöhetem Tile (h > 0.05) eine eigene BoxShape3D - macht die
	#   Seiten begehbar UND undurchdringbar. Dünne Trimesh-Wand-Quads haben den
	#   Nachteil, dass CharacterBody3D sie bei schrägemAufprall durchdringen
	#   kann (bekanntes Godot-Problem mit Trimesh vs. CharacterBody3D). Mit
	#   soliden Boxen ist das nicht möglich.
	var cs_top := CollisionShape3D.new()
	cs_top.shape = _terrain_node.mesh.create_trimesh_shape()
	cs_top.position = Vector3.ZERO
	_col_body.add_child(cs_top)

	# Box-Kollisionen für Seitenflächen
	var box_pool: BoxShape3D = BoxShape3D.new()
	box_pool.size = Vector3(TILE_SIZE, 1.0, TILE_SIZE)  # Vorlage, wird je Tile angepasst
	for x in world_w:
		for z in world_h:
			var tile: Dictionary = (world[x] as Array)[z] as Dictionary
			var h: float = float(tile.get("height", 0.0)) * HEIGHT_SCALE
			if h <= 0.05: continue
			var box := BoxShape3D.new()
			box.size = Vector3(TILE_SIZE, h, TILE_SIZE)
			var cs_box := CollisionShape3D.new()
			cs_box.shape = box
			# Mittelpunkt der Box: x-Mitte, halbe Höhe, z-Mitte des Tiles
			cs_box.position = Vector3(
				float(x) * TILE_SIZE + TILE_SIZE * 0.5,
				h * 0.5,
				float(z) * TILE_SIZE + TILE_SIZE * 0.5
			)
			_col_body.add_child(cs_box)

	_col_body.position = Vector3.ZERO
	add_child(_col_body)

# ── Wasseroberfläche (Wasserphysik) ──────────────────────────────────────────
## Baut eine eigene, halbtransparente Wasser-Oberflächen-Mesh - eine Quad pro
## Tile mit water_level > 0, auf Höhe (Terrain-Bett + simulierter Pegel) statt
## der statischen Terrain-Höhe. Dadurch sieht man Flüsse/Seen tatsächlich
## steigen und fallen (Quellen-Zufluss, Verdunstung, Dürre), statt einer
## starren Wasserfläche. Wird nicht bei jedem Terrain-Refresh neu gebaut
## (zu teuer für häufige Aufrufe wie beim Terrain-Drag), sondern separat
## und gedrosselt über refresh_water() von GameController aus.
##
## Bug-Fix/Feature (v10.16): "Übergänge zwischen Wassertiles zu hart" -
## bisher bekam JEDES Wasser-Tile eine eigene, in sich FLACHE Quad-Fläche
## auf seiner eigenen surf-Höhe. Lagen zwei benachbarte Tiles auf
## unterschiedlichem water_level (z.B. ein flacher Fluss-Arm neben einem
## tiefen Becken, oder die Flanke eines austrocknenden Sees), entstand an
## der gemeinsamen Tile-Kante eine sichtbare, treppenartige Stufe statt
## einer fliessenden Oberfläche. Die Oberfläche wird jetzt wie ein echtes
## Höhenfeld behandelt: jede Gitter-ECKE (nicht mehr jede Tile-FLAECHE)
## bekommt eine gemeinsame Höhe, gemittelt aus den bis zu 4 angrenzenden
## Wasser-Tiles (_water_corner_data). Da benachbarte Quads dieselbe
## vorberechnete Eckhöhe referenzieren, treffen sie exakt aneinander -
## kontinuierliche, weiche Oberfläche statt Treppen. Die Tiefenfarbe
## (depth_pct -> Alpha) wird nach demselben Prinzip pro Ecke gemittelt und
## dann über die Quad-Fläche interpoliert, statt hart pro Tile zu wechseln.
func _build_water_mesh(src_world: Array) -> void:
	if _water_node:
		_water_node.queue_free()
		_water_node = null
	if src_world.is_empty():
		return

	var corner_h: Dictionary = _water_corner_data(src_world, true)
	var corner_d: Dictionary = _water_corner_data(src_world, false)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
	mat.roughness    = 0.05
	mat.metallic     = 0.25
	st.set_material(mat)

	var any_water: bool = false
	for x in world_w:
		var col: Array = src_world[x] as Array
		for z in world_h:
			var tile: Dictionary = col[z] as Dictionary
			var lvl: float = float(tile.get("water_level", 0.0))
			if lvl <= 0.02: continue
			any_water = true
			_add_smooth_water_quad(st, x, z, corner_h, corner_d)

	if not any_water:
		return
	st.generate_normals()
	_water_node = MeshInstance3D.new()
	_water_node.name = "WaterSurface"
	_water_node.mesh = st.commit()
	_water_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water_node)

## Berechnet pro Gitter-Ecke (gx,gz mit gx in [0,world_w], gz in [0,world_h])
## den Mittelwert über die bis zu 4 angrenzenden Wasser-Tiles - entweder der
## Oberflächenhöhe (want_height=true) oder des depth_pct-Werts
## (want_height=false, für die Farbinterpolation). Tiles ohne Wasser
## (water_level <= 0.02) und Tiles ausserhalb der Karte fliessen nicht in
## den Mittelwert ein. Gibt nur Ecken zurück, an denen mindestens ein
## Wasser-Tile angrenzt.
func _water_corner_data(src_world: Array, want_height: bool) -> Dictionary:
	var result: Dictionary = {}
	for gx in range(world_w + 1):
		for gz in range(world_h + 1):
			var total: float = 0.0
			var count: int = 0
			for ddx in [-1, 0]:
				for ddz in [-1, 0]:
					var tx: int = gx + ddx
					var tz: int = gz + ddz
					if tx < 0 or tz < 0 or tx >= world_w or tz >= world_h: continue
					var tile: Dictionary = (src_world[tx] as Array)[tz] as Dictionary
					var lvl: float = float(tile.get("water_level", 0.0))
					if lvl <= 0.02: continue
					if want_height:
						var bed: float = float(tile.get("height", 0.0)) * HEIGHT_SCALE
						total += bed + lvl * HEIGHT_SCALE
					else:
						total += clampf(lvl / 2.0, 0.0, 1.0)
					count += 1
			if count > 0:
				result["%d,%d" % [gx, gz]] = total / float(count)
	return result

func _add_smooth_water_quad(st: SurfaceTool, tx: int, tz: int, corner_h: Dictionary, corner_d: Dictionary) -> void:
	var x0: float = float(tx) * TILE_SIZE
	var x1: float = x0 + TILE_SIZE
	var z0: float = float(tz) * TILE_SIZE
	var z1: float = z0 + TILE_SIZE

	var h00: float = float(corner_h.get("%d,%d" % [tx,   tz],   0.0))
	var h10: float = float(corner_h.get("%d,%d" % [tx+1, tz],   0.0))
	var h11: float = float(corner_h.get("%d,%d" % [tx+1, tz+1], 0.0))
	var h01: float = float(corner_h.get("%d,%d" % [tx,   tz+1], 0.0))
	var d00: float = float(corner_d.get("%d,%d" % [tx,   tz],   0.0))
	var d10: float = float(corner_d.get("%d,%d" % [tx+1, tz],   0.0))
	var d11: float = float(corner_d.get("%d,%d" % [tx+1, tz+1], 0.0))
	var d01: float = float(corner_d.get("%d,%d" % [tx,   tz+1], 0.0))

	var c00: Color = Color(0.16, 0.42, 0.78, 0.42 + d00 * 0.40)
	var c10: Color = Color(0.16, 0.42, 0.78, 0.42 + d10 * 0.40)
	var c11: Color = Color(0.16, 0.42, 0.78, 0.42 + d11 * 0.40)
	var c01: Color = Color(0.16, 0.42, 0.78, 0.42 + d01 * 0.40)

	st.set_normal(Vector3.UP)
	st.set_color(c00); st.add_vertex(Vector3(x0, h00, z0))
	st.set_color(c10); st.add_vertex(Vector3(x1, h10, z0))
	st.set_color(c11); st.add_vertex(Vector3(x1, h11, z1))

	st.set_color(c00); st.add_vertex(Vector3(x0, h00, z0))
	st.set_color(c11); st.add_vertex(Vector3(x1, h11, z1))
	st.set_color(c01); st.add_vertex(Vector3(x0, h01, z1))

## Öffentliche API, von GameController in einem gedrosselten Intervall
## aufgerufen (siehe _process()), damit die Wasseroberfläche der laufenden
## WaterSystem-Simulation folgt, ohne sie bei jedem einzelnen Frame neu zu
## erzeugen (Performance).
func refresh_water(src_world: Array) -> void:
	_build_water_mesh(src_world)

# ── Drought-Update ────────────────────────────────────────────────────────────
## Öffentliche API für Terrain-Neubau (Wege, Höhenänderungen).
## Baut auch die Kollision neu, da sich bei Höhenänderungen (z.B. Erde
## aufschütten) sonst die Klickerkennung von der sichtbaren Oberfläche
## entkoppeln würde (Klick-Versatz-Bug).
func refresh_terrain() -> void:
	_build_terrain_mesh()
	_build_collision()

func apply_drought(drought: bool) -> void:
	if drought == is_drought: return
	is_drought = drought
	_build_terrain_mesh()   # Farben neu backen

# ══════════════════════════════════════════════════════════════════════════════
# GEBÄUDE
# ══════════════════════════════════════════════════════════════════════════════
## Färbt NUR die Wand-Fläche eines instanzierten Gebäude-Modells ein
## (v10.20). Bis v10.19 hatte building.glb nur EIN Material für das gesamte
## Modell - material_override auf der MeshInstance3D selbst hat deshalb
## zwangsweise alles (inkl. Dach, Fenster, Sockel etc.) einheitlich
## eingefärbt. Das überarbeitete Modell liefert jetzt 7 getrennte
## Material-Flächen ("Dach", "Pfeiler_Holzbalken", "Wand", "Gras_Busch",
## "Fenster_Dunkel", "Schornstein", "Sockel_Stein") als eigene Surfaces einer
## einzigen Mesh-Resource. Statt material_override (färbt ALLE Surfaces)
## wird hier gezielt nur die Surface mit dem Material-Namen "Wand" per
## set_surface_override_material() ersetzt - alle anderen Teile behalten ihr
## importiertes Original-Material (und damit Look/Textur) bei. So bleibt der
## Gesamt-Look des Gebäudes erhalten, aber die Wandfarbe gibt weiterhin
## Auskunft über den Gebäudetyp.
const BUILDING_WALL_MATERIAL_NAME: String = "Wand"

func _tint_building_wall(node: Node, col: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				var base_mat: Material = mesh.surface_get_material(i)
				var mat_name: String = base_mat.resource_name if base_mat != null else ""
				if mat_name == BUILDING_WALL_MATERIAL_NAME:
					var tinted := StandardMaterial3D.new()
					tinted.albedo_color = col
					tinted.roughness = 0.78
					mi.set_surface_override_material(i, tinted)
	for child in node.get_children():
		_tint_building_wall(child, col)

func _rebuild_all_buildings() -> void:
	for key in _building_nodes:
		(_building_nodes[key] as Node).queue_free()
	_building_nodes.clear()
	_storage_labels.clear()
	for x in world_w:
		for y in world_h:
			var tile: Dictionary = (world[x] as Array)[y] as Dictionary
			var bld = tile.get("building")
			if bld != null:
				_spawn_building(bld as BuildingEntity)

func refresh_buildings() -> void:
	_rebuild_all_buildings()

func add_building(b: BuildingEntity) -> void:
	var key: String = "%d,%d" % [b.tile_x, b.tile_y]
	if _building_nodes.has(key):
		(_building_nodes[key] as Node).queue_free()
		_building_nodes.erase(key)
	_storage_labels.erase(key)
	_spawn_building(b)

func remove_building(tx: int, ty: int) -> void:
	var key: String = "%d,%d" % [tx, ty]
	if _building_nodes.has(key):
		(_building_nodes[key] as Node).queue_free()
		_building_nodes.erase(key)
	_storage_labels.erase(key)

func _spawn_building(b: BuildingEntity) -> void:
	var key: String = "%d,%d" % [b.tile_x, b.tile_y]
	var wp:  Vector3 = tile_to_world3d(b.tile_x, b.tile_y)
	var vis: Dictionary = BUILDING_VISUALS.get(
		b.id, {"color": Color(0.65, 0.65, 0.65), "h": 2.0}
	) as Dictionary
	var bh:  float = float(vis.get("h",  2.0)) * (1.0 + float(b.level - 1) * 0.18)
	var col: Color = vis.get("color", Color(0.65, 0.65, 0.65)) as Color

	# ── Root ──
	var root := StaticBody3D.new()
	root.name = "Bld_%s" % key
	root.collision_layer = 2
	root.collision_mask  = 0
	root.set_meta("tile_x", b.tile_x)
	root.set_meta("tile_y", b.tile_y)

	# Kollision
	var cs    := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size   = Vector3(TILE_SIZE * 0.86, bh, TILE_SIZE * 0.86)
	cs.shape     = shape
	cs.position  = Vector3(0.0, bh * 0.5, 0.0)
	root.add_child(cs)

	# ── Hauptkörper ──
	# Feature (v10.16/v10.18, Asset-Wechsel v10.19, materialbasiertes
	# Wand-Tinting v10.20): fertig gebaute Gebäude nutzen das
	# "Building"-Asset statt der generischen Box+Dach-Darstellung - für ALLE
	# Gebäudetypen. Während der Bauphase bleibt es bei der bisherigen
	# halbtransparenten Box (Baugerüst-Optik) - so bleibt der bekannte
	# "Baustelle"-Look für alle Gebäudetypen einheitlich. Die Skalierung
	# richtet sich nach der individuellen Ziel-Höhe "bh" des jeweiligen
	# Gebäudes, damit z.B. ein Brunnen kleiner wirkt als ein Wohnhaus, auch
	# wenn beide dasselbe Modell nutzen.
	var use_building_model: bool = not b.is_under_construction

	if use_building_model:
		# v12.8: eigenes Modell verwenden, falls für diesen Gebäudetyp
		# eins hinterlegt ist (aktuell WELL/STORAGE), sonst generisches
		# building.glb wie bisher.
		var override: Dictionary = BUILDING_MODEL_OVERRIDES.get(b.id, {}) as Dictionary
		var scene_to_use: PackedScene = override.get("scene", BUILDING_SCENE) as PackedScene
		var raw_h: float = float(override.get("raw_h", BUILDING_MODEL_RAW_HEIGHT))
		var bottom_off: float = float(override.get("bottom_off", BUILDING_MODEL_BOTTOM_OFFSET))

		var model := scene_to_use.instantiate()
		var scale_factor: float = (bh / raw_h) * BUILDING_MODEL_SCALE_FACTOR
		model.scale      = Vector3.ONE * scale_factor
		# Bug-Fix (v10.19, "Häuser stehen im Boden"): Modell-Ursprung liegt in
		# der Mitte des Mesh, nicht am Boden - ohne diesen Offset würde die
		# untere Hälfte des Modells unter der Tile-Oberfläche versinken.
		model.position.y = bottom_off * scale_factor
		model.rotation.y = BUILDING_ROT_OFFSET
		# v10.20: färbt nur noch die "Wand"-Fläche statt des gesamten
		# Modells (siehe _tint_building_wall()) - Dach, Fensterrahmen,
		# Schornstein, Sockel etc. behalten ihr Original-Aussehen.
		_tint_building_wall(model, col)
		root.add_child(model)
	else:
		var body_mi   := MeshInstance3D.new()
		var body_mesh := BoxMesh.new()
		body_mesh.size = Vector3(TILE_SIZE * 0.82, bh, TILE_SIZE * 0.82)
		body_mi.mesh   = body_mesh
		body_mi.position = Vector3(0.0, bh * 0.5, 0.0)

		var body_mat := StandardMaterial3D.new()
		if b.is_under_construction:
			body_mat.albedo_color = Color(0.90, 0.82, 0.42, 0.65)
			body_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		else:
			body_mat.albedo_color = col
		body_mat.roughness = 0.72
		body_mi.material_override = body_mat
		root.add_child(body_mi)

		# ── Dach ──
		var roof_mi   := MeshInstance3D.new()
		var roof_mesh := BoxMesh.new()
		roof_mesh.size = Vector3(TILE_SIZE * 0.90, 0.22, TILE_SIZE * 0.90)
		roof_mi.mesh   = roof_mesh
		roof_mi.position = Vector3(0.0, bh + 0.11, 0.0)
		var roof_mat := StandardMaterial3D.new()
		roof_mat.albedo_color = col.darkened(0.32)
		roof_mat.roughness    = 0.80
		roof_mi.material_override = roof_mat
		if not b.is_under_construction:
			root.add_child(roof_mi)

	# ── Emoji-Label ──
	var lbl := Label3D.new()
	lbl.text       = BUILDING_EMOJIS.get(b.id, "🏠")
	lbl.pixel_size = 0.008
	lbl.font_size  = 60
	lbl.billboard  = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position   = Vector3(0.0, bh + 0.9, 0.0)
	root.add_child(lbl)

	# ── Produktions-Anzeige (v14.0, Nutzerwunsch "zeige bei Fabriken an, was
	# sie produzieren"): kleines Icon der Ausgabe-Ressource seitlich neben
	# dem Gebäude-Icon, permanent sichtbar statt erst nach Anklicken im
	# Infopanel. Bei PROCESSOR (feste Ausgabe, z.B. Sägewerk -> Bretter) ein
	# einzelnes Icon mit kleinem "→"-Pfeil; bei MULTIPROCESSOR (z.B.
	# Kochhaus, mehrere mögliche Rezepte) alle möglichen Ausgabe-Icons klein
	# nebeneinander.
	if not b.is_under_construction:
		var out_icons: Array = []
		if b.btype == "PROCESSOR" and str(b.produces) != "":
			out_icons.append(str(BuildingData.RESOURCE_ICONS.get(b.produces, "")))
		elif b.btype == "MULTIPROCESSOR" and not b.recipes.is_empty():
			for r in b.recipes:
				out_icons.append(str(BuildingData.RESOURCE_ICONS.get(str(r), "")))
		out_icons = out_icons.filter(func(s): return s != "")
		if not out_icons.is_empty():
			var joined: String = ""
			for i in out_icons.size():
				joined += str(out_icons[i])
				if i < out_icons.size() - 1: joined += " "
			var out_lbl := Label3D.new()
			out_lbl.text = "→ " + joined
			out_lbl.pixel_size = 0.0055
			out_lbl.font_size  = 34
			out_lbl.modulate = Color(1.0, 0.95, 0.75)
			out_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			out_lbl.no_depth_test = true
			out_lbl.position = Vector3(0.0, bh + 0.55, 0.0)
			root.add_child(out_lbl)

	# ── Baustellen-Overlay ──
	if b.is_under_construction:
		var prog_lbl := Label3D.new()
		prog_lbl.text      = "🚧"
		prog_lbl.pixel_size = 0.008
		prog_lbl.font_size  = 48
		prog_lbl.billboard  = BaseMaterial3D.BILLBOARD_ENABLED
		prog_lbl.no_depth_test = true
		prog_lbl.position   = Vector3(0.0, bh + 1.7, 0.0)
		root.add_child(prog_lbl)

	# ── Lager-Füllstandsanzeige (v11.0, Lagersystem) ──
	# Produktionsgebäude haben ein begrenztes lokales Lager für die selbst
	# erzeugte Ressource (siehe BuildingEntity.local_storage) - hier wird der
	# Füllstand direkt am Gebäude als kleiner Balken aus Blockzeichen
	# angezeigt, der von refresh_storage_labels() periodisch aktualisiert
	# wird, ohne das Gebäude komplett neu aufzubauen.
	if not b.is_under_construction and b.local_storage_capacity > 0.0:
		var store_lbl := Label3D.new()
		store_lbl.text       = "░░░░░"
		store_lbl.pixel_size = 0.0065
		store_lbl.font_size  = 38
		store_lbl.billboard  = BaseMaterial3D.BILLBOARD_ENABLED
		store_lbl.no_depth_test = true
		store_lbl.position   = Vector3(0.0, bh + 1.35, 0.0)
		root.add_child(store_lbl)
		_storage_labels[key] = store_lbl

	root.position = wp
	_building_root.add_child(root)
	_building_nodes[key] = root

## Feature (v11.0): aktualisiert den Lager-Füllstandsbalken aller
## Produktionsgebäude (grüne → rote Färbung je näher am Limit), ohne die
## Gebäude-Nodes selbst neu aufzubauen - regelmässig (nicht jeden Frame)
## von GameController._process() aufgerufen.
func refresh_storage_labels(buildings: Array) -> void:
	for b in buildings:
		var be: BuildingEntity = b
		if be.is_under_construction or be.local_storage_capacity <= 0.0: continue
		var key: String = "%d,%d" % [be.tile_x, be.tile_y]
		if not _storage_labels.has(key): continue
		var lbl: Label3D = _storage_labels[key] as Label3D
		if lbl == null or not is_instance_valid(lbl): continue
		var pct: float = clampf(be.get_local_storage_total() / maxf(1.0, be.local_storage_capacity), 0.0, 1.0)
		var bars: int = int(round(pct * 5.0))
		var bar_str: String = ""
		for i in range(5):
			bar_str += "▓" if i < bars else "░"
		lbl.text = bar_str
		lbl.modulate = Color(0.30, 0.85, 0.30).lerp(Color(0.92, 0.18, 0.12), pct)

# ══════════════════════════════════════════════════════════════════════════════
# SELEKTION / GHOST
# ══════════════════════════════════════════════════════════════════════════════
func _create_highlight() -> void:
	_sel_mat = StandardMaterial3D.new()
	_sel_mat.albedo_color     = Color(1.0, 0.92, 0.18, 0.70)
	_sel_mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	_sel_mat.emission_enabled = true
	_sel_mat.emission         = Color(1.0, 0.85, 0.0) * 0.4
	_sel_mat.cull_mode        = BaseMaterial3D.CULL_DISABLED

	_highlight_node = MeshInstance3D.new()
	_highlight_node.name = "SelectHighlight"
	var m := BoxMesh.new()
	m.size = Vector3(TILE_SIZE * 0.97, 0.06, TILE_SIZE * 0.97)
	_highlight_node.mesh              = m
	_highlight_node.material_override = _sel_mat
	_highlight_node.visible           = false
	_highlight_node.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_highlight_node)

func _create_ghost() -> void:
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.albedo_color = Color(0.45, 0.80, 1.0, 0.42)
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.cull_mode    = BaseMaterial3D.CULL_DISABLED

	_ghost_node = MeshInstance3D.new()
	_ghost_node.name = "Ghost"
	var m := BoxMesh.new()
	m.size = Vector3(TILE_SIZE * 0.82, 2.0, TILE_SIZE * 0.82)
	_ghost_node.mesh              = m
	_ghost_node.material_override = _ghost_mat
	_ghost_node.visible           = false
	_ghost_node.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost_node)

## Feature (v14.0, Nutzerwunsch "Reichweiten-Vorschau beim Bauen"): dünner,
## flacher Ring auf dem Boden, der beim Platzieren eines Sammelgebäudes
## (Brunnen, Holzfäller, Steinbruch, ...) dessen collection_radius zeigt -
## verhindert genau den Fall, der den Wasser-Bug ausgelöst hat (Brunnen
## versehentlich zu weit vom Wasser weg gebaut, ohne dass man das vorher
## sehen konnte).
var _ghost_radius_node: MeshInstance3D = null
var _ghost_radius_mat: StandardMaterial3D = null

func _create_ghost_radius() -> void:
	_ghost_radius_mat = StandardMaterial3D.new()
	_ghost_radius_mat.albedo_color     = Color(0.55, 0.85, 1.0, 0.30)
	_ghost_radius_mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_radius_mat.emission_enabled = true
	_ghost_radius_mat.emission         = Color(0.55, 0.85, 1.0) * 0.5
	_ghost_radius_mat.cull_mode        = BaseMaterial3D.CULL_DISABLED
	_ghost_radius_mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED

	_ghost_radius_node = MeshInstance3D.new()
	_ghost_radius_node.name = "GhostRadius"
	var ring := TorusMesh.new()
	ring.inner_radius = 1.0; ring.outer_radius = 1.15
	_ghost_radius_node.mesh              = ring
	_ghost_radius_node.material_override = _ghost_radius_mat
	_ghost_radius_node.visible           = false
	_ghost_radius_node.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost_radius_node)

## Feature (v12.3, Tutorial-Überarbeitung): eigener, auffälliger Marker
## (kräftiges Grün, pulsierend per Tween) für die interaktive
## Tutorial-Anweisung "baue hier" - bewusst GETRENNT von _highlight_node
## (gelb, wird für normale Gebäude-Auswahl/Hover benutzt) und _ghost_node
## (Bau-Vorschau unter der Maus), damit sich die drei Marker nie gegenseitig
## überschreiben/verwirren.
var _tutorial_marker_node: MeshInstance3D = null
var _tutorial_marker_mat: StandardMaterial3D = null
var _tutorial_marker_tween: Tween = null

func _create_tutorial_marker() -> void:
	_tutorial_marker_mat = StandardMaterial3D.new()
	_tutorial_marker_mat.albedo_color     = Color(0.25, 1.0, 0.35, 0.55)
	_tutorial_marker_mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tutorial_marker_mat.emission_enabled = true
	_tutorial_marker_mat.emission         = Color(0.25, 1.0, 0.35) * 0.8
	_tutorial_marker_mat.cull_mode        = BaseMaterial3D.CULL_DISABLED
	_tutorial_marker_mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED

	_tutorial_marker_node = MeshInstance3D.new()
	_tutorial_marker_node.name = "TutorialMarker"
	var m := BoxMesh.new()
	m.size = Vector3(TILE_SIZE * 1.05, 0.10, TILE_SIZE * 1.05)
	_tutorial_marker_node.mesh              = m
	_tutorial_marker_node.material_override = _tutorial_marker_mat
	_tutorial_marker_node.visible           = false
	_tutorial_marker_node.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tutorial_marker_node)

## Zeigt den pulsierenden Marker auf Tile (tx,ty) - genau über der
## Terrain-Höhe an dieser Stelle (wie tile_to_world3d(), plus minimaler
## Y-Versatz, damit er sichtbar über dem Boden schwebt statt im Terrain zu
## clippen).
func show_tutorial_marker(tx: int, ty: int) -> void:
	if _tutorial_marker_node == null: return
	var p: Vector3 = tile_to_world3d(tx, ty)
	p.y += 0.08
	_tutorial_marker_node.position = p
	_tutorial_marker_node.visible = true
	if _tutorial_marker_tween: _tutorial_marker_tween.kill()
	_tutorial_marker_tween = create_tween().set_loops()
	_tutorial_marker_tween.tween_property(_tutorial_marker_node, "scale", Vector3(1.15, 1.0, 1.15), 0.6).set_trans(Tween.TRANS_SINE)
	_tutorial_marker_tween.tween_property(_tutorial_marker_node, "scale", Vector3(0.9, 1.0, 0.9), 0.6).set_trans(Tween.TRANS_SINE)

func hide_tutorial_marker() -> void:
	if _tutorial_marker_node == null: return
	_tutorial_marker_node.visible = false
	if _tutorial_marker_tween: _tutorial_marker_tween.kill()

## Feature (v11.1, Logistik-Feinschliff): legt den einmaligen Node für alle
## Hauler-Linien an. Unlit/no_depth_test, damit die dünnen Linien auch durch
## Gebäude/Terrain hindurch klar sichtbar bleiben.
func _create_haul_lines() -> void:
	_haul_line_mesh = ImmediateMesh.new()
	_haul_line_node = MeshInstance3D.new()
	_haul_line_node.name = "HaulLines"
	_haul_line_node.mesh = _haul_line_mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_haul_line_node.material_override = mat
	_haul_line_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_haul_line_node)

## Feature (v11.1, Logistik-Feinschliff): zeichnet für jedes Frettchen, das
## gerade aktiv Material transportiert (Selbst-Abtransport, Bau-Frettchen auf
## Materialsuche, Lagerarbeiter), eine dünne Linie von seiner aktuellen
## Position zum Transportziel - macht das Logistiknetzwerk auf einen Blick
## sichtbar. Farbcodiert nach Transportart:
##   gelb   = Produktions-Hauler trägt zum Lagerhaus (HAUL_TO_WAREHOUSE)
##   blau   = Bau-Frettchen holt Material vom Lagerhaus (FETCH_TO_WAREHOUSE)
##   grün  = Material wird gerade zur Baustelle gebracht (FETCH_TO_SITE/WH_TO_SITE)
##   lila   = Lagerarbeiter holt von einem Produktionsgebäude ab (WH_TO_SOURCE)
const _HAUL_LINE_COLORS: Dictionary = {
	"HAUL_TO_WAREHOUSE":   Color(1.0, 0.85, 0.15, 0.85),
	"FETCH_TO_WAREHOUSE":  Color(0.25, 0.55, 1.0, 0.85),
	"FETCH_TO_SITE":       Color(0.30, 0.90, 0.35, 0.85),
	"WH_TO_SOURCE":        Color(0.75, 0.35, 0.95, 0.85),
	"WH_TO_SITE":          Color(0.30, 0.90, 0.35, 0.85),
}
func refresh_haul_lines(ferrets: Array) -> void:
	if _haul_line_mesh == null: return
	_haul_line_mesh.clear_surfaces()
	# Bug-Fix (v11.2b-Hotfix): surface_end() wirft einen Fehler ("No vertices
	# were added"), wenn kein einziges Frettchen gerade transportiert - also
	# zuerst prüfen, ob überhaupt ein aktiver Haul-Transport vorliegt, und
	# nur dann eine Surface eröffnen.
	var has_lines: bool = false
	for f in ferrets:
		var fe: FerretEntity = f
		if fe.haul_target != null and is_instance_valid(fe.haul_target) \
				and _HAUL_LINE_COLORS.has(fe.work_state):
			has_lines = true; break
	if not has_lines: return
	_haul_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for f in ferrets:
		var fe: FerretEntity = f
		if fe.haul_target == null or not is_instance_valid(fe.haul_target): continue
		var col = _HAUL_LINE_COLORS.get(fe.work_state, null)
		if col == null: continue
		var target: BuildingEntity = fe.haul_target
		var from_wp: Vector3 = tile_to_world3d(int(fe.pos.x), int(fe.pos.y))
		from_wp.y += 0.6
		var to_wp: Vector3 = tile_to_world3d(target.tile_x, target.tile_y)
		to_wp.y += 0.6
		_haul_line_mesh.surface_set_color(col as Color)
		_haul_line_mesh.surface_add_vertex(from_wp)
		_haul_line_mesh.surface_set_color(col as Color)
		_haul_line_mesh.surface_add_vertex(to_wp)
	_haul_line_mesh.surface_end()

## Feature (v11.1, Logistik-Feinschliff): legt den Node für die statische
## Lieferketten-Vorschau an (gestrichelt wirkende, gedimmte Linien - durch
## kürzere, durch Lücken getrennte Liniensegmente simuliert, da ImmediateMesh
## kein echtes Dash-Pattern unterstützt).
func _create_chain_lines() -> void:
	_chain_line_mesh = ImmediateMesh.new()
	_chain_line_node = MeshInstance3D.new()
	_chain_line_node.name = "ChainLines"
	_chain_line_node.mesh = _chain_line_mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_chain_line_node.material_override = mat
	_chain_line_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_chain_line_node)

func clear_chain_lines() -> void:
	if _chain_line_mesh: _chain_line_mesh.clear_surfaces()

## Feature (v11.1, Logistik-Feinschliff): zeigt beim Anklicken eines Gebäudes
## dessen potenzielle Lieferkette, unabhängig davon, ob gerade aktiv
## transportiert wird:
##  - Produktionsgebäude → nächstes (nach storage_filter passendes) Lagerhaus
##  - Lagerhaus → alle Produktionsgebäude in Reichweite, die es bedienen
##    könnte, UND alle Baustellen in Reichweite, die noch Material brauchen
##  - Baustelle → nächstes Lagerhaus mit verfügbarem fehlendem Material
func refresh_chain_lines(b: BuildingEntity) -> void:
	clear_chain_lines()
	if b == null or _chain_line_mesh == null: return
	var lines: Array = []  # Array of [Vector3 from, Vector3 to, Color]
	var dim_warehouse := Color(1.0, 0.85, 0.15, 0.55)
	var dim_source    := Color(0.75, 0.35, 0.95, 0.45)
	var dim_site      := Color(0.30, 0.90, 0.35, 0.55)
	var b_wp: Vector3 = tile_to_world3d(b.tile_x, b.tile_y); b_wp.y += 0.55

	if b.local_storage_capacity > 0.0:
		# Produktionsgebäude: Linie zum nächsten passenden Lagerhaus.
		var best_wh: BuildingEntity = null; var best_d: float = INF
		for ob in BuildingSys.buildings:
			var obe: BuildingEntity = ob
			if obe.btype != "STORAGE" or obe.is_under_construction or obe.storage_capacity <= 0.0: continue
			var d: float = Vector2(float(b.tile_x), float(b.tile_y)).distance_to(Vector2(float(obe.tile_x), float(obe.tile_y)))
			if d < best_d: best_d = d; best_wh = obe
		if best_wh != null:
			var wh_wp: Vector3 = tile_to_world3d(best_wh.tile_x, best_wh.tile_y); wh_wp.y += 0.55
			lines.append([b_wp, wh_wp, dim_warehouse])
	elif b.btype == "STORAGE" and b.storage_capacity > 0.0:
		# Lagerhaus: Linien zu potenziellen Quellen und zu Baustellen, die es
		# bedienen könnte.
		for ob in BuildingSys.buildings:
			var obe: BuildingEntity = ob
			if obe.is_under_construction or obe.local_storage_capacity <= 0.0: continue
			var d: float = Vector2(float(b.tile_x), float(b.tile_y)).distance_to(Vector2(float(obe.tile_x), float(obe.tile_y)))
			if d > 70.0: continue
			var src_wp: Vector3 = tile_to_world3d(obe.tile_x, obe.tile_y); src_wp.y += 0.55
			lines.append([src_wp, b_wp, dim_source])
		for site in BuildingSys.get_construction_sites():
			var se: BuildingEntity = site
			if se.is_fully_supplied(): continue
			var d2: float = Vector2(float(b.tile_x), float(b.tile_y)).distance_to(Vector2(float(se.tile_x), float(se.tile_y)))
			if d2 > 70.0: continue
			var site_wp: Vector3 = tile_to_world3d(se.tile_x, se.tile_y); site_wp.y += 0.55
			lines.append([b_wp, site_wp, dim_site])
	elif b.is_under_construction:
		# Baustelle: Linie zum nächsten Lagerhaus mit verfügbarem Material.
		var best_wh2: BuildingEntity = null; var best_d2: float = INF
		for ob in BuildingSys.buildings:
			var obe2: BuildingEntity = ob
			if obe2.btype != "STORAGE" or obe2.is_under_construction or obe2.storage_capacity <= 0.0: continue
			var d3: float = Vector2(float(b.tile_x), float(b.tile_y)).distance_to(Vector2(float(obe2.tile_x), float(obe2.tile_y)))
			if d3 < best_d2: best_d2 = d3; best_wh2 = obe2
		if best_wh2 != null:
			var wh_wp2: Vector3 = tile_to_world3d(best_wh2.tile_x, best_wh2.tile_y); wh_wp2.y += 0.55
			lines.append([wh_wp2, b_wp, dim_site])

	if lines.is_empty(): return
	_chain_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for line in lines:
		var ld: Array = line
		_chain_line_mesh.surface_set_color(ld[2] as Color)
		_chain_line_mesh.surface_add_vertex(ld[0] as Vector3)
		_chain_line_mesh.surface_set_color(ld[2] as Color)
		_chain_line_mesh.surface_add_vertex(ld[1] as Vector3)
	_chain_line_mesh.surface_end()

func set_selection(tx: int, ty: int) -> void:
	selected_tile = Vector2i(tx, ty)
	if tx < 0 or ty < 0 or tx >= world_w or ty >= world_h:
		_highlight_node.visible = false
		return
	var wp := tile_to_world3d(tx, ty)
	_highlight_node.position = Vector3(wp.x, wp.y + 0.07, wp.z)
	_highlight_node.visible  = true

func clear_selection() -> void:
	selected_tile     = Vector2i(-1, -1)
	selected_building = null
	_highlight_node.visible = false
	clear_chain_lines()

func update_ghost(tx: int, ty: int, building_id: String) -> void:
	if tx < 0 or ty < 0 or tx >= world_w or ty >= world_h or building_id.is_empty():
		_ghost_node.visible = false
		_ghost_radius_node.visible = false
		return
	var wp:  Vector3 = tile_to_world3d(tx, ty)
	var vis: Dictionary = BUILDING_VISUALS.get(
		building_id, {"color": Color(0.5, 0.8, 1.0), "h": 2.0}
	) as Dictionary
	var bh: float = float(vis.get("h", 2.0))
	var m  := BoxMesh.new()
	m.size = Vector3(TILE_SIZE * 0.82, bh, TILE_SIZE * 0.82)
	_ghost_node.mesh     = m
	_ghost_node.position = Vector3(wp.x, wp.y + bh * 0.5, wp.z)
	_ghost_node.visible  = true

	# Feature (v14.0): Reichweiten-Ring bei Sammelgebäuden mit collection_radius.
	var bdata: Dictionary = BuildingData.BUILDINGS.get(building_id, {}) as Dictionary
	if bdata.has("collection_radius"):
		var r: float = float(bdata["collection_radius"]) * TILE_SIZE
		var ring := TorusMesh.new()
		ring.inner_radius = maxf(0.05, r - 0.12)
		ring.outer_radius = r + 0.12
		_ghost_radius_node.mesh = ring
		_ghost_radius_node.position = Vector3(wp.x, wp.y + 0.05, wp.z)
		_ghost_radius_node.visible = true
	else:
		_ghost_radius_node.visible = false

func clear_ghost() -> void:
	_ghost_node.visible = false
	_ghost_radius_node.visible = false

# ══════════════════════════════════════════════════════════════════════════════
# FRETTCHEN
# ══════════════════════════════════════════════════════════════════════════════
func update_ferrets(ferrets: Array) -> void:
	# Prüfen ob genug Nodes vorhanden, sonst neu erstellen
	while _ferret_nodes.size() < ferrets.size():
		var inst := FERRET_SCENE.instantiate() as Node3D
		inst.scale = Vector3.ONE * FERRET_MODEL_SCALE
		_disable_shadows(inst)
		# Feature (v11.9, Legendäre Frettchen): Anker-Node für Accessoires +
		# "Holy Glow" - mit Gegen-Skalierung (1/FERRET_MODEL_SCALE), damit die
		# in FerretAccessories.gd hinterlegten Offsets/Grössen direkt in
		# Metern gelten, statt vom 2.2x-Frettchen-Scale mit aufgebläht zu
		# werden. Leer, solange das Frettchen nicht legendär ist.
		var fx_anchor := Node3D.new(); fx_anchor.name = "LegendaryFX"
		fx_anchor.scale = Vector3.ONE / FERRET_MODEL_SCALE
		inst.add_child(fx_anchor)
		var anim: AnimationPlayer = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if anim and anim.get_animation_list().size() > 0:
			var anim_name: String = "Run" if anim.has_animation("Run") else anim.get_animation_list()[0]
			anim.play(anim_name)
			anim.speed_scale = randf_range(0.85, 1.2)
			inst.set_meta("anim_player", anim)
			inst.set_meta("anim_name", anim_name)
			inst.set_meta("anim_base_speed", anim.speed_scale)
		_ferret_root.add_child(inst)
		_ferret_nodes.append(inst)

	# Überschüssige Nodes verstecken
	for i in _ferret_nodes.size():
		var fn: Node3D = _ferret_nodes[i] as Node3D
		if i >= ferrets.size():
			fn.visible = false
			continue
		fn.visible = true
		var fe: FerretEntity = ferrets[i] as FerretEntity
		# pos ist jetzt Tile-Koordinaten (Floats)
		var ftx: int = clampi(int(fe.pos.x), 0, world_w - 1)
		var fty: int = clampi(int(fe.pos.y), 0, world_h - 1)
		var wp3: Vector3 = tile_to_world3d(ftx, fty)
		# Sub-Tile-Offset
		var sub_x: float = (fe.pos.x - float(ftx)) * TILE_SIZE
		var sub_z: float = (fe.pos.y - float(fty)) * TILE_SIZE
		var is_harvesting: bool = fe.work_state == "HARVESTING"
		var is_building: bool = fe.work_state == "BUILDING"
		var is_idle_at_work: bool = fe.work_state == "WORKING" or is_harvesting or is_building

		# Feature (v10.13): nachts legen sich Frettchen schlafen (siehe
		# FerretEntity._update_sleep()) - mit zugewiesenem Haus dort, sonst an
		# Ort und Stelle auf dem Boden. Das ferret.glb hat keine Liege-Pose,
		# daher wird das Modell stattdessen um 90° auf die Seite gekippt und
		# dicht auf den Boden gesetzt; ein sehr langsames Sinus-Wippen
		# deutet ruhiges Atmen an. Die Lauf-Animation wird dabei komplett
		# angehalten (eingefrorene Pose, siehe v10.12-Fix weiter unten).
		if fe.is_sleeping:
			var anim_s: AnimationPlayer = fn.get_meta("anim_player", null) as AnimationPlayer
			if anim_s != null and anim_s.is_playing():
				anim_s.stop(true)
			var breathe: float = sin(fe.sleep_anim_t * 1.1) * 0.015
			fn.rotation.x = 0.0
			fn.rotation.z = deg_to_rad(92.0)
			fn.position = Vector3(wp3.x + sub_x, wp3.y + FERRET_Y * 0.32 + breathe, wp3.z + sub_z)
			continue

		# Feature (v10.10/v10.11): das ferret.glb hat nur eine "Run"-Animation
		# (siehe Projektnotizen), keine eigene Ernte-/Arbeitsanimation. Als
		# Ersatz: die Lauf-Animation wird angehalten, sobald das Frettchen am
		# Gebäude/an der Quelle steht (kein Laufen auf der Stelle mehr), und
		# während des Erntens/Arbeitens wird stattdessen eine kleine,
		# prozedurale Pose simuliert - seit v10.11 je nach gesammelter
		# Ressource ein eigenes, passendes Bewegungsmuster (siehe
		# rendering/animations/): Pflücken (BERRIES), Axthieb (WOOD), Schöpfen
		# (WATER). Für STONE/IRON gibt es noch kein eigenes Modul, dafür
		# bleibt das generische Sinus-Wippen als Fallback erhalten.
		var bob_y: float = 0.0
		var rot_x: float = 0.0
		var rot_z: float = 0.0
		var ab_res: String = ""
		if fe.assigned_building != null:
			ab_res = (fe.assigned_building as BuildingEntity).collects_resource

		if is_harvesting:
			match ab_res:
				"BERRIES":
					var pose: Dictionary = BerryHarvestAnimation.compute(fe.harvest_anim_t, FerretEntity.HARVEST_DURATION)
					bob_y = pose.bob_y; rot_x = pose.rot_x; rot_z = pose.rot_z
				"WOOD":
					var pose2: Dictionary = TreeFellingAnimation.compute(fe.harvest_anim_t, FerretEntity.HARVEST_DURATION)
					bob_y = pose2.bob_y; rot_x = pose2.rot_x; rot_z = pose2.rot_z
				_:
					# STONE/IRON (noch kein eigenes Modul) - generisches Wippen
					bob_y = absf(sin(fe.harvest_anim_t * 6.0)) * 0.12
					rot_x = sin(fe.harvest_anim_t * 6.0) * 0.18
		elif fe.work_state == "WORKING" and ab_res == "WATER":
			var pose3: Dictionary = WaterCollectAnimation.compute(fe.work_anim_t, FerretEntity.HARVEST_DURATION)
			bob_y = pose3.bob_y; rot_x = pose3.rot_x; rot_z = pose3.rot_z
		elif is_building:
			# Feature (v10.13): kleines, schnelles Hammer-Wippen für
			# Bau-Frettchen, die gerade physisch an einer Baustelle stehen
			# (work_state == "BUILDING", siehe FerretEntity._update_builder_work()).
			bob_y = absf(sin(fe.work_anim_t * 7.0)) * 0.08
			rot_x = sin(fe.work_anim_t * 7.0) * 0.22

		var anim: AnimationPlayer = fn.get_meta("anim_player", null) as AnimationPlayer
		if anim != null:
			if is_idle_at_work:
				# Bug-Fix (v10.12): AnimationPlayer hat in Godot 4 keine
				# pause()/is_paused()-Methoden (Engine-Fehler "Nonexistent
				# function 'is_paused'"). stop(true) hält die Wiedergabe an
				# UND friert die aktuell animierte Pose ein (kein Zurücksetzen
				# auf die Standard-Pose) - das ist das Godot-4-Äquivalent zu
				# "pausieren" für AnimationPlayer.
				if anim.is_playing():
					anim.stop(true)
			else:
				if not anim.is_playing():
					anim.play(str(fn.get_meta("anim_name", "Run")))
					anim.speed_scale = float(fn.get_meta("anim_base_speed", 1.0))
		fn.rotation.x = rot_x
		fn.rotation.z = rot_z

		fn.position = Vector3(wp3.x + sub_x, wp3.y + FERRET_Y + bob_y, wp3.z + sub_z)
		var dir: Vector2 = fe.target_pos - fe.pos
		if dir.length() > 0.05 and not is_idle_at_work:
			fn.rotation.y = atan2(dir.x, dir.y) + FERRET_ROT_OFFSET

		# Feature (v11.9, Legendäre Frettchen): Accessoires + "Holy Glow" nur
		# neu aufbauen, wenn sich das Legendär-Set tatsächlich geändert hat
		# (Performance) - realistisch ändert sich das höchstens 1x pro
		# Frettchen-Leben (beim Legendär-Werden), NIE danach.
		var legend_key: String = ""
		if fe.is_legendary:
			legend_key = ",".join(PackedStringArray(fe.legendary_accessories))
		if str(fn.get_meta("legend_key", "")) != legend_key:
			_clear_ferret_accessories(fn)
			if fe.is_legendary:
				_attach_ferret_accessories(fn, fe.legendary_accessories)
				_attach_holy_glow(fn)
			fn.set_meta("legend_key", legend_key)
		if fe.is_legendary:
			var glow_light: OmniLight3D = fn.get_node_or_null("LegendaryFX/HolyGlowLight") as OmniLight3D
			if glow_light != null:
				# sanftes Pulsieren statt starrem Dauerlicht - "i" streut die
				# Phase zwischen mehreren legendären Frettchen.
				glow_light.light_energy = 1.0 + 0.45 * absf(sin(Time.get_ticks_msec() * 0.0018 + float(i)))

## Feature (v11.9, Legendäre Frettchen): entfernt alle Kind-Nodes des
## LegendaryFX-Ankers (Accessoires + Glow-Licht/-Sprite) - Vorbereitung für
## einen Neuaufbau nach einer Set-Änderung, siehe update_ferrets() oben.
## Bug-Fix (v11.18): Accessoires hängen seit diesem Fix direkt an "fn"
## (siehe _attach_ferret_accessories()), NICHT mehr am LegendaryFX-Anker -
## dieser trägt jetzt nur noch den Holy-Glow-Effekt. Diese Funktion muss
## deshalb BEIDE Stellen leeren: per Namens-Präfix markierte Accessoire-
## Kinder direkt an "fn", plus alle Kinder von "LegendaryFX" (Glow-Licht/
## -Sprite).
func _clear_ferret_accessories(fn: Node3D) -> void:
	for c in fn.get_children():
		if str(c.name).begins_with("AccessoryItem_"): c.queue_free()
	var fx: Node3D = fn.get_node_or_null("LegendaryFX")
	if fx != null:
		for c in fx.get_children(): c.queue_free()

## Feature (v11.9, Legendäre Frettchen): instanziiert das individuelle
## Accessoire-Set (siehe FerretAccessories.pick_random_set()) unter dem
## LegendaryFX-Anker des Frettchens.
## Bug-Fix (v11.16): Nutzer meldete, dass Accessoires trotz korrekt
## gefüllter Daten (Profil-Panel zeigt sie an) NICHT sichtbar im 3D-Modell
## erscheinen, während "Holy Glow" (nativ per OmniLight3D/MeshInstance3D
## erzeugt statt aus einer .glb geladen) einwandfrei rendert. Datei-Analyse
## (Material-Werte, Mesh-Geometrie, glTF-Struktur) ergab KEINEN erkennbaren
## Fehler in den .glb-Dateien selbst - ohne Godot-Editor liess sich die
## exakte Ursache nicht abschliessend verifizieren. Dieses Logging macht
## einen etwaigen stillen Lade-/Instanziierungs-Fehlschlag (z.B. falls
## Godot die neu hinzugefügten .glb-Dateien noch nicht importiert hat)
## sichtbar, statt ihn kommentarlos zu ignorieren - siehe General.md für
## die vollständige Fehlersuche-Dokumentation dieser Session.
## Bug-Fix (v11.18): Nutzer meldete per Screenshot ein riesiges, falsch
## positioniertes Accessoire (Farbe passte zu "Schal") statt eines gar nicht
## sichtbaren - das widerlegt die frühere Theorie eines Lade-Fehlschlags
## und deutet auf ein Skalierungs-/Transform-Problem hin. Datei-seitig
## (Material, Mesh-Geometrie, glTF-Struktur, Skalierungs-Rechnung von Hand)
## liess sich KEIN Fehler finden, aber die vorherige Konstruktion (Accessoire
## als Kind eines GEGEN-skalierten LegendaryFX-Ankers, der wiederum Kind des
## 2.2x-skalierten Frettchens ist - zwei ineinander verschachtelte
## Skalierungs-Stufen) war unnötig fehleranfällig. Jetzt: Accessoires
## hängen DIREKT an "fn" (dem Frettchen-Root), mit Position UND Skalierung
## explizit VORBERECHNET (durch FERRET_MODEL_SCALE geteilt) statt sich auf
## eine automatische Aufhebung durch die Elternkette zu verlassen - weniger
## Verschachtelung, weniger Fehlerüllen, leichter nachvollziehbar. Die
## GLB-Dateien selbst wurden zusätzlich neu generiert (fehlende
## Vertex-Normalen ergänzt, echte Lücke gegenüber der glTF-Spec-Empfehlung).
func _attach_ferret_accessories(fn: Node3D, accessory_ids: Array) -> void:
	for aid in accessory_ids:
		var ad: Dictionary = FerretAccessories.get_accessory(str(aid))
		if ad.is_empty():
			push_warning("FerretAccessories: unbekannte Accessoire-ID '%s'" % str(aid))
			continue
		var scene: PackedScene = ACCESSORY_SCENES.get(str(aid), null) as PackedScene
		if scene == null:
			push_warning("Accessoire-Szene nicht geladen (preload fehlgeschlagen?): '%s'" % str(aid))
			continue
		var acc_inst := scene.instantiate() as Node3D
		if acc_inst == null:
			push_warning("Accessoire '%s': instantiate() lieferte kein Node3D (Szenen-Root falscher Typ?)." % str(aid))
			continue
		acc_inst.name = "AccessoryItem_" + str(aid)
		_disable_shadows(acc_inst)
		acc_inst.visible = true
		# Bug-Fix (v11.20): zusätzlich zum Skalierungs-Fix aus v11.19 wurde
		# ein Achsen-Konventionsfehler in den .glb-Dateien selbst behoben
		# (trimesh baut Primitive standardmässig mit "Höhe" entlang der
		# Z-Achse, glTF/Godot erwarten Y-als-oben) - betraf v.a. Kopf-
		# Accessoires (Krone/Zylinder/Zauberhut), die dadurch "liegend" statt
		# "stehend" erschienen und ür ins Frettchen hineinstecken konnten.
		# Siehe General.md für Details zur Korrektur der .glb-Dateien selbst.
		# Revert (v11.23): der v11.22-Versuch (Position durch
		# FERRET_MODEL_SCALE teilen + acc_inst.scale = 1/FERRET_MODEL_SCALE)
		# beruhte auf einer FALSCHEN Annahme - dass die "offset"-Werte in
		# FerretAccessories.gd als reale End-Meter gedacht seien und noch
		# eine Gegen-Skalierung fehlte. Tatsächlich war aber der Zylinderhut
		# bereits VOR diesem Versuch korrekt positioniert (vom Nutzer in
		# v11.21 bestätigt) - d.h. die Offsets waren schon immer für genau
		# DIESES Setup kalibriert (direktes Kind von "fn", keine
		# Gegen-Skalierung; die .glb-Meshes selbst wurden bewusst klein
		# gebaut, damit sie durch fn's 2.2x-Skalierung auf sichtbare Grösse
		# aufgeblasen werden). Der v11.22-Fix hat dadurch alle Accessoires
		# zusätzlich um 2.2x verkleinert UND ihre Weltposition von
		# offset*2.2 auf schlicht offset reduziert - Nutzer-Feedback:
		# Accessoires danach komplett unsichtbar (vermutlich zu klein und zu
		# tief im Körper-Mesh vergraben). Zurück zum Original-Verhalten:
		# acc_inst OHNE eigene Skalierung, Position direkt = offset (wird
		# über fn's geerbte 2.2x-Skalierung automatisch korrekt aufgeblasen
		# UND positioniert).
		# Fix v11.24 (auf Basis exakter trimesh-Vermessung von ferret.glb,
		# statt Schätzwerten): Body_mesh belegt exakt X[-0.065,0.065]
		# Y[0.13,0.27] Z[-0.21,0.21], Head_mesh exakt X[-0.05,0.05]
		# Y[0.19,0.29] Z[0.21,0.33] - beide stossen bei Z=0.21 NAHTLOS
		# aneinander (kein Lücken-/Kehlbereich). NECK-Accessoires (Fliege/
		# Schal/Medaille) lagen bisher bei Z≈0.18-0.19 - das ist WEIT INNEN
		# in der massiven Body-Box (numerisch bestätigt), daher unsichtbar.
		# Tatsächlich gibt es aber eine echte Lücke: für Y<0.19 (unterhalb
		# von Head_mesh) UND Z>0.21 (ausserhalb von Body_mesh) existiert GAR
		# KEINE Geometrie ("Kehlnische" unterhalb des Kopfes). Neue Offsets
		# für BOWTIE/MEDAL/SCARF liegen jetzt in genau dieser Nische (siehe
		# FerretAccessories.gd für die einzelnen, per Mesh-Extents
		# durchgerechneten Werte). CAPE bekommt zusätzlich ein optionales
		# "rot_x" (X-Achsen-Rotation): eine an Y hängende, papierdünne
		# Flagge kollidiert bei JEDER Z-Position innerhalb der Body-Box
		# zwangsläufig mit deren massivem Volumen (Y=0.13-0.27 UND
		# Z=-0.21..0.21 überschneiden sich mit dem Körper komplett). Mit
		# rot_x=PI/2 wird die Flagge stattdessen zu einem dünnen,
		# waagerechten Rücken-Umhang, der OBERHALB der Body-Mesh-Oberkante
		# (Y=0.27) aufliegt statt durch den Körper zu clippen.
		acc_inst.position = ad.get("offset", Vector3.ZERO) as Vector3
		acc_inst.rotation.x = float(ad.get("rot_x", 0.0))
		acc_inst.rotation.y = float(ad.get("rot_y", 0.0))
		fn.add_child(acc_inst)

## Feature (v11.9, Legendäre Frettchen): "Holy Glow" - ein warmes, goldenes
## Licht (OmniLight3D, in update_ferrets() sanft pulsierend) plus eine kleine
## additiv-transparente, unshaded Glorienschein-Kugel (kein HDR-Bloom im
## Projekt vorausgesetzt, daher eigenständig emissiv statt bloom-abhängig).
func _attach_holy_glow(fn: Node3D) -> void:
	var fx: Node3D = fn.get_node_or_null("LegendaryFX")
	if fx == null: return
	var light := OmniLight3D.new(); light.name = "HolyGlowLight"
	light.light_color = Color(1.0, 0.85, 0.35)
	light.light_energy = 1.1
	light.omni_range = 2.2
	light.position = Vector3(0, 0.25, 0)
	fx.add_child(light)

	var glow := MeshInstance3D.new(); glow.name = "HolyGlowSprite"
	var sm := SphereMesh.new(); sm.radius = 0.22; sm.height = 0.44
	glow.mesh = sm
	var gm := StandardMaterial3D.new()
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(1.0, 0.9, 0.5, 0.22)
	gm.emission_enabled = true
	gm.emission = Color(1.0, 0.85, 0.4)
	gm.emission_energy_multiplier = 1.2
	glow.material_override = gm
	glow.position = Vector3(0, 0.22, 0)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(glow)

## Feature (v11.9, Frettchen-Klick-Interaktion): da Frettchen keine
## Collision-Shapes haben (siehe FERRET_CLICK_RADIUS_PX weiter oben), wird
## für jedes sichtbare Frettchen-Node dessen 3D-Position auf den Bildschirm
## projiziert (Camera3D.unproject_position()) und der Pixel-Abstand zur
## Klick-Position gemessen - das nächste Frettchen innerhalb des Radius
## gilt als getroffen. Reihenfolge _ferret_nodes[i] <-> ferrets[i] gilt nur
## INNERHALB desselben update_ferrets()-Aufrufs (siehe dortiger Kommentar),
## daher muss "ferrets" hier exakt das Array sein, das zuletzt an
## update_ferrets() übergeben wurde (PopMgr.ferrets - siehe GameController).
func find_ferret_at_screen_pos(screen_pos: Vector2, camera: Camera3D, ferrets: Array) -> FerretEntity:
	if camera == null: return null
	var best: FerretEntity = null
	var best_d: float = FERRET_CLICK_RADIUS_PX
	for i in mini(_ferret_nodes.size(), ferrets.size()):
		var fn: Node3D = _ferret_nodes[i] as Node3D
		if fn == null or not fn.visible: continue
		var world_p: Vector3 = fn.global_position + Vector3(0, 0.3, 0)
		if camera.is_position_behind(world_p): continue
		var screen_p: Vector2 = camera.unproject_position(world_p)
		var d: float = screen_p.distance_to(screen_pos)
		if d < best_d:
			best_d = d; best = ferrets[i] as FerretEntity
	return best

## Schaltet Schatten für ein importiertes Modell (und alle Kind-Meshes) aus,
## da viele kleine Frettchen-Modelle sonst unnötig Rendering-Last erzeugen.
func _disable_shadows(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_disable_shadows(c)

## Feature (v14.4, Nutzerwunsch "Cosy-Interaktionen mit anderen Frettchen"):
## findet das nächstgelegene NPC-Frettchen zu einer 3D-Weltposition (nicht
## bildschirmprojektionsbasiert wie find_ferret_at_screen_pos() - das hier
## läuft unabhängig von der Kamera, damit das Frettchen-Ich auch von hinten/
## seitlich erkennt, wenn ein Kolonie-Frettchen nah genug zum Streicheln ist).
func find_nearest_ferret_3d(world_pos: Vector3, ferrets: Array, max_dist: float) -> FerretEntity:
	var best: FerretEntity = null
	var best_d: float = max_dist
	for i in mini(_ferret_nodes.size(), ferrets.size()):
		var fn: Node3D = _ferret_nodes[i] as Node3D
		if fn == null or not is_instance_valid(fn) or not fn.visible: continue
		var d: float = world_pos.distance_to(fn.global_position)
		if d < best_d:
			best_d = d; best = ferrets[i] as FerretEntity
	return best

func _clear_ferrets() -> void:
	for n in _ferret_nodes:
		if is_instance_valid(n): (n as Node).queue_free()
	_ferret_nodes.clear()
