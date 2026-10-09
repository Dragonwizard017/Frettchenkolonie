extends Node
func _t(label: String, c: Callable) -> void:
	var t0 := Time.get_ticks_usec(); c.call()
	print("[FT] %-28s %6.1f ms" % [label, float(Time.get_ticks_usec() - t0) / 1000.0])
func _ready() -> void:
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate(); add_child(main)
	for i in 5: await get_tree().process_frame
	GraphicsSettings.set_realistic(false)
	var gc = main.get("_game_ctrl")
	gc.call("_ng_generate", "MEDIUM", "qa-seed", "T")
	await get_tree().process_frame
	var world = gc.world; var wg = gc.world_gen
	_t("ResourceSys.init", func(): ResourceSys.init())
	_t("BuildingSys.init", func(): BuildingSys.init())
	_t("PopMgr.init", func(): PopMgr.init(5))
	_t("DayNight.init", func(): DayNight.init())
	_t("TechTreeSys.init", func(): TechTreeSys.init())
	_t("DroughtSys.init", func(): DroughtSys.init())
	_t("SeasonSys.init", func(): SeasonSys.init())
	_t("ExpeditionSys.init", func(): ExpeditionSys.init())
	_t("AchievementSys.init", func(): AchievementSys.init())
	_t("PlayerAccessories.init", func(): PlayerAccessories.init())
	_t("DistrictSys.init", func(): DistrictSys.init())
	_t("FarmSys.init", func(): FarmSys.init())
	_t("WaterSys.init", func(): WaterSys.init(world, wg.w, wg.h))
	var b: BuildingEntity = null
	_t("BuildingEntity.from_type", func(): b = BuildingEntity.from_type("STORAGE", 10, 10))
	_t("DistrictSys.assign_district", func(): DistrictSys.assign_district(b, BuildingSys.buildings))
	_t("emit building_placed", func(): GameState.building_placed.emit(b))
	_t("emit hud_update_requested", func(): GameState.hud_update_requested.emit())
	_t("emit build_menu_update_requested", func(): GameState.build_menu_update_requested.emit())
	_t("emit build_menu_update (2.)", func(): GameState.build_menu_update_requested.emit())
	for c in GameState.building_placed.get_connections(): print("[FT]   building_placed -> ", c["callable"])
	for c in GameState.build_menu_update_requested.get_connections(): print("[FT]   menu_update -> ", c["callable"])
	for c in GameState.hud_update_requested.get_connections(): print("[FT]   hud_update -> ", c["callable"])
	get_tree().quit()
