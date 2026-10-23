## BuildingInfo.gd
extends PanelContainer

var _building: BuildingEntity = null
var _game_ctrl: Node = null
var _title_lbl: Label = null
var _status_lbl: Label = null
var _workers_lbl: Label = null
var _worker_minus_btn: Button = null
var _worker_plus_btn: Button = null
var _progress_bar: ProgressBar = null
var _upgrade_btn: Button = null
var _sell_btn: Button = null
var _rebuild_btn: Button = null
var _priority_slider: HSlider = null
var _priority_label: Label = null
var _desc_label: Label = null
var _filter_row: HBoxContainer = null
var _filter_option: OptionButton = null
var _district_label: Label = null

func _ready() -> void:
	hide()
	MenuManager.register(self)
	_title_lbl      = get_node_or_null("VBox/TitleRow/TitleLabel")
	_status_lbl     = get_node_or_null("VBox/StatusLabel")
	_workers_lbl    = get_node_or_null("VBox/WorkerRow/WorkersLabel")
	_worker_minus_btn = get_node_or_null("VBox/WorkerRow/WorkerMinusBtn")
	_worker_plus_btn  = get_node_or_null("VBox/WorkerRow/WorkerPlusBtn")
	_progress_bar   = get_node_or_null("VBox/ProgressBar")
	_upgrade_btn    = get_node_or_null("VBox/Buttons/UpgradeBtn")
	_sell_btn       = get_node_or_null("VBox/Buttons/SellBtn")
	_rebuild_btn    = get_node_or_null("VBox/RebuildRow/RebuildBtn")
	_priority_slider = get_node_or_null("VBox/PriorityRow/PrioritySlider")
	_priority_label = get_node_or_null("VBox/PriorityRow/PriorityLabel")
	_desc_label     = get_node_or_null("VBox/DescLabel")
	_filter_row     = get_node_or_null("VBox/FilterRow")
	_filter_option  = get_node_or_null("VBox/FilterRow/FilterOption")
	_district_label = get_node_or_null("VBox/DistrictLabel")
	var close: Button = get_node_or_null("VBox/TitleRow/CloseBtn")
	if close: close.pressed.connect(func(): GameState.building_deselected.emit())
	if _sell_btn:    _sell_btn.pressed.connect(_on_sell)
	if _upgrade_btn: _upgrade_btn.pressed.connect(_on_upgrade)
	if _rebuild_btn: _rebuild_btn.pressed.connect(_on_rebuild)
	if _priority_slider: _priority_slider.value_changed.connect(func(v): if _building: _building.work_priority = int(v))
	if _worker_minus_btn: _worker_minus_btn.pressed.connect(_on_worker_minus)
	if _worker_plus_btn:  _worker_plus_btn.pressed.connect(_on_worker_plus)
	if _filter_option: _filter_option.item_selected.connect(_on_filter_selected)

func set_game_controller(gc: Node) -> void:
	_game_ctrl = gc

func show_building(b: BuildingEntity, gc: Node) -> void:
	_building = b; _game_ctrl = gc; show(); _refresh()

func _process(_dt: float) -> void:
	if visible and _building != null: _refresh()

