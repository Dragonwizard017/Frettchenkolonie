class_name BuildingTooltip
extends RefCounted
## Tooltip-Inhalt für Gebäude im Baumenü (v15.7).
##
## Liefert BBCode für ein RichTextLabel. ALLE Zahlen werden mit denselben Formeln wie die
## Produktion selbst berechnet (BuildingEntity._collect/_process/_multi_process/_hunt/_farmhouse),
## damit der Tooltip nichts verspricht, was das Spiel nicht hält. Ändert sich eine Formel dort,
## muss sie hier mitgezogen werden (Konstanten stehen unten mit Verweis).
##
## Aufbau: Kopf (Name, Typ, Epoche) · Beschreibung · PRODUKTION · BEDARF · GEBÄUDE (Arbeiter, Kosten).

# ── Formel-Konstanten (Spiegel der Werte in BuildingEntity) ──────────────────────────────────
const COLLECT_FACTOR: float = 0.35      # BuildingEntity._collect: production_speed * workers * 0.35 / s
const NO_NODE_FACTOR: float = 0.35      # kein Ressourcen-Vorkommen im Radius -> Ertrag * 0.35
const WATER_FLOOR: float = 0.22         # Brunnen-Grundsockel (ohne Wasser in der Nähe)
const WATER_MAX: float = 1.22           # Grundsockel + max. Nähe-Bonus
const HUNT_FACTOR: float = 0.04         # BuildingEntity._hunt
const FARM_INTERVAL: float = 5.0        # BuildingEntity.FARMHOUSE_BASE_INTERVAL
const FARM_YIELD: float = 12.0          # BuildingEntity.FARMHOUSE_HARVEST_YIELD
const FARM_GROWTH: float = 200.0        # FarmFieldSystem.GROWTH_TIME
const UPGRADE_BONUS: float = 0.35       # +35 % je Stufe (Sammler)
const LOCAL_STORAGE: float = 50.0       # BuildingEntity.LOCAL_STORAGE_CAPACITY

const RES_NAMES: Dictionary = {
	"WOOD": "Holz", "STONE": "Stein", "BERRIES": "Beeren", "WATER": "Wasser", "PLANKS": "Bretter",
	"TOOLS": "Werkzeuge", "FOOD": "Essen", "IRON": "Eisen", "IRON_BARS": "Eisenbarren",
	"MACHINES": "Maschinen", "COAL": "Kohle", "STEEL": "Stahl", "MEAT": "Fleisch", "WHEAT": "Weizen",
	"DYNAMITE": "Dynamit", "COOKED_MEAT": "Braten", "BREAD": "Brot", "STEW": "Eintopf", "SCIENCE": "Wissenspunkte"}

## Wofür steht das "Vorkommen" im Radius (nur für Ressourcen mit Ertragsmalus ohne Vorkommen)?
const NODE_NAMES: Dictionary = {
	"WOOD": "Bäume", "STONE": "Felsen", "BERRIES": "Beerenbüsche", "IRON": "Erzvorkommen"}

const TYPE_LABELS: Dictionary = {
	"BUILDER": "Bauhof", "COLLECTOR": "Sammler", "DAM": "Wasserbau", "STORAGE": "Lager",
	"HOUSING": "Wohnen", "HAPPINESS": "Stimmung", "FORESTER": "Forstwirtschaft", "GRAVEYARD": "Gedenkstätte",
	"DECO": "Dekoration", "PROCESSOR": "Verarbeitung", "DISTRICT_GATE": "Bezirk", "TOWN_HALL": "Kolonie", "EXPLORER": "Erkundung", "STATION": "Schiene", "DEPOT": "Schiene", "FARMHOUSE": "Landwirtschaft",
	"WATERWHEEL": "Antrieb", "EXPEDITION": "Expedition", "MULTIPROCESSOR": "Küche", "HUNTER": "Jagd"}

