## _t/Export.gd - Feature (v16.11, Welt-Export/-Import): .fkw-Round-Trip.
## Prueft in der echten Engine (headless):
##   - drei Weltgroessen (MEDIUM/LARGE/HUGE) mit echtem Inhalt (Gebaeude,
##     2. Kolonie, Gleise + Zug, Felder, einige Spieltage),
##   - Export->Import->Laden: alle Spielstand-Bloecke identisch (JSON exakt),
##     Terrain identisch innerhalb der dokumentierten Quantisierung,
##   - derselbe Test ueber den echten Ladevorgang (serialize nach load),
##   - Kopf-Vorschau OHNE Entpacken korrekt,
##   - Weltcode-Weg (Base64) Erzeugung + Import,
##   - Negativtests: abgeschnittene Datei, falsche Pruefsumme, falsches Magic,
##     neuere Formatversion, neuere Spielstandsversion, Riesen-Entpackgroesse,
##     boesartiger Slot-Name (Pfad-Angriff wird neutralisiert).
extends Node

var main: Node
var gc: Node
var fails: int = 0

func _log(s: String) -> void: print("[TEST] ", s)
func check(cond: bool, msg: String) -> void:
	if cond: _log("  ok   " + msg)
	else: fails += 1; _log("  FAIL " + msg)

func sim(steps: int, dt: float) -> void:
	for i in steps:
		gc.call("_process", dt)
		if i % 400 == 0: await get_tree().process_frame

func _ready() -> void:
	await get_tree().process_frame
	_cleanup_test_slots()
	var base_dir: String = OS.get_environment("TEMP") + "/fkw_test"
	DirAccess.make_dir_recursive_absolute(base_dir)
	var row_fmt: String = "%-7s json=%9d B   fkw=%9d B   code=%9d B   (%.0f%% von json)"
	var meas: Dictionary = {}
	for sz in ["MEDIUM", "LARGE", "HUGE"]:
		meas[sz] = await _run_world_test(String(sz), base_dir, row_fmt)
	await _negative_tests(base_dir)
	# .fkw-Testdateien aufraeumen
	for f in _fkw_files_in(base_dir):
		DirAccess.remove_absolute(f)
	_log("FERTIG fails=%d" % fails)
	# Cleanup-Slots ebenfalls entfernen (hinter den Tests nicht stehen lassen)
	_cleanup_test_slots()

# ── Vorbereitung ─────────────────────────────────────────────────────────────
func _cleanup_test_slots() -> void:
	for n in SaveSys.get_save_names():
		if String(n).begins_with("QA-Exp"):
			SaveSys.delete_save(String(n))

func _fkw_files_in(base_dir: String) -> Array:
	var out: Array = []
	var d: DirAccess = DirAccess.open(base_dir)
	if d == null: return out
	d.list_dir_begin()
	var fname: String = d.get_next()
	while fname != "":
		if fname.ends_with(".fkw"): out.append(base_dir + "/" + fname)
		fname = d.get_next()
	return out

func _new_world(sz: String, slot: String) -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for i in 30: await get_tree().process_frame
	var intro = main.get("_intro")
	if intro != null: intro.call("skip")
	for i in 5: await get_tree().process_frame
	gc = main.get("_game_ctrl")
	gc.call("start_new_game", sz, "qa-seed", slot)
	await sim(30, 0.1)
	gc.call("bootstrap_test_colony")
	for k in ["WOOD", "STONE", "PLANKS", "TOOLS", "BERRIES", "IRON_BARS", "IRON"]:
		ResourceSys.force_add(k, 400.0)
	GameState.dev_all_buildings = true

