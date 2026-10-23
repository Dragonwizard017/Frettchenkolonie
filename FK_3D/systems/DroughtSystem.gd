## DroughtSystem.gd
extends Node

var is_drought: bool = false
var timer: float = 0.0
var wet_duration: float = 18.0 * 60.0
var drought_duration: float = 10.0 * 60.0
var transition_duration: float = 3.0 * 60.0
var phase: String = "WET"  # WET, TRANSITION, DROUGHT
var hud_color: Color = Color(0.2, 0.7, 1.0)
var display_text: String = ""

func init() -> void:
	is_drought = false
	timer = 0.0
	phase = "WET"

func update(dt: float) -> void:
	timer += dt
	match phase:
		"WET":
			display_text = ""
			hud_color = Color(0.2, 0.7, 1.0)
			if timer >= wet_duration:
				timer = 0.0
				phase = "TRANSITION"
				GameState.notify("⚠️ Dürre naht! Fülle dein Wasserreservoir! 🪣", Color(0.9, 0.6, 0.1))
		"TRANSITION":
			var pct := timer / transition_duration
			hud_color = Color(1.0, 0.7 - pct * 0.5, 0.1)
			display_text = "Dürre in %ds" % int((transition_duration - timer))
			if timer >= transition_duration:
				timer = 0.0
				phase = "DROUGHT"
				is_drought = true
				GameState.drought_started.emit()
				GameState.notify("🔥 DÜRRE! Wasserversorgung kritisch!", Color(0.85, 0.2, 0.1))
		"DROUGHT":
			hud_color = Color(0.85, 0.2, 0.1)
			display_text = "🔥 DÜRRE %ds" % int((drought_duration - timer))
			if timer >= drought_duration:
				timer = 0.0
				phase = "WET"
				is_drought = false
				GameState.drought_ended.emit()
				GameState.notify("🌧️ Dürre vorbei! Wasser fließt wieder!", Color(0.2, 0.7, 1.0))

func force_drought() -> void:
	phase = "DROUGHT"
	is_drought = true
	timer = 0.0
	GameState.drought_started.emit()

func serialize() -> Dictionary:
	return {"phase": phase, "timer": timer, "is_drought": is_drought}

func deserialize(data: Dictionary) -> void:
	phase = data.get("phase", "WET")
	timer = data.get("timer", 0.0)
	is_drought = data.get("is_drought", false)