## Kurzbeschreibungen. Fehlt eine ID, greift DESC_BY_TYPE bzw. das `desc`-Feld aus BuildingData.
const DESC: Dictionary = {
	"CONSTRUCTION_YARD_1": "Frettchen arbeiten hier als Bauarbeiter und errichten die platzierten Gebäude.",
	"LUMBERJACK": "Fällt Bäume in der Umgebung und liefert Holz.",
	"QUARRY": "Baut Stein aus Felsen in der Umgebung ab.",
	"QUARRY_ADV": "Größerer Steinbruch: mehr Arbeiter, größerer Radius, höherer Ertrag.",
	"BERRY_GATHERER": "Sammelt Beeren von Büschen in der Umgebung - die wichtigste frühe Nahrungsquelle.",
	"WELL": "Fördert Grundwasser. Je näher an See oder Fluss, desto ergiebiger.",
	"WATER_TOWER": "Leistungsstarke Wasserförderung mit großem Radius und eigenem Wasserlager.",
	"WATER_PUMP": "Pumpt Wasser aus der Umgebung, ergiebiger als ein Brunnen.",
	"AQUEDUCT": "Fördert und verteilt Wasser über einen sehr großen Radius.",
	"IRRIGATION": "Leitet Wasser über Kanäle heran und lagert es.",
	"GARDEN": "Zieht Beeren heran und hebt nebenbei die Stimmung.",
	"GARDEN_ADV": "Gewächshaus: deutlich höherer Beeren-Ertrag als der einfache Garten.",
	"IRON_MINE": "Fördert Eisenerz aus Vorkommen in der Umgebung.",
	"COAL_MINE": "Fördert Kohle.",
	"RESEARCH_HUT": "Produziert Wissenspunkte für den Technologiebaum.",
	"RESERVOIR": "Speichert Wasser - ein Puffer für Dürrezeiten.",
	"FOOD_STORE": "Lager für Nahrung mit großer Kapazität.",
	"HOUSE": "Wohnraum für Frettchen. Ohne freie Betten wächst die Kolonie nicht.",
	"HOUSE_ADV": "Wohnraum für mehr Frettchen und Stimmungsbonus in der Nähe.",
	"GATHERING_PLACE": "Treffpunkt, der die Stimmung in der Umgebung hebt.",
	"FORESTER": "Pflanzt neue Bäume, damit den Holzfällern das Holz nicht ausgeht.",
	"GRAVEYARD": "Gedenkstätte für verstorbene Frettchen (Name, Tag und Ursache).",
	"HUNTER_HUT": "Jäger erlegen Wild in der Umgebung und liefern Fleisch.",
	"COOKHOUSE": "Verarbeitet Nahrungsmittel zu höherwertigen Gerichten.",
	"FARMHOUSE": "Arbeiter säen, ernten und bestellen die Felder, die du im Bezirk markierst.",
	"WATERWHEEL": "Treibt Verarbeiter und Sammler in der Nähe an und steigert deren Ertrag.",
}
const DESC_BY_TYPE: Dictionary = {
	"BUILDER": "Bauhof: hier arbeiten Frettchen als Bauarbeiter.",
	"STORAGE": "Lagert Waren der Kolonie; Lagerarbeiter bringen die Ressourcen hierher.",
	"HAPPINESS": "Hebt die Stimmung der Frettchen im Umkreis.",
	"DECO": "Dekoration: hebt die Stimmung im Umkreis.",
	"DAM": "Staut Wasser auf - hält Flüsse und Seen in der Dürre länger gefüllt.",
}

