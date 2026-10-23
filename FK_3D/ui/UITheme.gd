class_name UITheme
extends RefCounted
## Zentrales UI-Theme (v15.0).
##
## EIN Ort für das gesamte Aussehen der Oberfläche: Palette, Schriften, Abstände
## und alle Control-Stile. WICHTIG: Godots Theme-Vererbung bricht an Eltern ab,
## die kein Control sind (Node, CanvasLayer) - das Window-Theme erreicht UI darunter
## NICHT. Deshalb setzt Main das Theme direkt auf die obersten Controls (die drei
## Menü-Screens und UIRoot); alles darunter erbt es.
##
## Gestaltungsregeln (aus der Recherche, siehe Changes v15.0):
##  - Raster: 8 px (Abstände nur als Vielfache/Hälften davon)
##  - 2 Schriften: Fredoka (Titel/Überschriften) + Nunito (alles andere)
##  - Palette nach ROLLEN (Hintergrund, Fläche, Text, Akzent, Gefahr), nicht
##    nach Einzelfarben - neue UI nutzt immer diese Konstanten
##  - EIN Button-Stil mit festen Zuständen + wenige Varianten (siehe unten)
##  - EIN Panel-Stil mit wenigen Varianten, überall gleiche Radien
##
## Theme-Varianten (per `node.theme_type_variation = "..."`):
##   Button:         PrimaryButton, DangerButton, GhostButton, SceneButton, SegButton, IconButton, BuildItem
##   PanelContainer: HudBar, FloatPanel, Card, Dialog, ChipPanel
##   Label:          Title, Heading, Subheading, Muted, Small, Chip, Display, OnScene

# ── Palette (Rollen) ─────────────────────────────────────────────────────────
const C_PANEL:      Color = Color("2a211a")   # Standard-Panelfläche (dunkles Nussholz)
const C_PANEL_ALT:  Color = Color("352a21")   # angehobene Fläche (Karten, Buttons)
const C_PANEL_HOVER: Color = Color("43352a")
const C_PANEL_DEEP: Color = Color("1c1611")   # eingelassen (Eingabefelder, Tracks)
const C_BORDER:     Color = Color("54432f")
const C_TEXT:       Color = Color("f4ead5")   # Pergament
const C_TEXT_MUTED: Color = Color("b8a98c")
const C_TEXT_DIM:   Color = Color("7d705c")
const C_ACCENT:     Color = Color("f2a93b")   # Bernstein (einzige Akzentfarbe)
const C_ACCENT_HI:  Color = Color("ffc15e")
const C_ACCENT_LO:  Color = Color("b8761a")
const C_ON_ACCENT:  Color = Color("2e1d08")   # Text auf Akzent
const C_GOOD:       Color = Color("8cc16a")
const C_DANGER:     Color = Color("d9604f")
const C_WATER:      Color = Color("71b6e8")
const C_SCIENCE:    Color = Color("7fd6b0")
const C_BEDS:       Color = Color("c7a6e8")

## Tönung der (einfarbigen) Ressourcen-Icons - sorgt für einheitlichen, bewusst
## gewählten Look statt bunter Systemsymbole.
const RES_COLORS: Dictionary = {
	"WOOD": Color("cf9f68"), "STONE": Color("b3b0a8"), "BERRIES": Color("e5708c"),
	"PLANKS": Color("e0b068"), "TOOLS": Color("b9c6d2"), "FOOD": Color("f2c985"),
	"IRON": Color("a3b0bd"), "IRON_BARS": Color("cdd5de"), "MACHINES": Color("cdd5de"),
	"COAL": Color("8a847e"), "STEEL": Color("86addb"), "MEAT": Color("e0746a"),
	"WHEAT": Color("e8cb64"), "COOKED_MEAT": Color("e09a62"), "BREAD": Color("e6b878"),
	"STEW": Color("e08d58"), "DYNAMITE": Color("ec6a48"), "WATER": Color("71b6e8"),
	"SCIENCE": Color("7fd6b0")}

