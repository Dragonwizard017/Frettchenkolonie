## TutorialManager.gd (v13.1+ - Bugfix für Tutorial-UI-Blockade)
## - Umlaute statt ä/ö/ü
## - Zeit pausiert während Tutorial
## - UI ist nicht blockierbar wenn hidden
class_name TutorialManager
extends Control

## Feature (v16.5): drei Rundgänge statt einer linearen Liste -
##   "basic"     Grundlagen (Kamera, Bauen, Versorgung, Forschung, Frettchenmodus)
##   "systems"   Systeme (Bezirke, Wasser & Dürre, Jahreszeiten, Felder, Expeditionen, Animationen)
##   "logistics" Kolonien & Schiene (Rathaus, Kolonien-Fenster, Gleise, Linien, Mitfahren)
## Gestartet werden sie über das Pause-Menü, den Dev-Modus oder (nur "basic", nur beim
## allerersten Spielstart) automatisch. Der Fortschritt steht in user://tutorial.cfg.
## wait_for-Varianten: "building_placed_at_marker", "fp_mode_entered", "panel:<Knotenname>"
## (wartet, bis das Fenster neben dem Tutorial sichtbar wird). Bei jedem wartenden Schritt
## gibt es "Schritt überspringen", damit man nie festhängt.
const CFG_PATH: String = "user://tutorial.cfg"
const HUD_BTNS: String = "../HUD/RightColumn/ExtraPanel/ExtraButtons/"

