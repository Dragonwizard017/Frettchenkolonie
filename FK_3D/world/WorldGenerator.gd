## WorldGenerator.gd
class_name WorldGenerator
extends RefCounted

# ── Perlin Noise (innere Klasse) ──────────────────────────────────────────────
class PerlinNoise:
	var _perm: Array = []

	func _init(seed_val: int = 0) -> void:
		_perm.resize(512)
		var p: Array = []
		p.resize(256)
		for i in 256:
			p[i] = i
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_val
		for i in range(255, 0, -1):
			var j: int = rng.randi_range(0, i)
			var tmp: int = p[i]
			p[i] = p[j]
			p[j] = tmp
		for i in 256:
			_perm[i] = p[i]
			_perm[i + 256] = p[i]

	func _fade(t: float) -> float:
		return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)

	func _lerpf(a: float, b: float, t: float) -> float:
		return a + t * (b - a)

	func _grad(h: int, x: float, y: float) -> float:
		match (h & 3):
			0: return  x + y
			1: return -x + y
			2: return  x - y
			3: return -x - y
		return 0.0

	# Renamed from get() to sample() to avoid conflict with Object.get()
	func sample(x: float, y: float) -> float:
		var xi: int = int(floor(x)) & 255
		var yi: int = int(floor(y)) & 255
		var xf: float = x - floor(x)
		var yf: float = y - floor(y)
		var u: float = _fade(xf)
		var v: float = _fade(yf)
		var aa: int = _perm[_perm[xi] + yi]
		var ab: int = _perm[_perm[xi] + yi + 1]
		var ba: int = _perm[_perm[xi + 1] + yi]
		var bb: int = _perm[_perm[xi + 1] + yi + 1]
		return _lerpf(
			_lerpf(_grad(aa, xf, yf),       _grad(ba, xf - 1.0, yf),       u),
			_lerpf(_grad(ab, xf, yf - 1.0), _grad(bb, xf - 1.0, yf - 1.0), u),
			v
		)

# ── Welt ──────────────────────────────────────────────────────────────────────
var w: int = 60
var h: int = 60
var seed_val: int = 0

