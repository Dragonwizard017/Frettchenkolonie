extends Node
func _ready() -> void:
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for i in 5: await get_tree().process_frame
	var gc = main.get("_game_ctrl")
	gc.call("start_new_game", "SMALL", "qa-seed", "QA")
	gc.call("bootstrap_test_colony")
	for i in 10: await get_tree().process_frame
	gc.call("_toggle_fp_mode")
	for i in 5: await get_tree().process_frame
	var f = PopMgr.ferrets[0]
	f.is_sleeping = false if "is_sleeping" in f else false
	for round in 3:
		gc.player.teleport_to(gc.renderer.tile_to_world3d(int(f.pos.x), int(f.pos.y)) + Vector3(0.5, 0, 0))
		var hits := 0
		for i in 6:
			gc.player.teleport_to(gc.renderer.tile_to_world3d(int(f.pos.x), int(f.pos.y)) + Vector3(0.5, 0, 0))
			gc.call("_process", 0.1)
			if gc._fp_target_ferret != null:
				hits += 1
				print("[EXP] Prompt-Pfad erreicht, Frettchen=", gc._fp_target_ferret.ferret_name)
				gc.call("_pet_ferret")
			await get_tree().process_frame
		print("[EXP] Runde ", round, ": Treffer=", hits)
		print("[EXP] Ziel-Frettchen: ", gc._fp_target_ferret.ferret_name if gc._fp_target_ferret else "keins", " kind=", gc._fp_target_kind)
		gc.call("_try_start_fp_interaction")
		await get_tree().process_frame
		gc.call("_pet_ferret")
		gc.set("_last_pet_time", {})
		await get_tree().process_frame
	print("[EXP] FERTIG")
	get_tree().quit()
