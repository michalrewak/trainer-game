class_name FitWriter
extends RefCounted
## Prosty koder plików FIT do testów i generowania fixture'ów (game/tests/fixtures/workouts/).
## Zapisuje rekordy definicji i danych (little/big endian, pola deweloperskie, nagłówek ze
## skompresowanym znacznikiem czasu), nagłówek 12 albo 14 B i sumy kontrolne CRC-16.
## CRC liczone wariantem „nibble” z FIT SDK – niezależnie od tablicy bajtowej w FitDecoder,
## więc testy porównują dwie różne implementacje.
##
##   var w := FitWriter.new()
##   w.define(0, 0, [[0, 1, FitDecoder.BASE_ENUM], [4, 4, FitDecoder.BASE_UINT32]])  # file_id
##   w.write(0, [5, 1_100_000_000])
##   var bytes := w.to_bytes()

const BASE_SIZES := {
	0x00: 1, 0x01: 1, 0x02: 1, 0x83: 2, 0x84: 2, 0x85: 4, 0x86: 4, 0x07: 1, 0x88: 4,
	0x89: 8, 0x0A: 1, 0x8B: 2, 0x8C: 4, 0x0D: 1, 0x8E: 8, 0x8F: 8, 0x90: 8,
}
const INVALID := {
	0x00: 0xFF, 0x01: 0x7F, 0x02: 0xFF, 0x83: 0x7FFF, 0x84: 0xFFFF, 0x85: 0x7FFFFFFF,
	0x86: 0xFFFFFFFF, 0x07: 0, 0x88: 0xFFFFFFFF, 0x89: -1, 0x0A: 0, 0x8B: 0, 0x8C: 0,
	0x0D: 0xFF, 0x8E: 0x7FFFFFFFFFFFFFFF, 0x8F: -1, 0x90: 0,
}
const _CRC_NIBBLES: Array[int] = [
	0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
	0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
]

var _records := PackedByteArray()
var _defs := {}


## Rekord definicji. fields: [[numer_pola, rozmiar_B, typ_bazowy], ...];
## dev_fields: [[numer, rozmiar_B, indeks_dewelopera], ...] (ustawia flagę pól deweloperskich).
func define(local: int, global_num: int, fields: Array, big_endian: bool = false, dev_fields: Array = []) -> FitWriter:
	var header := 0x40 | (local & 0x0F)
	if not dev_fields.is_empty():
		header |= 0x20
	_records.append(header)
	_records.append(0)
	_records.append(1 if big_endian else 0)
	append_uint(_records, global_num, 2, big_endian)
	_records.append(fields.size())
	for f: Array in fields:
		_records.append(int(f[0]))
		_records.append(int(f[1]))
		_records.append(int(f[2]))
	var dev_size := 0
	if not dev_fields.is_empty():
		_records.append(dev_fields.size())
		for d: Array in dev_fields:
			_records.append(int(d[0]))
			_records.append(int(d[1]))
			_records.append(int(d[2]))
			dev_size += int(d[1])
	_defs[local] = {"fields": fields, "big": big_endian, "dev_size": dev_size}
	return self


## Rekord danych z wartościami w kolejności pól definicji (null = wartość nieprawidłowa).
func write(local: int, values: Array, dev_bytes: PackedByteArray = PackedByteArray()) -> FitWriter:
	_records.append(local & 0x0F)
	_write_values(local, values, dev_bytes)
	return self


## Rekord danych z nagłówkiem skompresowanego znacznika czasu (typ lokalny 0–3, przesunięcie 0–31 s).
func write_compressed(local: int, time_offset: int, values: Array, dev_bytes: PackedByteArray = PackedByteArray()) -> FitWriter:
	_records.append(0x80 | ((local & 0x03) << 5) | (time_offset & 0x1F))
	_write_values(local, values, dev_bytes)
	return self


## Dowolne bajty w strumieniu rekordów (do testów uszkodzonych plików).
func write_raw(bytes: PackedByteArray) -> FitWriter:
	_records.append_array(bytes)
	return self


func records() -> PackedByteArray:
	return _records.duplicate()


