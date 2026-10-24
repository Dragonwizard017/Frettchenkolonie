## SaveSystem.gd
extends Node

const SAVE_DIR: String = "user://saves/"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func get_save_names() -> Array:
	var names: Array = []
	var dir: DirAccess = DirAccess.open(SAVE_DIR)
	if dir == null: return names
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			names.append(fname.get_basename())
		fname = dir.get_next()
	return names

## Feature (v11.4, Speicherslot-System): jeder Slot trägt jetzt kompakte
## Kolonie-Metadaten (Name, Seed, Tag, Jahreszeit, Bevölkerung, Weltgrösse)
## direkt auf oberster Ebene, damit die Welt-Auswahl-Liste (get_save_info)
## diese Werte lesen kann, ohne den kompletten Speicherstand zu deserialisieren.
func save(slot_name: String, game_ctrl: Node) -> bool:
	var data: Dictionary = build_save_dict(slot_name, game_ctrl)
	if not write_save_dict(slot_name, data):
		return false
	GameState.notify("Gespeichert: " + slot_name)
	return true

## v16.11: den Spielstand als Dictionary aufbauen (Kern aus save(), jetzt auch
## fuer den Welt-Export nutzbar - genau dasselbe Dictionary fuettert SaveSystem
## UND den FKWCodec).
func build_save_dict(slot_name: String, game_ctrl: Node) -> Dictionary:
	var meta: Dictionary = {}
	if game_ctrl.has_method("get_save_metadata"):
		meta = game_ctrl.call("get_save_metadata") as Dictionary
	var data: Dictionary = {
		"version": 10,
		"slot": slot_name,
		"colony_name": str(meta.get("colony_name", slot_name)),
		"seed": int(meta.get("seed", 0)),
		"day_count": int(meta.get("day_count", 0)),
		"season_name": str(meta.get("season_name", "")),
		"season_icon": str(meta.get("season_icon", "")),
		"population_count": int(meta.get("population_count", 0)),
		"world_w": int(meta.get("world_w", 0)),
		"world_h": int(meta.get("world_h", 0)),
		"timestamp": Time.get_datetime_string_from_system(),
		"world": game_ctrl.serialize_world(),
		"resources": ResourceSys.serialize(),
		"buildings": BuildingSys.serialize(),
		"population": PopMgr.serialize(),
		"day_night": DayNight.serialize(),
		"tech": TechTreeSys.serialize(),
		"drought": DroughtSys.serialize(),
		"season": SeasonSys.serialize(),
		# Bug-Fix (v10.14): "Expeditionen werden nicht gespeichert" - bisher
		# fehlte dieser Eintrag komplett, laufende Expeditionen (inkl. der
		# mitgereisten Frettchen) gingen beim Speichern/Laden verloren.
		"expeditions": ExpeditionSys.serialize(),
		# Feature (v11.8, Achievement-System):
		"achievements": AchievementSys.serialize(),
		# Feature (v11.11, Distrikt-System):
		"districts": DistrictSys.serialize(),
		# Feature (v16.0, Kolonie-Fundament): Kolonien (Rathaus, Gebiet, aktive Kolonie).
		"colonies": ColonySys.serialize(),
		# Feature (v16.2, Schiene): Gleise, Linien, Züge.
		"rail": RailSys.serialize(),
		# Feature (v16.6, Erkundung): aufgedecktes Gebiet (nur Entdeckerkarten; sonst enabled=false).
		"explore": ExploreSys.serialize(),
		# Feature (v16.7, Nachbarn): Ruf, Aufträge, Entdeckt/Annektiert (die Nachbar-Gebäude/-Pools stehen in den normalen Blöcken).
		"neighbors": NeighborSys.serialize(),
		# Feature (v14.5, Timberborn-Feld-System):
		"farm_fields": FarmSys.serialize(),
		# Feature (v11.25, Positions-Persistenz): Spielerposition/-Blickrichtung,
		# damit der Frettchenmodus beim nächsten Start/Laden dort weitermacht,
		# wo man ihn verlassen hat, statt immer neu zu spawnen.
		"player": game_ctrl.serialize_player(),
		# Feature (v12.2, Phase 4): Ausrüstung des Frettchen-Ich (die
		# Freischaltungen selbst sind implizit über "achievements" oben
		# gespeichert - PlayerAccessories.is_unlocked() leitet daraus ab).
		"player_accessories": PlayerAccessories.serialize()
	}
	return data

