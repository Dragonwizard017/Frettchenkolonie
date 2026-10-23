## LegendaryToast.gd
## Feature (v11.9, Legendäre Frettchen): auffälliges Popup, sobald ein
## Frettchen legendär wird (siehe GameController._on_ferret_became_legendary()
## bzw. GameState.ferret_became_legendary). Ein Klick auf das Popup öffnet
## direkt das Profil des betroffenen Frettchens (emittiert ferret_selected,
## das GameController bereits für normale Frettchen-Klicks verarbeitet -
## siehe _on_ferret_selected()).
## Baut strukturell auf AchievementToast.gd auf, aber klickbar (Button statt
## reinem Label-Panel) und golden statt neutral eingefärbt.
extends Control

const DISPLAY_DURATION := 5.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_toast(f) -> void:
	var fe: FerretEntity = f as FerretEntity
	if fe == null: return

	var btn := Button.new()
	btn.flat = true
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.20, 0.15, 0.02, 0.96)
	sb.border_color = Color(0.98, 0.82, 0.25)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 20; sb.content_margin_right = 20
	sb.content_margin_top = 12;  sb.content_margin_bottom = 12
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)

	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 2)
	btn.add_child(vb)

	var top_lbl := Label.new()
	top_lbl.text = "👑 Ein Frettchen wird legendär!"
	top_lbl.add_theme_font_size_override("font_size", 12)
	top_lbl.add_theme_color_override("font_color", Color(0.85, 0.72, 0.4))
	top_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(top_lbl)

	var name_lbl := Label.new()
	name_lbl.text = fe.ferret_name
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", Color(0.98, 0.85, 0.35))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(name_lbl)

	if fe.legendary_title != "":
		var title_lbl := Label.new()
		title_lbl.text = fe.legendary_title
		title_lbl.add_theme_font_size_override("font_size", 11)
		title_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(title_lbl)

	var hint_lbl := Label.new()
	hint_lbl.text = "Klicken für Profil"
	hint_lbl.add_theme_font_size_override("font_size", 9)
	hint_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.55))
	hint_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(hint_lbl)

	add_child(btn)
	btn.pressed.connect(func():
		GameState.ferret_selected.emit(fe)
		if is_instance_valid(btn): btn.queue_free()
	)

	btn.modulate.a = 0.0
	await get_tree().process_frame
	btn.position = Vector2(get_viewport_rect().size.x * 0.5 - btn.size.x * 0.5, 130)

	var tw_in := create_tween()
	tw_in.tween_property(btn, "modulate:a", 1.0, 0.3)
	tw_in.parallel().tween_property(btn, "position:y", 150, 0.3)

	# Bug-Fix (v11.17): Timer als Kind-Node von "btn" statt eines vom
	# SceneTree unabhängigen get_tree().create_timer() - siehe
	# NotificationLayer.gd für die ausführliche Begründung ("Lambda
	# capture at index 0 was freed"-Fehlerklasse). Hier besonders relevant:
	# ein Klick auf den Toast (siehe pressed-Handler oben) entfernt "btn"
	# VORZEITIG, bevor die 5 Sekunden um sind - der alte externe Timer hätte
	# dann garantiert auf ein bereits freigegebenes "btn" gezeigt.
	var t := Timer.new()
	t.wait_time = DISPLAY_DURATION
	t.one_shot = true
	btn.add_child(t)
	t.timeout.connect(func():
		var tw_out := create_tween()
		tw_out.tween_property(btn, "modulate:a", 0.0, 0.5)
		tw_out.tween_callback(btn.queue_free)
	)
	t.start()
