## MenuManager.gd
## Zentrale Verwaltung aller Popup-/Overlay-Menüs (PauseMenu, TechTreePanel,
## AchievementPanel, ExpeditionPanel, GraveyardPanel, DistrictPanel,
## StatsPanel, BuildingInfo, FerretProfilePanel).
##
## Nutzerwunsch: "UI Menüs sollen im Vordergrund sein und wenn ein Menü
## geöffnet wird, sollen alle anderen geschlossen werden, sodass immer nur
## ein Menü offen ist."
##
## Funktionsweise: jedes Menü ruft in seiner _ready()-Funktion einmalig
## MenuManager.register(self) auf. Alle betroffenen Panels schalten ihre
## Sichtbarkeit ohnehin ausschliesslich über show()/hide() bzw. die
## visible-Property um - beides löst Godots eingebautes visibility_changed-
## Signal aus. Wir hängen uns dort ein: wird ein registriertes Menü sichtbar,
## schliessen wir automatisch alle anderen registrierten Menüs und bringen
## das geöffnete an die letzte Position seines Elternknotens (= vorne, sowohl
## beim Zeichnen als auch bei der Eingabe-Priorität in Godots Control-Baum).
##
## Kein bestehender open()/close()-Aufruf musste dafür angepasst werden.
extends Node

signal open_state_changed(any_open: bool)

var _panels: Array[Control] = []
var _suppress: bool = false  # verhindert Rückkopplung während wir selbst schliessen

func register(panel: Control) -> void:
	if panel == null or _panels.has(panel):
		return
	_panels.append(panel)
	panel.visibility_changed.connect(_on_panel_visibility_changed.bind(panel))
	panel.tree_exiting.connect(func(): _panels.erase(panel))

func _on_panel_visibility_changed(panel: Control) -> void:
	if _suppress:
		return
	if not panel.visible:
		open_state_changed.emit(is_any_open())
		return
	_bring_to_front(panel)
	_suppress = true
	for p in _panels:
		if p != panel and is_instance_valid(p) and p.visible:
			p.hide()
	_suppress = false
	open_state_changed.emit(is_any_open())

func _bring_to_front(panel: Control) -> void:
	var parent := panel.get_parent()
	if parent != null:
		parent.move_child(panel, parent.get_child_count() - 1)

## Schliesst alle registrierten Menüs, z.B. bevor man ins Hauptmenü wechselt.
func close_all() -> void:
	_suppress = true
	for p in _panels:
		if is_instance_valid(p) and p.visible:
			p.hide()
	_suppress = false

## True, sobald irgendein registriertes Menü gerade offen ist - genutzt vom
## TouchOverlay, um das virtuelle Gamepad auszublenden, solange ein Menü
## offen ist (verhindert, dass Touch-Buttons Menü-Buttons überlagern und
## deren Taps abfangen).
func is_any_open() -> bool:
	for p in _panels:
		if is_instance_valid(p) and p.visible:
			return true
	return false