## v16.11 (aus save() ausgekoppelt): schreibt ein fertiges Spielstand-Dictionary
## als Slot-.json - wird von save() und vom Welt-Import gleichermaßen genutzt.
func write_save_dict(slot_name: String, data: Dictionary) -> bool:
	var path: String = SAVE_DIR + slot_name + ".json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveSystem: Kann Datei nicht schreiben: " + path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true

func load_game(slot_name: String, game_ctrl: Node) -> bool:
	var ctx: Dictionary = {}
	for st in load_game_steps(slot_name, game_ctrl, ctx): (st["fn"] as Callable).call()
	return bool(ctx.get("ok", false))

## v15.8: Laden in Schritten (Ladebildschirm). `ctx` sammelt den Zustand: "data" (geparster Spielstand),
## "fail" (true = abgebrochen, Folgeschritte tun nichts) und am Ende "ok".
## load_game() führt die Schritte einfach nacheinander aus.
func load_game_steps(slot_name: String, game_ctrl: Node, ctx: Dictionary) -> Array:
	var steps: Array = []
	steps.append({"label": "Spielstand wird gelesen …", "weight": 8.0, "fn": func(): _lg_read(slot_name, ctx)})
	steps.append({"label": "Welt wird rekonstruiert …", "weight": 8.0, "fn": func():
		if bool(ctx.get("fail", false)): return
		var wd: Dictionary = (ctx["data"] as Dictionary).get("world", {}) as Dictionary
		if wd.is_empty(): ctx["fail"] = true; return
		game_ctrl.call("_dw_world", wd)
		# v16.6: Nebel-Zustand VOR dem Renderer-Aufbau laden (Saves ohne "explore": alles bekannt)
		ExploreSys.deserialize((ctx["data"] as Dictionary).get("explore", {}))
		NeighborSys.deserialize((ctx["data"] as Dictionary).get("neighbors", {}))
		WaterSys.init(game_ctrl.world, game_ctrl.world_gen.w, game_ctrl.world_gen.h)})
	for st in game_ctrl.call("_setup_renderer_steps"):
		var inner: Callable = st["fn"]
		steps.append({"label": st["label"], "weight": st["weight"], "fn": func():
			if not bool(ctx.get("fail", false)): inner.call()})
	steps.append({"label": "", "weight": 0.5, "fn": func():
		if not bool(ctx.get("fail", false)): game_ctrl.call("_dw_finish")})
	steps.append({"label": "Kolonie wird wiederhergestellt …", "weight": 10.0, "fn": func():
		if not bool(ctx.get("fail", false)): _lg_restore(slot_name, game_ctrl, ctx["data"] as Dictionary)})
	steps.append({"label": "Gebäude werden aufgestellt …", "weight": 8.0, "fn": func():
		if bool(ctx.get("fail", false)): return
		var data: Dictionary = ctx["data"] as Dictionary
		# Bug 5-Fix: Gebäude wurden nach deserialize_world in die Tiles geschrieben -
		# Renderer muss jetzt nochmals die Building-Nodes erzeugen.
		if game_ctrl.has_method("post_load_refresh"):
			game_ctrl.call("post_load_refresh")
		GameState.notify("Geladen: " + str(data.get("colony_name", slot_name)))
		ctx["ok"] = true})
	return steps

func _lg_read(slot_name: String, ctx: Dictionary) -> void:
	var path: String = SAVE_DIR + slot_name + ".json"
	if not FileAccess.file_exists(path):
		GameState.notify("Speicherstand nicht gefunden: " + slot_name, Color(0.8, 0.2, 0.1))
		ctx["fail"] = true; return
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null: ctx["fail"] = true; return
	var json_str: String = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(json_str)
	if not (parsed is Dictionary):   # v14.6: beschädigte Datei (z.B. Array) nicht crashen lassen
		ctx["fail"] = true; return
	ctx["data"] = parsed as Dictionary