func generate(world_size: String, seed_str: String) -> Array:
	match world_size:
		"SMALL":  w = 40; h = 40
		"MEDIUM": w = 60; h = 60
		"LARGE":  w = 80; h = 80
		"HUGE":   w = 120; h = 120   # v16.6: Entdeckerkarte (Nebel, siehe ExploreSystem.gd)

	seed_val = seed_str.strip_edges().hash() if seed_str.strip_edges() != "" else randi()
	# Bug-Fix (v10.14): "Welt-Seed erzeugt keine vollständig reproduzierbare
	# Welt". Bisher wurde NUR das Perlin-Noise mit seed_val geseedet - alle
	# anderen Zufallsentscheidungen (Resource-Node-Platzierung weiter unten,
	# Ruinen, Baum-/Busch-Grössenvarianz in WorldRenderer3D, Start-Position
	# der Frettchen) liefen über Godots GLOBALEN RNG und blieben dadurch bei
	# jedem Versuch unterschiedlich, selbst mit identischem Seed. `seed()`
	# setzt diesen globalen RNG ebenfalls fest - solange die Generierung
	# danach immer in derselben Reihenfolge dieselbe Anzahl Zufallsaufrufe
	# macht (das ist hier der Fall), liefert derselbe Seed jetzt durchgehend
	# dieselbe komplette Welt.
	seed(seed_val)

	var noise := PerlinNoise.new(seed_val)
	var world: Array = []

	for x in w:
		var col: Array = []
		for y in h:
			var nx: float = float(x) / float(w) * 4.0
			var ny: float = float(y) / float(h) * 4.0
			# Bug-Fix (v10.10): Die Biom-/Höhenentscheidung nutzte bisher eine
			# 3-Oktaven-Mischung (0.6/0.3/0.1) inkl. einer hochfrequenten
			# 4x-Oktave. Nahe der WATER-Schwelle (n<0.25) erzeugte genau diese
			# hochfrequente Oktave wiederholt dünne, parallele diagonale
			# "Risse" (der Gesamtwert oszilliert mehrfach knapp unter/über die
			# Schwelle) statt zusammenhängender Seen/Flüsse - sichtbar als
			# regelmässige blaue Streifen ür durchs Land. Für die Biom-
			# Entscheidung wird daher nur noch die glatte, niedrigfrequente
			# Basis (n_smooth, 2 Oktaven OHNE die 4x-Oktave) verwendet; die
			# feine Oktave (detail) bleibt erhalten und sorgt nur noch für
			# kleine optische Höhenvariation INNERHALB eines Bioms, ohne die
			# Schwelle selbst flackern zu lassen.
			var base0: float = noise.sample(nx, ny)
			var base1: float = noise.sample(nx * 2.0, ny * 2.0)
			var detail: float = noise.sample(nx * 4.0, ny * 4.0)
			var n_smooth: float = base0 * 0.7 + base1 * 0.3
			n_smooth = (n_smooth + 1.0) / 2.0
			var n: float = clampf(n_smooth + detail * 0.05, 0.0, 1.0)

			var biome: String
			if n_smooth < 0.25:
				biome = "WATER"
			elif n_smooth < 0.38:
				biome = "BEACH"
			elif n_smooth < 0.6:
				biome = "PLAINS"
			elif n_smooth < 0.72:
				biome = "FOREST"
			elif n_smooth < 0.82:
				biome = "HILLS"
			else:
				biome = "MOUNTAIN"
			# Bug-Fix (v10.10): einheitliche, stetige Höhenformel über ALLE
			# Biome hinweg statt einer pro Biom unterschiedlichen linearen
			# Formel (n*8 / n*12 / n*16). Die alten Formeln hatten an JEDER
			# Biom-Grenze einen Sprung in der Höhe (z.B. PLAINS bei n=0.72 ->
			# 5.76, HILLS bei genau demselben n -> 8.64) - das erzeugte
			# sichtbare Klippen/Stufen genau an den Biom-Übergängen, am
			# stärksten beim Sprung zu HILLS/MOUNTAIN ("Berge beginnen
			# abrupt"). Jetzt hängt die Höhe nur noch von n selbst ab
			# (quadratisch, damit niedriges Land flach bleibt und hohe Berge
			# überproportional aufsteigen) - an Biom-Grenzen ändert sich
			# dadurch nichts Abruptes mehr, der Übergang ist immer stetig.
			var height_val: float = n * n * 20.0

			col.append({
				"biome": biome, "height": height_val,
				"building": null, "path": null,
				"resource_node": null, "dynamite": false,
				# Wasserphysik (WaterSystem.gd): tatsächliche, simulierte
				# Wassertiefe über dem Tile-Bett. Seen/Flüsse starten mit
				# einem normalen Pegel von 1.0, alle anderen Tiles trocken (0.0).
				"water_level": 1.0 if biome == "WATER" else 0.0,
				"is_water_source": false
			})
		world.append(col)

	_place_resource_nodes(world, noise)
	# Feature (v14.4, gemeldet: "ich sehe auf der ganzen Karte kein Eisen/
	# Stein"): HILLS (Stein) und vor allem MOUNTAIN (Eisen) brauchen einen
	# hohen Rausch-Schwellenwert (n_smooth > 0.72 bzw. > 0.82) - bei manchen
	# zufälligen Seeds/Kartenregionen kommt dieser hohe Wert kaum oder gar
	# nicht vor, wodurch eine ganze Karte fast ohne Stein/Eisen entstehen
	# konnte (kein Bug in der Anzeige, sondern schon bei der Erzeugung zu
	# wenig da). Jetzt eine Mindestmenge JEDES der 4 Grundressourcentypen
	# garantiert, egal wie das Rauschen für diesen Seed ausgefallen ist.
	_guarantee_all_resource_types(world)
	_place_ruins(world)
	_place_water_sources(world)
	return world

## Stellt sicher, dass von JEDEM Grundressourcentyp (WOOD/STONE/BERRIES/IRON)
## eine spielbare Mindestmenge an Nodes existiert. Fehlt einer, werden
## zufällige, noch unbebaute Land-Tiles (nicht WATER/BEACH) direkt in das
## passende Biom + einen Resource-Node umgewandelt - bevorzugt noch ohne
## eigenen Node, damit nichts überschrieben wird, das schon etwas anderes ist.
const MIN_RESOURCE_NODES: int = 10

