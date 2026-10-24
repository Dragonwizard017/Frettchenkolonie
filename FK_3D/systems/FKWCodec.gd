## FKWCodec.gd
## Feature (v16.11, Welt-Export/Import): kompaktes Format ".fkw".
##
## Aufbau einer .fkw-Datei (alles Little-Endian, PackedByteArray.encode_*/decode_*):
##   Kopf (unkomprimiert - die Import-Vorschau liest ihn OHNE Entpacken):
##     magic "FKW1" (4 Bytes) | format_version u16 | save_version u16 |
##     Spielversion-String (u8 Laenge + UTF-8) | Weltname-String |
##     seed s64 | size_w u16 | size_h u16 | day_count u32 | population u32 |
##     payload_len u32 | payload_raw_len u32 | checksum (8 Bytes) | Nutzdaten
##   checksum = erste 8 Bytes des SHA-256 ueber die komprimierten Nutzdaten.
##   Nutzdaten (zstd): [u32 meta_json_Laenge][meta_json][Terrain-Ebenen]
##     meta_json = kompletter Spielstand OHNE "world" (full_precision-JSON),
##     plus "biomes"/"paths" (String-Paletten) und "res" (sparse
##     [x, y, resource_node]-Liste).
##     Terrain-Ebenen (7 Bytes pro Kachel, Spaltenmajor, Index = x*h + y):
##       biom u8 | hoehe u16 (m * 2000) | wasser u16 (m * 2048) | pfad u8 (0 = keiner)
##       | flag u8 (Bit0 Ruine, Bit1 Wasserquelle)
##
## Quantisierung (dokumentiert in Changes/General): Hoehe Schritt 0,0005 m -
## alle exakten Spielstufen (1 m Aufschuetten, 3 m Dynamit, Schwellen 14/5/2 m)
## bleiben exakt; Wasser Schritt 1/2048 m - Startwerte 0/1/4 bleiben exakt und
## der halbe Schritt (0,00024 m) liegt weit unter WaterSys.MIN_FLOW (0,0008 m).
## Gebaeude/Frettchen/uebrige Systeme bleiben als Schluessel-JSON (ihr
## serialize() ist das stabile Speicherformat); zstd entfernt die Wiederholung.
class_name FKWCodec
extends RefCounted

const FORMAT_VERSION: int = 1
static var MAGIC: PackedByteArray = PackedByteArray([70, 75, 87, 49])   # "FKW1"
const SAVE_VERSION_MAX: int = 10
const PAYLOAD_RAW_MAX: int = 256 * 1024 * 1024   # Entpack-Wache (kein Memory-Bombing)
const STRING_MAX: int = 255
const HEIGHT_SCALE: int = 2000    # Hoehe 0..20 m -> u16, Schritt 0,0005 m
const WATER_SCALE: int = 2048     # Wasser 0..4 m -> u16, Schritt 1/2048 m
const HEIGHT_MAX_M: float = 20.0
const WATER_MAX_M: float = 4.0