## Alles außer Welt/Renderer: Ressourcen, Gebäude, Bevölkerung, Systeme.
func _lg_restore(slot_name: String, game_ctrl: Node, data: Dictionary) -> void:
	ResourceSys.deserialize(data.get("resources", {}) as Dictionary)
	BuildingSys.deserialize(data.get("buildings", []) as Array, game_ctrl.world)
	PopMgr.deserialize(data.get("population", {}) as Dictionary)
	DayNight.deserialize(data.get("day_night", {}) as Dictionary)
	# Bug-Fix (v11.15): TechTreeSys.serialize() gibt seit der Einführung von
	# "unlocked_epochs"/"total_spent" ein DICTIONARY zurück (siehe TechTree.gd),
	# nicht mehr das ursprüngliche einfache Array. Der erzwungene "as Array"-
	# Cast hier ist deshalb bei JEDEM Speicherstand mit gespeichertem
	# Tech-Fortschritt sofort mit "Invalid cast: could not convert value to
	# 'Array'" abgestürzt - TechTreeSys.deserialize() selbst unterstützt
	# BEIDE Formate (Array = alte Saves, Dictionary = aktuelle) und darf daher
	# nicht durch einen vorzeitigen Zwangs-Cast hier blockiert werden.
	TechTreeSys.deserialize(data.get("tech", {}))
	# Feature (Tech Tree, Bugfix): stellt sicher, dass alle geladenen Gebäude
	# exakt die Boni ihrer im Save vermerkten erforschten Tech-Knoten tragen,
	# auch falls sich BuildingData/TechTree seit dem Speichern geändert hat.
	BuildingSys.recalculate_all_bonuses()
	DroughtSys.deserialize(data.get("drought", {}) as Dictionary)
	SeasonSys.deserialize(data.get("season", {}) as Dictionary)
	ExpeditionSys.deserialize(data.get("expeditions", []) as Array)
	# Feature (v11.8, Achievement-System): "achievements" fehlt in Saves von
	# vor diesem Feature - deserialize() fängt das per init()-Fallback ab.
	AchievementSys.deserialize(data.get("achievements", {}))
	# Feature (v11.11, Distrikt-System):
	DistrictSys.deserialize(data.get("districts", {}))
	# Feature (v16.0, Kolonie-Fundament): fehlt in Saves von vor v16.0 -> eine
	# einzige Kolonie 0, das Rathaus wird gleich nachgerüstet (Migration).
	ColonySys.deserialize(data.get("colonies", {}))
	RailSys.deserialize(data.get("rail", {}))
	# Feature (v14.5, Timberborn-Feld-System): fehlt in Saves von vor diesem
	# Feature - deserialize() fängt das per init()-Fallback ab (leeres Feld-
	# Register, wie bei einer frischen Kolonie).
	FarmSys.deserialize(data.get("farm_fields", {}))
	# Feature (v11.25, Positions-Persistenz): deserialize_world() (oben) hat
	# bereits einen Fallback-Spawnpunkt gesetzt (für Speicherstände vor
	# v11.25) - hier wird das bei Bedarf mit der tatsächlich gespeicherten
	# Position überschrieben (deserialize_player() macht selbst nichts, falls
	# "player"-Feld fehlt oder "valid" false ist, siehe GameController.gd).
	game_ctrl.deserialize_player(data.get("player", {}) as Dictionary)
	# Feature (v12.2, Phase 4): MUSS nach AchievementSys.deserialize() (oben)
	# laufen, da PlayerAccessories.deserialize() pro Slot prüft, ob das
	# jeweilige Accessoire überhaupt noch freigeschaltet ist.
	PlayerAccessories.deserialize(data.get("player_accessories", {}))
	# Feature (v11.4, Speicherslot-System): aktuellen Slot + Kolonie-Namen im
	# GameController merken, damit "Speichern" im Pause-Menü automatisch
	# wieder in denselben, benannten Slot schreibt statt in einen festen
	# "quicksave"-Slot.
	game_ctrl.current_save_slot = slot_name
	game_ctrl.current_world_name = str(data.get("colony_name", slot_name))
	# v16.0: Rathaus/Gebiet für alte Saves nachrüsten, dann die gespeicherte
	# aktive Kolonie wieder zur "aktuellen" machen (deserialize setzt Pool 0).
	if game_ctrl.has_method("migrate_colonies_after_load"):
		game_ctrl.call("migrate_colonies_after_load")
	ResourceSys.use_colony(ColonySys.active_id)

## Feature (v11.4, Speicherslot-System): liest nur die kompakten Metadaten
## eines Speicherstands (für die Welt-Auswahl-Liste), ohne Welt/Gebäude/
## Bevölkerung vollständig zu deserialisieren - schnell auch bei vielen Slots.
func get_save_info(slot_name: String) -> Dictionary:
	var path: String = SAVE_DIR + slot_name + ".json"
	if not FileAccess.file_exists(path): return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var json_str: String = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(json_str)
	if not (parsed is Dictionary): return {}
	var data: Dictionary = parsed as Dictionary
	return {
		"slot": slot_name,
		"colony_name": str(data.get("colony_name", slot_name)),
		"seed": int(data.get("seed", 0)),
		"day_count": int(data.get("day_count", 0)),
		"season_name": str(data.get("season_name", "")),
		"season_icon": str(data.get("season_icon", "")),
		"population": int(data.get("population_count", 0)),
		"world_w": int(data.get("world_w", 0)),
		"world_h": int(data.get("world_h", 0)),
		"timestamp": str(data.get("timestamp", "")),
	}

