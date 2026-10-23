## TechTreeCanvas.gd
## Feature (v11.12, Skilltree-Redesign): eigene Control-Subklasse, die per
## _draw() die Verbindungslinien zwischen Knoten UND die Epochen-Zonen (als
## konzentrische, unterschiedlich eingefärbte Kreisflächen statt Tabs -
## Nutzerwunsch: "Epochen sollten eher durch Grenzen dargestellt werden")
## zeichnet. TechTreePanel.gd befüllt `edges`/`epoch_rings` und ruft
## queue_redraw() auf; die eigentlichen Knoten-Buttons werden von
## TechTreePanel.gd als Kind-Nodes DIESES Controls hinzugefügt (Container
## selbst ist ein einfaches Control, kein Box/GridContainer, damit absolute
## Positionierung der Knoten funktioniert - siehe TechTreePanel._build_node_cell()).
extends Control
class_name TechTreeCanvas

## Jeder Eintrag: {"from": Vector2, "to": Vector2, "color": Color, "width": float}
var edges: Array = []
## Jeder Eintrag: {"radius": float, "fill": Color}. MUSS absteigend nach
## radius sortiert übergeben werden (größter Ring zuerst), damit kleinere
## Ringe die größeren korrekt überdecken und so "Zonen" entstehen.
var epoch_rings: Array = []
var ring_center: Vector2 = Vector2.ZERO
var ring_border_color: Color = Color(0.7, 0.58, 0.22, 0.55)

func _draw() -> void:
	for ring in epoch_rings:
		var r: Dictionary = ring as Dictionary
		draw_circle(ring_center, float(r.get("radius", 0.0)), r.get("fill", Color.WHITE) as Color)
	for ring in epoch_rings:
		var r2: Dictionary = ring as Dictionary
		draw_arc(ring_center, float(r2.get("radius", 0.0)), 0.0, TAU, 64, ring_border_color, 2.0, true)
	for e in edges:
		var ed: Dictionary = e as Dictionary
		draw_line(ed.get("from", Vector2.ZERO), ed.get("to", Vector2.ZERO), ed.get("color", Color.WHITE) as Color, float(ed.get("width", 2.0)), true)