# ── Maße ─────────────────────────────────────────────────────────────────────
const U:        int = 8          # Rastereinheit
const R_PANEL:  int = 12
const R_BTN:    int = 8
const FONT_BODY: int = 15
const FONT_SMALL: int = 13

static var _theme: Theme = null
static var _font_body: Font = null
static var _font_bold: Font = null
static var _font_title: Font = null

# ── Öffentliche API ──────────────────────────────────────────────────────────
static func get_theme() -> Theme:
	if _theme == null: _theme = _build()
	return _theme

static func font_title() -> Font:
	get_theme(); return _font_title

## Kleine Fabrik-Helfer, damit neue UI-Teile nicht wieder mit Einzel-Overrides
## gebaut werden.
static func lbl(text: String, variation: String = "") -> Label:
	var l := Label.new(); l.text = text
	if variation != "": l.theme_type_variation = variation
	return l

static func btn(text: String, variation: String = "", min_size: Vector2 = Vector2.ZERO) -> Button:
	var b := Button.new(); b.text = text
	if variation != "": b.theme_type_variation = variation
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE   # Maus-/Touch-Spiel; verhindert hässliche Fokusrahmen nach Klick
	return b

static func panel(variation: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	if variation != "": p.theme_type_variation = variation
	return p

## Farb-Hex für BBCode/RichText.
static func hex(c: Color) -> String: return "#" + c.to_html(false)

# ── Aufbau ───────────────────────────────────────────────────────────────────
static func _sb(bg: Color, radius: int = R_BTN, border: Color = Color(0, 0, 0, 0), bw: int = 0,
		pad_h: int = 16, pad_v: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(bw)
	s.border_color = border
	s.content_margin_left = pad_h; s.content_margin_right = pad_h
	s.content_margin_top = pad_v;  s.content_margin_bottom = pad_v
	s.anti_aliasing = true
	return s

static func _fonts() -> void:
	var tag: int = TextServerManager.get_primary_interface().name_to_tag("weight")
	var emoji: FontFile = load("res://assets/fonts/NotoEmoji.ttf") as FontFile
	var nunito: FontFile = load("res://assets/fonts/Nunito.ttf") as FontFile
	var fredoka: FontFile = load("res://assets/fonts/Fredoka.ttf") as FontFile
	# kräftigere Strichstärke für die einfarbigen Icons (sonst wirken sie blass/klein)
	var emoji_bold: FontVariation = null
	if emoji != null:
		emoji_bold = FontVariation.new(); emoji_bold.base_font = emoji
		emoji_bold.variation_opentype = {tag: 700}
	var make := func(base: Font, weight: int) -> FontVariation:
		var fv := FontVariation.new()
		fv.base_font = base
		fv.variation_opentype = {tag: weight}
		if emoji_bold != null: fv.fallbacks = [emoji_bold]
		return fv
	_font_body = make.call(nunito, 600)
	_font_bold = make.call(nunito, 800)
	_font_title = make.call(fredoka, 600)

static func _circle_tex(d: int, col: Color, ring: Color) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := Vector2(d / 2.0 - 0.5, d / 2.0 - 0.5)
	for y in d:
		for x in d:
			var dist: float = Vector2(x, y).distance_to(c)
			var r: float = d / 2.0
			var a: float = clampf(r - dist, 0.0, 1.0)
			var col_here: Color = ring if dist > r - 2.5 else col
			img.set_pixel(x, y, Color(col_here.r, col_here.g, col_here.b, col_here.a * a))
	return ImageTexture.create_from_image(img)

static func _build() -> Theme:
	_fonts()
	var t := Theme.new()
	t.default_font = _font_body
	t.default_font_size = FONT_BODY

	# ── Label ──
	t.set_color("font_color", "Label", C_TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.35))
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("shadow_offset_y", "Label", 1)
	_label_var(t, "Title", _font_title, 44, C_ACCENT_HI)
	_label_var(t, "Heading", _font_title, 26, C_TEXT)
	_label_var(t, "Subheading", _font_bold, 13, C_ACCENT)
	_label_var(t, "Muted", _font_body, FONT_SMALL, C_TEXT_MUTED)
	_label_var(t, "Small", _font_body, 12, C_TEXT_MUTED)
	_label_var(t, "Chip", _font_bold, 13, C_TEXT)
	# Auf der Spielszene/dem Panorama (kein Panel dahinter): mit dunkler Kontur
	_label_var(t, "Display", _font_title, 84, C_ACCENT_HI, 16, Color("3a230a"))
	_label_var(t, "OnScene", _font_bold, 18, C_TEXT, 6, Color(0.1, 0.07, 0.04, 0.85))

	# ── Button (Basis) ──
	_button_states(t, "Button", C_PANEL_ALT, C_PANEL_HOVER, C_PANEL_DEEP, C_BORDER, C_TEXT, 0)
	t.set_font("font", "Button", _font_bold)
	t.set_font_size("font_size", "Button", FONT_BODY)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", C_ACCENT_HI)
	t.set_color("font_hover_pressed_color", "Button", C_ACCENT_HI)
	t.set_color("font_disabled_color", "Button", Color("a39680"))
	t.set_color("font_focus_color", "Button", C_TEXT)
	t.set_stylebox("focus", "Button", _focus_box(R_BTN))

	# Primär: bernsteinfarben, mit "dickem" unteren Rand (Spielbutton-Gefühl)
	t.add_type("PrimaryButton"); t.set_type_variation("PrimaryButton", "Button")
	_primary_states(t, "PrimaryButton", C_ACCENT, C_ACCENT_HI, C_ACCENT_LO, C_ON_ACCENT)
	t.add_type("DangerButton"); t.set_type_variation("DangerButton", "Button")
	_primary_states(t, "DangerButton", C_DANGER, C_DANGER.lightened(0.15), C_DANGER.darkened(0.3), Color.WHITE)
	t.add_type("GhostButton"); t.set_type_variation("GhostButton", "Button")
	t.set_stylebox("normal", "GhostButton", _sb(Color(0, 0, 0, 0), R_BTN))
	t.set_stylebox("hover", "GhostButton", _sb(Color(1, 1, 1, 0.08), R_BTN))
	t.set_stylebox("pressed", "GhostButton", _sb(Color(0, 0, 0, 0.25), R_BTN))
	t.set_stylebox("disabled", "GhostButton", _sb(Color(0, 0, 0, 0), R_BTN))
	t.set_color("font_color", "GhostButton", C_TEXT_MUTED)
	t.set_color("font_hover_color", "GhostButton", C_TEXT)
	# Nebenaktion direkt auf der Szene/dem Panorama: halbtransparenter Grund, damit lesbar
	t.add_type("SceneButton"); t.set_type_variation("SceneButton", "Button")
	t.set_stylebox("normal", "SceneButton", _sb(Color(0.12, 0.08, 0.05, 0.62), R_BTN, Color(1, 1, 1, 0.14), 1, 16, 8))
	t.set_stylebox("hover", "SceneButton", _sb(Color(0.12, 0.08, 0.05, 0.85), R_BTN, C_ACCENT, 1, 16, 8))
	t.set_stylebox("pressed", "SceneButton", _sb(Color(0.05, 0.03, 0.02, 0.9), R_BTN, C_ACCENT, 1, 16, 8))
	t.set_color("font_color", "SceneButton", C_TEXT)
	# Segment-/Toggle-Knopf (Spielgeschwindigkeit): gedrückt = Akzent
	t.add_type("SegButton"); t.set_type_variation("SegButton", "Button")
	_button_states(t, "SegButton", C_PANEL_ALT, C_PANEL_HOVER, C_ACCENT, C_BORDER, C_TEXT_MUTED, 0)
	t.set_stylebox("pressed", "SegButton", _sb(C_ACCENT, R_BTN, C_ACCENT_LO, 0, 12, 6))
	t.set_stylebox("hover_pressed", "SegButton", _sb(C_ACCENT_HI, R_BTN, C_ACCENT_LO, 0, 12, 6))
	t.set_color("font_pressed_color", "SegButton", C_ON_ACCENT)
	t.set_color("font_hover_pressed_color", "SegButton", C_ON_ACCENT)
	# Quadratischer Icon-Knopf
	t.add_type("IconButton"); t.set_type_variation("IconButton", "Button")
	_button_states(t, "IconButton", C_PANEL_ALT, C_PANEL_HOVER, C_PANEL_DEEP, C_BORDER, C_TEXT, 0)
	for st in ["normal", "hover", "pressed", "disabled"]:
		var sbx: StyleBoxFlat = t.get_stylebox(st, "IconButton") as StyleBoxFlat
		sbx.content_margin_left = 4; sbx.content_margin_right = 4
		sbx.content_margin_top = 4; sbx.content_margin_bottom = 4
	t.set_font_size("font_size", "IconButton", 19)
	t.set_color("font_color", "IconButton", C_TEXT)
	# Baumenü-Eintrag: linksbündig, Akzentkante bei Hover/Auswahl
	t.add_type("BuildItem"); t.set_type_variation("BuildItem", "Button")
	var bi_n := _sb(C_PANEL_ALT, 10, C_BORDER, 1, 12, 8)
	var bi_h := _sb(C_PANEL_HOVER, 10, C_ACCENT_LO, 1, 12, 8)
	var bi_p := _sb(Color("4a3a22"), 10, C_ACCENT, 2, 12, 8)
	var bi_d := _sb(Color(C_PANEL_ALT, 0.5), 10, Color(C_BORDER, 0.4), 1, 12, 8)
	t.set_stylebox("normal", "BuildItem", bi_n); t.set_stylebox("hover", "BuildItem", bi_h)
	t.set_stylebox("pressed", "BuildItem", bi_p); t.set_stylebox("hover_pressed", "BuildItem", bi_p)
	t.set_stylebox("disabled", "BuildItem", bi_d)

	# ── Panel ──
	var panel := _sb(C_PANEL, R_PANEL, C_BORDER, 1, 16, 16)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	t.add_type("HudBar"); t.set_type_variation("HudBar", "PanelContainer")
	var hud := _sb(Color(C_PANEL, 0.94), 0, Color(0, 0, 0, 0), 0, 12, 3)
	hud.border_width_bottom = 2; hud.border_color = C_BORDER
	hud.shadow_color = Color(0, 0, 0, 0.35); hud.shadow_size = 8; hud.shadow_offset = Vector2(0, 2)
	t.set_stylebox("panel", "HudBar", hud)
	t.add_type("FloatPanel"); t.set_type_variation("FloatPanel", "PanelContainer")
	var fp := _sb(Color(C_PANEL, 0.92), R_PANEL, C_BORDER, 1, 6, 6)
	fp.shadow_color = Color(0, 0, 0, 0.35); fp.shadow_size = 10; fp.shadow_offset = Vector2(0, 3)
	t.set_stylebox("panel", "FloatPanel", fp)
	t.add_type("ChipPanel"); t.set_type_variation("ChipPanel", "PanelContainer")
	t.set_stylebox("panel", "ChipPanel", _sb(Color(0, 0, 0, 0.26), 12, Color(1, 1, 1, 0.05), 1, 8, 1))
	t.add_type("Card"); t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", _sb(C_PANEL_ALT, 10, C_BORDER, 1, 16, 12))
	t.add_type("Dialog"); t.set_type_variation("Dialog", "PanelContainer")
	var dlg := _sb(Color(C_PANEL, 0.97), 16, C_BORDER, 2, 26, 22)
	dlg.shadow_color = Color(0, 0, 0, 0.5); dlg.shadow_size = 24; dlg.shadow_offset = Vector2(0, 8)
	t.set_stylebox("panel", "Dialog", dlg)

	# ── Eingabefelder ──
	var le_n := _sb(C_PANEL_DEEP, R_BTN, C_BORDER, 1, 12, 8)
	var le_f := _sb(C_PANEL_DEEP, R_BTN, C_ACCENT, 2, 12, 8)
	t.set_stylebox("normal", "LineEdit", le_n); t.set_stylebox("focus", "LineEdit", le_f)
	t.set_stylebox("read_only", "LineEdit", le_n)
	t.set_color("font_color", "LineEdit", C_TEXT)
	t.set_color("font_placeholder_color", "LineEdit", C_TEXT_DIM)
	t.set_color("caret_color", "LineEdit", C_ACCENT_HI)
	t.set_color("selection_color", "LineEdit", Color(C_ACCENT, 0.4))

	# ── OptionButton / PopupMenu ──
	_button_states(t, "OptionButton", C_PANEL_DEEP, C_PANEL_HOVER, C_PANEL_DEEP, C_BORDER, C_TEXT, 0)
	t.set_font("font", "OptionButton", _font_body)
	t.set_stylebox("focus", "OptionButton", _focus_box(R_BTN))
	t.set_stylebox("panel", "PopupMenu", _sb(C_PANEL, 10, C_BORDER, 1, 6, 6))
	t.set_stylebox("hover", "PopupMenu", _sb(C_PANEL_HOVER, 6, Color(0, 0, 0, 0), 0, 8, 4))
	t.set_color("font_color", "PopupMenu", C_TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_constant("v_separation", "PopupMenu", 6)
	t.set_font("font", "PopupMenu", _font_body)

	# ── ProgressBar ──
	t.set_stylebox("background", "ProgressBar", _sb(C_PANEL_DEEP, 6, C_BORDER, 1, 0, 0))
	t.set_stylebox("fill", "ProgressBar", _sb(C_GOOD, 6, Color(0, 0, 0, 0), 0, 0, 0))
	t.set_color("font_color", "ProgressBar", C_TEXT)
	t.set_font_size("font_size", "ProgressBar", 11)
	_bar_var(t, "WaterBar", C_WATER)
	_bar_var(t, "StorageBar", C_ACCENT)
	_bar_var(t, "ScienceBar", C_SCIENCE)

	# ── Slider ──
	var track := _sb(C_PANEL_DEEP, 4, C_BORDER, 1, 0, 0); track.content_margin_top = 4; track.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", _sb(C_ACCENT, 4, Color(0, 0, 0, 0), 0, 0, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", _sb(C_ACCENT_HI, 4, Color(0, 0, 0, 0), 0, 0, 0))
	var knob: ImageTexture = _circle_tex(20, C_TEXT, C_ACCENT_LO)
	var knob_hi: ImageTexture = _circle_tex(20, Color.WHITE, C_ACCENT)
	t.set_icon("grabber", "HSlider", knob); t.set_icon("grabber_highlight", "HSlider", knob_hi)
	t.set_icon("grabber_disabled", "HSlider", knob)

	# ── Scrollbar (schmal) ──
	for sb_type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb_type, _sb(Color(0, 0, 0, 0.18), 4, Color(0, 0, 0, 0), 0, 0, 0))
		t.set_stylebox("grabber", sb_type, _sb(Color(C_TEXT_DIM, 0.8), 4, Color(0, 0, 0, 0), 0, 0, 0))
		t.set_stylebox("grabber_highlight", sb_type, _sb(C_TEXT_MUTED, 4, Color(0, 0, 0, 0), 0, 0, 0))
		t.set_stylebox("grabber_pressed", sb_type, _sb(C_ACCENT, 4, Color(0, 0, 0, 0), 0, 0, 0))
	t.set_constant("separation", "ScrollContainer", 4)

	# ── CheckButton/CheckBox: nur Schrift/Farbe ──
	for ct in ["CheckButton", "CheckBox"]:
		t.set_color("font_color", ct, C_TEXT)
		t.set_color("font_hover_color", ct, Color.WHITE)
		t.set_font("font", ct, _font_body)

	# ── RichTextLabel ──
	t.set_color("default_color", "RichTextLabel", C_TEXT)
	t.set_font("normal_font", "RichTextLabel", _font_body)
	t.set_font("bold_font", "RichTextLabel", _font_bold)
	t.set_font_size("normal_font_size", "RichTextLabel", FONT_BODY)

	# ── Trenner ──
	var line := StyleBoxLine.new(); line.color = Color(C_BORDER, 0.9); line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	t.set_constant("separation", "HSeparator", 12)

	# ── Tooltip ──
	t.set_stylebox("panel", "TooltipPanel", _sb(Color("120d09"), 8, C_ACCENT_LO, 1, 12, 8))
	t.set_color("font_color", "TooltipLabel", C_TEXT)
	t.set_font_size("font_size", "TooltipLabel", 13)

	# ── Container-Abstände (Raster) ──
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 8)
	return t

