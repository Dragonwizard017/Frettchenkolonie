# Test- & Panorama-Werkzeuge (NICHT Teil der Spiel-ZIP)

Alles läuft in Claudes Sandbox mit der echten Godot-Binary (siehe "General",
Abschnitt "Echte Engine-Tests"). Zum Benutzen: Ordner in das entpackte Projekt
nach `_t/` kopieren (`cp tools/*.{gd,tscn} proj/_t/`), `godot --headless --import`
ausführen (nach neuen `class_name`-Skripten Pflicht!), dann:

| Datei | Zweck | Aufruf |
|---|---|---|
| `TestRunner.tscn` | Komplette Partie simulieren (Testwelt, Felder, Dürre, Speichern/Laden, Verkaufen, FP-Modus). Fehler = `SCRIPT ERROR` im Log | `godot --headless --path . res://_t/TestRunner.tscn` (dauert Minuten -> Hintergrund) |
| `Exp5.tscn` | FP-Modus: Spieler neben Frettchen setzen, Streicheln-Pfad ausführen | `godot --headless --path . res://_t/Exp5.tscn` |
| `Exp6.tscn` | Accessoire-Editor: alle Achievements freischalten, ▶/◀ klicken, Ausrüstung prüfen | `godot --headless --path . res://_t/Exp6.tscn` |
| `lambda_scan.py` | Findet Lambdas, die lokale Variablen ändern (siehe Lambda-Falle) | im Projektordner: `python3 lambda_scan.py` |
| `ModelCheck.tscn` / `BldCheck.tscn` / `AnimCheck.tscn` | Neue GLBs prüfen: Maße/Mitte/Unterkante, Gebäudeversatz in der laufenden Kolonie, Animationen + Loop | `godot --headless --path . res://_t/<Name>.tscn` |
| `Acc.tscn` | Frettchen mit allen Accessoires als Nahaufnahme (vorn/hinten, Pose frei) | unter xvfb: `... res://_t/Acc.tscn -- bild.png Idle 35` |
| `Shot.tscn` | Screenshot einer Ansicht: `menu`, `world`, `load`, `game`, `colony`, `pause`, `info`, `equip`, `season:<0-3>:<0|1 realistisch>[:fp[:<tageszeit 0-1>[:<yaw°>]]]`, `panel:<NodeName>` | `xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver vulkan --resolution 1600x900 res://_t/Shot.tscn -- <modus> /pfad/bild.png` |
| `Pano2.tscn` + `stitch.py` | Menü-Panorama MIT Realismus-Modus/Saison-Optik rendern (aktuell genutzt, 6 Seiten, ~15-20 Min. unter Software-Vulkan -> Hintergrund) | `... res://_t/Pano2.tscn -- alpha 7 <prefix> 1536 1 0.69` |
| `Pano.tscn` + `stitch.py` (alt) | Menü-Panorama neu rendern (6 Cubemap-Seiten) und zum Equirect-Streifen zusammensetzen | siehe unten |

Screenshots brauchen Xvfb + Software-Vulkan:
`apt-get update && apt-get install -y xvfb mesa-vulkan-drivers libgl1-mesa-dri libegl1 libxcursor1 libxinerama1 libxi6 libxrandr2 libasound2t64`

## Panorama neu erzeugen
```
godot --path . --rendering-driver vulkan res://_t/Pano.tscn -- <seed> <höhe> <prefix> 0 0 1536   # unter xvfb-run
python3 stitch.py <prefix> proj/assets/panorama/colony_panorama.jpg 6144 45
```
Seed `alpha`, Höhe `7` ergibt das aktuelle Bild. 6 Seiten à 1536 px brauchen auf
Software-Vulkan ca. 6 Min -> mit `setsid nohup ... &` im Hintergrund starten (ein
Tool-Aufruf darf max. 300 s dauern). Im aktuellen Bild war eine zweite "Sonnenscheibe"
(Füll-Licht) sichtbar und wurde per Interpolation herausretuschiert; `Pano.gd` setzt
für das Füll-Licht jetzt `sky_mode = SKY_MODE_LIGHT_ONLY`, bei einem Neu-Rendern
entfällt die Retusche.