## Baut echten Weltinhalt: Gebäude, 2. Kolonie, Bahnhöfe + Gleise + Zug, Felder.
func _build_content() -> void:
	var hall0: Vector2i = ColonySys.get_hall_tile(0)
	# 8 gemischte Gebaeude in Kolonie 0
	var txd := 0
	for id in ["LUMBERJACK", "FISHER", "SAWMILL", "FARM", "STORAGE", "GRANARY", "HOUSE", "MENTOR"]:
		var p: Vector2i = gc.call("_find_free_tile_ring", hall0.x, hall0.y, gc.world, 3 + txd, 30)
		txd += 1
		if p.x < 0: continue
		var b = BuildingSys.build_free(id, p.x, p.y, gc.world, 0)
		if b == null: continue
		(b as BuildingEntity).placed_day = 0
		gc.renderer.add_building(b)
	# Felder in der Startkolonie
	for i in 3:
		var p2: Vector2i = gc.call("_find_free_tile_ring", hall0.x, hall0.y, gc.world, 5 + i, 40)
		if p2.x >= 0: FarmSys.register_field(p2.x, p2.y, 0)
	# zweite Kolonie + Bahnhofspaar + Gleise + Zug (Muster wie Rail-Test)
	var site: Vector2i = _far_free_tile(hall0, 20.0, 34.0)
	if site.x < 0: return
	gc.call("_found_colony", site.x, site.y)
	await sim(20, 0.1)
	if ColonySys.count() < 2: return
	var hall1: Vector2i = ColonySys.get_hall_tile(1)
	var pa: Vector2i = gc.call("_find_free_tile_ring", hall0.x, hall0.y, gc.world, 3, 7)
	var pb: Vector2i = gc.call("_find_free_tile_ring", hall1.x, hall1.y, gc.world, 3, 7)
	if pa.x < 0 or pb.x < 0: return
	var A = BuildingSys.build_free("STATION", pa.x, pa.y, gc.world, 0)
	var B = BuildingSys.build_free("STATION", pb.x, pb.y, gc.world, 1)
	for b in [A, B]:
		if b != null:
			(b as BuildingEntity).placed_day = 0
			gc.renderer.add_building(b)
	var route: Array = _bfs(pa, pb)
	if route.size() < 6: return
	for v in route:
		var t: Dictionary = (gc.world[(v as Vector2i).x] as Array)[(v as Vector2i).y]
		t["resource_node"] = null
	var line: int = RailSys.create_line()
	RailSys.add_stop(line, RailSys.key(pa.x, pa.y))
	RailSys.add_stop(line, RailSys.key(pb.x, pb.y))
	for i in range(1, route.size() - 1):
		var v2: Vector2i = route[i]
		gc.call("_place_rail", v2.x, v2.y, "PLACE", true)
	# Depot neben Bahnhof A + Zug kaufen
	var pd := Vector2i(-1, -1)
	for d in RailSys.DIRS:
		var c: Vector2i = pa + (d as Vector2i)
		var tt: Dictionary = (gc.world[c.x] as Array)[c.y]
		if (c in route) or tt.get("building") != null or FarmSys.has_field(c.x, c.y): continue
		if str(tt.get("biome", "")) in ["WATER", "MOUNTAIN"]: continue
		pd = c; break
	if pd.x >= 0:
		var D = BuildingSys.build_free("DEPOT", pd.x, pd.y, gc.world, 0)
		if D != null:
			(D as BuildingEntity).placed_day = 0
			gc.renderer.add_building(D)
			RailSys.buy_train(D, line)

func _far_free_tile(from: Vector2i, min_d: float, max_d: float) -> Vector2i:
	for r in 40:
		@warning_ignore("integer_division")
		var x: int = from.x + (r * 7) % (gc.world_gen.w - 4) + 2
		var y: int = from.y + ((r * 13) % (gc.world_gen.h - 4)) + 2
		if x + 1 >= gc.world_gen.w or y + 1 >= gc.world_gen.h: continue
		var t: Dictionary = (gc.world[x] as Array)[y]
		if t.get("building") == null and str(t.get("biome", "")) != "WATER" and not FarmSys.has_field(x, y):
			var dist: float = Vector2(Vector2i(x, y) - Vector2i(from.x, from.y)).length()
			if dist >= min_d and dist <= max_d: return Vector2i(x, y)
	return Vector2i(-1, -1)

