## WaterSystem.gd
## Timberborn-artige Wasserphysik für FrettchenKolonie.
## Simuliert pro Tile eine tatsächliche Wassertiefe ("water_level"), die
## additiv zur Terrain-"height" steht (Tile-Wasseroberfläche = height +
## water_level). Jeden Simulationsschritt:
##  1) Wasserüllen (von WorldGenerator markiert) speisen neues Wasser ein
##     - das simuliert Fluss-Zustrom von ausserhalb der Karte.
##  2) Wasser fliesst zu Nachbar-Tiles mit niedrigerer Oberfläche (einfacher
##     zellulärer Automat, vier Nachbarn) - genau wie in Timberborn breitet
##     sich Wasser über die Landschaft aus und sammelt sich in Senken.
##  3) Verdunstung reduziert den Pegel kontinuierlich, während einer Dürre
##     (DroughtSys.is_drought) stark verstärkt UND mit reduziertem
##     Quellzufluss - Flüsse/Seen trocknen während einer Dürre sichtbar aus
##     und füllen sich in der nassen Phase wieder auf.
## Gebäude vom Typ "DAM" (Damm) reduzieren den Ausgehenden Fluss eines Tiles,
## sodass Spieler aktiv Wasser aufstauen können, um Dürreperioden besser zu
## überstehen - das zentrale strategische Element aus Timberborn.
extends Node

# ── Konstanten ────────────────────────────────────────────────────────────────
# Bug-Fix/Feature (v10.16): "Wasser breitet sich zu langsam aus" - FLOW_RATE
# bestimmte bisher nur einen kleinen Bruchteil des Höhenunterschieds, der
# pro Sekunde ausgeglichen wird (0.9 * 0.5 * STEP=0.15 ≈ 6.75% des
# Unterschieds pro Sekunde) - neue Flüsse/Seen brauchten dadurch sehr lange,
# um sich über mehrere Tiles zu verteilen. Deutlich erhöht (0.9 -> 3.2,
# ca. 4x schnellerer Ausgleich). MAX_OUTFLOW_FRACTION (ehemals fest 0.25 im
# Code) ebenfalls leicht erhöht (0.25 -> 0.35) für einen stärkeren
# Spitzenfluss bei grossen Gefällen; der theoretische Maximalfall aller 4
# Nachbarn gleichzeitig (4 * 0.35 = 1.4x lvl) wird über das abschliessende
# clampf(...,0.0,MAX_DEPTH) sicher abgefangen, falls er je auftritt.
const FLOW_RATE:          float = 3.2    # Anteil des Höhenunterschieds, der pro Sek. ausgeglichen wird
const MAX_OUTFLOW_FRACTION: float = 0.35 # max. Anteil des eigenen Pegels, der je Nachbar pro Schritt abfliessen darf
const MIN_FLOW:           float = 0.0008 # unterhalb dieser Menge wird nicht mehr geflossen (Stabilität)
# Bug-Fix (v11.10, "kein Wasser wird produziert"): 0.004/Schritt trocknete
# einen Nicht-Quell-Tile (Startpegel 1.0) in ca. 4 Minuten Spielzeit
# komplett aus, lange bevor Diffusion von den (vorher sehr spärlichen)
# Quell-Tiles nachfliessen konnte. Zusätzlich zur dichteren Quellverteilung
# (siehe WorldGenerator._place_water_sources()) auch die Verdunstungsrate
# selbst reduziert - das hilft insbesondere BESTEHENDEN Speicherständen, die
# ihre (alte, spärliche) Quellverteilung bereits gespeichert haben und nicht
# rückwirkend dichter gemacht werden kann, ohne die Karte zu verändern.
const EVAP_RATE_WET:      float = 0.0022 # Verdunstung/Sek. in der nassen Phase
const EVAP_RATE_DROUGHT:  float = 0.05   # Verdunstung/Sek. während einer Dürre
const SOURCE_RATE_WET:    float = 0.6    # Zufluss/Sek. je Quell-Tile in der nassen Phase
const SOURCE_RATE_DROUGHT: float = 0.05  # Zufluss/Sek. je Quell-Tile während einer Dürre
const MAX_DEPTH:          float = 4.0    # Kappung, damit Quellen nicht endlos aufstauen
const DAM_RETENTION:      float = 0.85   # Dämme reduzieren ausgehenden Fluss um diesen Faktor
const STEP:               float = 0.15   # feste Simulationsschrittweite (Stabilität, unabhängig von Framerate)
const NEIGHBORS: Array = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]

