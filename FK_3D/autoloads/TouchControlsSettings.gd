## TouchControlsSettings.gd – Autoload: speichert, ob Touch-Controls aktiv sind.
## Trennt die Einstellung bewusst vom Overlay selbst, damit sie auch im
## Hauptmenue abfragbar ist (das Overlay existiert nur im Spiel-Screen).
extends Node

const SAVE_FILE := "user://touch_controls.cfg"

var enabled: bool = false

signal changed(is_enabled: bool)

func _ready() -> void:
	_load()

func set_enabled(val: bool) -> void:
	if enabled == val:
		return
	enabled = val
	_save()
	changed.emit(enabled)

func toggle() -> void:
	set_enabled(not enabled)

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("touch", "enabled", enabled)
	cfg.save(SAVE_FILE)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_FILE) == OK:
		enabled = bool(cfg.get_value("touch", "enabled", false))
