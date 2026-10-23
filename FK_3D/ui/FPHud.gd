## FPHud.gd
## Feature (v11.2, First-Person-Modus): minimale HUD-Ebene, die nur sichtbar
## ist, während man sein Frettchen im First-Person-Modus steuert -
## Fadenkreuz, Interaktions-Prompt ("[E] Holz fällen") und ein kurzer
## Steuerungs-Hinweis unten. Komplett von der normalen Kolonie-HUD (HUD.gd)
## getrennt, damit sich beide UI-Ebenen nicht gegenseitig stören.
extends Control

var _crosshair: Label = null
var _prompt_lbl: Label = null
var _help_lbl: Label = null
var _floaty_lbl: Label = null
var _floaty_t: float = 0.0
# Feature (v12.2, Phase 4): Anzeige, welche Accessoires am Frettchen-Ich
# gerade aktiv sind (Nutzeranfrage: "eine Anzeige im FP-HUD wäre nicht
# schlecht"), oben links, dezent.
var _accessory_lbl: Label = null

func _ready() -> void:
	hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_crosshair = Label.new(); _crosshair.text = "+"
	_crosshair.add_theme_font_size_override("font_size", 22)
	_crosshair.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.85))
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.position = Vector2(-7.0, -16.0)
	add_child(_crosshair)

	_prompt_lbl = Label.new(); _prompt_lbl.text = ""
	_prompt_lbl.add_theme_font_size_override("font_size", 16)
	_prompt_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	_prompt_lbl.set_anchors_preset(Control.PRESET_CENTER)
	_prompt_lbl.position = Vector2(-140.0, 30.0)
	_prompt_lbl.custom_minimum_size = Vector2(280.0, 0.0)
	_prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_prompt_lbl)

	_floaty_lbl = Label.new(); _floaty_lbl.text = ""
	_floaty_lbl.add_theme_font_size_override("font_size", 20)
	_floaty_lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	_floaty_lbl.set_anchors_preset(Control.PRESET_CENTER)
	_floaty_lbl.position = Vector2(-100.0, -70.0)
	_floaty_lbl.custom_minimum_size = Vector2(200.0, 0.0)
	_floaty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floaty_lbl.visible = false
	add_child(_floaty_lbl)

	_help_lbl = Label.new()
	_help_lbl.text = "WASD: Bewegen | Maus: Umsehen | E: Interagieren | ESC: Zurück zur Kolonie"
	_help_lbl.add_theme_font_size_override("font_size", 12)
	_help_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 0.8))
	_help_lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_help_lbl.position.y = -28.0
	_help_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_help_lbl)

	# Feature (v12.2, Phase 4):
	_accessory_lbl = Label.new()
	_accessory_lbl.text = ""
	_accessory_lbl.add_theme_font_size_override("font_size", 12)
	_accessory_lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0, 0.85))
	_accessory_lbl.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_accessory_lbl.position = Vector2(14.0, 14.0)
	_accessory_lbl.custom_minimum_size = Vector2(260.0, 0.0)
	add_child(_accessory_lbl)
	PlayerAccessories.equipment_changed.connect(_refresh_accessory_label)
	_refresh_accessory_label()

## Feature (v12.2, Phase 4): baut die Zeile "🎨 Zylinder, Fliege, ..." aus
## allen aktuell ausgerüsteten Accessoires (leere Slots werden ausgelassen).
func _refresh_accessory_label() -> void:
	if _accessory_lbl == null: return
	var names: Array = []
	for slot in PlayerAccessories.equipped:
		var aid: String = str(PlayerAccessories.equipped[slot])
		if aid == "": continue
		var ad: Dictionary = FerretAccessories.get_accessory(aid)
		if not ad.is_empty(): names.append(str(ad.get("name", aid)))
	_accessory_lbl.text = ("🎨 " + ", ".join(names)) if not names.is_empty() else ""

func _process(dt: float) -> void:
	if _floaty_lbl.visible:
		_floaty_t -= dt
		_floaty_lbl.position.y -= dt * 18.0
		_floaty_lbl.modulate.a = clampf(_floaty_t / 1.2, 0.0, 1.0)
		if _floaty_t <= 0.0: _floaty_lbl.visible = false

## prompt_text == "" blendet den Hinweis aus (kein Ziel in Reichweite).
func set_prompt(prompt_text: String) -> void:
	_prompt_lbl.text = prompt_text
	_prompt_lbl.visible = prompt_text != ""

## Kurze, nach oben wegschwebende Erfolgsmeldung ("+14 🪵"), genutzt nach
## einem abgeschlossenen Minispiel.
func show_floaty(text: String, success: bool) -> void:
	_floaty_lbl.text = text
	_floaty_lbl.add_theme_color_override("font_color",
		Color(0.4, 1.0, 0.5) if success else Color(0.9, 0.4, 0.35))
	_floaty_lbl.position = Vector2(-100.0, -70.0)
	_floaty_lbl.modulate.a = 1.0
	_floaty_lbl.visible = true
	_floaty_t = 1.2
