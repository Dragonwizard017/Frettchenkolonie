extends Node
# Kosten pro Frame (dt=1/60) je Weltgröße, aufgeschlüsselt.
func ts() -> int: return Time.get_ticks_usec()
func measure(label: String, f: Callable, n: int) -> float:
	var t := ts()
	for i in n: f.call()
	var per: float = float(ts() - t) / float(n) / 1000.0
	print("[PERF]   %-28s %.3f ms" % [label, per])
	return per
func _ready() -> void:
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate(); add_child(main)
	for i in 30: await get_tree().process_frame
	var intro = main.get("_intro")
	if intro != null: intro.call("skip")
	for i in 5: await get_tree().process_frame
	var gc = main.get("_game_ctrl")
	for size in ["MEDIUM", "LARGE", "HUGE"]:
		gc.call("start_new_game", size, "qa-seed", "QA")
		for i in 3: await get_tree().process_frame
		gc.call("bootstrap_test_colony")
		for i in 5: await get_tree().process_frame
		print("[PERF] ── %s (%dx%d)" % [size, gc.world_gen.w, gc.world_gen.h])
		var dt := 1.0 / 60.0
		measure("gc._process gesamt", func(): gc.call("_process", dt), 600)
		measure("WaterSys.update (0.1 s)", func(): WaterSys.update(0.1, gc.world), 20)
		measure("BuildingSys.update", func(): BuildingSys.update(dt, true, gc.world), 300)
		measure("PopMgr.update", func(): PopMgr.update(dt, true, gc.world), 300)
		measure("FarmSys.update", func(): FarmSys.update(dt), 300)
		for k in 4:
			var tq := ts(); gc.renderer.refresh_water(gc.world); var d1: float = float(ts() - tq) / 1000.0
			var tq2 := ts(); gc.renderer._water_signature(gc.world); var d2: float = float(ts() - tq2) / 1000.0
			print("[PERF]   refresh_water #%d: %.1f ms (Signatur allein: %.1f ms)" % [k, d1, d2])
		measure("renderer.apply_fog", func(): gc.renderer.apply_fog(), 5)
	get_tree().quit()
