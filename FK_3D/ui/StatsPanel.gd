## StatsPanel.gd
extends PanelContainer

func _ready() -> void:
	hide()
	MenuManager.register(self)

func open() -> void:
	show(); _refresh()

func _refresh() -> void:
	for c in get_children(): c.queue_free()
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation",6); add_child(vb)
	var hdr := HBoxContainer.new(); vb.add_child(hdr)
	var tl := Label.new(); tl.text="Statistiken"
	tl.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tl.add_theme_font_size_override("font_size",16)
	tl.add_theme_color_override("font_color",Color(0.96,0.69,0.1)); hdr.add_child(tl)
	var cb := Button.new(); cb.text="X"; cb.pressed.connect(hide); hdr.add_child(cb)
	vb.add_child(HSeparator.new())
	var stats: Array = [
		["Frettchen", str(PopMgr.get_count())],
		["Glück", "%.0f%%" % PopMgr.total_happiness],
		["Epoche", str(TechTreeSys.get_epoch())],
		["Tag", str(DayNight.day_count+1)],
		["Saison", SeasonSys.get_season_name()],
		["Gebäude", str(BuildingSys.buildings.size())],
		["Lager", "%d/%d" % [int(ResourceSys.get_total_stored()), int(ResourceSys.storage_capacity)]],
		["Wasser", "%d/%d" % [int(ResourceSys.water), int(ResourceSys.water_capacity)]],
		["Verstorben", str(PopMgr.dead_ferrets.size())],
	]
	for stat in stats:
		var sa: Array = stat as Array
		var row := HBoxContainer.new(); vb.add_child(row)
		var key := Label.new(); key.text=str(sa[0]); key.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(key)
		var val := Label.new(); val.text=str(sa[1])
		val.add_theme_color_override("font_color",Color(0.96,0.69,0.1)); row.add_child(val)