# ── Encode ───────────────────────────────────────────────────────────────────
## Baut die .fkw-Datei aus einem Spielstand-Dictionary (gleiches Format wie in
## SaveSystem.save() geschrieben). Bei Problemen: leeres Array (Rueckgabe).
static func encode(data: Dictionary) -> PackedByteArray:
	var world: Dictionary = data.get("world", {}) as Dictionary if data.get("world", {}) is Dictionary else {}
	var w: int = int(world.get("size_w", 0))
	var h: int = int(world.get("size_h", 0))
	var tiles: Array = world.get("tiles", []) as Array
	if w <= 0 or h <= 0 or tiles.is_empty():
		return PackedByteArray()

	# Paletten einsammeln (deterministisch sortiert) + sparse Ressourcenliste.
	var biome_set: Dictionary = {}
	var path_set: Dictionary = {}
	var res_list: Array = []
	for x in w:
		var col: Array = tiles[x] as Array
		for y in h:
			var td: Dictionary = col[y] as Dictionary
			biome_set[str(td.get("biome", "PLAINS"))] = true
			var p: Variant = td.get("path", null)
			if p is Dictionary and (p as Dictionary).has("type"):
				path_set[str((p as Dictionary)["type"])] = true
			var rn: Variant = td.get("resource_node", null)
			if rn is Dictionary:
				res_list.append([x, y, rn])
	var biomes: Array = biome_set.keys()
	var paths: Array = path_set.keys()
	biomes.sort()
	paths.sort()
	var biome_idx: Dictionary = {}
	for i in biomes.size(): biome_idx[biomes[i] as String] = i
	var path_idx: Dictionary = {}
	for i2 in paths.size(): path_idx[paths[i2] as String] = i2 + 1

	# meta = kompletter Spielstand ohne "world", plus Paletten + "res".
	var meta: Dictionary = data.duplicate(true)
	meta.erase("world")
	meta["biomes"] = biomes
	meta["paths"] = paths
	meta["res"] = res_list
	var meta_json: String = JSON.stringify(meta, "", false, true)
	if meta_json.is_empty():
		return PackedByteArray()

	# Terrain-Ebenen (7 Bytes pro Kachel).
	var n: int = w * h
	var plane_b := PackedByteArray(); plane_b.resize(n)
	var plane_h := PackedByteArray(); plane_h.resize(n * 2)
	var plane_w := PackedByteArray(); plane_w.resize(n * 2)
	var plane_f := PackedByteArray(); plane_f.resize(n)
	var plane_p := PackedByteArray(); plane_p.resize(n)
	for x2 in w:
		var col2: Array = tiles[x2] as Array
		for y2 in h:
			var td2: Dictionary = col2[y2] as Dictionary
			var idx: int = x2 * h + y2
			plane_b[idx] = int(biome_idx.get(str(td2.get("biome", "PLAINS")), 0))
			var hv: float = clampf(float(td2.get("height", 0.0)), 0.0, HEIGHT_MAX_M)
			plane_h.encode_u16(idx * 2, clampi(int(roundf(hv * float(HEIGHT_SCALE))), 0, 65535))
			var wv: float = clampf(float(td2.get("water_level", 0.0)), 0.0, WATER_MAX_M)
			plane_w.encode_u16(idx * 2, clampi(int(roundf(wv * float(WATER_SCALE))), 0, 65535))
			var fl: int = 0
			if bool(td2.get("ruin", false)): fl |= 1
			if bool(td2.get("is_water_source", false)): fl |= 2
			plane_f[idx] = fl
			var pd: Variant = td2.get("path", null)
			if pd is Dictionary and (pd as Dictionary).has("type"):
				plane_p[idx] = int(path_idx.get(str((pd as Dictionary)["type"]), 0))

	var meta_bytes := meta_json.to_utf8_buffer()
	var payload := PackedByteArray()
	payload.append_array(PackedByteArray([0, 0, 0, 0]))    # Platzhalter meta_len
	payload.append_array(meta_bytes)
	payload.append_array(plane_b)
	payload.append_array(plane_h)
	payload.append_array(plane_w)
	payload.append_array(plane_f)
	payload.append_array(plane_p)
	payload.encode_u32(0, meta_bytes.size())
	var comp: PackedByteArray = payload.compress(FileAccess.COMPRESSION_ZSTD)
	if comp.is_empty():
		return PackedByteArray()

	# Kopf: feste Teile, Strings, dann Offsets fuer die Zahlenwerte.
	var head := PackedByteArray()
	head.append_array(MAGIC)
	head.append_array(PackedByteArray([0, 0, 0, 0]))       # 4: fv+sv (später)
	_push_string(head, _clip(str(ProjectSettings.get_setting("application/config/version", "0"))))
	_push_string(head, _clip(str(data.get("colony_name", "Kolonie"))))
	var pos_seed: int = head.size(); head.append_array(PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	head.append_array(PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))   # w+h+day+pop (12 Bytes, spaeter)
	var pos_plen: int = head.size(); head.append_array(PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))  # plen+rawlen
	head.append_array(PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))   # Pruefsumme (8 Bytes, spaeter)
	var body_off: int = head.size()
	# Zahlenwerte eintragen:
	head.encode_u16(4, FORMAT_VERSION)
	head.encode_u16(6, int(data.get("version", SAVE_VERSION_MAX)))
	head.encode_s64(pos_seed, int(data.get("seed", 0)))
	var pos_w: int = pos_seed + 8
	var pos_h: int = pos_w + 2
	var pos_day: int = pos_h + 2
	var pos_pop: int = pos_day + 4
	head.encode_u16(pos_w, w)
	head.encode_u16(pos_h, h)
	head.encode_u32(pos_day, int(data.get("day_count", 0)))
	head.encode_u32(pos_pop, int(data.get("population_count", 0)))
	head.encode_u32(pos_plen, comp.size())
	head.encode_u32(pos_plen + 4, payload.size())
	var chk: PackedByteArray = _sha8(comp)
	for i in 8:
		head.encode_u8(body_off - 8 + i, int(chk[i]))
	head.append_array(comp)
	return head

