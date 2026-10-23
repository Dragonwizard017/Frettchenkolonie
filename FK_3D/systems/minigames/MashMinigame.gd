## MashMinigame.gd
## Feature (v11.2, First-Person-Modus): Stein wird durch wiederholtes Drücken
## der Aktionstaste (E) "zertrümmert". Eine Füllstandsleiste steigt mit
## jedem Tastendruck und fällt gleichzeitig kontinuierlich leicht ab -
## sporadisches Drücken reicht also nicht, es braucht einen stetigen
## Rhythmus, um die Leiste zu fuellen. Wird die Leiste voll, ist der Stein
## "geknackt" (volle Belohnung, Minispiel endet sofort) - sonst zählt am
## Ende der Zeit der erreichte Füllstand.
class_name MashMinigame
extends RefCounted

var resource_type: String
var max_reward: float
var fill_per_press: float
var decay_per_sec: float
var max_time: float

var fill: float = 0.0
var elapsed: float = 0.0
var finished: bool = false
var press_flash_t: float = -10.0   # für kurzes visuelles "Schlag"-Feedback

func _init(p_resource: String, p_max_reward: float, p_fill_per_press: float,
		p_decay_per_sec: float, p_max_time: float) -> void:
	resource_type = p_resource
	max_reward = p_max_reward
	fill_per_press = p_fill_per_press
	decay_per_sec = p_decay_per_sec
	max_time = p_max_time

func update(dt: float) -> void:
	if finished: return
	elapsed += dt
	fill = maxf(0.0, fill - decay_per_sec * dt)
	if elapsed >= max_time:
		finished = true

func press() -> void:
	if finished: return
	fill = minf(1.0, fill + fill_per_press)
	press_flash_t = elapsed
	if fill >= 1.0:
		finished = true

func is_finished() -> bool:
	return finished

func get_reward() -> float:
	return max_reward * clampf(fill, 0.0, 1.0)