# ── State ─────────────────────────────────────────────────────────────────────
## Feature (v13.3, Performance): Wasser wird nicht jeden Frame aktualisiert
## sondern nur alle 0.1s - spart massive Rechenleistung
const WATER_UPDATE_INTERVAL: float = 0.1
var _water_update_timer: float = 0.0

var world_ref: Array = []
var w: int = 60
var h: int = 60
var _accum: float = 0.0
var _delta: PackedFloat32Array = PackedFloat32Array()

func init(world: Array, world_w: int, world_h: int) -> void:
	world_ref = world
	w = world_w
	h = world_h
	_accum = 0.0
	_delta.resize(w * h)
	_delta.fill(0.0)

## Wird jeden Frame von GameController._process() aufgerufen. dt ist bereits
## mit game_speed/Jahreszeit skaliert (gleiches Muster wie andere Systeme).
## Die Simulation selbst läuft intern in festen STEP-Schritten, damit sie bei
## hoher Spielgeschwindigkeit (mehrere Schritte pro Frame) stabil bleibt.
func update(dt: float, world: Array) -> void:
	world_ref = world
	if _delta.size() != w * h:
		_delta.resize(w * h); _delta.fill(0.0)
	_accum += dt
	var safety: int = 0
	while _accum >= STEP and safety < 10:
		_accum -= STEP
		_simulate_step(STEP)
		safety += 1
	if safety >= 10:
		_accum = 0.0 # extreme Nachholbedarf (z.B. nach Laden) abbrechen statt einfrieren

func _simulate_step(step: float) -> void:
	var drought: bool = DroughtSys.is_drought
	var evap: float = EVAP_RATE_DROUGHT if drought else EVAP_RATE_WET
	# Feature (Tech Tree): "Dürrevorsorge"/"Meister der Wasserwirtschaft"
	# (WATER) senken die Verdunstung während einer Dürre spürbar.
	if drought:
		evap *= 1.0 - clampf(TechTreeSys.get_global_bonus("drought_evaporation_reduction"), 0.0, 0.8)
	var source_rate: float = SOURCE_RATE_DROUGHT if drought else SOURCE_RATE_WET

	_delta.fill(0.0)

	# 1) Quellen speisen ein
	for x in w:
		var col: Array = world_ref[x]
		for y in h:
			var tile: Dictionary = col[y]
			if bool(tile.get("is_water_source", false)):
				_delta[x * h + y] += source_rate * step

	# 2) Fluss zu Nachbarn mit niedrigerer Oberfläche
	for x in w:
		var col: Array = world_ref[x]
		for y in h:
			var tile: Dictionary = col[y]
			var lvl: float = float(tile.get("water_level", 0.0))
			if lvl <= MIN_FLOW: continue
			var bed: float = float(tile.get("height", 0.0))
			var surface: float = bed + lvl
			var retention: float = (DAM_RETENTION - TechTreeSys.get_global_bonus("dam_retention_bonus")) if _has_dam(tile) else 1.0
			retention = clampf(retention, 0.05, 1.0)
			var idx: int = x * h + y
			for d in NEIGHBORS:
				_flow_to(x, y, x + d.x, y + d.y, lvl, surface, retention, step, idx)

	# 3) Delta anwenden + Verdunstung
	for x in w:
		var col: Array = world_ref[x]
		for y in h:
			var tile: Dictionary = col[y]
			var idx: int = x * h + y
			var lvl: float = float(tile.get("water_level", 0.0)) + _delta[idx]
			lvl = clampf(lvl, 0.0, MAX_DEPTH)
			if lvl > 0.0:
				lvl = maxf(0.0, lvl - evap * step)
			tile["water_level"] = lvl

