## CharacterEditorPanel.gd
## Feature (v12.2, Phase 4 - Frettchen-Ich-Anpassung; v12.4 überarbeitet).
## Seit v12.4 KEIN eigenständiges Popup mehr, sondern DAUERHAFT im
## Pause-Menü angedockt (Nutzeranfrage, Design angelehnt an das
## Pause-Menü von Minecraft Bedrock Edition: ständig sichtbare
## Charakter-Vorschau seitlich, mit einem Button darunter, der die
## Ausrüstungs-Optionen ein-/ausklappt). Wird als Kind-Node direkt in
## _build_pause_menu() (Main.gd) eingehängt und erbt dadurch automatisch
## die Sichtbarkeit des Pause-Menüs - kein eigenes show()/hide() mehr
## nötig.
extends PanelContainer

const SLOT_ORDER: Array = ["HEAD", "NECK", "FACE", "BACK"]
const SLOT_NAMES: Dictionary = {"HEAD": "Kopf", "NECK": "Hals", "FACE": "Gesicht", "BACK": "Rücken"}
const PREVIEW_SIZE: Vector2i = Vector2i(240, 260)
const ROTATE_SPEED: float = 0.5  # rad/Sek

var _preview_model: Node3D = null
var _sub_viewport: SubViewport = null
var _equip_section: VBoxContainer = null
var _toggle_btn: Button = null
var _equip_expanded: bool = false

func _ready() -> void:
	custom_minimum_size = Vector2(260, 0)
	_build_static_ui()
	# Bug-Fix (v12.4): reagiert jetzt live auf Freischaltungs-/
	# Ausrüstungs-Änderungen, auch während das Pause-Menü offen ist (z.B.
	# per Dev-Mode "Alle Achievements freischalten") - vorher musste man das
	# Panel schliessen und neu öffnen, damit neu unlockte Accessoires
	# überhaupt in der Auswahl auftauchten.
	AchievementSys.achievement_unlocked_toast.connect(func(_id): _refresh_equip_section())
	PlayerAccessories.equipment_changed.connect(_refresh_preview_accessories)
	# v15.1: Slot-Zeilen bei JEDER Ausrüstungsänderung neu aufbauen (z.B. nach Laden),
	# sonst zeigen sie veralteten Zustand. Deferred, weil der Auslöser oft ein Klick auf
	# einen Knopf genau dieser Zeilen ist.
	PlayerAccessories.equipment_changed.connect(func(): call_deferred("_refresh_equip_section"))

func _process(delta: float) -> void:
	# is_visible_in_tree() statt visible: diese Node selbst hat immer
	# visible=true, sichtbar ist sie aber nur, wenn das umschliessende
	# Pause-Menü offen ist - die Rotation soll dann auch nur dann laufen.
	if not is_visible_in_tree() or _preview_model == null: return
	_preview_model.rotation.y += delta * ROTATE_SPEED

## Baut den STATISCHEN Teil einmalig: 3D-Vorschau + Umschalt-Button + den
## (anfangs leeren/eingeklappten) Ausrüstungs-Bereich darunter.
func _build_static_ui() -> void:
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 8)
	add_child(vb)

	var tl := Label.new()
	tl.text = "🐾 Frettchen-Ich"
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.theme_type_variation = "Heading"
	tl.add_theme_font_size_override("font_size", 19)
	vb.add_child(tl)

	# ── Live-3D-Vorschau ──────────────────────────────────────────────────
	var preview_frame := PanelContainer.new()
	var pf_sb := StyleBoxFlat.new()
	pf_sb.bg_color = Color(0.03, 0.04, 0.05, 0.55)
	pf_sb.set_corner_radius_all(8)
	pf_sb.border_width_left = 1; pf_sb.border_width_right = 1
	pf_sb.border_width_top = 1;  pf_sb.border_width_bottom = 1
	pf_sb.border_color = Color(0.3, 0.3, 0.32)
	preview_frame.add_theme_stylebox_override("panel", pf_sb)
	vb.add_child(preview_frame)

	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = Vector2(PREVIEW_SIZE)
	svc.stretch = true
	preview_frame.add_child(svc)
	_sub_viewport = SubViewport.new()
	_sub_viewport.size = PREVIEW_SIZE
	_sub_viewport.own_world_3d = true  # eigene, isolierte 3D-Welt - kein Überlappen mit der Kolonie-Szene
	_sub_viewport.transparent_bg = true
	svc.add_child(_sub_viewport)
	_build_preview_scene(_sub_viewport)

	# ── Umschalt-Button (Minecraft-Bedrock-Stil: Vorschau immer sichtbar,
	# Anpassungs-Optionen erst nach Klick) ──────────────────────────────────
	_toggle_btn = Button.new()
	_toggle_btn.text = "🎨 Accessoires ausrüsten"
	_toggle_btn.custom_minimum_size = Vector2(0, 44)
	_toggle_btn.focus_mode = Control.FOCUS_NONE
	_toggle_btn.pressed.connect(_on_toggle_equip)
	vb.add_child(_toggle_btn)

	_equip_section = VBoxContainer.new()
	_equip_section.add_theme_constant_override("separation", 10)
	_equip_section.visible = false
	vb.add_child(_equip_section)