const STEPS_BASIC: Array = [
	{"title": "Willkommen!",
	 "text": "Hallo, ich bin Freddy Frettchen! Ich zeige dir Schritt für Schritt, wie deine Kolonie funktioniert. Das dauert nur ein paar Minuten."},
	{"title": "Kamera bewegen",
	 "text": "Bewege die Kamera mit WASD oder den Pfeiltasten. Mit dem Mausrad zoomst du, mit gedrückter rechter Maustaste ziehst du die Ansicht."},
	{"title": "Dein Bauhof",
	 "text": "Das ist dein Bauhof - hier arbeiten Frettchen-Baumeister an deinen Baustellen. Ohne freie Bauhof-Arbeiter geht keine Baustelle voran."},
	{"title": "Bau-Menü",
	 "text": "Links siehst du das Bau-Menü mit allen verfügbaren Gebäuden, sortiert nach Kategorie.",
	 "highlight_path": "../BuildMenu"},
	{"title": "Dein erstes Gebäude",
	 "text": "Am Boden siehst du eine grün markierte Kachel. Öffne das Bau-Menü, wähle den Holzfäller (🪓) und platziere ihn auf der markierten Kachel.",
	 "wait_for": "building_placed_at_marker", "marker": true},
	{"title": "Gut gemacht!",
	 "text": "Super! Der Holzfäller sammelt jetzt automatisch Holz von nahen Bäumen. So arbeiten fast alle Sammel-Gebäude: Sie brauchen die passende Ressource in ihrem Radius."},
	{"title": "Ressourcen im Blick",
	 "text": "Oben siehst du deine Rohstoffe (Holz, Stein, Beeren, Wasser) und wie viele Frettchen deine Kolonie hat.",
	 "highlight_path": "../HUD/TopBar"},
	{"title": "Das Wichtigste: Essen & Trinken",
	 "text": "Deine Frettchen brauchen Essen und Wasser - das ist die oberste Priorität! Baue schnell einen Brunnen und eine Nahrungsquelle wie einen Beerensammler."},
	{"title": "Ein Zuhause bauen",
	 "text": "Ein Wohnhaus gibt deinen Frettchen Schlafplätze. Ohne freie Betten gibt es keinen Nachwuchs - die Kolonie wächst nur bei guter Versorgung und Stimmung."},
	{"title": "Stimmung heben",
	 "text": "Gebäude wie der Versammlungsplatz heben die Laune aller Frettchen in der Nähe. Glückliche Frettchen arbeiten schneller und bekommen mehr Nachwuchs."},
	{"title": "Gelände formen",
	 "text": "Im Bau-Menü unter 'Terrain' kannst du Erde aufschütten oder mit Sprengstoff Hügel abtragen."},
	{"title": "Forschung & Tech-Baum",
	 "text": "Die Forschungsstube produziert Wissenspunkte. Damit schaltest du im Tech-Baum (hier markiert) Verbesserungen für deine Gebäude frei.",
	 "highlight_path": HUD_BTNS + "TechTreeBtn"},
	{"title": "Epochen-Fortschritt",
	 "text": "Oben im Bau-Menü zeigt der Epochen-Button, was du brauchst um in die nächste Epoche zu gehen. Jede neue Epoche schaltet viele neue Gebäude frei.",
	 "highlight_path": "../BuildMenu"},
	{"title": "Der Frettchenmodus",
	 "text": "Drücke [F], um die Perspektive eines einzelnen Frettchens zu sehen! Du kannst dort herumlaufen und mit [E] Ressourcen in Minispielen sammeln. Probier's jetzt!",
	 "wait_for": "fp_mode_entered"},
	{"title": "Willkommen zurück!",
	 "text": "Mit [ESC] oder erneut [F] kommst du zurück zur Kolonie-Ansicht. Dein Frettchen merkt sich seine Position."},
	{"title": "Dein Frettchen personalisieren",
	 "text": "Im Pause-Menü siehst du dein Frettchen-Ich. Accessoires, die du durch Erfolge freischaltest, geben eigene kleine Boni."},
	{"title": "Erfolge sammeln",
	 "text": "Für Meilensteine (viele Frettchen, große Lager, überstandene Dürren, die erste Zugfahrt) schaltest du Erfolge frei - hier markiert.",
	 "highlight_path": HUD_BTNS + "AchievementBtn"},
	{"title": "Spielgeschwindigkeit",
	 "text": "Die Zeit läuft automatisch. Mit diesen Buttons (hier markiert) oder [Leertaste] kannst du beschleunigen oder pausieren.",
	 "highlight_path": "../HUD/RightColumn/SpeedPanel"},
	{"title": "Speichern",
	 "text": "Über das Pause-Menü ([Leertaste]) kannst du jederzeit speichern - dein Fortschritt, dein Frettchen-Ich und deine Ausrüstung bleiben erhalten."},
	{"title": "Viel Erfolg!",
	 "text": "Das war's für den Anfang! Weitere Rundgänge findest du jederzeit im Pause-Menü: 'Systeme' (Bezirke, Wasser, Dürre, Jahreszeiten, Expeditionen) und 'Kolonien & Schiene' (mehrere Kolonien, Züge, Mitfahren)."},
]