func _flow_to(x: int, y: int, nx: int, ny: int, lvl: float, surface: float, retention: float, step: float, idx: int) -> void:
	if nx < 0 or ny < 0 or nx >= w or ny >= h:
		# Kartenrand = Senke/Abfluss, simuliert Fluss ins Meer/aus der Karte heraus.
		var edge_amt: float = minf(lvl * MAX_OUTFLOW_FRACTION, surface * 0.5 * FLOW_RATE * step) * retention
		if edge_amt > MIN_FLOW:
			_delta[idx] -= edge_amt
		return
	var ntile: Dictionary = (world_ref[nx] as Array)[ny]
	var nlvl:  float = float(ntile.get("water_level", 0.0))
	var nbed:  float = float(ntile.get("height", 0.0))
	var nsurface: float = nbed + nlvl
	var diff: float = surface - nsurface
	if diff <= MIN_FLOW: return
	var amt: float = minf(lvl * MAX_OUTFLOW_FRACTION, diff * 0.5 * FLOW_RATE * step) * retention
	if amt <= MIN_FLOW: return
	_delta[idx] -= amt
	_delta[nx * h + ny] += amt

func _has_dam(tile: Dictionary) -> bool:
	var b = tile.get("building")
	if b == null: return false
	return str((b as BuildingEntity).id) == "DAM"

## Liefert den durchschnittlichen, TATSAECHLICHEN Wasserstand in einem Radius
## um eine Tile-Position. Wird von Sammelgebäuden (Brunnen, Wasserturm,
## Aquädukt, ...) genutzt, damit ihre Produktion von der simulierten
## Wassermenge abhängt statt nur von der statischen Biom-Zugehörigkeit -
## trocknet der Fluss in einer Dürre aus, sinkt auch ihre Förderleistung.
func get_avg_level_near(tx: int, ty: int, radius: int) -> float:
	if world_ref.is_empty(): return 0.0
	var total: float = 0.0
	var count: int = 0
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var wx: int = tx + dx
			var wy: int = ty + dy
			if wx < 0 or wy < 0 or wx >= w: continue
			var col: Array = world_ref[wx]
			if wy >= col.size(): continue
			total += float((col[wy] as Dictionary).get("water_level", 0.0))
			count += 1
	return total / float(maxi(1, count))

## Bug-Fix (v14.6): Summe der TATSAECHLICHEN Wasserpegel im Radius (statt des
## Durchschnitts über die ganze Kreisfläche). Gemessen: Karten haben nur 3
## (SMALL) bzw. 8 (MEDIUM) Wasserkacheln - der Kreisdurchschnitt lag bei einem
## Brunnen direkt am Wasser bei nur 0.006-0.024, der "Nähe zum See"-Bonus war
## dadurch praktisch wirkungslos (jeder Brunnen lief immer nur auf dem
## Grundsockel). Das Wasservolumen in Reichweite bleibt dagegen aussagekräftig
## und sinkt in der Dürre (Pegel fallen) weiterhin spürbar.
func get_water_volume_near(tx: int, ty: int, radius: int) -> float:
	if world_ref.is_empty(): return 0.0
	var total: float = 0.0
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var wx: int = tx + dx
			var wy: int = ty + dy
			if wx < 0 or wy < 0 or wx >= w: continue
			var col: Array = world_ref[wx]
			if wy >= col.size(): continue
			total += float((col[wy] as Dictionary).get("water_level", 0.0))
	return total

## Wasserstand wird direkt in den Tile-Daten von "world" gehalten (siehe
## GameController.serialize_world/deserialize_world) - dieses System selbst
## braucht keinen eigenen Speicherstand.
func serialize() -> Dictionary:
	return {}

func deserialize(_data: Dictionary) -> void:
	pass