## Feature (v11.4, Speicherslot-System): löscht einen benannten Speicherstand
## unwiderruflich (genutzt von der Welt-Auswahl-Liste im "Löschen"-Button).
func delete_save(slot_name: String) -> bool:
	var dir: DirAccess = DirAccess.open(SAVE_DIR)
	if dir == null: return false
	var fname: String = slot_name + ".json"
	if not dir.file_exists(fname): return false
	var err: int = dir.remove(fname)
	if err == OK:
		GameState.notify("Speicherstand gelöscht: " + slot_name)
		return true
	return false

# ══════════════════════════════════════════════════════════════════════════════
# Feature (v16.11, WELT-EXPORT/-IMPORT): eine Welt als platzsparende .fkw-Datei
# exportieren und auf einem anderen System wieder importieren. Design: der
# Export liest denselben Speicherstand-Woerterbuch (build_save_dict bzw. den
# Slot-.json) und verpackt ihn per FKWCodec (zstd + Binaerezustand, siehe
# systems/FKWCodec.gd). Der Import erzeugt einen NORMALen Slot (.json) und
# laeuft danach ueber den normalen Lade-Pfad - Migrationen bleiben wirksam,
# es gibt KEINEN zweiten Ladepfad. Der "Weltcode" ist dieselbe Datei als
# Base64-Text (Zwischenablage, gilt als Weg fuer Geraete ohne Datei-Dialog).
# ══════════════════════════════════════════════════════════════════════════════

## Vorschau einer .fkw-Datei (nur Kopf, OHNE Entpacken).
## Rueckgabe {} oder ein info-Dictionary mit "err" bei Problemen.
func read_fkw_preview(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"err": "Die Datei konnte nicht gelesen werden."}
	var buf: PackedByteArray = file.get_buffer(4096)   # der Kopf ist immer unter 512 Bytes
	file.close()
	return FKWCodec.read_head(buf)

## Die Datei aus einem bestehenden Slot als .fkw exportieren (Welt-Auswahl).
## Rueckgabe: "" bei Erfolg, sonst deutsche Fehlermeldung.
func export_fkw_file(slot_name: String, out_path: String) -> String:
	var data: Dictionary = read_save_dict(slot_name)
	if data.is_empty():
		return "Der Spielstand '%s' konnte nicht gelesen werden." % slot_name
	var buf: PackedByteArray = FKWCodec.encode(data)
	if buf.is_empty():
		return "Die Welt konnte nicht gepackt werden (keine Welt-Daten vorhanden)."
	var err_msg: String = _write_fkw(out_path, buf)
	if not err_msg.is_empty(): return err_msg
	_copy_code_to_clipboard(buf)
	GameState.notify("Welt exportiert: " + slot_name)
	return ""

## Die aktuell laufende Welt als .fkw exportieren (Pausenmenue).
## Rueckgabe: "" bei Erfolg, sonst deutsche Fehlermeldung.
func export_current_fkw(game_ctrl: Node, out_path: String) -> String:
	var slot: String = str(game_ctrl.get("current_save_slot"))
	if slot.is_empty():
		slot = str(game_ctrl.get("current_world_name"))
		if slot.is_empty(): slot = "Kolonie"
	var data: Dictionary = build_save_dict(slot, game_ctrl)
	var buf: PackedByteArray = FKWCodec.encode(data)
	if buf.is_empty():
		return "Die Welt konnte nicht gepackt werden (keine Welt-Daten vorhanden)."
	var err_msg: String = _write_fkw(out_path, buf)
	if not err_msg.is_empty(): return err_msg
	_copy_code_to_clipboard(buf)
	GameState.notify("Welt exportiert: " + slot)
	return ""

