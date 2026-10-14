extends Node
# Screenshots: Dev-Fenster (Reiter), Tutorial mit Markierung, Pause-Menü. Nutzung: ... -- /pfad/praefix
func frames(n: int) -> void:
	for i in n: await get_tree().process_frame
func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/home/claude/devshot"
	GraphicsSettings.set_realistic(false)
	await frames(2)
	var main = load("res://scenes/Main.tscn").instantiate(); add_child(main)
	await frames(30)
	var intro = main.get("_intro")
	if intro != null: intro.call("skip")
	await frames(5)
	var gc = main.get("_game_ctrl")
	gc.call("start_new_game", "SMALL", "qa-seed", "QA")
	await frames(10)
	Engine.time_scale = 0.001
	TutorialManager.reset_progress()
	DevMode.try_enable("frettchendev")
	var dt: Control = main.find_child("DevToolsPanel", true, false)
	await frames(10)
	get_viewport().get_texture().get_image().save_png(out + "_1_basis.png")
	dt._tabs.current_tab = 3
	await frames(5)
	get_viewport().get_texture().get_image().save_png(out + "_2_schiene.png")
	var tut: Control = main.find_child("Tutorial", true, false)
	tut.call("start", "logistics")
	for i in 2: tut.call("_on_next")
	await frames(6)
	get_viewport().get_texture().get_image().save_png(out + "_3_tutorial.png")
	tut.call("_on_skip"); await frames(3)
	dt._collapsed = true; dt._refresh(); await frames(5)
	GameState.set_state(GameState.State.PAUSED)
	await frames(8)
	get_viewport().get_texture().get_image().save_png(out + "_4_pause.png")
	print("[SHOT] fertig")
	get_tree().quit()