const STEPS_SYSTEMS: Array = [
	{"title": "Systeme-Rundgang",
	 "text": "Dieser Rundgang erklärt die Systeme, die dich im Lauf des Spiels begleiten: Bezirke, Wasser & Dürre, Jahreszeiten, Felder, Expeditionen und lebendige Gebäude. Du kannst jederzeit überspringen."},
	{"title": "Bezirke",
	 "text": "Jeder Bauhof gründet einen Bezirk. Neue Gebäude gehören zum nächsten Bauhof, und Frettchen holen Baumaterial nur aus Lagern ihres Bezirks. Mit dem Bezirkstor (ab Epoche 2) verbindest du benachbarte Bezirke. Hier siehst du alle Bezirke.",
	 "highlight_path": HUD_BTNS + "DistrictBtn"},
	{"title": "Wasser",
	 "text": "Wasser ist lebenswichtig. Brunnen und Wasserpumpen sammeln es, Wassertürme und Reservoire speichern es. Der blaue Wassertank oben zeigt, wie viel noch da ist - ist er leer, werden die Frettchen durstig.",
	 "highlight_path": "../HUD/TopBar"},
	{"title": "Dürre",
	 "text": "Regelmäßig naht eine Dürre. Unter der Uhr erscheint dann ein Countdown. Fülle vorher dein Wasserreservoir - in der Dürre verbrauchen Felder und Frettchen mehr Wasser und Quellen liefern weniger.",
	 "highlight_path": "../HUD/RightColumn/InfoPanel"},
	{"title": "Jahreszeiten",
	 "text": "Es gibt vier Jahreszeiten mit je 15 Tagen. Im Sommer produzierst du am meisten, im Winter am wenigsten - plane Vorräte für die kalte Zeit. Die aktuelle Jahreszeit steht unter der Uhr.",
	 "highlight_path": "../HUD/RightColumn/InfoPanel"},
	{"title": "Felder & Landwirtschaft",
	 "text": "Mit einem Bauernhof schaltest du im Bau-Menü das Feld-Werkzeug frei: Felder malst du per Ziehen auf Wiesen. Sie brauchen Wasser - besonders in der Dürre. Weizen wird zu Brot und Eintopf."},
	{"title": "Expeditionen",
	 "text": "Im Expeditionslager (ab Epoche 2) schickst du mehrere Frettchen für einige Tage auf Reisen. Sie bringen Rohstoffe und seltene Fundstücke mit. Hier verwaltest du alle Expeditionen.",
	 "highlight_path": HUD_BTNS + "ExpeditionBtn"},
	{"title": "Gebäude bei der Arbeit",
	 "text": "Arbeitende Gebäude werden lebendig: Sägen, Räder, Schmieden und Türen bewegen sich. Steht ein Gebäude still, fehlen Arbeiter oder Rohstoffe - oder es ist Nacht. Bei Pause stehen auch die Animationen still, bei 2x/3x laufen sie schneller."},
	{"title": "Fertig!",
	 "text": "Das waren die wichtigsten Systeme. Der Rundgang 'Kolonien & Schiene' im Pause-Menü zeigt dir das Spätspiel."},
]