## .fkw-Datei importieren (erzeugt einen neuen Slot im normalen Format).
## Rueckgabe: "" bei Erfolg, sonst deutsche Fehlermeldung.
func import_fkw_file(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "Die Datei konnte nicht gelesen werden."
	var buf: PackedByteArray = file.get_buffer(FKWCodec.PAYLOAD_RAW_MAX)
	file.close()
	return import_fkw_bytes(buf)

## .fkw-Weltcode (Base64-Text, z.B. aus der Zwischenablage) importieren.
## Rueckgabe: "" bei Erfolg, sonst deutsche Fehlermeldung.
func import_fkw_worldcode(code: String) -> String:
	# Sauber halten: Zeilenumbrueche/Leerraum entfernen; ist ein Anzeigepraefix
	# ("FKW Weltcode: ...") dabei, wird alles bis zum Doppelpunkt uebersprungen.
	var clean: String = code.strip_edges().replace("\n", "").replace("\r", "").replace("\t", "").replace(" ", "")
	if clean.begins_with("FKW"):
		var pos: int = clean.find(":")
		if pos > 0 and pos < 30:
			clean = clean.substr(pos + 1)
	var buf: PackedByteArray = Marshalls.base64_to_raw(clean)
	if buf.is_empty():
		return "Der Weltcode ist ungültig (keine gültigen Base64-Daten)."
	return import_fkw_bytes(buf)

func import_fkw_bytes(buf: PackedByteArray) -> String:
	var decoded: Dictionary = FKWCodec.decode(buf)
	if decoded.has("err"):
		return str(decoded["err"])
	var save_data: Dictionary = decoded["save"] as Dictionary
	var head: Dictionary = decoded["head"] as Dictionary
	var base_name: String = sanitize_slot_name(str(head.get("name", "Import")))
	var slot: String = unique_slot_name(base_name)
	save_data["slot"] = slot
	# Der Slot traegt den Namen der importierten Welt; der Spiecherzeitpunkt
	# (timestamp) bleibt der der Export-Datei.
	if not write_save_dict(slot, save_data):
		return "Der importierte Spielstand konnte nicht gespeichert werden."
	GameState.notify("Welt importiert: " + str(save_data.get("colony_name", slot)))
	return ""

## Vorschau per Weltcode (fuer den Import-Dialog OHNE Datei).
func read_fkw_preview_worldcode(code: String) -> Dictionary:
	# Gleiches Praefix-Wegputzen wie in import_fkw_worldcode.
	var clean: String = code.strip_edges().replace("\n", "").replace("\r", "").replace("\t", "").replace(" ", "")
	if clean.begins_with("FKW"):
		var pos: int = clean.find(":")
		if pos > 0 and pos < 30:
			clean = clean.substr(pos + 1)
	var buf: PackedByteArray = Marshalls.base64_to_raw(clean)
	if buf.is_empty():
		return {"err": "Der Weltcode ist ungültig (keine gültigen Base64-Daten)."}
	return FKWCodec.read_head(buf)

## Slot-Namen fuer den IMPORT reinigen (kein "../", keine
## Sonderzeichen vom Betriebssystem, max 40 Zeichen).
func sanitize_slot_name(raw: String) -> String:
	var clean: String = raw.strip_edges()
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "%", "#", "&", "{", "}", "$", "!", "'", "+", "`", "=", "@", "~"]:
		clean = clean.replace(ch, "")
	clean = clean.replace("..", ".")
	clean = clean.strip_edges()
	# Keine fuehrenden Punkte (Windows/Unix-Hilfsdateien) und keine abschliessenden.
	while clean.begins_with("."):
		clean = clean.substr(1).strip_edges()
	while clean.ends_with("."):
		clean = clean.substr(0, clean.length() - 1).rstrip(" ")
	clean = clean.substr(0, 40).strip_edges()
	if clean.is_empty():
		clean = "Import"
	return clean

## Eindeutigen Slotlinamen machen (bei Kollision "(2)", "(3)", ...).
func unique_slot_name(base: String) -> String:
	var existing: Array = get_save_names()
	if not existing.has(base): return base
	var i: int = 2
	while existing.has(base + " (%d)" % i): i += 1
	return base + " (%d)" % i

## Liest den VOLLESTAENDIGEN Spielstand eines Slots (fuer den Export).
func read_save_dict(slot_name: String) -> Dictionary:
	var path: String = SAVE_DIR + slot_name + ".json"
	if not FileAccess.file_exists(path): return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var json_str: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(json_str)
	if not (parsed is Dictionary): return {}
	return parsed as Dictionary

func _write_fkw(out_path: String, buf: PackedByteArray) -> String:
	var target: String = out_path
	if not target.to_lower().ends_with(".fkw"):
		target += ".fkw"
	var file: FileAccess = FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return "'%s' konnte nicht geschrieben werden." % target
	file.store_buffer(buf)
	file.close()
	return ""

## Weltcode in die Zwischenablage (wenn die Platform es kann) - oder still.
func _copy_code_to_clipboard(buf: PackedByteArray) -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set("FKW Weltcode:\n" + Marshalls.raw_to_base64(buf))
		GameState.notify("Weltcode in die Zwischenablage kopiert (fuer Handy/Messenger).")

