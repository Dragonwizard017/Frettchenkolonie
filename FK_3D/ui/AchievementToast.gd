## AchievementToast.gd
## Feature (v11.8, Achievement-System): auffälligerer Popup-Effekt für
## freigeschaltete Erfolge, zusätzlich zur unauffälligen Notification-Zeile
## (siehe AchievementSystem._unlock()). Baut strukturell auf NotificationLayer.gd
## auf, aber grösser/prominenter, mittig oben, mit Icon + Name + Fade-In/-Out.
extends Control

const DISPLAY_DURATION := 3.0

func _ready() -> void:
	AchievementSys.achievement_unlocked_toast.connect(_show_toast)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _show_toast(id: String) -> void:
	if not AchievementSys.ACHIEVEMENTS.has(id): return
	var ad: Dictionary = AchievementSys.ACHIEVEMENTS[id]

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.12, 0.02, 0.95)
	sb.border_color = Color(0.96, 0.78, 0.25)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 18; sb.content_margin_right = 18
	sb.content_margin_top = 10;  sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)

	var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 10); panel.add_child(hb)
	var icon_lbl := Label.new()
	icon_lbl.text = str(ad.get("icon", "🏆"))
	icon_lbl.add_theme_font_size_override("font_size", 26)
	hb.add_child(icon_lbl)

	var vb := VBoxContainer.new(); hb.add_child(vb)
	var top_lbl := Label.new()
	top_lbl.text = "Erfolg freigeschaltet!"
	top_lbl.add_theme_font_size_override("font_size", 11)
	top_lbl.add_theme_color_override("font_color", Color(0.8, 0.7, 0.5))
	vb.add_child(top_lbl)
	var name_lbl := Label.new()
	name_lbl.text = str(ad.get("name", id))
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(0.98, 0.85, 0.35))
	vb.add_child(name_lbl)

	add_child(panel)
	# Zentriert, etwas oberhalb der Bildschirmmitte - deutlich sichtbar, aber
	# ohne die normale Notification-Zeile darunter zu verdecken (siehe
	# NotificationLayer.gd, das ab y=80 nach unten wächst).
	panel.modulate.a = 0.0
	await get_tree().process_frame
	panel.position = Vector2(get_viewport_rect().size.x * 0.5 - panel.size.x * 0.5, 130)

	var tw_in := create_tween()
	tw_in.tween_property(panel, "modulate:a", 1.0, 0.3)
	tw_in.parallel().tween_property(panel, "position:y", 150, 0.3)

	# Bug-Fix (v11.17): Timer als Kind-Node von "panel" statt eines vom
	# SceneTree unabhängigen get_tree().create_timer() - siehe
	# NotificationLayer.gd für die ausführliche Begründung ("Lambda
	# capture at index 0 was freed"-Fehlerklasse).
	var t := Timer.new()
	t.wait_time = DISPLAY_DURATION
	t.one_shot = true
	panel.add_child(t)
	t.timeout.connect(func():
		var tw_out := create_tween()
		tw_out.tween_property(panel, "modulate:a", 0.0, 0.5)
		tw_out.tween_callback(panel.queue_free)
	)
	t.start()
