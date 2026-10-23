## BuildingExplanations.gd
## Feature (v12.3, Tutorial-Überarbeitung). Kurze, verständliche
## Erklärungen zu jedem im Bau-Menü erscheinenden Gebäude - Grundlage
## sowohl für das Einführungs-Tutorial (Epoche-1-Gebäude) als auch für
## den neuen "Freischaltungs-Erklärer" (ui/UnlockExplainer.gd), der bei
## jeder Epochen-/Tech-Freischaltung automatisch die neu verfügbaren
## Gebäude vorstellt. Bewusst als eigene, kleine Daten-Datei getrennt von
## BuildingData.gd (dort steht nur ein Teil der Gebäude schon ein knappes
## "desc"-Feld, viele gar keins - hier gibt es für ALLE eine Erklärung,
## ohne BuildingData.gd selbst aufzublähen).
extends RefCounted
class_name BuildingExplanations

## bid -> {"summary": Haupterklärung (1-2 Sätze, verständlich für
## Neulinge), "tip": optionaler kurzer Praxis-Tipp}
const TEXTS: Dictionary = {
	# ── Epoche 1 ──────────────────────────────────────────────────────────
	"CONSTRUCTION_YARD_1": {"summary": "Der Bauhof ist dein Start-Gebäude: hier arbeiten die Frettchen, die alle deine Baustellen errichten.", "tip": "Ohne freie Bauhof-Arbeiter geht keine Baustelle voran."},
	"LUMBERJACK": {"summary": "Der Holzfäller sammelt automatisch Holz von Bäumen in seinem Radius.", "tip": "Steht er zu weit von Bäumen entfernt, produziert er nichts - platziere ihn nah am Wald."},
	"QUARRY": {"summary": "Der Steinbruch fördert Stein aus Felsvorkommen in der Nähe.", "tip": "Braucht Felsen/Stein-Ressourcenknoten im Radius, sonst bleibt er untätig."},
	"BERRY_GATHERER": {"summary": "Sammelt Beeren von Büschen - deine erste Nahrungsülle.", "tip": "Reicht meist nur für wenige Frettchen; später mit Garten/Kochhaus ausbauen."},
	"WELL": {"summary": "Der Brunnen fördert Trinkwasser und speichert etwas davon.", "tip": "Muss auf oder nahe Wasser-Tiles gebaut werden."},
	"DAM": {"summary": "Staut Wasser auf und hält Flüsse/Seen während einer Dürre länger gefüllt.", "tip": "Baue ihn an einer Engstelle im Flusslauf."},
	"STORAGE": {"summary": "Ein Lagerhaus erhöht deine Lagerkapazität für Rohstoffe.", "tip": "Ohne genug Lagerplatz verschwenden deine Sammler überschüssige Ressourcen."},
	"HOUSE": {"summary": "Bietet Schlafplätze - ohne Betten wächst deine Kolonie nicht weiter.", "tip": "Neue Frettchen brauchen ein freies Bett, sonst kein Nachwuchs."},
	"GATHERING_PLACE": {"summary": "Hebt die Stimmung aller Frettchen in der Nähe.", "tip": "Unglückliche Frettchen arbeiten langsamer und werden seltener."},
	"FORESTER": {"summary": "Pflanzt automatisch neue Bäume in ihrem Radius nach - sichert deinen Holz-Nachschub dauerhaft.", "tip": "Am besten in der Nähe deines Holzfällers bauen."},
	"GRAVEYARD": {"summary": "Gedenkstätte für verstorbene Frettchen - hebt leicht die Stimmung.", "tip": ""},
	"DECO_FLOWERS": {"summary": "Rein dekorativ, hebt aber leicht die Stimmung im Umkreis.", "tip": ""},
	"DECO_MUSHROOM": {"summary": "Rein dekorativ, hebt aber leicht die Stimmung im Umkreis.", "tip": ""},
	"DECO_STONES": {"summary": "Rein dekorativ, hebt aber leicht die Stimmung im Umkreis.", "tip": ""},
	"DECO_BUSH": {"summary": "Rein dekorativ, hebt aber leicht die Stimmung im Umkreis.", "tip": ""},
	"SAWMILL": {"summary": "Verarbeitet Holz zu Brettern - die Grundlage fast aller späteren Bauwerke.", "tip": "Ohne Sägewerk kommst du über Epoche 1 nicht hinaus."},
	"WORKSHOP": {"summary": "Verarbeitet Holz und Stein zu Werkzeugen, die viele Gebäude zum Arbeiten brauchen.", "tip": ""},
	"RESEARCH_HUT": {"summary": "Produziert Wissenspunkte für den Tech-Baum - ohne sie kannst du nichts erforschen.", "tip": "Baue sie früh, sonst stockt dein technischer Fortschritt."},
	# ── Epoche 2 ──────────────────────────────────────────────────────────
	"CONSTRUCTION_YARD_2": {"summary": "Größerer Bauhof mit mehr Arbeitsplätzen für schnellere Baustellen.", "tip": ""},
	"WATER_TOWER": {"summary": "Fördert deutlich mehr Wasser als ein Brunnen und speichert mehr.", "tip": ""},
	"TAVERN": {"summary": "Deutlich stärkerer Stimmungs-Bonus als der Versammlungsplatz.", "tip": ""},
	"GARDEN": {"summary": "Verbesserte Beerenernte gegenüber dem einfachen Beerensammler.", "tip": ""},
	"LARGE_STORAGE": {"summary": "Größeres Lagerhaus mit deutlich mehr Kapazität.", "tip": ""},
	"FARMHOUSE": {"summary": "Bestellt vom Spieler zugewiesene Feld-Kacheln im Bezirk - Grundlage für Brot im Kochhaus.", "tip": "Mit dem Feld-Werkzeug im Baumenü Wiesen-Kacheln als Acker markieren, sonst haben die Arbeiter nichts zu tun!"},
	"WATER_PUMP": {"summary": "Fördert Wasser schneller als ein Brunnen, braucht aber Wasser in der Nähe.", "tip": ""},
	"RESERVOIR": {"summary": "Reines Wasser-Speichergebäude mit großer Kapazität.", "tip": ""},
	"FOOD_STORE": {"summary": "Lagerhaus speziell für Nahrungsmittel.", "tip": ""},
	"WATERWHEEL": {"summary": "Erhöht die Produktion aller Verarbeitungsgebäude in seinem Radius, wenn es an Wasser steht.", "tip": "Muss auf/nahe Wasser gebaut werden, um zu wirken."},
	"BATHHOUSE": {"summary": "Starker Stimmungs-Bonus mit großem Radius.", "tip": ""},
	"EXPEDITION_CAMP": {"summary": "Schicke Frettchen auf Erkundungstouren - bringt seltene Belohnungen mit.", "tip": "Je länger die Expedition, desto besser die Beute, aber auch riskanter."},
	"COOKHOUSE": {"summary": "Verarbeitet Rohstoffe zu besserem Essen (gekochtes Fleisch, Brot, Eintopf) - sättigt mehr als rohe Beeren.", "tip": ""},
	"HUNTER_HUT": {"summary": "Jäger erlegen Wild und liefern Fleisch als Nahrung.", "tip": ""},
	"DYNAMITE_WORKSHOP": {"summary": "Stellt Dynamit her, mit dem du Hügel/Felsen sprengen kannst.", "tip": "Nützlich für schnelles Terraforming statt mühsamem Abtragen."},
	"DECO_LANTERN": {"summary": "Rein dekorativ, hebt aber leicht die Stimmung im Umkreis.", "tip": ""},
	"OBSERVATORY": {"summary": "Löst auf Entdeckerkarten den Nebel auf: Arbeiter beobachten und kartieren das Land, der aufgedeckte Kreis wächst mit der Zeit. Erst aufgedecktes Gebiet ist bebaubar.", "tip": "Setze die Station an den Rand deiner Kolonie. Mit Upgrades wird der Radius größer (14 → 21 → 28). Dahinter liegen neue Rohstoffe wie Eisen."},
	"STATION": {"summary": "Haltestelle der Güterzüge. Die Waren werden direkt gegen das Lager der Kolonie getauscht, in der der Bahnhof steht.", "tip": "Lege Gleise zwischen zwei Bahnhöfen, erstelle im 🚂-Fenster eine Linie und gib an, welche Ware von wo nach wo fahren soll."},
	"DEPOT": {"summary": "Hier stehen die Züge. Ohne Depot gibt es keine Lokomotiven.", "tip": "Ein Zug kostet Eisenstangen, Werkzeuge und Bretter. Mehr Züge auf einer Linie = mehr Durchsatz."},
	"TOWN_HALL": {"summary": "Das Herz einer Kolonie: legt ihr Gebiet fest. Ein weiteres Rathaus fern der Startkolonie gründet eine neue Kolonie mit eigenem Lager, Wasser und eigener Bevölkerung.", "tip": "Das Gründungspaket (die Baukosten) wird zum Startbestand der neuen Kolonie. Das Rathaus selbst kann nicht verkauft werden."},
	"DISTRICT_GATE": {"summary": "Verbindet Lager-Netzwerke benachbarter Bezirke, solange ein Frettchen hier arbeitet.", "tip": "Ohne Bezirkstor holen Lagerarbeiter Material nur innerhalb ihres eigenen Bezirks."},
	# ── Epoche 3 ──────────────────────────────────────────────────────────
	"ENGINEERS_GUILD": {"summary": "Fortgeschrittener Bauhof mit vielen Arbeitsplätzen für Epoche-3-Bauprojekte.", "tip": ""},
	"IRON_MINE": {"summary": "Fördert Eisenerz - Grundstoff für Werkzeuge und spätere High-Tech-Gebäude.", "tip": ""},
	"COAL_MINE": {"summary": "Fördert Kohle, die in Schmelze und Hochofen gebraucht wird.", "tip": ""},
	"SMELTER": {"summary": "Verhüttet Eisenerz zu Eisenstäben - notwendig für viele Epoche-3/4-Gebäude.", "tip": ""},
	"AQUEDUCT": {"summary": "Sehr leistungsstarke Wasserversorgung mit riesigem Radius und Speicher.", "tip": ""},
	"THEATER": {"summary": "Der stärkste Stimmungs-Booster im Spiel, mit sehr großem Radius.", "tip": ""},
	"WAREHOUSE": {"summary": "Großes Industrie-Lagerhaus mit sehr hoher Kapazität.", "tip": ""},
	"IRRIGATION": {"summary": "Bewässerungskanal mit hoher Wasserförderung und -speicherung.", "tip": ""},
	# ── Epoche 4 ──────────────────────────────────────────────────────────
	"CONSTRUCTION_OFFICE": {"summary": "Die fortschrittlichste Bauhof-Stufe mit den meisten Arbeitsplätzen.", "tip": ""},
	"MACHINE_FACTORY": {"summary": "Stellt Maschinen her - werden für die höchste Technologiestufe gebraucht.", "tip": ""},
	"BLAST_FURNACE": {"summary": "Verarbeitet Eisenstäbe und Kohle zu Stahl, dem wertvollsten Baustoff.", "tip": ""},
	"STATUE": {"summary": "Das mächtigste Stimmungsgebäude im Spiel - riesiger Radius und Bonus.", "tip": ""},
	# ── Sonderfall: über Tech-Knoten statt Epoche freigeschaltet ────────────
	"NURSERY": {"summary": "Kümmert sich um den Nachwuchs und hebt die Stimmung der Kolonie.", "tip": "Schaltest du über einen bestimmten Tech-Knoten frei, nicht automatisch mit der Epoche."},
}

## Liefert die Erklärung für eine Gebäude-ID (leeres Dictionary, falls
## keine hinterlegt ist - der Aufrufer soll das Gebäude dann einfach
## überspringen statt mit Platzhaltertext zu verwirren).
static func get_explanation(bid: String) -> Dictionary:
	return TEXTS.get(bid, {})
