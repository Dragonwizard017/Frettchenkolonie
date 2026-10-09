extends Node
func _ready() -> void:
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate(); add_child(main)
	for i in 5: await get_tree().process_frame
	GraphicsSettings.set_realistic(false)
	var gc = main.get("_game_ctrl"); var ld = main._loading
	print("[LF] Overlay vorhanden: ", ld != null, " sichtbar am Start: ", ld.visible)
	# 1) Neue Welt mit Ladebalken
	var t0 := Time.get_ticks_msec()
	await ld.run("Welt wird erstellt", gc.call("new_game_steps", "SMALL", "qa-seed", "LoadFlow"))
	var dt1: int = Time.get_ticks_msec() - t0
	print("[LF] Neue Welt: Zustand=", GameState.current_state, " (PLAYING=", GameState.State.PLAYING, ") Gebäude=", BuildingSys.buildings.size(), " Frettchen=", PopMgr.ferrets.size(), " Dauer=", dt1, " ms, Overlay sichtbar=", ld.visible)
	var labels: Array = []; var last := -1.0; var mono := true
	for e in ld.debug_log:
		if str(e["label"]) != "" and (labels.is_empty() or labels[-1] != e["label"]): labels.append(e["label"])
		if float(e["target"]) < last: mono = false
		last = float(e["target"])
	print("[LF] Schritte (", ld.debug_log.size(), "), Fortschritt monoton=", mono, ", Beschriftungen: ", labels)
	print("[LF] UI-Sounds nach dem Laden wieder aktiv (suppress=", UISounds.suppress_windows, ")")
	# 2) Speichern + Laden mit Ladebalken
	gc.call("save_now")
	var slot: String = gc.current_save_slot
	GameState.set_state(GameState.State.MAIN_MENU)
	var ctx: Dictionary = {}
	t0 = Time.get_ticks_msec()
	await ld.run("Spielstand wird geladen", SaveSys.load_game_steps(slot, gc, ctx), ctx)
	print("[LF] Laden: ok=", ctx.get("ok"), " fail=", ctx.get("fail", false), " Gebäude=", BuildingSys.buildings.size(), " Dauer=", Time.get_ticks_msec() - t0, " ms")
	# 3) Fehlerfall: Slot existiert nicht
	var ctx2: Dictionary = {}
	await ld.run("Spielstand wird geladen", SaveSys.load_game_steps("gibt-es-nicht", gc, ctx2), ctx2)
	print("[LF] Fehlerfall: ok=", ctx2.get("ok", false), " fail=", ctx2.get("fail", false), " Overlay sichtbar=", ld.visible, " suppress=", UISounds.suppress_windows)
	# 4) Synchroner Wrapper (alte API) funktioniert weiter
	var okk: bool = SaveSys.load_game(slot, gc)
	print("[LF] Sync-Wrapper load_game: ", okk, " Gebäude=", BuildingSys.buildings.size())
	var syn_t0 := Time.get_ticks_msec()
	gc.call("start_new_game", "SMALL", "qa-seed", "Sync")
	print("[LF] Sync-Wrapper start_new_game: Zustand=", GameState.current_state, " Gebäude=", BuildingSys.buildings.size(), " (", Time.get_ticks_msec() - syn_t0, " ms)")
	get_tree().quit()