func _guarantee_all_resource_types(world: Array) -> void:
	var biome_for_res: Dictionary = {"WOOD": "FOREST", "STONE": "HILLS", "BERRIES": "PLAINS", "IRON": "MOUNTAIN"}
	var counts: Dictionary = {"WOOD": 0, "STONE": 0, "BERRIES": 0, "IRON": 0}
	var candidates: Array = []  # Tiles ohne resource_node, kein WATER/BEACH, keine Baustelle
	for x in w:
		for y in h:
			var tile: Dictionary = world[x][y]
			if tile["building"] != null: continue
			var nd = tile.get("resource_node")
			if nd != null and nd is Dictionary:
				var rt: String = str((nd as Dictionary).get("type", ""))
				if counts.has(rt): counts[rt] += 1
			else:
				var b: String = str(tile.get("biome", ""))
				if b != "WATER" and b != "BEACH":
					candidates.append(Vector2i(x, y))
	candidates.shuffle()
	var ci: int = 0
	for res_type in counts:
		var missing: int = MIN_RESOURCE_NODES - int(counts[res_type])
		while missing > 0 and ci < candidates.size():
			var p: Vector2i = candidates[ci]; ci += 1
			var tile: Dictionary = world[p.x][p.y]
			tile["biome"] = biome_for_res[res_type]
			var start_amount: float = randf_range(80.0, 200.0)
			tile["resource_node"] = {
				"type": res_type, "amount": start_amount,
				"max_amount": start_amount, "regen_timer": 0.0,
				"depleted": false
			}
			missing -= 1

## Feature (v16.6, Entdeckerkarte): Eisen liegt NICHT im Heimat-Bereich (Radius r0 um das Zentrum),
## sondern nur dahinter im Nebel. So lohnt sich Erkundung, und eine Bergbau-Kolonie samt Bahnstrecke
## wird zum natürlichen Ziel. Es bleiben mindestens MIN_RESOURCE_NODES Erzkacheln außerhalb.
func push_iron_outside(world: Array, cx: int, cy: int, r0: float) -> void:
	var outside: int = 0
	var spots: Array = []
	for x in w:
		for y in h:
			var tile: Dictionary = world[x][y]
			var d: float = Vector2(float(x - cx), float(y - cy)).length()
			var nd = tile.get("resource_node")
			var is_iron: bool = nd != null and nd is Dictionary and str((nd as Dictionary).get("type", "")) == "IRON"
			if d < r0:
				if is_iron: tile["resource_node"] = null
			else:
				if is_iron: outside += 1
				elif nd == null and tile["building"] == null and str(tile.get("biome", "")) == "MOUNTAIN" and d > r0 + 3.0:
					spots.append(Vector2i(x, y))
	spots.shuffle()
	var need: int = MIN_RESOURCE_NODES - outside
	var i: int = 0
	while need > 0 and i < spots.size():
		var p: Vector2i = spots[i]; i += 1
		var amount: float = randf_range(80.0, 200.0)
		(world[p.x][p.y] as Dictionary)["resource_node"] = {"type": "IRON", "amount": amount, "max_amount": amount, "regen_timer": 0.0, "depleted": false}
		need -= 1

## Findet jedes zusammenhängende Gewässer (Flood-Fill über WATER-Tiles) und
## markiert dessen "tiefste" Stelle(n) (= meiste Wasser-Nachbarn) als
## Wasserülle. Quellen speisen im WaterSystem kontinuierlich Wasser ein -
## das simuliert den Fluss-Zustrom von ausserhalb der Karte. Ohne diese
## Markierung würde jeder See/Fluss durch Verdunstung dauerhaft austrocknen.
func _place_water_sources(world: Array) -> void:
	var visited: Dictionary = {}
	for x in w:
		for y in h:
			var key: String = "%d,%d" % [x, y]
			if visited.has(key): continue
			if str(world[x][y].get("biome", "")) != "WATER":
				visited[key] = true
				continue
			var component: Array = []
			var stack: Array = [Vector2i(x, y)]
			visited[key] = true
			while not stack.is_empty():
				var p: Vector2i = stack.pop_back()
				component.append(p)
				for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
					var nx: int = p.x + d.x
					var ny: int = p.y + d.y
					if nx < 0 or ny < 0 or nx >= w or ny >= h: continue
					var nkey: String = "%d,%d" % [nx, ny]
					if visited.has(nkey): continue
					if str(world[nx][ny].get("biome", "")) != "WATER": continue
					visited[nkey] = true
					stack.append(Vector2i(nx, ny))
			if component.is_empty(): continue
			component.sort_custom(func(a, b): return _water_neighbor_count(world, a) > _water_neighbor_count(world, b))
			# Bug-Fix (v11.10, "kein Wasser wird produziert"): Quelldichte war
			# component.size()/35 - bei einem typischen See/Fluss-Abschnitt von
			# z.B. 50-100 Tiles ergab das nur 1-2 Quell-Tiles IRGENDWO in der
			# Mitte. Da Verdunstung (EVAP_RATE_WET=0.004/Schritt) einen
			# Start-Pegel von 1.0 an NICHT-Quell-Tiles in ca. 4 Minuten
			# Spielzeit komplett austrocknet (Zufluss über Nachbar-Diffusion
			# ist dagegen viel langsamer), waren Brunnen/Wasserpumpen ausserhalb
			# des kleinen Radius um diese wenigen Quell-Tiles nach kurzer Zeit
			# komplett trocken - "kein Wasser produziert", je nach exakter
			# Bauposition. Deutlich dichtere Quellverteilung (1 von 6 statt 1
			# von 35 Tiles) hält jetzt einen viel grösseren Teil jedes
			# Gewässers dauerhaft gespeist.
			var source_count: int = maxi(1, component.size() / 6)
			for i in mini(source_count, component.size()):
				var p: Vector2i = component[i]
				world[p.x][p.y]["is_water_source"] = true

