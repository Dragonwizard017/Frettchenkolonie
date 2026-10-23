## AchievementPanel.gd
## Feature (v11.8, Achievement-System). Baut seine UI komplett dynamisch in
## _refresh() selbst auf, analog zu GraveyardPanel.gd/ExpeditionPanel.gd -
## Main.gd erzeugt nur den leeren PanelContainer mit diesem Skript.
extends PanelContainer

func _ready() -> void:
	hide()
	MenuManager.register(self)
	AchievementSys.achievement_unlocked_toast.connect(func(_id): if visible: _refresh())

func open() -> void:
	show(); _refresh()

func _refresh() -> void:
	for c in get_children(): c.queue_free()
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 6); add_child(vb)

	var hdr := HBoxContainer.new(); vb.add_child(hdr)
	var tl := Label.new()
	tl.text = "Erfolge – %d/%d" % [AchievementSys.get_progress_count(), AchievementSys.get_total_count()]
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.add_theme_font_size_override("font_size", 15)
	tl.add_theme_color_override("font_color", Color(0.96, 0.78, 0.25))
	hdr.add_child(tl)
	var cb := Button.new(); cb.text = "X"; cb.pressed.connect(hide); hdr.add_child(cb)
	vb.add_child(HSeparator.new())

	var sc := ScrollContainer.new(); sc.custom_minimum_size = Vector2(0, 320); vb.add_child(sc)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 10)
	sc.add_child(inner)

	for cat in AchievementSys.CATEGORY_ORDER:
		var cd: Dictionary = AchievementSys.CATEGORIES[cat]
		var ids: Array = AchievementSys.get_achievements_by_category(cat)
		var done: int = 0
		for aid in ids:
			if AchievementSys.is_unlocked(aid): done += 1

		var cat_lbl := Label.new()
		cat_lbl.text = "%s %s (%d/%d)" % [str(cd.get("icon", "")), str(cd.get("name", cat)), done, ids.size()]
		cat_lbl.add_theme_font_size_override("font_size", 13)
		cat_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
		inner.add_child(cat_lbl)

		for aid in ids:
			var ad: Dictionary = AchievementSys.ACHIEVEMENTS[aid]
			var unlocked: bool = AchievementSys.is_unlocked(aid)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			inner.add_child(row)

			var icon_lbl := Label.new()
			icon_lbl.text = str(ad.get("icon", "🏆")) if unlocked else "🔒"
			icon_lbl.custom_minimum_size = Vector2(28, 0)
			icon_lbl.add_theme_font_size_override("font_size", 16)
			row.add_child(icon_lbl)

			var text_vb := VBoxContainer.new()
			text_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(text_vb)

			var name_lbl := Label.new()
			name_lbl.text = str(ad.get("name", aid))
			name_lbl.add_theme_font_size_override("font_size", 12)
			name_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4) if unlocked else Color(0.55, 0.55, 0.55))
			text_vb.add_child(name_lbl)

			var desc_lbl := Label.new()
			desc_lbl.text = str(ad.get("desc", ""))
			desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			desc_lbl.add_theme_font_size_override("font_size", 10)
			desc_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6) if unlocked else Color(0.42, 0.42, 0.42))
			text_vb.add_child(desc_lbl)