# ── Öffentliche API ──────────────────────────────────────────────────────────────────────────
static func build(bid: String) -> String:
	if not BuildingData.BUILDINGS.has(bid): return ""
	var d: Dictionary = BuildingData.BUILDINGS[bid] as Dictionary
	var t: String = str(d.get("type", ""))
	var out: PackedStringArray = []
	# Kopf
	out.append("[font_size=18][b]%s  %s[/b][/font_size]" % [str(d.get("icon", "")), str(d.get("name", bid))])
	out.append(_c("%s · Epoche %d" % [str(TYPE_LABELS.get(t, t)), int(d.get("epoch", 1))], UITheme.C_TEXT_MUTED))
	# Beschreibung
	var desc: String = str(DESC.get(bid, ""))
	if desc == "": desc = str(d.get("desc", ""))
	if desc == "": desc = str(DESC_BY_TYPE.get(t, ""))
	if desc != "": out.append(desc)
	# Produktion / Bedarf je Typ
	var prod: PackedStringArray = []
	var need: PackedStringArray = []
	match t:
		"COLLECTOR": _collector(d, prod, need)
		"PROCESSOR": _processor(d, prod, need)
		"MULTIPROCESSOR": _multi(d, prod, need)
		"HUNTER": _hunter(d, prod, need)
		"FARMHOUSE": _farm(d, prod, need)
		"HOUSING": _housing(d, prod)
		"STORAGE": _storage(d, prod)
		"WATERWHEEL": _wheel(d, prod, need)
		"FORESTER": prod.append("Pflanzt Bäume im Radius von %d Kacheln." % int(d.get("planting_radius", 0)))
		"DISTRICT_GATE": prod.append("Verbindet die Lager benachbarter Bezirke (Radius %d), solange hier jemand arbeitet." % int(d.get("collection_radius", 0)))
		"EXPLORER": prod.append("Deckt den Nebel im Umkreis (Radius %d, +50%% je Upgrade) nach und nach auf, solange Frettchen hier arbeiten. Aufgedecktes Gebiet wird bebaubar." % int(d.get("collection_radius", 0)))
		"STATION": prod.append("Haltestelle für Güterzüge: Züge laden hier Waren aus dem Lager der Kolonie und liefern Waren aus anderen Kolonien ab.")
		"DEPOT": prod.append("Hier werden Züge gekauft und abgestellt. Ein Zug braucht eine Linie (🚂-Knopf) und ein Gleisnetz zu den Bahnhöfen.")
		"TOWN_HALL": prod.append("Gründet eine neue Kolonie mit Gebiet (Radius %d), eigenem Lager und eigener Bevölkerung. Mind. %d Kacheln Abstand zu jedem Rathaus, %d Frettchen als Siedler." % [int(d.get("territory_radius", 0)), int(ColonySys.MIN_HALL_DISTANCE), ColonySys.SETTLERS])
	if t in ["HAPPINESS", "DECO", "GRAVEYARD"] or (int(d.get("happiness_bonus", 0)) > 0 and t == "COLLECTOR"):
		_happiness(d, prod)
	if not prod.is_empty():
		out.append(_head("PRODUKTION")); out.append_array(prod)
	if not need.is_empty():
		out.append(_head("BEDARF")); out.append_array(need)
	# Gebäude
	var info: PackedStringArray = []
	var mw: int = int(d.get("max_workers", 0))
	if mw > 0: info.append("Arbeiter: bis zu %d" % mw)
	info.append("Bauaufwand: %d" % int(d.get("construction_work", 0)))
	info.append("Kosten: " + costs_rich(d.get("costs", {}) as Dictionary))
	if t in ["COLLECTOR"]:
		info.append(_c("Ausbau bis Stufe 3: +%d %% Ertrag je Stufe" % int(UPGRADE_BONUS * 100.0), UITheme.C_TEXT_MUTED))
	out.append(_head("GEBÄUDE")); out.append_array(info)
	return "\n".join(out)

## Kostenzeile (getönte Icons, nicht bezahlbare Beträge rot) - auch vom Baumenü genutzt.
static func costs_rich(costs: Dictionary) -> String:
	var parts: Array = []
	for res in costs:
		var r: String = str(res)
		var need_amt: float = float(costs[res])
		var amount_col: Color = UITheme.C_TEXT if ResourceSys.has(r, need_amt) else UITheme.C_DANGER
		parts.append("%s [color=%s]%s[/color]" % [ic(r), UITheme.hex(amount_col), str(costs[res])])
	return "   ".join(parts) if not parts.is_empty() else "kostenlos"

## Getöntes Ressourcen-Icon als BBCode.
static func ic(res: String) -> String:
	var icons: Dictionary = BuildingData.RESOURCE_ICONS
	var col: Color = UITheme.RES_COLORS.get(res, UITheme.C_TEXT_MUTED)
	return "[color=%s]%s[/color]" % [UITheme.hex(col), str(icons.get(res, "?"))]

