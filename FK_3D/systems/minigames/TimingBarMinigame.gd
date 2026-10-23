## TimingBarMinigame.gd
## Feature (v11.2, First-Person-Modus): klassisches Timing-Leisten-Minispiel.
## Ein Marker oszilliert per Sinuskurve stetig zwischen 0.0 und 1.0 über eine
## Leiste; in der Mitte liegt eine "Sweet Spot"-Zone fester Breite. Der
## Spieler drückt im richtigen Moment (Aktionstaste E) - je näher an der
## Mitte der Zone, desto besser die Trefferqualität. Wird sowohl für Holz
## (breite Zone, langsam) als auch Erz (schmale Zone, schnell) verwendet -
## nur die Konstruktor-Parameter unterscheiden sich, wodurch sich beide trotz
## gleicher Mechanik klar unterschiedlich anfühlen (Erz ist spürbar
## präziser/schwerer).
class_name TimingBarMinigame
extends RefCounted

var resource_type: String
var max_reward: float
var zone_width: float      # Anteil der Leiste (0..1), z.B. 0.22 = 22%
var speed: float           # Oszillationen pro Sekunde
var hits_required: int
var max_time: float

var elapsed: float = 0.0
var hits_done: int = 0
var total_quality: float = 0.0
var finished: bool = false
var last_hit_quality: float = -1.0   # für kurzes visuelles Feedback, -1 = kein Treffer kuerzlich
var last_hit_t: float = -10.0

func _init(p_resource: String, p_max_reward: float, p_zone_width: float,
		p_speed: float, p_hits_required: int, p_max_time: float) -> void:
	resource_type = p_resource
	max_reward = p_max_reward
	zone_width = p_zone_width
	speed = p_speed
	hits_required = p_hits_required
	max_time = p_max_time

func get_marker_pos() -> float:
	return (sin(elapsed * speed * TAU) + 1.0) * 0.5

func get_zone_range() -> Vector2:
	return Vector2(0.5 - zone_width * 0.5, 0.5 + zone_width * 0.5)

func update(dt: float) -> void:
	if finished: return
	elapsed += dt
	if elapsed >= max_time:
		finished = true

func try_hit() -> void:
	if finished: return
	var marker: float = get_marker_pos()
	var dist: float = absf(marker - 0.5)
	var half: float = zone_width * 0.5
	last_hit_t = elapsed
	if dist <= half:
		var quality: float = 1.0 - (dist / half)
		hits_done += 1
		total_quality += quality
		last_hit_quality = quality
		if hits_done >= hits_required:
			finished = true
	else:
		last_hit_quality = 0.0

func is_finished() -> bool:
	return finished

func get_reward() -> float:
	if hits_done <= 0: return 0.0
	# volle Punktzahl nur bei perfekten Treffern UND vollstaendiger
	# Trefferzahl - durchschnittliche Qualitaet skaliert den max_reward.
	var avg_quality: float = total_quality / float(hits_required)
	return max_reward * clampf(avg_quality, 0.0, 1.0)
