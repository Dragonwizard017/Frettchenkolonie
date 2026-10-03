extends Node
func _find_buttons(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Button: out.append(c)
		_find_buttons(c, out)
func _ready() -> void:
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate(); add_child(main)
	for i in 5: await get_tree().process_frame
	var gc = main.get("_game_ctrl")
	gc.call("start_new_game", "SMALL", "qa-seed", "QA")
	for i in 10: await get_tree().process_frame
	for aid in AchievementSys.ACHIEVEMENTS: AchievementSys.debug_force_unlock(aid)
	var panel = gc.get_node("GameUI/UIRoot/PauseMenu/Row/CharacterEditorPanel")
	panel.call("_on_toggle_equip")
	await get_tree().process_frame
	var section: VBoxContainer = panel.get("_equip_section")
	print("[EXP] Zeilen: ", section.get_child_count())
	var row0 = section.get_child(0)   # HEAD
	var btns: Array = []; _find_buttons(row0, btns)
	print("[EXP] HEAD-Buttons: ", btns.map(func(b): return b.text))
	var seen: Array = []
	for i in 8:
		# wie ein Spieler: jedes Mal den AKTUELLEN Knopf der Zeile klicken
		var cur: Array = []; _find_buttons(section.get_child(0), cur)
		(cur[1] as Button).emit_signal("pressed")
		for k in 3: await get_tree().process_frame
		seen.append(str(PlayerAccessories.equipped["HEAD"]))
	print("[EXP] HEAD nach 8x ▶: ", seen)
	# Anzeige-Label der Zeile
	var lbls: Array = []; for c in section.get_child(0).get_child(0).get_children(): if c is Label: lbls.append(c.text)
	# ◀ einmal zurück
	var cur2: Array = []; _find_buttons(section.get_child(0), cur2)
	(cur2[0] as Button).emit_signal("pressed")
	for k in 3: await get_tree().process_frame
	print("[EXP] nach ◀: ", PlayerAccessories.equipped["HEAD"])
	print("[EXP] Label-Texte: ", lbls)
	get_tree().quit()
