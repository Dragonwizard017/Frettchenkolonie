extends Node
func _ready() -> void:
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate(); add_child(main)
	for i in 5: await get_tree().process_frame
	GraphicsSettings.set_realistic(false)
	var gc = main.get("_game_ctrl")
	for sz in ["SMALL", "MEDIUM", "LARGE"]:
		var steps: Array = gc.call("new_game_steps", sz, "qa-seed", "T")
		var total := 0.0
		var rows: Array = []
		for st in steps:
			await get_tree().process_frame
			var t0 := Time.get_ticks_usec()
			(st["fn"] as Callable).call()
			var dt: float = float(Time.get_ticks_usec() - t0) / 1000.0
			total += dt
			rows.append([str(st["label"]), float(st["weight"]), dt])
		print("[LT] === ", sz, " gesamt ", int(total), " ms")
		for r in rows:
			print("[LT]   %-34s Gewicht %5.1f   gemessen %6.0f ms (%4.1f %%)" % [r[0], r[1], r[2], 100.0 * r[2] / total])
	get_tree().quit()