func _bfs(a: Vector2i, b: Vector2i) -> Array:
	var prev: Dictionary = {a: null}
	var q: Array = [a]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if c == b: break
		for d in RailSys.DIRS:
			var n: Vector2i = c + (d as Vector2i)
			if n.x < 0 or n.y < 0 or n.x >= gc.world_gen.w or n.y >= gc.world_gen.h or prev.has(n): continue
			var t: Dictionary = (gc.world[n.x] as Array)[n.y]
			if str(t.get("biome", "")) in ["WATER", "MOUNTAIN"]: continue
			if (t.get("building") != null and n != b) or FarmSys.has_field(n.x, n.y): continue
			prev[n] = c; q.append(n)
	if not prev.has(b): return []
	var path: Array = []; var cur: Vector2i = b
	while cur != a and cur != Vector2i(-1, -1):
		path.push_front(cur); cur = prev.get(cur, Vector2i(-1, -1))
	path.push_front(a)
	return path

# ── Ablauf pro Weltgroesse ───────────────────────────────────────────────────
func _run_world_test(sz: String, base_dir: String, row_fmt: String) -> Dictionary:
	_log("── Welt %s ──" % sz)
	await _new_world(sz, "QA-Exp-" + sz)
	await _build_content()
	# einige Spieltage simulieren (Tag-Laenge temporär verkuert)
	var restore_day_len: float = DayNight.day_length
	DayNight.day_length = 20.0
	var day0: int = int(DayNight.day_count)
	await sim(700, 0.2)   # 140 s = 7 Tage
	DayNight.day_length = restore_day_len
	check(int(DayNight.day_count) > day0, "Spieltage simuliert (%d -> %d)" % [day0, int(DayNight.day_count)])
	check(BuildingSys.buildings.size() > 0, "Gebaeude vorhanden: %d" % BuildingSys.buildings.size())

	var slot: String = "QA-Exp-" + sz
	check(SaveSys.save(slot, gc), "gespeichert: " + slot)
	var json_path: String = SaveSys.SAVE_DIR + slot + ".json"
	var json_len: int = FileAccess.open(json_path, FileAccess.READ).get_length()
	var fkw_path: String = base_dir + "/welt_" + sz + ".fkw"
	var err_msg: String = SaveSys.export_fkw_file(slot, fkw_path)
	check(err_msg == "", "export_fkw_file: '%s'" % err_msg)
	var fkw_len: int = 0
	if err_msg == "":
		fkw_len = FileAccess.open(fkw_path, FileAccess.READ).get_length()
		var code_len: int = int(ceil(fkw_len / 3.0)) * 4
		_log(row_fmt % [sz, json_len, fkw_len, code_len, 100.0 * float(fkw_len) / float(json_len)])
	check(fkw_len > 0 and fkw_len < json_len, ".fkw ist kleiner als das JSON-Save (%d < %d)" % [fkw_len, json_len])

	var before: Dictionary = SaveSys.read_save_dict(slot)
	check(not before.is_empty(), "Slot-.json lesbar")
	# Kopf-Vorschau ohne Entpacken
	var pv: Dictionary = SaveSys.read_fkw_preview(fkw_path)
	check(not pv.has("err"), "Kopf-Vorschau ohne err: %s" % str(pv.get("err", "-")))
	check(int(pv.get("w", -1)) == int(before["world_w"]) and int(pv.get("day", -1)) == int(before["day_count"]),
		"Vorschau-Stimmt mit Spielstand (w=%s, Tag=%s)" % [str(pv.get("w")), str(pv.get("day"))])
	check(str(pv.get("name", "")) == str(before.get("colony_name", "?")), "Vorschau-Name = Kolonie-Name")

	# ── Echter Lade-Round-Trip A (Original): Welt laden, Zustand abgreifen
	var names_before: Array = SaveSys.get_save_names()
	var snap_a: Dictionary = await _load_and_snap(slot)
	# Import (Datei-Weg)
	var imp_msg: String = SaveSys.import_fkw_file(fkw_path)
	check(imp_msg == "", "import (Datei): '%s'" % imp_msg)
	var imp_slot: String = ""
	for n in SaveSys.get_save_names():
		if not names_before.has(n): imp_slot = String(n); break
	check(imp_slot != "", "importierter Slot vorhanden: " + imp_slot)
	# Weltcode-Weg (Vorschau + Import)
	var code_raw: PackedByteArray = FileAccess.open(fkw_path, FileAccess.READ).get_buffer(fkw_len)
	var code: String = "FKW Weltcode:\n" + Marshalls.raw_to_base64(code_raw)
	var pv2: Dictionary = SaveSys.read_fkw_preview_worldcode(code)
	check(not pv2.has("err"), "Weltcode-Vorschau ohne err")
	var imp_msg2: String = SaveSys.import_fkw_worldcode(code)
	check(imp_msg2 == "", "import (Weltcode mit Anzeige-Praefix): '%s'" % imp_msg2)
	var imp_slot2: String = ""
	for n2 in SaveSys.get_save_names():
		if not names_before.has(n2) and String(n2) != imp_slot: imp_slot2 = String(n2); break
	check(imp_slot2 != "", "Weltcode-Import-Slot vorhanden: " + imp_slot2)

	# Spielstand-Dateien direkt vergleichen (Bloecke exakt, Terrain quantisiert)
	var after: Dictionary = SaveSys.read_save_dict(imp_slot)
	_compare_blocks(before, after)
	check(await _terrain_quant_ok(before, after), "Terrain quantisiert identisch (0,0005 m / 1/2048 m)")
	var after2: Dictionary = SaveSys.read_save_dict(imp_slot2)
	check(bool(_dict_eq_ignoring(after, after2, ["slot"])), "Datei-Import und Weltcode-Import ergeben denselben Spielstand")

	# ── Echter Lade-Round-Trip B (importiert): Welt laden, Zustand abgreifen
	var snap_b: Dictionary = await _load_and_snap(imp_slot)
	var ser_ok := true
	for key in snap_a.keys():
		if key == "world":
			# Terrain mit der dokumentierten Quantisierung vergleichen
			var qres: Variant = _terrain_q(snap_a["world"], snap_b["world"])
			if bool(qres) == false:
				ser_ok = false
				check(false, "Lade-Round-Trip: Terrain (quantisiert) ungleich")
		else:
			var sa: String = JSON.stringify(snap_a[key], "", false, true)
			var sb: String = JSON.stringify(snap_b[key], "", false, true)
			if sa != sb:
				ser_ok = false
				check(false, "Lade-Round-Trip Block '%s' ungleich:\n    A: %s\n    B: %s" % [key, sa.substr(0, 240), sb.substr(0, 240)])
	check(ser_ok, "Lade-Round-Trip: alle Bloecke identisch nach echtem Laden")

	var meas: Dictionary = {"json": json_len, "fkw": fkw_len}
	await _drop_main()
	return meas