func _refresh() -> void:
	if _building == null: return
	if _title_lbl: _title_lbl.text = "%s %s (Stufe %d)" % [_building.icon, _building.name, _building.level]
	if _status_lbl:
		if _building.is_under_construction:
			# Feature (v11.0): solange noch Baumaterial fehlt, gibt es noch
			# gar keinen "echten" Baufortschritt (siehe GameController.
			# _process_construction()) - die Status-Zeile zeigt das jetzt
			# klar an, statt einfach bei 0% zu verharren.
			var verb: String = "Wird umgebaut" if _building.is_rebuild else "Im Bau"
			if not _building.is_fully_supplied():
				_status_lbl.text = "Wartet auf Material: %s" % _missing_str(_building)
			else:
				_status_lbl.text = "%s... %d%%" % [verb, int(_building.construction_progress / maxf(1.0, _building.construction_work_needed) * 100.0)]
		elif _building.btype == "FARMHOUSE":
			# Feature (v14.5, Timberborn-Feld-System): zeigt Lagerfüllstand
			# UND Feld-Aufschlüsselung in einem - macht sofort sichtbar, ob
			# gerade z.B. "keine Felder zugewiesen" oder "alle wachsen noch"
			# der Grund für Stillstand ist, statt dass das wie ein Bug wirkt.
			var stored2: int = int(_building.get_local_storage_total())
			var cap2: int = int(_building.local_storage_capacity)
			var status3: String = "Aktiv" if _building.is_active else "Inaktiv"
			var st: Dictionary = FarmSys.get_district_stats(int(_building.district_id))
			var fstr: String = "keine Felder zugewiesen ⚠️" if int(st.get("total",0)) == 0 \
				else "%d Felder (🟫%d 🌱%d 🌾%d)" % [int(st.get("total",0)), int(st.get("empty",0)), int(st.get("growing",0)), int(st.get("ready",0))]
			_status_lbl.text = "%s | Lager: %d/%d | %s" % [status3, stored2, cap2, fstr]
		elif _building.local_storage_capacity > 0.0:
			# Feature (v11.0): Lager-Füllstand des Gebäudes selbst (siehe
			# Anfrage: "muss irgendwie am Herstellungsgebäude angezeigt
			# werden, weil die Resourcen dort gelagert werden").
			var stored: int = int(_building.get_local_storage_total())
			var cap: int = int(_building.local_storage_capacity)
			var status: String = "Aktiv" if _building.is_active else "Inaktiv"
			_status_lbl.text = "%s | Lager: %d/%d" % [status, stored, cap]
		elif _building.btype == "HOUSING":
			# Feature (v11.1, Betten): zeigt belegte/freie Schlafplätze direkt
			# am Wohnhaus an.
			_status_lbl.text = "🛏️ Betten: %d/%d belegt" % [_building.residents.size(), _building.max_residents]
		elif _building.collects_resource == "WATER":
			# Feature (v13.7, Fix zum gemeldeten Wasser-Bug): zeigt jetzt direkt
			# an, wie gut die Wasserversorgung am Standort ist, statt dass die
			# Ursache für "0 Wasser trotz Arbeiter" unsichtbar bleibt.
			var status2: String = "Aktiv" if _building.is_active else "Inaktiv"
			# v14.6: gleiche Basis wie die Produktion (BuildingEntity._collect)
			var lvl: float = minf(1.0, WaterSys.get_water_volume_near(_building.tile_x, _building.tile_y, _building.collection_radius) / 3.0)
			var hint: String = ""
			if lvl < 0.15:
				hint = "  ⚠️ Kaum Wasser in der Nähe - näher an See/Fluss bauen oder Damm errichten hilft!"
			elif lvl < 0.5:
				hint = "  💧 Fördermenge mittelmässig (weiter weg vom Wasser)"
			_status_lbl.text = "%s | Wasserstand: %d/%d%s" % [status2, int(ResourceSys.water), int(ResourceSys.water_capacity), hint]
		else:
			_status_lbl.text = "Aktiv" if _building.is_active else "Inaktiv"
	if _workers_lbl:
		_workers_lbl.text = "Arbeiter: %d/%d" % [_building.assigned_workers.size(), _building.get_effective_worker_cap()] if _building.max_workers > 0 else ""
	if _worker_minus_btn or _worker_plus_btn:
		var show_controls: bool = _building.max_workers > 0 and not _building.is_under_construction
		if _worker_minus_btn:
			_worker_minus_btn.visible = show_controls
			_worker_minus_btn.disabled = _building.get_effective_worker_cap() <= 0
		if _worker_plus_btn:
			_worker_plus_btn.visible = show_controls
			_worker_plus_btn.disabled = _building.get_effective_worker_cap() >= _building.max_workers
	if _progress_bar:
		if _building.is_under_construction:
			_progress_bar.value = _building.construction_progress / maxf(1.0, _building.construction_work_needed) * 100.0; _progress_bar.show()
		elif _building.produces != "" or not _building.recipes.is_empty():
			var ct: float = float(BuildingData.PRODUCTION_CHAINS.get(_building.produces,{}).get("time",5.0))
			_progress_bar.value = _building.production_progress / ct * 100.0; _progress_bar.show()
		else: _progress_bar.hide()
	if _upgrade_btn:
		var uc: Dictionary = _building.get_upgrade_costs()
		_upgrade_btn.text = "Max. Stufe" if uc.is_empty() else "Upgrade (%s)" % _costs_str(uc)
		_upgrade_btn.disabled = uc.is_empty() or not ResourceSys.can_afford(uc)
	if _sell_btn:
		# Feature (v11.0): Erstattung basiert jetzt auf tatsächlich
		# angeliefertem Material (delivered_resources), nicht mehr auf den
		# vollen Baukosten - siehe BuildingSystem.sell().
		var rd: Dictionary = {}
		var src: Dictionary = _building.delivered_resources if _building.is_under_construction else _building.costs
		for r in src: rd[r] = int(float(src[r]) * 0.7)
		_sell_btn.text = "Verkaufen (%s)" % _costs_str(rd)
	if _rebuild_btn:
		# Feature (Tech Tree): "Umbauen"-Schaltfläche - nur sichtbar, wenn es
		# für diesen Gebäudetyp überhaupt ein Umbau-Ziel gibt UND der dafür
		# nötige Tech-Knoten bereits freigeschaltet wurde (siehe
		# BuildingData.REBUILDS, TechTreeSys.can_rebuild()). Während eines
		# bereits laufenden Umbaus (oder eines Neubaus) bleibt sie versteckt.
		var rd2: Dictionary = BuildingData.REBUILDS.get(_building.id, {})
		var show_rebuild: bool = not rd2.is_empty() and not _building.is_under_construction \
			and TechTreeSys.can_rebuild(_building.id)
		_rebuild_btn.visible = show_rebuild
		if show_rebuild:
			var rcosts: Dictionary = rd2.get("costs", {}) as Dictionary
			_rebuild_btn.text = "Umbauen zu %s (%s)" % [str(rd2.get("name","")), _costs_str(rcosts)]
			_rebuild_btn.disabled = not ResourceSys.can_afford(rcosts)
	if _priority_slider and _building.max_workers > 0:
		_priority_slider.show(); if _priority_label: _priority_label.show()
		_priority_slider.set_value_no_signal(float(_building.work_priority))
		if _priority_label: _priority_label.text = "Priorität: %d" % _building.work_priority
	elif _priority_slider:
		_priority_slider.hide(); if _priority_label: _priority_label.hide()
	# Feature (v11.1, Logistik-Feinschliff): Filter-Auswahl nur für fertige
	# Lagerhäuser sichtbar (Verkaufsbuden, Decos etc. haben keinen Sinn dafür).
	if _filter_row:
		var show_filter: bool = _building.btype == "STORAGE" \
			and _building.storage_capacity > 0.0 and not _building.is_under_construction
		_filter_row.visible = show_filter
		if show_filter and _filter_option:
			var idx: int = 0
			if _building.storage_filter != "":
				idx = BuildingData.STORAGE_FILTER_OPTIONS.find(_building.storage_filter) + 1
			_filter_option.select(maxi(0, idx))
	if _desc_label:
		var desc: String = str(BuildingData.BUILDINGS.get(_building.id,{}).get("desc",""))
		_desc_label.text = desc; _desc_label.visible = desc != ""
	# Feature (v11.11, Distrikt-System): zeigt den Bezirk dieses Gebäudes,
	# eingefärbt in der jeweiligen Bezirksfarbe (siehe DistrictSystem.gd).
	if _district_label:
		var did: int = int(_building.district_id)
		var dname: String = DistrictSys.get_district_name(did)
		_district_label.text = "🏘️ %s" % dname
		var col: Array = ((DistrictSys.districts.get(did, {}) as Dictionary).get("color", [0.7,0.7,0.7]) as Array)
		if col.size() == 3:
			_district_label.add_theme_color_override("font_color", Color(float(col[0]), float(col[1]), float(col[2])))
		_district_label.visible = true