func _on_toggle_equip() -> void:
	_equip_expanded = not _equip_expanded
	_toggle_btn.text = ("▲ Ausrüstung schließen" if _equip_expanded else "🎨 Accessoires ausrüsten")
	_equip_section.visible = _equip_expanded
	if _equip_expanded: _refresh_equip_section()

## Baut die 4 Slot-Zeilen neu auf (Freischalt-Stand kann sich jederzeit
## ändern, siehe achievement_unlocked_toast-Verbindung in _ready()).
func _refresh_equip_section() -> void:
	if _equip_section == null or not _equip_expanded: return
	for c in _equip_section.get_children(): c.queue_free()
	for slot in SLOT_ORDER:
		_equip_section.add_child(_build_slot_row(slot))

func _build_preview_scene(sv: SubViewport) -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.85, 1.9)
	cam.fov = 45.0
	# Bug-Fix (v12.4): look_at() braucht is_inside_tree() (liest den
	# aktuellen globalen Transform) - "Node not inside tree"-Fehler trat
	# auf, weil look_at() VOR add_child() aufgerufen wurde.
	sv.add_child(cam)
	cam.look_at(Vector3(0.0, 0.55, 0.0), Vector3.UP)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-30.0), 0.0)
	sun.light_energy = 1.1
	sv.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(150.0), 0.0)
	fill.light_energy = 0.4
	sv.add_child(fill)

	# Feature (v12.2): dieselbe Bau-Logik wie PlayerController.gd
	# (_apply_player_tint() + refresh_accessories()) - EIGENE, unabhängige
	# Instanz, damit die Vorschau nicht am tatsächlichen Spieler-Node hängt
	# (der z.B. gerade unsichtbar im First-Person-Modus stecken könnte).
	_preview_model = PlayerController.FERRET_SCENE.instantiate() as Node3D
	_preview_model.scale = Vector3.ONE * PlayerController.FERRET_MODEL_SCALE
	_tint_recursive(_preview_model)
	sv.add_child(_preview_model)
	_refresh_preview_accessories()

