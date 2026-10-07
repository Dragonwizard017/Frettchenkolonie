extends Node
func _ready() -> void:
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate(); add_child(main)
	for i in 5: await get_tree().process_frame
	print("[UIS] Start-Skalierung: ", get_tree().root.content_scale_factor, " (gespeichert ", GraphicsSettings.ui_scale, ")")
	GraphicsSettings.set_ui_scale(0.85)
	print("[UIS] nach 85%: ", get_tree().root.content_scale_factor)
	GraphicsSettings.set_ui_scale(1.15)
	print("[UIS] nach 115%: ", get_tree().root.content_scale_factor)
	GraphicsSettings.set_ui_scale(0.9)   # ungültiger Wert -> ignoriert
	print("[UIS] ungültig 90%: ", get_tree().root.content_scale_factor)
	GraphicsSettings.set_ui_scale(1.0)
	var cf := ConfigFile.new(); cf.load(GraphicsSettings.PATH)
	print("[UIS] Datei: ", cf.get_value("graphics", "ui_scale"), " zurück auf ", get_tree().root.content_scale_factor)
	get_tree().quit()