# ── Kopf lesen (Import-Vorschau OHNE Entpacken) ──────────────────────────────
## Rueckgabe: {"err": "..."} oder Felder name/seed/w/h/day/pop/game_version/
## save_version/payload_len/raw_len/checksum/body_off.
static func read_head(buf: PackedByteArray) -> Dictionary:
	if buf.size() < 16 or buf.slice(0, 4) != MAGIC:
		return {"err": "Das ist keine Welt-Exportdatei (.fkw) von FrettchenKolonie."}
	var fv: int = buf.decode_u16(4)
	if fv > FORMAT_VERSION:
		return {"err": "Die Datei stammt von einer neueren Spielversion (Format %d > %d)." % [fv, FORMAT_VERSION]}
	if fv != FORMAT_VERSION:
		return {"err": "Unbekanntes Dateiformat (Version %d)." % fv}
	var sv: int = buf.decode_u16(6)
	if sv > SAVE_VERSION_MAX:
		return {"err": "Der Spielstand stammt von einer neueren Spielversion und kann nicht geladen werden."}
	var off: int = 8
	var s: Array = _read_string(buf, off)
	if s.is_empty(): return {"err": "Die Datei ist beschädigt (Spielversion unverlesbar)."}
	var game_version: String = s[0]; off = int(s[1])
	s = _read_string(buf, off)
	if s.is_empty(): return {"err": "Die Datei ist beschädigt (Weltname unverlesbar)."}
	var world_name: String = s[0]; off = int(s[1])
	if off + 24 > buf.size():
		return {"err": "Die Datei ist abgeschnitten (Kopf unvollständig)."}
	var seed_val: int = buf.decode_s64(off); off += 8
	var ww: int = buf.decode_u16(off); off += 2
	var hh: int = buf.decode_u16(off); off += 2
	var day: int = buf.decode_u32(off); off += 4
	var pop: int = buf.decode_u32(off); off += 4
	var plen: int = buf.decode_u32(off); off += 4
	var raw_len: int = buf.decode_u32(off); off += 4
	if raw_len > PAYLOAD_RAW_MAX:
		return {"err": "Die Datei ist zu gross zum sicheren Laden (interne Groesse unzulässig)."}
	if off + 8 > buf.size():
		return {"err": "Die Datei ist abgeschnitten (Prüfsumme fehlt)."}
	var chk: PackedByteArray = buf.slice(off, off + 8); off += 8
	return {"name": world_name, "seed": seed_val, "w": ww, "h": hh, "day": day, "pop": pop,
		"game_version": game_version, "save_version": sv, "format": fv,
		"payload_len": plen, "raw_len": raw_len, "checksum": chk, "body_off": off}