func _load_and_snap(slot: String) -> Dictionary:
	check(SaveSys.load_game(slot, gc), "geladen: " + slot)
	return {
		"resources": ResourceSys.serialize(),
		"buildings": BuildingSys.serialize(),
		"population": PopMgr.serialize(),
		"day_night": DayNight.serialize(),
		"drought": DroughtSys.serialize(),
		"season": SeasonSys.serialize(),
		"expeditions": ExpeditionSys.serialize(),
		"achievements": AchievementSys.serialize(),
		"districts": DistrictSys.serialize(),
		"colonies": ColonySys.serialize(),
		"rail": RailSys.serialize(),
		"explore": ExploreSys.serialize(),
		"neighbors": NeighborSys.serialize(),
		"farm_fields": FarmSys.serialize(),
		"player": gc.serialize_player(),
		"world": gc.serialize_world(),
	}

func _compare_blocks(before: Dictionary, after: Dictionary) -> void:
	var ok := true
	for key in before.keys():
		if key == "world" or key == "slot": continue
		if not after.has(key):
			ok = false; check(false, "Block '%s' fehlt nach Import" % str(key)); continue
		var j1: String = JSON.stringify(before[key], "", false, true)
		var j2: String = JSON.stringify(after[key], "", false, true)
		if j1 != j2:
			ok = false
			check(false, "Block '%s' ungleich:%s  A: %s%s  B: %s" % [str(key), char(10), j1.substr(0, 240), char(10), j2.substr(0, 240)])
	check(ok, "Alle Spielstand-Bloecke identisch (JSON exakt, ausser slot)")

