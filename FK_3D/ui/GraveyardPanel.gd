## GraveyardPanel.gd
extends PanelContainer

func _ready() -> void:
	hide()
	MenuManager.register(self)
	GameState.ferret_died.connect(func(_f, _c): if visible: _refresh())

func open() -> void:
	show(); _refresh()

func _refresh() -> void:
	for c in get_children(): c.queue_free()
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation",6); add_child(vb)
	var hdr := HBoxContainer.new(); vb.add_child(hdr)
	var tl := Label.new(); tl.text = "Gedenkstätte – %d Frettchen" % PopMgr.dead_ferrets.size()
	tl.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tl.add_theme_font_size_override("font_size",15)
	tl.add_theme_color_override("font_color",Color(0.96,0.69,0.1)); hdr.add_child(tl)
	var cb := Button.new(); cb.text="X"; cb.pressed.connect(hide); hdr.add_child(cb)
	vb.add_child(HSeparator.new())
	var sc := ScrollContainer.new(); sc.custom_minimum_size=Vector2(0,200); vb.add_child(sc)
	var inner := VBoxContainer.new(); inner.size_flags_horizontal=Control.SIZE_EXPAND_FILL; sc.add_child(inner)
	for entry in PopMgr.dead_ferrets:
		var ed: Dictionary = entry as Dictionary
		# Feature (v11.9, Legendäre Frettchen): prominenterer, ausführlicherer
		# Eintrag statt nur Name/Tag/Ursache - siehe PopulationManager._kill_ferret().
		if bool(ed.get("is_legendary", false)):
			var leg_lbl := Label.new()
			leg_lbl.text = "👑 %s – %s" % [str(ed.get("name","")), str(ed.get("legendary_title",""))]
			leg_lbl.add_theme_font_size_override("font_size", 12)
			leg_lbl.add_theme_color_override("font_color", Color(0.98, 0.82, 0.25))
			inner.add_child(leg_lbl)
			var leg_sub := Label.new()
			leg_sub.text = "     War %d Tage im selben Beruf tätig – gestorben an Tag %d (%s), Alter %d Tage." % [
				int(ed.get("career_days", 0)), int(ed.get("day", 0)), str(ed.get("cause","")), int(ed.get("age", 0))
			]
			leg_sub.add_theme_font_size_override("font_size", 10)
			leg_sub.add_theme_color_override("font_color", Color(0.75, 0.7, 0.55))
			inner.add_child(leg_sub)
			continue
		var lbl := Label.new()
		lbl.text = "  %s  –  Tag %d  –  %s" % [str(ed.get("name","")), int(ed.get("day",0)), str(ed.get("cause",""))]
		lbl.add_theme_font_size_override("font_size",12); inner.add_child(lbl)
	if PopMgr.dead_ferrets.is_empty():
		var empty := Label.new(); empty.text = "Noch keine Verstorbenen."
		empty.add_theme_color_override("font_color",Color(0.5,0.5,0.5)); inner.add_child(empty)
