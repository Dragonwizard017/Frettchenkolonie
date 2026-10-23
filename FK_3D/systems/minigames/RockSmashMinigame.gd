## RockSmashMinigame.gd
## Feature (v14.0, Nutzerwunsch "eigenes Minispiel zum Stein sammeln"): bisher
## nutzte "Stein brechen" einfach dieselbe Mash-Mechanik (Leiste durch
## Drücken füllen) wie "Mitbauen" - fühlte sich identisch an. Dieses
## Minispiel hat eine eigene, andere Mechanik: mehrere Gesteinsbrocken
## nacheinander, jeder muss innerhalb eines eigenen kleinen Zeitfensters mit
## einer festen Anzahl Schlägen zertrümmert werden. Je schneller (mehr Zeit
## beim letzten Schlag übrig), desto besser die Qualität dieses Brockens -
## bleibt Zeit übrig, war der Schlagrhythmus gut getroffen.
class_name RockSmashMinigame
extends RefCounted

var resource_type: String = "STONE"
var max_reward: float
var chunk_count: int
var hits_per_chunk: int
var time_per_chunk: float

var current_chunk: int = 0
var hits_in_chunk: int = 0
var chunk_timer: float = 0.0
var chunk_quality: Array = []   # Qualität (0..1) pro bereits abgeschlossenem Brocken
var finished: bool = false
var last_hit_t: float = -10.0
var elapsed: float = 0.0

func _init(p_max_reward: float, p_chunk_count: int = 3, p_hits_per_chunk: int = 5,
		p_time_per_chunk: float = 4.0) -> void:
	max_reward = p_max_reward
	chunk_count = maxi(1, p_chunk_count)
	hits_per_chunk = maxi(1, p_hits_per_chunk)
	time_per_chunk = p_time_per_chunk

func update(dt: float) -> void:
	if finished: return
	elapsed += dt
	chunk_timer += dt
	if chunk_timer >= time_per_chunk:
		# Zeit für diesen Brocken abgelaufen, bevor er ganz zerschlagen war -
		# er zählt trotzdem als "geschafft", aber mit 0 Qualität, und es
		# geht direkt zum nächsten Brocken weiter (kein Totalausfall).
		_finish_chunk(0.0)

func try_hit() -> void:
	if finished: return
	hits_in_chunk += 1
	last_hit_t = elapsed
	if hits_in_chunk >= hits_per_chunk:
		var time_left_frac: float = clampf(1.0 - (chunk_timer / time_per_chunk), 0.0, 1.0)
		# Grundqualität 0.55 selbst bei knapper Zeit, damit ein normales
		# Durchklicken schon ordentlich belohnt wird - der Rest ist ein Bonus
		# für ein flottes Tempo.
		_finish_chunk(0.55 + 0.45 * time_left_frac)

func _finish_chunk(quality: float) -> void:
	chunk_quality.append(quality)
	current_chunk += 1
	hits_in_chunk = 0
	chunk_timer = 0.0
	if current_chunk >= chunk_count:
		finished = true

func is_finished() -> bool:
	return finished

func get_progress() -> float:
	return float(hits_in_chunk) / float(hits_per_chunk)

func get_reward() -> float:
	if chunk_quality.is_empty(): return 0.0
	var total: float = 0.0
	for q in chunk_quality:
		total += float(q)
	return max_reward * (total / float(chunk_count))