# ── Typ-Abschnitte ───────────────────────────────────────────────────────────────────────────
static func _collector(d: Dictionary, prod: PackedStringArray, need: PackedStringArray) -> void:
	var res: String = str(d.get("collects_resource", ""))
	var ps: float = float(d.get("production_speed", 1.0))
	var mw: int = int(d.get("max_workers", 1))
	var radius: int = int(d.get("collection_radius", 0))
	var per_worker: float = ps * COLLECT_FACTOR
	var full: float = per_worker * float(mw)
	if res == "WATER":
		prod.append("%s Wasser: %s bis %s (voll besetzt)" % [ic("WATER"), _min(full * WATER_FLOOR), _min(full * WATER_MAX)])
		if int(d.get("water_capacity", 0)) > 0:
			prod.append("Eigenes Wasserlager: +%d" % int(d.get("water_capacity", 0)))
		need.append("Wasser (See/Fluss) im Radius von %d Kacheln: je mehr, desto höher der Ertrag - ohne Wasser in der Nähe nur ca. %d %% des Maximums." % [radius, int(WATER_FLOOR * 100.0 / WATER_MAX)])
	elif res == "SCIENCE":
		prod.append("%s Wissenspunkte: %s (voll besetzt)" % [ic("SCIENCE"), _min(full)])
	elif res != "":
		prod.append("%s %s: %s (voll besetzt), %s je Arbeiter" % [ic(res), str(RES_NAMES.get(res, res)), _min(full), _min(per_worker)])
		if NODE_NAMES.has(res):
			need.append("%s im Radius von %d Kacheln - ohne nur %d %% Ertrag." % [str(NODE_NAMES[res]), radius, int(NO_NODE_FACTOR * 100.0)])
		elif radius > 0:
			need.append("Sammelradius: %d Kacheln." % radius)
		prod.append(_c("Frettchen bringen die Ware aus dem Zwischenlager (%d) ins Lager." % int(LOCAL_STORAGE), UITheme.C_TEXT_MUTED))

static func _processor(d: Dictionary, prod: PackedStringArray, need: PackedStringArray) -> void:
	var out_res: String = str(d.get("produces", ""))
	var chains: Dictionary = BuildingData.PRODUCTION_CHAINS
	if out_res == "" or not chains.has(out_res): return
	var chain: Dictionary = chains[out_res] as Dictionary
	_recipe_lines(chain, out_res, float(d.get("production_speed", 1.0)), prod, need)
	need.append(_c("Leistung steigt mit der Zahl der Arbeiter.", UITheme.C_TEXT_MUTED))

static func _multi(d: Dictionary, prod: PackedStringArray, need: PackedStringArray) -> void:
	var chains: Dictionary = BuildingData.PRODUCTION_CHAINS
	var ps: float = float(d.get("production_speed", 1.0))
	var recipes: Array = d.get("recipes", []) as Array
	var needed: Array = []
	for r in ["STEW", "COOKED_MEAT", "BREAD", "FOOD"]:
		if not (r in recipes) or not chains.has(r): continue
		_recipe_lines(chains[r] as Dictionary, r, ps, prod, need, true)
		for k in (chains[r] as Dictionary).get("inputs", {}):
			if not (str(k) in needed): needed.append(str(k))
	prod.append(_c("Wählt selbst das höchstwertige Rezept, für das Zutaten im Lager sind (Eintopf > Braten > Brot > Essen).", UITheme.C_TEXT_MUTED))
	var names: PackedStringArray = []
	for k2 in needed: names.append("%s %s" % [ic(str(k2)), str(RES_NAMES.get(str(k2), str(k2)))])
	need.append("Zutaten im Lager: " + ", ".join(names))

static func _recipe_lines(chain: Dictionary, out_res: String, ps: float, prod: PackedStringArray, need: PackedStringArray, compact: bool = false) -> void:
	var inputs: Dictionary = chain.get("inputs", {}) as Dictionary
	var out_n: float = float(chain.get("output", 1.0))
	var time: float = float(chain.get("time", 5.0))
	var cycle: float = time / maxf(0.01, ps)        # Sekunden je Zyklus (voll besetzt)
	var in_txt: PackedStringArray = []
	var use_txt: PackedStringArray = []
	for k in inputs:
		in_txt.append("%d× %s %s" % [int(inputs[k]), ic(str(k)), str(RES_NAMES.get(str(k), str(k)))])
		use_txt.append("%s %s" % [_min(float(inputs[k]) / cycle), str(RES_NAMES.get(str(k), str(k)))])
	prod.append("%s → %d× %s %s  (alle %.1f s)" % [", ".join(in_txt), int(out_n), ic(out_res), str(RES_NAMES.get(out_res, out_res)), cycle])
	if compact:
		return     # Küche: Rezeptzeile genügt, Bedarf wird gesammelt ausgegeben
	prod.append("Durchsatz: %s %s (voll besetzt)" % [_min(out_n / cycle), str(RES_NAMES.get(out_res, out_res))])
	need.append("Verbraucht: %s" % ", ".join(use_txt))
	need.append("Die Zutaten müssen im Lager vorhanden sein.")

