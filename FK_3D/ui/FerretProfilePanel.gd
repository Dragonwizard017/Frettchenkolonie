## FerretProfilePanel.gd
## Feature (v11.9, Frettchen-Klick-Interaktion): öffnet sich beim Anklicken
## eines Frettchens in der 3D-Welt (siehe WorldRenderer3D.find_ferret_at_screen_pos()
## + GameController._on_ferret_selected()).
##
## BUGFIX (v11.10): der X-Schließen-Button ließ sich nicht zuverlässig klicken.
## Ursache: die alte Version hat in _process() JEDEN Frame die komplette UI
## (inkl. X-Button) mit queue_free()+Neubau ersetzt. Ein Maus-Klick besteht
## aus "Drücken" + "Loslassen" über mehrere Frames hinweg - da Godots Button
## den Druck-Zustand am KONKRETEN Node-Objekt verfolgt, wurde zwischen Drücken
## und Loslassen bereits ein neuer, anderer Button an dieselbe Stelle gesetzt,
## der vom "Loslassen" nichts wusste → "pressed" feuerte nie zuverlässig.
## Fix: der statische Rahmen (Panel-Stil, Kopfzeile samt X-Button) wird nur
## EINMAL beim Öffnen (show_ferret()) bzw. bei einem Legendär-Statuswechsel
## gebaut. _process() aktualisiert danach nur noch die WERTE der bereits
## bestehenden Labels/Balken (siehe _update_dynamic()), OHNE Nodes zu ersetzen.
extends PanelContainer

var _ferret: FerretEntity = null
var _built_legendary_state: bool = false  # für Neuaufbau bei Legendär-Wechsel

const NORMAL_STYLE_COLOR := Color(0.13, 0.13, 0.15, 0.94)
const NORMAL_BORDER := Color(0.35, 0.35, 0.4)
const LEGENDARY_STYLE_COLOR := Color(0.20, 0.16, 0.03, 0.96)
const LEGENDARY_BORDER := Color(0.98, 0.82, 0.25)

# Referenzen auf die dynamischen Teile, damit _update_dynamic() sie
# aktualisieren kann, OHNE die Nodes (insbesondere den X-Button) neu zu bauen.
var _health_bar: ProgressBar
var _food_bar: ProgressBar
var _water_bar: ProgressBar
var _happiness_bar: ProgressBar
var _age_lbl: Label
var _spec_lbl: Label
var _progress_bar: ProgressBar

func _ready() -> void:
	hide()
	MenuManager.register(self)
	GameState.ferret_died.connect(_on_any_ferret_died)

func show_ferret(f) -> void:
	_ferret = f as FerretEntity
	_built_legendary_state = _ferret.is_legendary
	_build_static_shell()
	show()

func _process(_dt: float) -> void:
	if not visible or _ferret == null: return
	# Ein Legendär-Wechsel WÄHREND das Panel offen ist, ändert Rahmenfarbe/
	# Titel/Accessoires - das rechtfertigt einen (seltenen) Neuaufbau.
	if _ferret.is_legendary != _built_legendary_state:
		_built_legendary_state = _ferret.is_legendary
		_build_static_shell()
	_update_dynamic()

func _on_any_ferret_died(f, _cause: String) -> void:
	if f == _ferret: hide()