func _quant_h(v: float) -> int: return int(roundf(clampf(v, 0.0, 20.0) * 2000.0))
func _quant_w(v: float) -> int: return int(roundf(clampf(v, 0.0, 4.0) * 2048.0))

func _terrain_quant_ok(before: Dictionary, after: Dictionary) -> bool:
	var w1: Dictionary = before.get("world", {}) as Dictionary
	var w2: Dictionary = after.get("world", {}) as Dictionary
	return bool(_terrain_q(w1, w2))

func _terrain_q(w1: Dictionary, w2: Dictionary) -> Variant:
	if int(w1.get("size_w", -1)) != int(w2.get("size_w", -2)): return false
	if int(w1.get("size_h", -1)) != int(w2.get("size_h", -2)): return false
	var t1: Array = w1.get("tiles", []) as Array
	var t2: Array = w2.get("tiles", []) as Array
	if t1.size() != t2.size(): return false
	for x in t1.size():
		var c1: Array = t1[x] as Array
		var c2: Array = t2[x] as Array
		if c1.size() != c2.size(): return false
		for y in c1.size():
			var d1: Dictionary = c1[y] as Dictionary
			var d2: Dictionary = c2[y] as Dictionary
			if str(d1.get("biome")) != str(d2.get("biome")): return false
			if _quant_h(float(d1.get("height", 0.0))) != _quant_h(float(d2.get("height", 0.0))): return false
			if _quant_w(float(d1.get("water_level", 0.0))) != _quant_w(float(d2.get("water_level", 0.0))): return false
			if bool(d1.get("ruin", false)) != bool(d2.get("ruin", false)): return false
			if bool(d1.get("is_water_source", false)) != bool(d2.get("is_water_source", false)): return false
			var p1 = d1.get("path", null)
			var p2 = d2.get("path", null)
			var t1s: bool = (p1 is Dictionary and (p1 as Dictionary).has("type"))
			var t2s: bool = (p2 is Dictionary and (p2 as Dictionary).has("type"))
			if t1s != t2s: return false
			if t1s and str((p1 as Dictionary).get("type")) != str((p2 as Dictionary).get("type")): return false
			var r1 = d1.get("resource_node", null)
			var r2 = d2.get("resource_node", null)
			if (r1 is Dictionary) != (r2 is Dictionary): return false
			if r1 is Dictionary and not bool(_rn_eq(r1, r2)): return false
	return true

func _rn_eq(r1: Dictionary, r2: Dictionary) -> bool:
	if r1.keys().size() != r2.keys().size(): return false
	for k in r1.keys():
		if not r2.has(k): return false
		var v1: Variant = r1[k]
		var v2: Variant = r2[k]
		if str(v1) == str(v2): continue
		# Zahlen (z.B. -0.0 / 0.0): Float-Vergleich als Fallback
		if v1 is float and v2 is float and float(v1) == float(v2): continue
		return false
	return true

func _dict_eq_ignoring(a: Dictionary, b: Dictionary, skip: Array) -> bool:
	for k in a.keys():
		if k in skip: continue
		if not b.has(k): return false
		if JSON.stringify(a[k], "", false, true) != JSON.stringify(b[k], "", false, true): return false
	return a.keys().size() >= b.keys().size()

func _drop_main() -> void:
	if main != null:
		main.queue_free()
		for i in 5: await get_tree().process_frame