# ── Decode (ganzer Spielstand) ───────────────────────────────────────────────
## Rueckgabe: {"err": "..."} oder {"save": <Spielstand>, "head": <Kopf>}.
static func decode(buf: PackedByteArray) -> Dictionary:
	var head: Dictionary = read_head(buf)
	if head.has("err"): return head
	var off: int = int(head["body_off"])
	var plen: int = int(head["payload_len"])
	var raw_len: int = int(head["raw_len"])
	if off + plen != buf.size():
		return {"err": "Die Datei ist beschädigt (Grössenangabe passt nicht zur Dateilänge)."}
	var comp: PackedByteArray = buf.slice(off, off + plen)
	if _sha8(comp) != head["checksum"]:
		return {"err": "Prüfsumme falsch - die Datei ist beschädigt oder wurde geändert."}
	var payload: PackedByteArray = comp.decompress(raw_len, FileAccess.COMPRESSION_ZSTD)
	if payload.is_empty() or payload.size() != raw_len:
		return {"err": "Die Nutzdaten liessen sich nicht entpacken (Datei beschädigt oder zu gross)."}
	if payload.size() < 4:
		return {"err": "Die Nutzdaten sind zu klein (Datei beschädigt)."}
	var meta_len: int = payload.decode_u32(0)
	if 4 + meta_len > raw_len:
		return {"err": "Die Datei ist beschädigt (Inhaltsstruktur kaputt)."}
	var meta_json: String = payload.slice(4, 4 + meta_len).get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(meta_json)
	if not (parsed is Dictionary):
		return {"err": "Der Spielstand-Inhalt liess sich nicht lesen (Datei beschädigt)."}
	var meta: Dictionary = parsed as Dictionary
	var b: String = _type_check_blocks(meta)
	if not b.is_empty():
		return {"err": b}
	var biomes: Array = meta.get("biomes", []) as Array
	var paths: Array = meta.get("paths", []) as Array
	var res_list: Array = meta.get("res", []) as Array
	# Terrain-Ebenen lesen: b(1N) + h(2N) + w(2N) + f(1N) + p(1N) = 7N Bytes.
	var w: int = int(head["w"])
	var h: int = int(head["h"])
	var n: int = w * h
	var plane_start: int = 4 + meta_len
	if plane_start + 7 * n != raw_len:
		return {"err": "Die Terrain-Daten sind unvollständig (Datei beschädigt)."}
	var pb: PackedByteArray = payload.slice(plane_start, plane_start + n)
	var ph: PackedByteArray = payload.slice(plane_start + n, plane_start + 3 * n)
	var pw: PackedByteArray = payload.slice(plane_start + 3 * n, plane_start + 5 * n)
	var pf: PackedByteArray = payload.slice(plane_start + 5 * n, plane_start + 6 * n)
	var pp: PackedByteArray = payload.slice(plane_start + 6 * n, plane_start + 7 * n)
	# resource_node aus "res" aufbauen (sparse).
	var res_map: Dictionary = {}
	for r in res_list:
		var r0: Array = r as Array
		if r0.size() != 3: continue
		var ri: int = int(r0[0]) * h + int(r0[1])
		if ri < 0 or ri >= n: continue
		res_map[ri] = r0[2]
	var rows: Array = []
	for x3 in w:
		var idx_col: int = x3 * h
		var row: Array = []
		for y3 in h:
			var bi: int = pb[idx_col + y3]
			if bi >= biomes.size():
				return {"err": "Terrain-Datensatz unbekannt (Biom-Typ ausserhalb der Palette)."}
			var fl2: int = pf[idx_col + y3]
			var pi2: int = pp[idx_col + y3]
			var path_val: Variant = null
			if pi2 > 0:
				if pi2 > paths.size():
					return {"err": "Terrain-Datensatz unbekannt (Weg-Typ ausserhalb der Palette)."}
				path_val = {"type": str(paths[pi2 - 1])}
			var rnode: Variant = res_map.get(idx_col + y3, null)
			row.append({
				"biome": str(biomes[bi]),
				"height": float(ph.decode_u16((idx_col + y3) * 2)) / float(HEIGHT_SCALE),
				"path": path_val,
				"ruin": (fl2 & 1) != 0,
				"resource_node": rnode,
				"water_level": float(pw.decode_u16((idx_col + y3) * 2)) / float(WATER_SCALE),
				"is_water_source": (fl2 & 2) != 0,
			})
		rows.append(row)
	meta.erase("biomes"); meta.erase("paths"); meta.erase("res")
	meta["world"] = {"size_w": w, "size_h": h, "seed": int(head["seed"]), "tiles": rows}
	return {"save": meta, "head": head}

# ── Helfer ───────────────────────────────────────────────────────────────────
static func _clip(s: String) -> String:
	return s.substr(0, STRING_MAX)

static func _push_string(buf: PackedByteArray, s: String) -> void:
	var b: PackedByteArray = _clip(s).to_utf8_buffer()
	buf.append(clampi(b.size(), 0, STRING_MAX))
	buf.append_array(b)

## -> [String, naechster_offset]; bei Fehlern: []
static func _read_string(buf: PackedByteArray, off: int) -> Array:
	if off + 1 > buf.size(): return []
	var l: int = buf.decode_u8(off)
	if off + 1 + l > buf.size(): return []
	return [buf.slice(off + 1, off + 1 + l).get_string_from_utf8(), off + 1 + l]

static func _sha8(data: PackedByteArray) -> PackedByteArray:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(data)
	return h.finish().slice(0, 8)

## Prueft die Spielstand-Bloecke, deren Ladepfad starke Casts nutzt.
## Rueckgabe: "" oder deutsche Fehlermeldung.
static func _type_check_blocks(meta: Dictionary) -> String:
	var dict_fields: Array = ["resources", "population", "day_night", "drought", "season",
		"achievements", "districts", "colonies", "rail", "explore", "neighbors",
		"farm_fields", "player", "player_accessories"]
	for f in dict_fields:
		if meta.has(f) and not (meta[f] is Dictionary):
			return "Spielstand-Inhalt entspricht nicht dem erwarteten Format (Block '%s')." % str(f)
	var arr_fields: Array = ["buildings", "expeditions"]
	for f2 in arr_fields:
		if meta.has(f2) and not (meta[f2] is Array):
			return "Spielstand-Inhalt entspricht nicht dem erwarteten Format (Block '%s')." % str(f2)
	# Hinweis: JSON.parse_string liefert Zahlen als float zurueck - Block-Checks
	# akzeptieren deshalb int ODER float (wie im normalen Speicher-Lade-Pfad).
	if meta.has("version") and not (meta["version"] is int or meta["version"] is float):
		return "Spielstand-Inhalt entspricht nicht dem erwarteten Format (Block 'version')."
	if int(meta.get("version", SAVE_VERSION_MAX)) > SAVE_VERSION_MAX:
		return "Der Spielstand stammt von einer neueren Spielversion und kann nicht geladen werden."
	return ""
