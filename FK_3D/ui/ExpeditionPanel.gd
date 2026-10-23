## ExpeditionPanel.gd
extends PanelContainer

func _ready() -> void:
	hide()
	MenuManager.register(self)
	GameState.expedition_returned.connect(func(_r: Dictionary): if visible: _refresh())

func open() -> void:
	show()
	_refresh()

func _refresh() -> void:
	# Build UI on demand - no @onready needed
	for c in get_children(): c.queue_free()

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	add_child(vb)

	var hdr := HBoxContainer.new(); vb.add_child(hdr)
	var title := Label.new(); title.text = "Expeditionen"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.96,0.69,0.1))
	hdr.add_child(title)
	var close_btn := Button.new(); close_btn.text = "X"
	close_btn.pressed.connect(hide); hdr.add_child(close_btn)

	vb.add_child(_sep())

	if ExpeditionSys.active_expeditions.is_empty():
		var lbl := Label.new(); lbl.text = "Keine aktiven Expeditionen."
		lbl.add_theme_color_override("font_color", Color(0.6,0.6,0.6))
		vb.add_child(lbl)
	else:
		for expd in ExpeditionSys.active_expeditions:
			var row := HBoxContainer.new(); vb.add_child(row)
			var lbl := Label.new()
			var d_elapsed: float = float(expd.get("days_elapsed") if expd is Dictionary else expd.days_elapsed)
			var d_total:   float = float(expd.get("days_total")   if expd is Dictionary else expd.days_total)
			var ename: String    = str(expd.get("exp_name")       if expd is Dictionary else expd.exp_name)
			lbl.text = "%s  %.0f/%.0f Tage" % [ename, d_elapsed, d_total]
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(lbl)
			var bar := ProgressBar.new(); bar.value = d_elapsed/maxf(1.0,d_total)*100.0
			bar.custom_minimum_size = Vector2(80,0); row.add_child(bar)

	vb.add_child(_sep())

	var ctrl_row := HBoxContainer.new(); vb.add_child(ctrl_row)
	ctrl_row.add_child(_lbl("Frettchen:"))
	var fspin := SpinBox.new(); fspin.min_value=1; fspin.max_value=4; fspin.value=2
	ctrl_row.add_child(fspin)
	ctrl_row.add_child(_lbl("  Tage:"))
	var dspin := SpinBox.new(); dspin.min_value=3; dspin.max_value=12; dspin.value=5
	ctrl_row.add_child(dspin)

	var send_btn := Button.new()
	send_btn.text = "Expedition starten"
	send_btn.disabled = not ExpeditionSys.can_send()
	send_btn.pressed.connect(func():
		ExpeditionSys.send(int(fspin.value), float(dspin.value))
		_refresh()
	)
	vb.add_child(send_btn)

func _lbl(text: String) -> Label:
	var l := Label.new(); l.text = text; return l

func _sep() -> HSeparator:
	return HSeparator.new()
