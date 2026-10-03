extends Node
var main: Node
var gc: Node
func _log(s: String) -> void: print("[TEST] ", s)
func sim(steps: int, dt: float, yield_every: int = 400) -> void:
	for i in steps:
		gc.call("_process", dt)
		if i % yield_every == 0: await get_tree().process_frame
func summary(tag: String) -> void:
	var tot := 0.0
	for k in ResourceSys.resources: tot += float(ResourceSys.resources[k])
	var nan := false
	for k in ResourceSys.resources:
		if is_nan(float(ResourceSys.resources[k])) or is_inf(float(ResourceSys.resources[k])): nan = true
	_log("%s: day=%d ferrets=%d dead=%d buildings=%d water=%.1f res_total=%.1f nan=%s drought=%s season=%s fields=%d" % [tag, DayNight.day_count, PopMgr.ferrets.size(), PopMgr.dead_ferrets.size(), BuildingSys.buildings.size(), ResourceSys.water, tot, nan, DroughtSys.is_drought, SeasonSys.get_season_name(), FarmSys.fields.size()])
func _ready() -> void:
	await get_tree().process_frame
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for i in 5: await get_tree().process_frame
	gc = main.get("_game_ctrl")
	_log("gc=%s" % str(gc))
	gc.call("start_new_game", "SMALL", "qa-seed", "QA")
	await sim(100, 0.1)
	summary("neues Spiel")
	gc.call("bootstrap_test_colony")
	await sim(300, 0.1)
	summary("bootstrap")
	# Felder anlegen
	var placed := 0
	var cx: int = gc.world_gen.w / 2
	var cy: int = gc.world_gen.h / 2
	for r in range(2, 16):
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				var tx: int = cx + dx
				var ty: int = cy + dy
				if placed >= 25: break
				gc.call("_place_field", tx, ty, "SET", true)
				if FarmSys.has_field(tx, ty): placed += 1
	_log("Felder platziert: %d" % placed)
	# lange Simulation inkl. Dürre/Jahreszeiten
	for chunk in 3:
		await sim(2500, 0.25)
		summary("chunk %d" % chunk)
	# Dürre erzwingen
	DroughtSys.force_drought()
	await sim(1500, 0.25)
	summary("Dürre")
	# Speichern/Laden
	var ok: bool = SaveSys.save("qa_test", gc)
	_log("save ok=%s" % ok)
	var ok2: bool = SaveSys.load_game("qa_test", gc)
	_log("load ok=%s" % ok2)
	await sim(1000, 0.25)
	summary("nach Laden")
	# Gebäude verkaufen/upgraden/umbauen
	var n := 0
	for b in BuildingSys.buildings.duplicate():
		n += 1
		if n % 3 == 0:
			BuildingSys.sell(b, gc.world)
		elif n % 3 == 1:
			b.upgrade()
	await sim(500, 0.25)
	summary("nach Verkauf/Upgrade")
	# FP-Modus
	gc.call("_toggle_fp_mode")
	await sim(300, 0.1)
	gc.call("_toggle_fp_mode")
	await sim(100, 0.1)
	# alle Hungertode abwarten
	for chunk in 1:
		await sim(2500, 0.25)
		summary("spät %d" % chunk)
	_log("FERTIG")
	get_tree().quit()
