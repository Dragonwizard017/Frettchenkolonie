## GameState.gd
## Zentraler Hub für globale Signale und Spielzustand.
## Alle Systeme kommunizieren über diese Signale.
extends Node

# ── Spielzustand ──────────────────────────────────────────────────────────────
enum State { MAIN_MENU, WORLD_CREATION, PLAYING, PAUSED, GAME_OVER, LOAD_SCREEN, INTRO }
# v15.9: INTRO (Vollbild-Video-Intros) bewusst am Ende angehängt - bestehende
# Speicherstände/Zustandsnummern bleiben dadurch unverändert gültig.
var current_state: State = State.MAIN_MENU
var game_speed: float = 1.0
var _speed_before_pause: float = 1.0
var is_day: bool = true
var dev_mode: bool = false
var dev_all_buildings: bool = false
## v16.5 (Dev-Modus): ignoriert das Lager-Limit beim Einlagern (ResourceSys.add), z. B. damit Züge im Test immer entladen können.
var dev_unlimited_storage: bool = false

# ── Signale ───────────────────────────────────────────────────────────────────
signal state_changed(new_state: State)
signal hud_update_requested
signal build_menu_update_requested
signal notification_requested(msg: String, color: Color)
signal building_placed(building: RefCounted)
signal building_sold(building: RefCounted)
signal building_selected(building: RefCounted)
signal building_deselected
signal ferret_born(ferret: RefCounted)
signal ferret_died(ferret: RefCounted, cause: String)
signal day_changed(day: int)
signal night_started
signal day_started
signal drought_started
signal drought_ended
signal season_changed(season: String)
signal expedition_returned(result: Dictionary)
signal tech_unlocked(tech_id: String)
signal game_over_triggered(cause: String)
signal resource_changed(resource: String, amount: float)
signal placement_mode_changed(mode: String, sub: String)
signal world_ready
# Feature (v11.8, Achievement-System / Umbau-Tracking):
signal building_rebuilt(building: RefCounted)
signal achievement_unlocked(id: String)
# Feature (v12.3, Tutorial-Überarbeitung): wird beim Betreten/Verlassen des
# Frettchenmodus ausgelöst - u.a. für den interaktiven Tutorial-Schritt
# "probiere den Frettchenmodus aus" (siehe ui/TutorialManager.gd).
signal fp_mode_changed(active: bool)
# Feature (v11.9, Frettchen-Klick-Interaktion / Legendäre Frettchen):
signal ferret_selected(ferret: RefCounted)
signal ferret_became_legendary(ferret: RefCounted)

# ── Platzierungszustand ───────────────────────────────────────────────────────
var placement_mode: String = ""      # "BUILDING", "PATH", "FIELD", "TERRAIN", ""
var placement_sub: String = ""       # Building-ID, Path-Type, "SET"/"CLEAR" (FIELD), "RAISE"/"DYNAMITE"
var ghost_tile: Vector2i = Vector2i(-1, -1)

func set_placement(mode: String, sub: String = "") -> void:
	placement_mode = mode
	placement_sub = sub
	placement_mode_changed.emit(mode, sub)

func cancel_placement() -> void:
	set_placement("")

# ── Hilfsmethoden ─────────────────────────────────────────────────────────────
func notify(msg: String, color: Color = Color(0.18, 0.38, 0.18, 0.92)) -> void:
	notification_requested.emit(msg, color)

func set_state(s: State) -> void:
	current_state = s
	state_changed.emit(s)

func is_playing() -> bool:
	return current_state == State.PLAYING

## Bug-Fix (v13.7, Tutorial/Pausenmenü-Konflikt): während des Tutorials wird
## die Zeit über game_speed=0 eingefroren, OHNE den State auf PAUSED zu
## wechseln (siehe GameController.set_simulation_paused()) - genau deshalb
## darf das "echte" Pausenmenü währenddessen nicht durch ESC/Leertaste/
## Pause-Button zusätzlich geöffnet werden (es würde sich über die
## Tutorial-Box legen und beide Panels um Klicks konkurrieren lassen, was
## sich für Spieler wie ein kaputtes Pausenmenü anfühlt).
func toggle_pause() -> void:
	if tutorial_active: return
	if current_state == State.PLAYING:
		# Bug-Fix (v14.6): Geschwindigkeit merken - vorher fiel sie nach der
		# Pause immer auf 1x zurück, auch wenn 2x/3x eingestellt war.
		if game_speed > 0.0: _speed_before_pause = game_speed
		set_state(State.PAUSED)
		game_speed = 0.0
	elif current_state == State.PAUSED:
		set_state(State.PLAYING)
		game_speed = _speed_before_pause if _speed_before_pause > 0.0 else 1.0

func set_game_speed(speed: float) -> void:
	game_speed = speed
	if speed > 0.0 and current_state == State.PAUSED:
		set_state(State.PLAYING)

# Feature (v13.0, Tutorial-Pause): Flag für Tutorial-aktiv-Status
var tutorial_active: bool = false
