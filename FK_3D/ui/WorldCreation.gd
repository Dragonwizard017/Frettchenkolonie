## WorldCreation.gd
extends Control

@onready var name_input: LineEdit    = $Panel/VBox/NameInput
@onready var seed_input: LineEdit    = $Panel/VBox/SeedInput
@onready var size_option: OptionButton = $Panel/VBox/SizeOption
@onready var start_btn: Button       = $Panel/VBox/StartBtn
@onready var back_btn: Button        = $Panel/VBox/BackBtn
@onready var preview_lbl: Label      = $Panel/VBox/PreviewLabel

signal start_requested(world_name: String, seed_str: String, world_size: String)
signal back_requested

const SIZES: Array = ["SMALL", "MEDIUM", "LARGE", "HUGE"]
const SIZE_LABELS: Array = ["Klein (40x40)", "Mittel (60x60)", "Gross (80x80)", "Entdecker (120x120, Nebel)"]

func _ready() -> void:
	GameState.state_changed.connect(_on_state_changed)
	if size_option:
		for lbl in SIZE_LABELS: size_option.add_item(str(lbl))
		size_option.selected = 1
	if start_btn: start_btn.pressed.connect(_on_start)
	if back_btn:  back_btn.pressed.connect(func(): back_requested.emit())
	if seed_input:
		seed_input.placeholder_text = "Leer = Zufällig"
		seed_input.text_changed.connect(_on_seed_changed)

func _on_start() -> void:
	var wname: String = name_input.text.strip_edges() if name_input else "Kolonie"
	if wname.is_empty(): wname = "Meine Kolonie"
	var seed_str: String = seed_input.text.strip_edges() if seed_input else ""
	var idx: int = size_option.selected if size_option else 1
	var world_size: String = str(SIZES[idx])
	start_requested.emit(wname, seed_str, world_size)

func _on_seed_changed(text: String) -> void:
	if preview_lbl:
		if text.strip_edges().is_empty():
			preview_lbl.text = "Seed: Zufällig"
		else:
			preview_lbl.text = "Seed-Hash: %d" % text.hash()

func _on_state_changed(state: GameState.State) -> void:
	visible = (state == GameState.State.WORLD_CREATION)