func _costs_str(costs: Dictionary) -> String:
	var parts: Array = []
	for r in costs: parts.append(str(BuildingData.RESOURCE_ICONS.get(str(r),"?"))+str(costs[r]))
	return " ".join(parts)

## Feature (v11.0): zeigt, was an einer Baustelle noch fehlt, z.B. "🪵15 🪨0"
## - macht sichtbar, worauf Bau-/Lagerfrettchen gerade warten.
func _missing_str(b: BuildingEntity) -> String:
	var parts: Array = []
	for r in b.costs:
		var missing: float = b.get_missing_amount(str(r))
		if missing > 0.01:
			parts.append(str(BuildingData.RESOURCE_ICONS.get(str(r),"?"))+str(int(ceil(missing))))
	return " ".join(parts) if not parts.is_empty() else "-"

func _on_sell() -> void:
	if _game_ctrl and _game_ctrl.has_method("sell_selected_building"): _game_ctrl.call("sell_selected_building")
	hide()

func _on_upgrade() -> void:
	if _game_ctrl and _game_ctrl.has_method("upgrade_selected_building"): _game_ctrl.call("upgrade_selected_building")

func _on_rebuild() -> void:
	if _game_ctrl and _game_ctrl.has_method("rebuild_selected_building"): _game_ctrl.call("rebuild_selected_building")

func _on_worker_minus() -> void:
	if _building == null: return
	_building.set_worker_cap(_building.get_effective_worker_cap() - 1)

func _on_worker_plus() -> void:
	if _building == null: return
	_building.set_worker_cap(_building.get_effective_worker_cap() + 1)
	PopMgr.try_fill_building(_building)

## Feature (v11.1, Logistik-Feinschliff): Index 0 = "Alles" (kein Filter),
## Index 1..n = BuildingData.STORAGE_FILTER_OPTIONS[Index-1].
func _on_filter_selected(idx: int) -> void:
	if _building == null: return
	if idx <= 0:
		_building.storage_filter = ""
	else:
		_building.storage_filter = str(BuildingData.STORAGE_FILTER_OPTIONS[idx - 1])