## Gotowy plik. Opcje: header_size (12/14, domyślnie 14), header_crc ("ok" | "zero" | "bad"),
## file_crc ("ok" | "bad" | "none"), protocol (0x20), profile (2132), data_size (nadpisanie pola).
func to_bytes(opts: Dictionary = {}) -> PackedByteArray:
	var header_size: int = opts.get("header_size", 14)
	var out := PackedByteArray()
	out.append(header_size)
	out.append(int(opts.get("protocol", 0x20)))
	append_uint(out, int(opts.get("profile", 2132)), 2, false)
	append_uint(out, int(opts.get("data_size", _records.size())), 4, false)
	out.append_array(".FIT".to_ascii_buffer())
	if header_size >= 14:
		var mode: String = opts.get("header_crc", "ok")
		var crc := crc16(out)
		if mode == "zero":
			crc = 0
		elif mode == "bad":
			crc ^= 0xFFFF
		append_uint(out, crc, 2, false)
		while out.size() < header_size:
			out.append(0)
	out.append_array(_records)
	var file_mode: String = opts.get("file_crc", "ok")
	if file_mode != "none":
		var file_crc := crc16(out)
		if file_mode == "bad":
			file_crc ^= 0x5A5A
		append_uint(out, file_crc, 2, false)
	return out


## CRC-16 wariantem z FIT SDK (dwie połówki bajtu przez 16-elementową tablicę).
static func crc16(bytes: PackedByteArray) -> int:
	var crc := 0
	for b in bytes:
		var tmp := _CRC_NIBBLES[crc & 0xF]
		crc = (crc >> 4) & 0x0FFF
		crc = crc ^ tmp ^ _CRC_NIBBLES[b & 0xF]
		tmp = _CRC_NIBBLES[crc & 0xF]
		crc = (crc >> 4) & 0x0FFF
		crc = crc ^ tmp ^ _CRC_NIBBLES[(b >> 4) & 0xF]
	return crc


static func append_uint(out: PackedByteArray, value: int, size: int, big_endian: bool) -> void:
	for i in size:
		var shift := 8 * (size - 1 - i) if big_endian else 8 * i
		out.append((value >> shift) & 0xFF)


## Rozmiar pola tekstowego mieszczący najdłuższy z tekstów (UTF-8 + bajt zerowy).
static func string_size(texts: Array) -> int:
	var size := 1
	for t: Variant in texts:
		if t is String:
			size = maxi(size, (t as String).to_utf8_buffer().size() + 1)
	return mini(size, 255)


func _write_values(local: int, values: Array, dev_bytes: PackedByteArray) -> void:
	var def: Dictionary = _defs[local]
	var fields: Array = def["fields"]
	var big: bool = def["big"]
	for i in fields.size():
		var f: Array = fields[i]
		_encode(_records, values[i] if i < values.size() else null, int(f[1]), int(f[2]), big)
	var dev_size: int = def["dev_size"]
	for i in dev_size:
		_records.append(dev_bytes[i] if i < dev_bytes.size() else 0xFF)


func _encode(out: PackedByteArray, value: Variant, size: int, base: int, big: bool) -> void:
	if base == FitDecoder.BASE_STRING:
		var text := PackedByteArray() if value == null else str(value).to_utf8_buffer()
		text = text.slice(0, maxi(0, size - 1))
		for i in size:
			out.append(text[i] if i < text.size() else 0)
		return
	if base == FitDecoder.BASE_BYTE or not BASE_SIZES.has(base):
		var raw: PackedByteArray = value if value is PackedByteArray else PackedByteArray()
		for i in size:
			out.append(raw[i] if i < raw.size() else 0xFF)
		return
	var element: int = BASE_SIZES[base]
	var count := floori(float(size) / element)
	for i in count:
		var item: Variant = null
		if value is Array:
			item = (value as Array)[i] if i < (value as Array).size() else null
		elif i == 0:
			item = value
		_encode_scalar(out, item, element, base, big)


func _encode_scalar(out: PackedByteArray, value: Variant, size: int, base: int, big: bool) -> void:
	var raw: int = INVALID[base]
	if value != null:
		var tmp := PackedByteArray()
		tmp.resize(8)
		if base == FitDecoder.BASE_FLOAT32:
			tmp.encode_float(0, float(value))
			raw = tmp.decode_u32(0)
		elif base == FitDecoder.BASE_FLOAT64:
			tmp.encode_double(0, float(value))
			raw = tmp.decode_s64(0)
		else:
			raw = int(value)
	append_uint(out, raw, size, big)