## Färbt die Vorschau exakt wie das echte Frettchen-Ich (siehe
## PlayerController._apply_player_tint() - bewusst dieselbe Logik dupliziert
## statt eine Instanz-Methode auf dem echten Spieler-Node aufzurufen, da die
## Vorschau ein völlig unabhängiges Preview-Modell ist).
func _tint_recursive(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var src_mat: Material = mi.get_active_material(i)
				var new_mat: Material = (src_mat.duplicate() as Material) if src_mat else StandardMaterial3D.new()
				if new_mat is BaseMaterial3D:
					(new_mat as BaseMaterial3D).albedo_color *= PlayerController.PLAYER_TINT
				mi.set_surface_override_material(i, new_mat)
	for c in n.get_children():
		_tint_recursive(c)

func _refresh_preview_accessories() -> void:
	if _preview_model == null: return
	for c in _preview_model.get_children():
		if str(c.name).begins_with("AccessoryItem_"): c.queue_free()
	for slot in PlayerAccessories.equipped:
		var aid: String = str(PlayerAccessories.equipped[slot])
		if aid == "": continue
		var ad: Dictionary = FerretAccessories.get_accessory(aid)
		if ad.is_empty(): continue
		var scene: PackedScene = load(str(ad.get("glb", "")))
		if scene == null: continue
		var inst := scene.instantiate() as Node3D
		if inst == null: continue
		inst.name = "AccessoryItem_" + aid
		inst.position = ad.get("offset", Vector3.ZERO) as Vector3
		inst.rotation.x = float(ad.get("rot_x", 0.0))
		inst.rotation.y = float(ad.get("rot_y", 0.0))
		_preview_model.add_child(inst)

func _build_slot_row(slot: String) -> Control:
	var options: Array = []  # Array[String], "" = "leer"
	options.append("")
	for aid in FerretAccessories.ACCESSORIES:
		var ad: Dictionary = FerretAccessories.ACCESSORIES[aid]
		if str(ad.get("slot", "")) == slot and PlayerAccessories.is_unlocked(aid):
			options.append(aid)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)

	var slot_lbl := Label.new()
	slot_lbl.text = str(SLOT_NAMES.get(slot, slot))
	slot_lbl.custom_minimum_size = Vector2(48, 0)
	slot_lbl.add_theme_font_size_override("font_size", 12)
	slot_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	row.add_child(slot_lbl)

	var prev_btn := UITheme.btn("◀", "IconButton", Vector2(34, 34)); prev_btn.add_theme_font_size_override("font_size", 15)
	row.add_child(prev_btn)

	var name_lbl := Label.new()
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 14)
	row.add_child(name_lbl)

	var next_btn := UITheme.btn("▶", "IconButton", Vector2(34, 34)); next_btn.add_theme_font_size_override("font_size", 15)
	row.add_child(next_btn)

	var count_lbl := Label.new()
	var unlocked_count: int = options.size() - 1
	var total_count: int = 0
	for aid2 in FerretAccessories.ACCESSORIES:
		if str((FerretAccessories.ACCESSORIES[aid2] as Dictionary).get("slot", "")) == slot: total_count += 1
	count_lbl.text = "%d/%d freigeschaltet" % [unlocked_count, total_count]
	count_lbl.add_theme_font_size_override("font_size", 9)
	count_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(count_lbl)

	var current_id: String = str(PlayerAccessories.equipped.get(slot, ""))
	var current_idx: int = options.find(current_id)
	if current_idx < 0: current_idx = 0
	# Bug-Fix (v15.1): GDScript-Lambdas KOPIEREN lokale Variablen beim Erzeugen.
	# Das alte `current_idx` wurde in den ◀/▶-Lambdas nur auf einer Kopie geändert
	# und blieb für alle weiteren Aufrufe (und für refresh_label/apply_selection)
	# auf dem Startwert -> Durchschalten ging nie weiter, die Auswahl wurde sogar
	# sofort wieder auf "leer" gesetzt. Ein Dictionary wird als Referenz
	# geteilt, Änderungen darin sind für alle Lambdas sichtbar.
	var state: Dictionary = {"idx": current_idx}

	var refresh_label := func():
		var aid: String = options[int(state["idx"])]
		if aid == "":
			name_lbl.text = "— leer —"
			name_lbl.add_theme_color_override("font_color", UITheme.C_TEXT_DIM)
		else:
			var ad: Dictionary = FerretAccessories.get_accessory(aid)
			name_lbl.text = str(ad.get("name", aid))
			name_lbl.add_theme_color_override("font_color", UITheme.C_ACCENT_HI)
	refresh_label.call()

	var apply_selection := func():
		var aid: String = options[int(state["idx"])]
		if aid == "":
			PlayerAccessories.unequip_slot(slot)
		else:
			PlayerAccessories.equip(aid)

	prev_btn.pressed.connect(func():
		if options.size() <= 1: return
		state["idx"] = (int(state["idx"]) - 1 + options.size()) % options.size()
		refresh_label.call(); apply_selection.call()
	)
	next_btn.pressed.connect(func():
		if options.size() <= 1: return
		state["idx"] = (int(state["idx"]) + 1) % options.size()
		refresh_label.call(); apply_selection.call()
	)
	if options.size() <= 1:
		prev_btn.disabled = true; next_btn.disabled = true

	return box