static func _hunter(d: Dictionary, prod: PackedStringArray, need: PackedStringArray) -> void:
	var ps: float = float(d.get("production_speed", 1.0))
	var mw: int = int(d.get("max_workers", 1))
	prod.append("%s Fleisch: %s (voll besetzt)" % [ic("MEAT"), _min(ps * float(maxi(1, mw)) * HUNT_FACTOR)])
	need.append("Jagdradius: %d Kacheln." % int(d.get("collection_radius", 0)))
	prod.append(_c("Fleisch wird im Kochhaus zu Braten weiterverarbeitet.", UITheme.C_TEXT_MUTED))

static func _farm(d: Dictionary, prod: PackedStringArray, need: PackedStringArray) -> void:
	var ps: float = float(d.get("production_speed", 1.0))
	var mw: int = int(d.get("max_workers", 1))
	var interval: float = FARM_INTERVAL / (float(mw) * ps)
	var per_field: float = FARM_YIELD / FARM_GROWTH * 60.0
	var worker_cap: float = FARM_YIELD / (2.0 * interval) * 60.0
	prod.append("%s Weizen: %d je Ernte; pro Feld ca. %s (Wachstum ~%d s)" % [ic("WHEAT"), int(FARM_YIELD), _min(per_field / 60.0), int(FARM_GROWTH)])
	prod.append("Arbeiter-Limit: ca. %d Felder gleichzeitig (voll besetzt)" % int(round(worker_cap / per_field)))
	need.append("Vom Spieler gesetzte Feld-Kacheln im selben Bezirk (Wiese).")
	need.append("Mehr Felder = mehr Ertrag, bis die Arbeiter nicht mehr hinterherkommen.")

static func _housing(d: Dictionary, prod: PackedStringArray) -> void:
	prod.append("Wohnplätze: %d Frettchen" % int(d.get("max_residents", 0)))
	_happiness(d, prod)

static func _storage(d: Dictionary, prod: PackedStringArray) -> void:
	if int(d.get("storage_capacity", 0)) > 0:
		prod.append("Lagerkapazität: +%d" % int(d.get("storage_capacity", 0)))
	if int(d.get("water_capacity", 0)) > 0:
		prod.append("%s Wasserlager: +%d" % [ic("WATER"), int(d.get("water_capacity", 0))])

static func _wheel(d: Dictionary, prod: PackedStringArray, need: PackedStringArray) -> void:
	prod.append("+%d %% Ertrag für Gebäude im Radius von %d Kacheln" % [int(float(d.get("boost_factor", 0.0)) * 100.0), int(d.get("boost_radius", 0))])
	need.append("Wasser in der Nähe, damit sich das Rad dreht.")

static func _happiness(d: Dictionary, prod: PackedStringArray) -> void:
	var hb: int = int(d.get("happiness_bonus", 0))
	if hb <= 0: return
	var r: int = int(d.get("happiness_radius", 0))
	if r > 0: prod.append("Stimmung: +%d im Umkreis von %d Kacheln" % [hb, r])
	else: prod.append("Stimmung: +%d" % hb)

# ── Format-Helfer ────────────────────────────────────────────────────────────────────────────
static func _head(txt: String) -> String:
	return "[color=%s][b][font_size=12]%s[/font_size][/b][/color]" % [UITheme.hex(UITheme.C_ACCENT), txt]

static func _c(txt: String, col: Color) -> String:
	return "[color=%s]%s[/color]" % [UITheme.hex(col), txt]

## Rate pro Sekunde -> "x / Min."
static func _min(per_sec: float) -> String:
	var m: float = per_sec * 60.0
	if m >= 100.0: return "%d / Min." % int(round(m))
	if m >= 10.0: return "%.0f / Min." % m
	return "%.1f / Min." % m