const STEPS_LOGISTICS: Array = [
	{"title": "Kolonien & Schiene",
	 "text": "Im Spätspiel gründest du weitere Kolonien und verbindest sie mit Zügen. Diese Funktionen schaltest du über die Epochen frei - der Rundgang erklärt sie schon jetzt."},
	{"title": "Das Rathaus",
	 "text": "Das Rathaus ist das Herz einer Kolonie: Es legt ihr Gebiet fest (Radius 16 Kacheln). Gebaut wird nur im Gebiet der aktiven Kolonie. Deine Startkolonie hat ihr Rathaus von Anfang an."},
	{"title": "Das Kolonien-Fenster",
	 "text": "Klicke jetzt auf 🏛️ (hier markiert), um alle Kolonien zu sehen.",
	 "highlight_path": HUD_BTNS + "ColonyBtn", "wait_for": "panel:ColonyPanel"},
	{"title": "Mehrere Kolonien",
	 "text": "Jede Kolonie hat eigene Lager, eigenes Wasser und eine eigene Bevölkerung. Mit 'Anzeigen' wechselst du die Kolonie - die Kamera springt zum Rathaus. Forschung gilt für alle gemeinsam. Auch ein Klick auf ein Gebäude wechselt die Kolonie."},
	{"title": "Neue Kolonie gründen",
	 "text": "Baue ab Epoche 2 im Bau-Menü unter 'Kolonie' ein weiteres Rathaus - mindestens 20 Kacheln von jedem anderen entfernt. Deine Kolonie braucht mindestens 5 Frettchen, 3 ziehen als Siedler mit. Die Baukosten sind das Gründungspaket: Sie werden zum Startbestand der neuen Kolonie, Bauhof und Lager gibt es gratis.",
	 "highlight_path": "../BuildMenu"},
	{"title": "Die Entdeckerkarte",
	 "text": "Wählst du beim neuen Spiel 'Entdecker (120x120, Nebel)', kennst du anfangs nur dein Heimatland - der Rest liegt im Nebel. Im Nebel darf nichts gebaut werden. Dort liegt auch das Eisen, das du für Maschinen und Züge brauchst."},
	{"title": "Die Erkundungsstation",
	 "text": "Ab Epoche 5 ('Eisenbahnzeit') baust du im Bau-Menü unter 'Erkundung' die Erkundungsstation. Solange Frettchen darin arbeiten, löst sich der Nebel im Umkreis nach und nach auf (Radius 14, mit Upgrades 21 und 28). Stelle sie an den Rand deiner Kolonie.",
	 "highlight_path": "../BuildMenu"},
	{"title": "Nachbarkolonien",
	 "text": "Im Nebel liegen fremde Kolonien. Deckst du ihr Dorf auf, erscheinen sie - klicke auf 🤝 (hier markiert), um zu sehen, was sie bieten und brauchen. Jedes Dorf hat einen eigenen Bahnhof: Verbinde ihn per Gleis mit deinem Netz und stelle eine Linie dorthin ein.",
	 "highlight_path": HUD_BTNS + "NeighborBtn", "wait_for": "panel:NeighborPanel"},
	{"title": "Handel & Ruf",
	 "text": "Waren, die dein Zug am Bahnhof eines Nachbarn ABLIEFERT, steigern den Ruf - gewünschte Waren doppelt. Wenn dein Zug dort lädt, kostet das etwas Ruf. Erfülle ihre Aufträge für Bonus-Ruf. Ab Ruf 80 und mit Bahnanschluss kannst du das Dorf friedlich annektieren: Es wird eine eigene Kolonie von dir. Dort liegt zum Beispiel das Eisen für deine Maschinen!"},
	{"title": "Die Weltkarte",
	 "text": "Klicke jetzt auf 🧭 (hier markiert): Die Weltkarte zeigt, was du schon kennst, deine Kolonie-Gebiete, Gleise und Züge. Ein Klick auf die Karte springt mit der Kamera dorthin.",
	 "highlight_path": HUD_BTNS + "WorldMapBtn", "wait_for": "panel:WorldMapPanel"},
	{"title": "Die Schiene",
	 "text": "Epoche 5 schaltet auch Bahnhof, Depot und das Gleis-Werkzeug frei. Damit tauschen deine Kolonien Waren: Bretter für Eisen, Holz für Kohle ...",
	 "highlight_path": "../BuildMenu"},
	{"title": "Gleise legen",
	 "text": "Wähle 'Gleis legen' im Bau-Menü und ziehe die Strecke mit gedrückter Maustaste. Jede Kachel kostet 1 Brett und 1 Eisen. Gleise gehen nicht über Wasser oder durchs Gebirge und nicht auf Gebäude, Felder oder Vorkommen. Ist ein Hang zu steil, schütte Erde auf oder sprenge ihn ab."},
	{"title": "Bahnhof & Depot",
	 "text": "Der Bahnhof ist eine Haltestelle: Er tauscht Waren mit dem Lager der Kolonie, in der er steht. Im Depot stehen deine Züge. Beide gehören ans Gleisnetz - stelle sie an die Strecke, dann verbinden sie sich von selbst."},
	{"title": "Das Linien-Fenster",
	 "text": "Klicke jetzt auf 🚂 (hier markiert), um Linien und Züge zu verwalten.",
	 "highlight_path": HUD_BTNS + "LineBtn", "wait_for": "panel:LinePanel"},
	{"title": "Eine Linie einrichten",
	 "text": "So geht's: 1) '+ Neue Linie'  2) Bahnhöfe als Haltestellen hinzufügen  3) '+ Fracht': Ware wählen, von welchem Halt nach welchem  4) im Depot 'Zug kaufen' und auf die Linie setzen. Steht oben 'fahrbereit', fährt der Zug los. Ist ein Ziellager voll, bleibt die Fracht an Bord."},
	{"title": "Im Zug mitfahren",
	 "text": "Im Frettchenmodus ([F]) kannst du zu einem haltenden Zug laufen und mit [E] einsteigen. Du sitzt auf der Lok, siehst dich mit der Maus um und steigst am nächsten Halt mit [E] wieder aus. Deine erste Fahrt bringt den Erfolg 'Fahrgast'."},
	{"title": "Selbst fahren (Lokführer)",
	 "text": "Im Zug kannst du selbst fahren: [W] gibt Gas, [S] bremst, [T] schaltet zur Automatik zurück. Auch am Bahnhof heißt [W] 'vorzeitige Abfahrt'. Fährst du einen Halt schnell an (ohne vorher stark zu bremsen), gilt er als 'pünktlich' und der Stopp halbiert sich - pünktliche, selbst gefahrene Ablieferungen beim Nachbarn bringen 25 % mehr Ruf. Der Erfolg 'Lokführer' zählt deine selbst gefahrenen Halte."},
	{"title": "Tipps für den Handel",
	 "text": "Eisen und Kohle liegen oft weit weg: Baue dort eine Bergbau-Kolonie und fahre Bretter und Essen hin. Behalte die Lager im Blick - ein volles Ziellager bremst die Linie. Mehrere Züge auf einer Linie erhöhen den Durchsatz."},
	{"title": "Gute Fahrt!",
	 "text": "Viel Erfolg beim Aufbau deines Schienennetzes! Alle Rundgänge kannst du jederzeit im Pause-Menü wiederholen."},
]

