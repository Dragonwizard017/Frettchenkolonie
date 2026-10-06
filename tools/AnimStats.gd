extends Node
func _ready() -> void:
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate(); add_child(main)
	for i in 5: await get_tree().process_frame
	var gc = main.get("_game_ctrl")
	gc.call("start_new_game", "MEDIUM", "qa-seed", "QA")
	gc.call("bootstrap_test_colony")
	for i in 10: await get_tree().process_frame
	var rend = gc.renderer
	var hist := {}
	var states := {}
	var steps := 4200
	for t in steps:
		gc.call("_process", 0.25)
		if t % 12 == 0:
			for n in rend._ferret_nodes:
				if not (n as Node3D).visible: continue
				var c: String = str(n.get_meta("cur_clip", "?"))
				hist[c] = int(hist.get(c, 0)) + 1
			for f in PopMgr.ferrets:
				var k: String = "%s%s" % [f.work_state, "+schlaf" if f.is_sleeping else ""]
				states[k] = int(states.get(k, 0)) + 1
		if t % 300 == 0: await get_tree().process_frame
	print("[ANIMSTAT] Clip-Häufigkeit: ", hist)
	print("[ANIMSTAT] Frettchen-Zustände: ", states)
	print("[ANIMSTAT] Tage simuliert: ", DayNight.day_count)
	# Tod: Geist-Node
	var before: int = rend._ferret_root.get_child_count()
	GameState.ferret_died.emit(PopMgr.ferrets[0], "test")
	await get_tree().process_frame
	print("[ANIMSTAT] Todes-Geist erzeugt: ", rend._ferret_root.get_child_count() - before)
	var ghost: Node = rend._ferret_root.get_child(rend._ferret_root.get_child_count() - 1)
	var gap: AnimationPlayer = ghost.find_child("AnimationPlayer", true, false)
	print("[ANIMSTAT] Geist spielt: ", gap.current_animation)
	# Geburt + Streicheln
	var f1 = PopMgr.ferrets[1]
	GameState.ferret_born.emit(f1)
	print("[ANIMSTAT] Geburt -> react=", f1.react_clip)
	var f2 = PopMgr.ferrets[2]
	gc.set("_fp_target_ferret", f2); gc.set("_last_pet_time", {})
	gc.call("_pet_ferret")
	print("[ANIMSTAT] Streicheln -> react=", f2.react_clip)
	for i in 5:
		gc.call("_process", 0.1); await get_tree().process_frame
	var seen := []
	for n in rend._ferret_nodes: seen.append(str(n.get_meta("cur_clip", "?")))
	print("[ANIMSTAT] Clips direkt danach: ", seen)
	get_tree().quit()
