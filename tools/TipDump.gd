extends Node
func _strip(t: String) -> String:
	var re := RegEx.new(); re.compile("\\[/?[a-z_]+(=[^\\]]*)?\\]")
	return re.sub(t, "", true)
func _ready() -> void:
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate(); add_child(main)
	for i in 5: await get_tree().process_frame
	main.get("_game_ctrl").call("start_new_game", "SMALL", "qa-seed", "QA")
	for i in 5: await get_tree().process_frame
	var bad := 0; var total := 0; var maxlen := 0
	for id in BuildingData.BUILDINGS:
		var t: String = BuildingTooltip.build(id)
		total += 1
		var plain := _strip(t)
		maxlen = maxi(maxlen, plain.length())
		if plain.length() < 40 or plain.contains("?") or plain.contains("nan") or plain.contains("inf"):
			bad += 1; print("[TIP] AUFFÄLLIG ", id, ": ", plain.replace("\n", " | "))
	print("[TIP] ", total, " Gebäude, auffällig: ", bad, ", längster Text: ", maxlen, " Zeichen")
	for id in ["COOKHOUSE", "HOUSE", "FARMHOUSE"]:
		print("[TIP] ==== ", id); print(_strip(BuildingTooltip.build(id)))
	get_tree().quit()