const TRACKS: Dictionary = {
	"basic": {"name": "Grundlagen", "steps": STEPS_BASIC},
	"systems": {"name": "Systeme", "steps": STEPS_SYSTEMS},
	"logistics": {"name": "Kolonien & Schiene", "steps": STEPS_LOGISTICS},
}

var _track: String = "basic"
var _steps: Array = []
var _wait_panel: Control = null     # bei wait_for "panel:<Name>": das beobachtete Fenster
var _step: int = 0
var _waiting_for: String = ""
var _marker_tile: Vector2i = Vector2i(-1, -1)
var _highlight_target: Control = null
var _box: PanelContainer
var _title_lbl: Label
var _text_lbl: Label
var _next_btn: Button
var _skip_btn: Button
var _step_lbl: Label
var _game_ctrl: Node = null

# ── Fortschritt (user://tutorial.cfg) ─────────────────────────────────────────
static func is_done(track: String) -> bool:
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) != OK: return false
	return bool(cf.get_value("done", track, false))

static func mark_done(track: String) -> void:
	var cf := ConfigFile.new()
	cf.load(CFG_PATH)
	cf.set_value("done", track, true)
	cf.save(CFG_PATH)

static func reset_progress() -> void:
	var cf := ConfigFile.new()
	cf.save(CFG_PATH)   # leere Datei = nichts erledigt

func is_running() -> bool:
	return visible

## Startet die Grundlagen automatisch - aber nur einmal (beim allerersten Spielstart).
func maybe_autostart() -> void:
	if not is_done("basic"):
		start("basic")

func _ready() -> void:
	# v16.5: das Vollbild-Control darf KEINE Klicks schlucken (vorher STOP -> Bau-Menü und
	# Welt waren während des Tutorials nicht klickbar, der Schritt "Dein erstes Gebäude"
	# unlösbar). Nur die Tutorial-Box selbst (_box) fängt Mausereignisse ab.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide()
	_build_ui()
	GameState.building_placed.connect(_on_building_placed)
	DevMode.dev_mode_changed.connect(func(_e): _layout_box())
	get_viewport().size_changed.connect(_layout_box)
	GameState.fp_mode_changed.connect(_on_fp_mode_changed)
	_game_ctrl = get_node_or_null("../../..")

