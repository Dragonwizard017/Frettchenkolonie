## NotificationLayer.gd
## Zeigt temporäre Benachrichtigungen (entspricht notify() im HTML).
extends Control

const NOTIF_DURATION := 3.5
const MAX_NOTIFS := 5

var _notifs: Array = []

func _ready() -> void:
	GameState.notification_requested.connect(show_notification)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_notification(msg: String, color: Color = Color(0.18, 0.38, 0.18, 0.92)) -> void:
	# Bug-Fix (v11.17): "Lambda capture at index 0 was freed" - wenn viele
	# Benachrichtigungen kurz hintereinander auftreten (z.B. beim Testwelt-
	# Aufbau: mehrere GameState.notify()-Aufrufe + Achievement-Freischaltungen
	# durch die vielen platzierten Gebäude), konnte MAX_NOTIFS überschritten
	# werden - das älteste Panel wurde dann per queue_free() entfernt, während
	# sein eigener, weiter unten erzeugter Timer (get_tree().create_timer(),
	# unabhängig vom Panel-Lebenszyklus) noch aussteht. Feürte dieser externe
	# Timer später, zeigte seine Lambda (die "panel" von AUSSEN einfängt)
	# genau diesen Fehler - Godot prüft freigegebene Lambda-Captures auf
	# Engine-Ebene BEVOR der Funktionskörper (inkl. is_instance_valid()-
	# Checks!) überhaupt läuft, ein interner is_instance_valid()-Check
	# hätte das NICHT verhindert.
	if _notifs.size() >= MAX_NOTIFS:
		var oldest = _notifs.pop_front()
		if is_instance_valid(oldest): oldest.queue_free()

	# v15.0: einheitlicher dunkler Toast; die Meldungsfarbe wird nur noch als
	# Akzentkante links verwendet (vorher: knallige Vollfarb-Pillen).
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UITheme.C_PANEL, 0.96)
	sb.set_corner_radius_all(10)
	sb.border_width_left = 5
	sb.border_color = Color(color.r, color.g, color.b, 1.0).lightened(0.28)
	sb.content_margin_left = 16; sb.content_margin_right = 16
	sb.content_margin_top = 9;   sb.content_margin_bottom = 9
	sb.shadow_color = Color(0, 0, 0, 0.4); sb.shadow_size = 8; sb.shadow_offset = Vector2(0, 2)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var lbl := Label.new()
	lbl.text = msg
	lbl.add_theme_font_size_override("font_size", 15)
	panel.add_child(lbl)

	add_child(panel)
	_notifs.append(panel)
	_reposition()

	# Bug-Fix (v11.17): Timer als KIND-NODE von "panel" statt eines vom
	# SceneTree unabhängigen get_tree().create_timer(). Wird "panel" (z.B.
	# durch die MAX_NOTIFS-Aufräumlogik oben) vorzeitig freigegeben, gibt
	# Godot automatisch auch alle Kind-Nodes frei - dieser Timer kann dadurch
	# NIE mehr auf ein bereits freigegebenes "panel" zeigen bzw. überhaupt
	# noch feuern. Das macht den o.g. Fehler strukturell unmöglich, statt
	# ihn nur abzufangen.
	var t := Timer.new()
	t.wait_time = NOTIF_DURATION
	t.one_shot = true
	panel.add_child(t)
	t.timeout.connect(func():
		_notifs.erase(panel)
		var fade_out_tw := create_tween()
		fade_out_tw.tween_property(panel, "modulate:a", 0.0, 0.4)
		fade_out_tw.tween_callback(panel.queue_free)
		_reposition()
	)
	t.start()

	# Einblend-Animation
	panel.modulate.a = 0.0
	var fade_in_tw := create_tween()
	fade_in_tw.tween_property(panel, "modulate:a", 1.0, 0.25)

func _reposition() -> void:
	var y := 46.0
	for n in _notifs:
		if is_instance_valid(n):
			n.position = Vector2(get_viewport_rect().size.x * 0.5 - n.size.x * 0.5, y)
			y += n.size.y + 8.0
