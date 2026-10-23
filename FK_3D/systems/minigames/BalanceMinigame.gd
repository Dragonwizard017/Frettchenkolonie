## BalanceMinigame.gd
## Feature (v11.2, First-Person-Modus): ein Wassereimer wird beim Schoepfen
## ständig durch eine "Strömung" (zufaellig wechselnde Driftbeschleunigung)
## aus dem Gleichgewicht gebracht. Der Spieler hält mit move_left/move_right
## (A/D) dagegen, um den Wert nahe der Mitte (0.0) zu halten. Belohnung
## basiert auf der über die Zeit gemittelten Nähe zur Mitte - bewusst eine
## STETIGE Balance-Mechanik statt diskreter Treffer, um sich klar von den
## anderen vier Minispielen abzuheben.
class_name BalanceMinigame
extends RefCounted

var resource_type: String
var max_reward: float
var correct_speed: float
var max_time: float
var spill_limit: float      # |value| ab hier zählt als "verschuettet" (0 Punkte)

var value: float = 0.0
var drift_vel: float = 0.0
var drift_change_timer: float = 0.0
var elapsed: float = 0.0
var score_accum: float = 0.0
var finished: bool = false

func _init(p_resource: String, p_max_reward: float, p_correct_speed: float,
		p_max_time: float, p_spill_limit: float = 1.0) -> void:
	resource_type = p_resource
	max_reward = p_max_reward
	correct_speed = p_correct_speed
	max_time = p_max_time
	spill_limit = p_spill_limit
	drift_change_timer = randf_range(0.8, 1.6)

func update(dt: float, left_held: bool, right_held: bool) -> void:
	if finished: return
	elapsed += dt
	drift_change_timer -= dt
	if drift_change_timer <= 0.0:
		drift_vel = randf_range(-0.55, 0.55)
		drift_change_timer = randf_range(0.8, 1.6)
	value += drift_vel * dt
	if left_held:  value -= correct_speed * dt
	if right_held: value += correct_speed * dt
	value = clampf(value, -1.5, 1.5)
	var closeness: float = clampf(1.0 - absf(value) / spill_limit, 0.0, 1.0)
	score_accum += closeness * dt
	if elapsed >= max_time:
		finished = true

func is_finished() -> bool:
	return finished

func get_reward() -> float:
	if max_time <= 0.0: return 0.0
	return max_reward * clampf(score_accum / max_time, 0.0, 1.0)
