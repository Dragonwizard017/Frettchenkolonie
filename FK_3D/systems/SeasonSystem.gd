## SeasonSystem.gd
extends Node

const SEASONS: Array = [
	{"name": "Frühling", "icon": "🌸", "prod_mult": 1.1, "days": 15},
	{"name": "Sommer",   "icon": "☀️", "prod_mult": 1.3, "days": 15},
	{"name": "Herbst",   "icon": "🍂", "prod_mult": 0.9, "days": 15},
	{"name": "Winter",   "icon": "❄️", "prod_mult": 0.6, "days": 15}
]

var current_season: int = 0
var season_day: int = 0
var production_multiplier: float = 1.0

func init() -> void:
	current_season = 0
	season_day = 0
	production_multiplier = SEASONS[0]["prod_mult"]

func update(day: int) -> void:
	var old_season := current_season
	var total_days := 0
	for i in SEASONS.size():
		total_days += SEASONS[i]["days"]
	var day_in_year := day % total_days
	var acc := 0
	for i in SEASONS.size():
		acc += SEASONS[i]["days"]
		if day_in_year < acc:
			current_season = i
			season_day = day_in_year - (acc - SEASONS[i]["days"])
			break
	production_multiplier = SEASONS[current_season]["prod_mult"]
	if old_season != current_season:
		GameState.season_changed.emit(get_season_name())
		GameState.notify("🍂 Saison: " + get_season_name() + " " + get_season_icon())

func get_season_name() -> String:
	return SEASONS[current_season]["name"]

func get_season_icon() -> String:
	return SEASONS[current_season]["icon"]

func serialize() -> Dictionary:
	return {"current_season": current_season, "season_day": season_day}

func deserialize(data: Dictionary) -> void:
	current_season = data.get("current_season", 0)
	season_day = data.get("season_day", 0)
	production_multiplier = SEASONS[current_season]["prod_mult"]
