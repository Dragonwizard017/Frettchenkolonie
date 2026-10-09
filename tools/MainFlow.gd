extends Node
func _wait_overlay(ld: Node) -> void:
	for i in 6: await get_tree().process_frame
	var g := 0
	while ld.visible and g < 2000: await get_tree().process_frame; g += 1
func _ready() -> void:
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate(); add_child(main)
	for i in 5: await get_tree().process_frame
	GraphicsSettings.set_realistic(false)
	var ld = main._loading
	# 1) "Neue Welt" über den echten Handler
	main._name_input.text = "FlowTest"; main._seed_input.text = "flow"; main._size_option.selected = 0
	main.call("_on_start_game"); await _wait_overlay(ld)
	print("[MF] Neue Welt: Zustand=", GameState.current_state, " Name=", _g(main).current_world_name, " Gebäude=", BuildingSys.buildings.size(), " Overlay sichtbar=", ld.visible)
	var slot: String = _g(main).current_save_slot
	_g(main).call("save_now")
	GameState.set_state(GameState.State.MAIN_MENU)
	# 2) Laden über den echten Handler
	main.call("_load_from_slot", slot); await _wait_overlay(ld)
	print("[MF] Laden: Zustand=", GameState.current_state, " Gebäude=", BuildingSys.buildings.size(), " Overlay sichtbar=", ld.visible)
	GameState.set_state(GameState.State.MAIN_MENU)
	# 3) Laden eines nicht vorhandenen Slots: darf nicht in PLAYING springen
	main.call("_load_from_slot", "gibt-es-nicht"); await _wait_overlay(ld)
	print("[MF] Laden Fehlerfall: Zustand=", GameState.current_state, " (MAIN_MENU=", GameState.State.MAIN_MENU, ")")
	# 4) Testwelt über den echten Handler (landet danach im Hauptmenü)
	main.call("_on_create_test_world"); await _wait_overlay(ld)
	print("[MF] Testwelt: Zustand=", GameState.current_state, " Gebäude=", BuildingSys.buildings.size(), " Frettchen=", PopMgr.ferrets.size())
	get_tree().quit()
func _g(main) -> Node: return main.get("_game_ctrl")