func _water_neighbor_count(world: Array, p: Vector2i) -> int:
	var count: int = 0
	for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1),
			  Vector2i(1,1), Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1)]:
		var nx: int = p.x + d.x
		var ny: int = p.y + d.y
		if nx < 0 or ny < 0 or nx >= w or ny >= h: continue
		if str(world[nx][ny].get("biome", "")) == "WATER": count += 1
	return count

func _place_resource_nodes(world: Array, _noise: PerlinNoise) -> void:
	var res_map: Dictionary = {
		"FOREST": "WOOD", "HILLS": "STONE",
		"PLAINS": "BERRIES", "MOUNTAIN": "IRON"
	}
	for x in w:
		for y in h:
			var tile: Dictionary = world[x][y]
			if tile["building"] != null: continue
			var biome: String = tile["biome"]
			if biome == "WATER" or biome == "BEACH": continue
			var res_type: String = res_map.get(biome, "")
			if res_type == "": continue
			if randf() < 0.35:
				# Feature (v10.10): Quellen erschöpfen sich jetzt beim Farmen
				# und brauchen danach Zeit zum Regenerieren (siehe FerretEntity
				# Harvest-Logik). max_amount merkt sich die ursprüngliche
				# Grösse für die visuelle Skalierung (kleinere/leerere
				# Bäume/Büsche bei sinkendem amount), regen_timer zählt
				# während der Erholungsphase, depleted markiert "aktuell
				# nicht erntbar".
				var start_amount: float = randf_range(50.0, 200.0)
				tile["resource_node"] = {
					"type": res_type, "amount": start_amount,
					"max_amount": start_amount, "regen_timer": 0.0,
					"depleted": false
				}

func _place_ruins(world: Array) -> void:
	var count: int = randi_range(4, 8)
	for _i in count:
		for _attempt in 20:
			var rx: int = randi_range(5, w - 5)
			var ry: int = randi_range(5, h - 5)
			var tile: Dictionary = world[rx][ry]
			if tile["biome"] != "WATER" and tile["building"] == null:
				tile["ruin"] = true
				break

# ── Terrain-Editing (statische Hilfsmethoden) ─────────────────────────────────
## Feature (v10.10): lässt erschöpfte Resource-Nodes (siehe FerretEntity-
## Ernte-Logik) nach REGEN_TIME Sekunden wieder auf einen Teil ihrer
## ursprünglichen Grösse anwachsen, und lässt nicht-erschöpfte Nodes
## langsam passiv weiter Richtung max_amount nachwachsen. Wird jeden Frame
## von PopulationManager.update() aufgerufen.
## v16.6 (Performance): läuft für JEDE Kachel - auf großen Karten (80+, vor allem 120x120) würde das jeden Frame
## 6400-14400 Kacheln kosten. Deshalb bearbeitet jeder Aufruf nur einen Streifen Spalten (Rest kommt in den nächsten
## Frames dran) und rechnet dafür mit entsprechend größerem dt - im Mittel dasselbe Verhalten.
static var _tick_cursor: int = 0