## v16.5: Box zwischen Bau-Menü (links, ca. 290 px) und rechtem Rand legen; ist der Dev-Modus an,
## bleibt rechts Platz für das Dev-Fenster (DevToolsPanel.WIDTH), damit nichts überlappt.
const BOX_LEFT: float = 290.0
const BOX_MAX_WIDTH: float = 900.0
func _layout_box() -> void:
	if _box == null: return
	var vw: float = get_viewport_rect().size.x
	var right_gap: float = (300.0 + 24.0) if DevMode.enabled else 24.0
	var avail: float = maxf(320.0, vw - BOX_LEFT - right_gap)
	var width: float = minf(BOX_MAX_WIDTH, avail)
	var x0: float = BOX_LEFT + (avail - width) * 0.5
	_box.anchor_left = 0.0; _box.anchor_right = 0.0
	_box.anchor_top = 1.0; _box.anchor_bottom = 1.0
	_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_box.offset_left = x0; _box.offset_right = x0 + width
	_box.offset_top = -192.0; _box.offset_bottom = -24.0

func _build_ui() -> void:
	_box = PanelContainer.new(); _box.name = "TutorialBox"
	_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_layout_box()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.13, 0.95)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 18; sb.content_margin_right = 18
	sb.content_margin_top = 14;  sb.content_margin_bottom = 14
	sb.border_width_top = 2; sb.border_color = Color(0.96, 0.69, 0.1)
	_box.add_theme_stylebox_override("panel", sb)
	add_child(_box)

	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 8)
	_box.add_child(vb)

	var hdr := HBoxContainer.new(); hdr.add_theme_constant_override("separation", 10)
	vb.add_child(hdr)

	var icon := Label.new(); icon.text = "🦡"
	icon.add_theme_font_size_override("font_size", 30)
	hdr.add_child(icon)

	var hdr_vb := VBoxContainer.new(); hdr_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(hdr_vb)
	_title_lbl = Label.new()
	_title_lbl.add_theme_font_size_override("font_size", 16)
	_title_lbl.add_theme_color_override("font_color", Color(0.96, 0.69, 0.1))
	hdr_vb.add_child(_title_lbl)
	_step_lbl = Label.new()
	_step_lbl.add_theme_font_size_override("font_size", 11)
	_step_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	hdr_vb.add_child(_step_lbl)

	_text_lbl = Label.new()
	_text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	_text_lbl.add_theme_font_size_override("font_size", 14)
	_text_lbl.custom_minimum_size = Vector2(0, 64)
	vb.add_child(_text_lbl)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	_skip_btn = Button.new(); _skip_btn.text = "Tutorial überspringen"
	_skip_btn.pressed.connect(_on_skip)
	row.add_child(_skip_btn)
	_next_btn = Button.new(); _next_btn.text = "Weiter"
	_next_btn.pressed.connect(_on_next)
	row.add_child(_next_btn)

## track: "basic" | "systems" | "logistics" (siehe TRACKS)
func start(track: String = "basic") -> void:
	if not TRACKS.has(track): track = "basic"
	_track = track
	_steps = (TRACKS[track] as Dictionary)["steps"] as Array
	_step = 0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show()
	_pause_game()
	_show_step()

func _pause_game() -> void:
	GameState.tutorial_active = true
	if _game_ctrl != null:
		_game_ctrl.call_deferred("set_simulation_paused", true)

func _unpause_game() -> void:
	GameState.tutorial_active = false
	if _game_ctrl != null:
		_game_ctrl.call_deferred("set_simulation_paused", false)

func _show_step() -> void:
	_clear_marker()
	_unwatch_panel()
	if _step >= _steps.size():
		_finish()
		return
	var s: Dictionary = _steps[_step]
	_title_lbl.text = str(s.get("title",""))
	_text_lbl.text = str(s.get("text",""))
	_step_lbl.text = "%s · Schritt %d/%d" % [str((TRACKS[_track] as Dictionary)["name"]), _step + 1, _steps.size()]
	_waiting_for = str(s.get("wait_for",""))
	# Wartende Schritte bleiben überspringbar, damit man nie festhängt.
	_next_btn.visible = true
	_next_btn.text = "Weiter" if _waiting_for.is_empty() else "Schritt überspringen"
	if _waiting_for.begins_with("panel:"):
		_watch_panel(_waiting_for.substr(6))
	if bool(s.get("marker", false)):
		_place_marker()
	var hp: String = str(s.get("highlight_path", ""))
	_highlight_target = (get_node_or_null(hp) as Control) if hp != "" else null