static func _label_var(t: Theme, name: String, font: Font, size: int, col: Color,
		outline: int = 0, outline_col: Color = Color(0, 0, 0, 1)) -> void:
	t.add_type(name); t.set_type_variation(name, "Label")
	t.set_font("font", name, font); t.set_font_size("font_size", name, size)
	t.set_color("font_color", name, col)
	if outline > 0:
		t.set_constant("outline_size", name, outline)
		t.set_color("font_outline_color", name, outline_col)

static func _bar_var(t: Theme, name: String, col: Color) -> void:
	t.add_type(name); t.set_type_variation(name, "ProgressBar")
	t.set_stylebox("fill", name, _sb(col, 6, Color(0, 0, 0, 0), 0, 0, 0))

static func _focus_box(radius: int) -> StyleBoxFlat:
	var f := _sb(Color(0, 0, 0, 0), radius, Color(C_ACCENT, 0.9), 2, 0, 0)
	f.draw_center = false
	return f

static func _button_states(t: Theme, type: String, normal: Color, hover: Color, pressed: Color,
		border: Color, _font: Color, _unused: int) -> void:
	t.set_stylebox("normal", type, _sb(normal, R_BTN, border, 1, 16, 8))
	t.set_stylebox("hover", type, _sb(hover, R_BTN, C_ACCENT_LO, 1, 16, 8))
	t.set_stylebox("pressed", type, _sb(pressed, R_BTN, C_ACCENT, 1, 16, 8))
	t.set_stylebox("hover_pressed", type, _sb(hover, R_BTN, C_ACCENT, 1, 16, 8))
	t.set_stylebox("disabled", type, _sb(Color(normal, 0.45), R_BTN, Color(border, 0.4), 1, 16, 8))

static func _primary_states(t: Theme, type: String, base: Color, hi: Color, lo: Color, text: Color) -> void:
	var make := func(bg: Color, shift_down: bool) -> StyleBoxFlat:
		var s := _sb(bg, R_BTN, lo, 0, 20, 10)
		s.border_width_bottom = 3 if not shift_down else 1
		s.content_margin_top = 10 if not shift_down else 12
		s.content_margin_bottom = 8 if not shift_down else 8
		return s
	t.set_stylebox("normal", type, make.call(base, false))
	t.set_stylebox("hover", type, make.call(hi, false))
	t.set_stylebox("pressed", type, make.call(lo.lightened(0.1), true))
	t.set_stylebox("hover_pressed", type, make.call(lo.lightened(0.1), true))
	t.set_stylebox("disabled", type, make.call(Color(base, 0.35), false))
	t.set_stylebox("focus", type, _focus_box(R_BTN))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, type, text)
	t.set_color("font_disabled_color", type, Color(text, 0.55))
	t.set_font_size("font_size", type, 17)