func _build_static_shell() -> void:
	if _ferret == null: return
	for c in get_children(): c.queue_free()

	var sb := StyleBoxFlat.new()
	sb.bg_color = LEGENDARY_STYLE_COLOR if _ferret.is_legendary else NORMAL_STYLE_COLOR
	sb.border_color = LEGENDARY_BORDER if _ferret.is_legendary else NORMAL_BORDER
	sb.set_border_width_all(3 if _ferret.is_legendary else 1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14; sb.content_margin_right = 14
	sb.content_margin_top = 10;  sb.content_margin_bottom = 10
	add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 6); add_child(vb)

	var hdr := HBoxContainer.new(); vb.add_child(hdr)
	var tl := Label.new()
	tl.text = ("👑 " if _ferret.is_legendary else "") + _ferret.ferret_name
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.add_theme_font_size_override("font_size", 16)
	tl.add_theme_color_override("font_color", LEGENDARY_BORDER if _ferret.is_legendary else Color(0.9, 0.9, 0.92))
	hdr.add_child(tl)
	var cb := Button.new(); cb.text = "X"; cb.custom_minimum_size = Vector2(28, 0)
	cb.pressed.connect(hide)
	hdr.add_child(cb)

	if _ferret.is_legendary and _ferret.legendary_title != "":
		var title_lbl := Label.new()
		title_lbl.text = _ferret.legendary_title
		title_lbl.add_theme_font_size_override("font_size", 12)
		title_lbl.add_theme_color_override("font_color", LEGENDARY_BORDER)
		vb.add_child(title_lbl)

	vb.add_child(HSeparator.new())

	var trait_data: Dictionary = _ferret.get_trait_data()
	var trait_row := HBoxContainer.new(); trait_row.add_theme_constant_override("separation", 6); vb.add_child(trait_row)
	var trait_icon := Label.new(); trait_icon.text = str(trait_data.get("icon", "❔")); trait_row.add_child(trait_icon)
	var trait_lbl := Label.new()
	trait_lbl.text = str(trait_data.get("name", "Unbekannt")) + " – " + str(trait_data.get("desc", ""))
	trait_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trait_lbl.add_theme_font_size_override("font_size", 10)
	trait_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trait_row.add_child(trait_lbl)

	_spec_lbl = Label.new()
	_spec_lbl.add_theme_font_size_override("font_size", 11)
	vb.add_child(_spec_lbl)

	_age_lbl = Label.new()
	_age_lbl.add_theme_font_size_override("font_size", 11)
	vb.add_child(_age_lbl)

	_health_bar = _add_bar(vb, "Gesundheit", Color(0.8, 0.25, 0.25))
	_food_bar = _add_bar(vb, "Nahrung", Color(0.75, 0.55, 0.2))
	_water_bar = _add_bar(vb, "Wasser", Color(0.25, 0.55, 0.85))
	_happiness_bar = _add_bar(vb, "Glück", Color(0.35, 0.75, 0.35))

	if _ferret.is_legendary:
		vb.add_child(HSeparator.new())
		var acc_hdr := Label.new(); acc_hdr.text = "Accessoires"
		acc_hdr.add_theme_font_size_override("font_size", 11)
		acc_hdr.add_theme_color_override("font_color", LEGENDARY_BORDER)
		vb.add_child(acc_hdr)
		if _ferret.legendary_accessories.is_empty():
			var none_lbl := Label.new(); none_lbl.text = "– keine –"
			none_lbl.add_theme_font_size_override("font_size", 10)
			vb.add_child(none_lbl)
		for aid in _ferret.legendary_accessories:
			var ad: Dictionary = FerretAccessories.get_accessory(str(aid))
			var acc_lbl := Label.new()
			acc_lbl.text = "• " + str(ad.get("name", aid))
			acc_lbl.add_theme_font_size_override("font_size", 10)
			vb.add_child(acc_lbl)
		_progress_bar = null
	else:
		vb.add_child(HSeparator.new())
		var prog_lbl := Label.new(); prog_lbl.text = "Karriere-Fortschritt"
		prog_lbl.add_theme_font_size_override("font_size", 10)
		prog_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		vb.add_child(prog_lbl)
		_progress_bar = ProgressBar.new()
		_progress_bar.max_value = FerretEntity.LEGENDARY_THRESHOLD_DAYS
		_progress_bar.custom_minimum_size = Vector2(0, 10)
		_progress_bar.show_percentage = false
		vb.add_child(_progress_bar)

	# Feature (v11.10, Dev Mode): im Entwickler-Modus zusätzlicher Button,
	# um DIESES Frettchen direkt legendär zu machen (Test-Werkzeug, siehe
	# DevMode.gd) - erscheint nur, wenn Dev Mode aktiv und Frettchen noch
	# nicht legendär ist.
	if DevMode.enabled and not _ferret.is_legendary:
		vb.add_child(HSeparator.new())
		var dev_btn := Button.new()
		dev_btn.text = "🛠️ [Dev] Sofort legendär machen"
		var fe_ref: FerretEntity = _ferret
		dev_btn.pressed.connect(func():
			fe_ref.is_legendary = true
			fe_ref.legendary_title = "%s-Legende" % (fe_ref.specialization if fe_ref.specialization != "" else "Kolonie")
			fe_ref.legendary_accessories = FerretAccessories.pick_random_set()
			GameState.ferret_became_legendary.emit(fe_ref)
		)
		vb.add_child(dev_btn)

	_update_dynamic()

func _update_dynamic() -> void:
	if _ferret == null: return
	_spec_lbl.text = "Beruf: %s" % (_ferret.specialization if _ferret.specialization != "" else "Ungelernt")
	_age_lbl.text = "Alter: %d Tage" % int(_ferret.age_days)
	_health_bar.value = clampf(_ferret.health, 0.0, 100.0)
	_food_bar.value = clampf(float(_ferret.needs.get("food", 0.0)), 0.0, 100.0)
	_water_bar.value = clampf(float(_ferret.needs.get("water", 0.0)), 0.0, 100.0)
	_happiness_bar.value = clampf(float(_ferret.needs.get("happiness", 0.0)), 0.0, 100.0)
	if _progress_bar != null:
		_progress_bar.value = _ferret.career_days

func _add_bar(vb: VBoxContainer, label: String, color: Color) -> ProgressBar:
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 6); vb.add_child(row)
	var lbl := Label.new(); lbl.text = label; lbl.custom_minimum_size = Vector2(64, 0)
	lbl.add_theme_font_size_override("font_size", 10)
	row.add_child(lbl)
	var pb := ProgressBar.new()
	pb.min_value = 0; pb.max_value = 100; pb.value = 0
	pb.custom_minimum_size = Vector2(140, 10); pb.show_percentage = false
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fill_sb := StyleBoxFlat.new(); fill_sb.bg_color = color; fill_sb.set_corner_radius_all(3)
	pb.add_theme_stylebox_override("fill", fill_sb)
	row.add_child(pb)
	return pb