func _place_marker() -> void:
	if _game_ctrl == null: return
	var renderer = _game_ctrl.get("renderer")
	if renderer == null: return
	var start_tile: Vector2i = renderer.call("world3d_to_tile", _game_ctrl.get("_cam_target"))
	_marker_tile = _game_ctrl.call("find_nearby_buildable_tile", start_tile.x, start_tile.y)
	if _marker_tile.x >= 0:
		renderer.call("show_tutorial_marker", _marker_tile.x, _marker_tile.y)

func _clear_marker() -> void:
	if _marker_tile.x < 0: return
	_marker_tile = Vector2i(-1, -1)
	if _game_ctrl == null: return
	var renderer = _game_ctrl.get("renderer")
	if renderer: renderer.call("hide_tutorial_marker")

func _process(_delta: float) -> void:
	if _highlight_target != null:
		queue_redraw()

func _draw() -> void:
	if _highlight_target == null or not is_instance_valid(_highlight_target): return
	if not _highlight_target.is_visible_in_tree(): return
	var r: Rect2 = _highlight_target.get_global_rect()
	r.position -= global_position
	var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)
	var col := Color(1.0, 0.85, 0.15, 0.55 + 0.35 * pulse)
	draw_rect(r.grow(5.0 + pulse * 2.0), col, false, 3.5)

func _on_next() -> void:
	_step += 1
	_show_step()

func _on_skip() -> void:
	_finish()

## wait_for "panel:<Name>": wartet, bis das Fenster (Geschwister des Tutorials) sichtbar wird.
func _watch_panel(panel_name: String) -> void:
	_wait_panel = get_node_or_null("../" + panel_name) as Control
	if _wait_panel == null or not is_instance_valid(_wait_panel):
		_wait_panel = null
		return
	if _wait_panel.visible:
		_waiting_for = ""; _step += 1; call_deferred("_show_step"); return
	_wait_panel.visibility_changed.connect(_on_watched_panel_visibility)

func _unwatch_panel() -> void:
	if _wait_panel != null and is_instance_valid(_wait_panel) and _wait_panel.visibility_changed.is_connected(_on_watched_panel_visibility):
		_wait_panel.visibility_changed.disconnect(_on_watched_panel_visibility)
	_wait_panel = null

func _on_watched_panel_visibility() -> void:
	if not visible or not _waiting_for.begins_with("panel:"): return
	if _wait_panel == null or not _wait_panel.visible: return
	_waiting_for = ""
	_step += 1
	call_deferred("_show_step")

func _on_building_placed(b) -> void:
	if not visible or _waiting_for != "building_placed_at_marker": return
	if _marker_tile.x >= 0 and b != null:
		var btx: int = int(b.tile_x)
		var bty: int = int(b.tile_y)
		if absi(btx - _marker_tile.x) > 1 or absi(bty - _marker_tile.y) > 1:
			return
	_waiting_for = ""
	_step += 1
	_show_step()

func _on_fp_mode_changed(active: bool) -> void:
	if not visible or _waiting_for != "fp_mode_entered": return
	if not active: return
	_waiting_for = ""
	_step += 1
	_show_step()

func _finish() -> void:
	mark_done(_track)   # auch beim Überspringen: nicht bei jedem Start erneut nerven
	_unwatch_panel()
	_clear_marker()
	_highlight_target = null
	_unpause_game()
	# Feature (v13.1, Bugfix): Zuerst komplett verbergen und UI-Events
	# freigeben, DANN unpause
	hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
