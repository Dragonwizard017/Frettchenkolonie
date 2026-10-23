## DayNightSystem.gd
extends Node

var day_length: float = 180.0  # Sekunden
var time: float = 0.0
var day_count: int = 0
var is_day: bool = true
var display_time: String = "06:00"
var icon: String = "☀️"

func init() -> void:
	time = 0.0
	day_count = 0
	is_day = true

func update(dt: float) -> void:
	time += dt
	if time >= day_length:
		time -= day_length
		day_count += 1
		GameState.day_changed.emit(day_count)
	var pct := time / day_length
	var hour := 6 + int(pct * 24.0)
	var old_day := is_day
	# Feature (Tech Tree): "Nachtschicht-Training" (BREEDING) lässt Frettchen
	# abends spürbar länger wach bleiben, bevor die Nachtruhe einsetzt -
	# verschiebt einfach die Tag/Nacht-Schwelle nach hinten (gedeckelt, damit
	# es immer noch eine echte Nacht gibt).
	var day_threshold: float = clampf(0.75 + TechTreeSys.get_global_bonus("day_length_extend"), 0.75, 0.92)
	is_day = (pct < day_threshold)
	icon = "☀️" if is_day else "🌙"
	display_time = "%02d:00" % (hour % 24)
	if old_day != is_day:
		GameState.is_day = is_day
		if is_day:
			GameState.day_started.emit()
			SoundSys.play_day()
		else:
			GameState.night_started.emit()
			SoundSys.play_night()

func serialize() -> Dictionary:
	return {"time": time, "day_count": day_count}

func deserialize(data: Dictionary) -> void:
	time = data.get("time", 0.0)
	day_count = data.get("day_count", 0)