# ── Negativtests ─────────────────────────────────────────────────────────────
func _negative_tests(base_dir: String) -> void:
	_log("── Negativtests ──")
	var src: String = base_dir + "/welt_MEDIUM.fkw"
	if not FileAccess.file_exists(src):
		check(false, "Negativtests: Quelldatei fehlt"); return
	var f: FileAccess = FileAccess.open(src, FileAccess.READ)
	var buf: PackedByteArray = f.get_buffer(1024 * 1024 * 64)
	f.close()
	var names_now: Array = SaveSys.get_save_names()

	# 1: abgeschnittene Datei (letzte 13 Bytes weg)
	var t1: PackedByteArray = buf.slice(0, buf.size() - 13)
	var d1: Dictionary = FKWCodec.decode(t1)
	check(d1.has("err"), "abgeschnitten -> Fehler: '%s'" % str(d1.get("err", "WENT THROUGH")))
	# 2: Bitfehler in den Nutzdaten -> Pruefsumme falsch
	var t2 := PackedByteArray(buf)
	var probe: Dictionary = FKWCodec.read_head(buf)
	if not probe.has("err"):
		var chk_off: int = int(probe["body_off"])   # unmittelbar danach beginnt der Payload
		t2.encode_u8(chk_off + 2, int(t2[chk_off + 2]) ^ 0xFF)
		var d2: Dictionary = FKWCodec.decode(t2)
		check(d2.has("err") and str(d2["err"]).contains("Prüfsumme"), "falsche Prüfsumme -> '%s'" % str(d2.get("err")))
	else:
		check(false, "Negativtest 2: Kopf unlesbar")
	# 3: falsches Magic
	var t3 := PackedByteArray(buf)
	for i in 4: t3.encode_u8(i, 88)
	var d3: Dictionary = FKWCodec.decode(t3)
	check(d3.has("err"), "falsches Magic -> '%s'" % str(d3.get("err")))
	# 4: neuere Formatversion
	var t4 := PackedByteArray(buf)
	t4.encode_u16(4, 99)
	var d4: Dictionary = FKWCodec.decode(t4)
	check(d4.has("err") and str(d4["err"]).contains("neueren"), "Formatversion 99 -> '%s'" % str(d4.get("err")))
	# 5: neuere Spielstandsversion
	var t5 := PackedByteArray(buf)
	t5.encode_u16(6, 99)
	var d5: Dictionary = FKWCodec.decode(t5)
	check(d5.has("err") and str(d5["err"]).contains("neueren"), "Spielstandsversion 99 -> '%s'" % str(d5.get("err")))
	# 6: Riesige Entpackgroesse (raw_len = 4 GB Kopf-Wert)
	var t6 := PackedByteArray(buf)
	var probe6: Dictionary = FKWCodec.read_head(buf)
	if not probe6.has("err"):
		var raw_off: int = int(probe6["body_off"]) - 12   # raw_len liegt unmittelbar vor Pruefsumme+body
		t6.encode_u32(raw_off, 0xFFFFFFFF)
		var d6: Dictionary = FKWCodec.decode(t6)
		check(d6.has("err"), "raw_len 4 GB -> '%s'" % str(d6.get("err")))
	else:
		check(false, "Negativtest 6: Kopf unlesbar")
	# 7: boesartiger Slot-Name (Pfad-Angriff Жber colony_name)
	var data: Dictionary = SaveSys.read_save_dict("QA-Exp-MEDIUM")
	if data.is_empty():
		check(false, "Negativtest 7: Basis-Spielstand fehlt")
	else:
		data["colony_name"] = "../../Evil"
		var enc: PackedByteArray = FKWCodec.encode(data)
		check(not enc.is_empty(), "Angriffsdatei gepackt")
		var imp: String = SaveSys.import_fkw_bytes(enc)
		check(imp == "", "Angriffs-Import ack: '%s'" % imp)
		var got: String = ""
		for n in SaveSys.get_save_names():
			if not names_now.has(n): got = String(n)
		check(got == "Evil", "Slot-Name neutralisiert: '%s' (soll 'Evil')" % got)
		check(FileAccess.file_exists(SaveSys.SAVE_DIR + "Evil.json"), "Import landet im Save-Ordner ( Evil.json)")
		if got != "":
			SaveSys.delete_save(got)
