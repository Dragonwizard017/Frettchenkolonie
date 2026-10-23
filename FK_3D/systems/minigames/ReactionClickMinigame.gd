## ReactionClickMinigame.gd
## Feature (v11.2, First-Person-Modus): Beeren tauchen nacheinander (bis zu
## max_concurrent gleichzeitig) an zufälligen Positionen in einem
## rechteckigen Bereich auf und verschwinden nach einer kurzen Lebenszeit
## wieder, wenn sie nicht angeklickt werden. Ziel: möglichst viele der
## total_targets Beeren rechtzeitig anklicken. MinigameOverlay.gd liest
## get_active_targets() aus, um eine feste Pool-Größe an Buttons
## entsprechend zu positionieren/zeigen/verstecken.
class_name ReactionClickMinigame
extends RefCounted

var resource_type: String
var max_reward: float
var total_targets: int
var max_concurrent: int
var target_lifetime: float
var spawn_interval: float
var max_time: float
var area_size: Vector2

var elapsed: float = 0.0
var spawn_timer: float = 0.0
var total_spawned: int = 0
var total_clicked: int = 0
var finished: bool = false
# Jedes Element: {"pos": Vector2, "life": float, "alive": bool}
var targets: Array = []

func _init(p_resource: String, p_max_reward: float, p_total_targets: int,
		p_max_concurrent: int, p_target_lifetime: float, p_spawn_interval: float,
		p_max_time: float, p_area_size: Vector2) -> void:
	resource_type = p_resource
	max_reward = p_max_reward
	total_targets = p_total_targets
	max_concurrent = p_max_concurrent
	target_lifetime = p_target_lifetime
	spawn_interval = p_spawn_interval
	max_time = p_max_time
	area_size = p_area_size
	spawn_timer = spawn_interval * 0.25  # erste Beere erscheint schnell

func _active_count() -> int:
	var n: int = 0
	for t in targets:
		if bool((t as Dictionary)["alive"]): n += 1
	return n

func update(dt: float) -> void:
	if finished: return
	elapsed += dt
	for t in targets:
		var td: Dictionary = t
		if not bool(td["alive"]): continue
		td["life"] = float(td["life"]) - dt
		if float(td["life"]) <= 0.0:
			td["alive"] = false

	spawn_timer -= dt
	if spawn_timer <= 0.0 and total_spawned < total_targets and _active_count() < max_concurrent:
		var margin: float = 18.0
		var p := Vector2(
			randf_range(margin, area_size.x - margin),
			randf_range(margin, area_size.y - margin))
		targets.append({"pos": p, "life": target_lifetime, "alive": true})
		total_spawned += 1
		spawn_timer = spawn_interval

	if elapsed >= max_time or (total_spawned >= total_targets and _active_count() == 0):
		finished = true

## click_pos in denselben lokalen Koordinaten wie area_size. Trifft die
## naechstgelegene lebende Beere im Klickradius.
func try_click(click_pos: Vector2, click_radius: float = 26.0) -> void:
	var best_i: int = -1
	var best_d: float = click_radius
	for i in targets.size():
		var td: Dictionary = targets[i]
		if not bool(td["alive"]): continue
		var d: float = click_pos.distance_to(td["pos"] as Vector2)
		if d <= best_d:
			best_d = d; best_i = i
	if best_i >= 0:
		(targets[best_i] as Dictionary)["alive"] = false
		total_clicked += 1

## Gibt aktive (lebende) Beeren mit Restlebenszeit-Anteil zurueck, sortiert
## stabil nach Erstellungsindex - MinigameOverlay mappt das 1:1 auf einen
## festen Button-Pool.
func get_active_targets() -> Array:
	var result: Array = []
	for t in targets:
		var td: Dictionary = t
		if bool(td["alive"]):
			result.append({"pos": td["pos"], "life_frac": clampf(float(td["life"]) / target_lifetime, 0.0, 1.0)})
	return result

func is_finished() -> bool:
	return finished

func get_reward() -> float:
	if total_targets <= 0: return 0.0
	return max_reward * (float(total_clicked) / float(total_targets))