static func tick_resource_nodes(world: Array, dt: float) -> void:
	const REGEN_TIME: float = 75.0
	var wcols: int = world.size()
	if wcols == 0: return
	var slices: int = 1 if wcols <= 60 else clampi(wcols / 20, 2, 8)   # 80 -> 4, 120 -> 6
	var x_start: int = 0; var x_end: int = wcols
	if slices > 1:
		var per: int = ceili(float(wcols) / float(slices))
		x_start = _tick_cursor if _tick_cursor < wcols else 0
		x_end = mini(wcols, x_start + per)
		_tick_cursor = x_end if x_end < wcols else 0
		dt *= float(slices)
	const REGEN_FRACTION: float = 0.55
	# Feature (Tech Tree, Bugfix): "wood_regen_speed" (Holzwirtschaft) wurde
	# bisher in TechTree.gd definiert, aber nirgends abgefragt - der Bonus tat
	# nichts. Lässt WOOD-Knoten (Bäume) gezielt schneller nachwachsen als
	# andere Ressourcen.
	var wood_speed_mult: float = 1.0 + TechTreeSys.get_global_bonus("wood_regen_speed")
	for xi in range(x_start, x_end):
		var col: Array = world[xi]
		for tile in col:
			var node_data = (tile as Dictionary).get("resource_node")
			if node_data == null or not (node_data is Dictionary): continue
			var nd: Dictionary = node_data
			var max_amount: float = float(nd.get("max_amount", 100.0))
			var speed_mult: float = wood_speed_mult if str(nd.get("type","")) == "WOOD" else 1.0
			if bool(nd.get("depleted", false)):
				nd["regen_timer"] = float(nd.get("regen_timer", 0.0)) + dt * speed_mult
				if float(nd["regen_timer"]) >= REGEN_TIME:
					nd["amount"] = max_amount * REGEN_FRACTION
					nd["depleted"] = false
					nd["regen_timer"] = 0.0
			elif float(nd.get("amount", 0.0)) < max_amount:
				nd["amount"] = minf(max_amount,
					float(nd["amount"]) + dt * (max_amount / REGEN_TIME) * 0.3 * speed_mult)

static func raise_terrain(world: Array, tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= world.size(): return false
	var col: Array = world[tx]
	if ty >= col.size(): return false
	var tile: Dictionary = col[ty]
	if tile["biome"] == "WATER" or tile["building"] != null:
		return false
	if not ResourceSys.has("STONE", 2):
		GameState.notify("Nicht genug Stein! (2 pro Tile)", Color(0.8, 0.2, 0.1))
		return false
	ResourceSys.remove("STONE", 2)
	tile["height"] = minf(20.0, float(tile["height"]) + 1.0)
	if float(tile["height"]) >= 14.0:
		tile["biome"] = "MOUNTAIN"
	elif float(tile["height"]) >= 5.0 and tile["biome"] == "WATER":
		tile["biome"] = "PLAINS"
	return true

static func place_dynamite(world: Array, tx: int, ty: int, explosions: Array) -> bool:
	if tx < 0 or ty < 0 or tx >= world.size(): return false
	var col: Array = world[tx]
	if ty >= col.size(): return false
	var tile: Dictionary = col[ty]
	if tile["building"] != null:
		GameState.notify("Sprengstoff nicht auf Gebäude!", Color(0.8, 0.2, 0.1))
		return false
	if not bool(tile.get("dynamite", false)):
		if not ResourceSys.has("DYNAMITE", 1):
			GameState.notify("Kein Sprengstoff vorhanden!", Color(0.8, 0.2, 0.1))
			return false
		ResourceSys.remove("DYNAMITE", 1)
		tile["dynamite"] = true
		GameState.notify("Sprengstoff gelegt - nochmal klicken zum Zünden!")
	else:
		tile["dynamite"] = false
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var nx: int = tx + dx
				var ny: int = ty + dy
				if nx < 0 or ny < 0 or nx >= world.size(): continue
				var ncol: Array = world[nx]
				if ny >= ncol.size(): continue
				var t: Dictionary = ncol[ny]
				if t["building"] != null: continue
				t["height"] = maxf(0.0, float(t["height"]) - 3.0)
				if float(t["height"]) <= 2.0:
					t["biome"] = "WATER"; t["height"] = 0.0
				elif float(t["height"]) < 5.0:
					t["biome"] = "PLAINS"
				t["resource_node"] = null
		explosions.append({"wx": tx, "wy": ty, "t": 0.0, "max_t": 1.2})
		SoundSys.play_explosion()
		GameState.notify("BOOM! Terrain geformt!", Color(1.0, 0.4, 0.1))
	return true
