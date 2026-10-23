## UnlockExplainer.gd
## Feature (v12.3, Tutorial-Überarbeitung): reagiert auf
## GameState.tech_unlocked (sowohl Epochen- als auch einzelne
## Tech-Knoten-Freischaltungen) und zeigt automatisch eine kurze
## Einführungskarte für JEDES dadurch neu verfügbare Gebäude - genau die
## vom Nutzer gewünschte "progressive Erklärung": man muss nicht mehr
## selbst herausfinden, was ein neues Gebäude tut, sondern bekommt es
## automatisch in dem Moment erklärt, in dem es relevant wird. Läuft die
## GESAMTE Spielsitzung über im Hintergrund (nicht nur während des
## Einführungs-Tutorials) - siehe ui/TutorialManager.gd für den separaten
## anfänglichen Rundgang.
extends PanelContainer

var _queue: Array = []   # Array[String] Gebäude-IDs, noch anzuzeigen
var _box: PanelContainer
var _icon_lbl: Label
var _title_lbl: Label
var _summary_lbl: Label
var _tip_lbl: Label
var _next_btn: Button
var _count_lbl: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	offset_left = -360; offset_right = -20
	offset_top = -110; offset_bottom = 110
	hide()
	_build_ui()
	GameState.tech_unlocked.connect(_on_tech_unlocked)

func _build_ui() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.11, 0.08, 0.96)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 16; sb.content_margin_right = 16
	sb.content_margin_top = 14;  sb.content_margin_bottom = 14
	sb.border_width_left = 3; sb.border_color = Color(0.35, 0.85, 0.4)
	add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 6)
	add_child(vb)

	var hdr := HBoxContainer.new(); hdr.add_theme_constant_override("separation", 8)
	vb.add_child(hdr)
	var badge := Label.new(); badge.text = "🆕"
	badge.add_theme_font_size_override("font_size", 13)
	badge.add_theme_color_override("font_color", Color(0.35, 0.85, 0.4))
	hdr.add_child(badge)
	var badge_txt := Label.new(); badge_txt.text = "Neu verfügbar"
	badge_txt.add_theme_font_size_override("font_size", 11)
	badge_txt.add_theme_color_override("font_color", Color(0.6, 0.85, 0.6))
	hdr.add_child(badge_txt)

	var title_row := HBoxContainer.new(); title_row.add_theme_constant_override("separation", 8)
	vb.add_child(title_row)
	_icon_lbl = Label.new(); _icon_lbl.add_theme_font_size_override("font_size", 26)
	title_row.add_child(_icon_lbl)
	_title_lbl = Label.new()
	_title_lbl.add_theme_font_size_override("font_size", 15)
	_title_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.85))
	title_row.add_child(_title_lbl)

	_summary_lbl = Label.new()
	_summary_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	_summary_lbl.add_theme_font_size_override("font_size", 12)
	vb.add_child(_summary_lbl)

	_tip_lbl = Label.new()
	_tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	_tip_lbl.add_theme_font_size_override("font_size", 11)
	_tip_lbl.add_theme_color_override("font_color", Color(0.8, 0.75, 0.4))
	vb.add_child(_tip_lbl)

	var row := HBoxContainer.new(); vb.add_child(row)
	_count_lbl = Label.new()
	_count_lbl.add_theme_font_size_override("font_size", 10)
	_count_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	_count_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_count_lbl)
	_next_btn = Button.new(); _next_btn.text = "Verstanden"
	_next_btn.pressed.connect(_on_dismiss)
	row.add_child(_next_btn)

## Feature (v12.3): ermittelt aus einer Freischaltungs-ID (Epoche ODER
## einzelner Tech-Knoten) alle dadurch neu verfügbaren Gebäude-IDs -
## dieselbe Logik wie TechTreeSys.get_unlocked_buildings(), nur eingegrenzt
## auf GENAU diese eine Freischaltung statt auf den gesamten bisherigen
## Fortschritt.
func _on_tech_unlocked(id: String) -> void:
	var new_buildings: Array = []
	if TechTreeSys.EPOCHS.has(id):
		for bid in (TechTreeSys.EPOCHS[id] as Dictionary).get("unlocks", []):
			new_buildings.append(str(bid))
	elif TechTreeSys.NODES.has(id):
		for eff in (TechTreeSys.NODES[id] as Dictionary).get("effects", []):
			var e: Dictionary = eff
			if str(e.get("type", "")) == "unlock":
				new_buildings.append(str(e.get("building", "")))
	for bid in new_buildings:
		# Nur Gebäude mit hinterlegter Erklärung UND nur Dekorationen NICHT
		# separat erklären (die sind selbsterklärend - reine Deko) -
		# spart unnötige Karten bei einem Epochensprung mit vielen
		# Gebäuden auf einmal.
		if BuildingExplanations.get_explanation(bid).is_empty(): continue
		var bd: Dictionary = BuildingData.BUILDINGS.get(bid, {})
		if str(bd.get("type", "")) == "DECO": continue
		_queue.append(bid)
	if not _queue.is_empty() and not visible:
		_show_next()

func _show_next() -> void:
	if _queue.is_empty():
		hide(); return
	var bid: String = str(_queue[0])
	var bd: Dictionary = BuildingData.BUILDINGS.get(bid, {})
	var ex: Dictionary = BuildingExplanations.get_explanation(bid)
	_icon_lbl.text = str(bd.get("icon", "🏗️"))
	_title_lbl.text = str(bd.get("name", bid))
	_summary_lbl.text = str(ex.get("summary", ""))
	var tip: String = str(ex.get("tip", ""))
	_tip_lbl.text = ("💡 " + tip) if tip != "" else ""
	_tip_lbl.visible = tip != ""
	_count_lbl.text = ("noch %d weitere" % (_queue.size() - 1)) if _queue.size() > 1 else ""
	show()

func _on_dismiss() -> void:
	if not _queue.is_empty(): _queue.pop_front()
	_show_next()
