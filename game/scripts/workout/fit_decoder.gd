class_name FitDecoder
extends RefCounted
## Dekoder binarnego formatu FIT (Garmin) – tylko warstwa rekordów, bez profilu wiadomości.
## Czyta: nagłówek 12/14 B (z CRC nagłówka albo bez), rekordy definicji i danych (lokalne typy
## 0–15, architektura little/big endian, pola deweloperskie pomijane), nagłówki ze skompresowanym
## znacznikiem czasu, wszystkie typy bazowe i ich wartości „nieprawidłowe” (zamieniane na null).
##
##   var dec := FitDecoder.new()
##   if dec.open(bytes):
##       while true:
##           var msg := dec.next_message()   # {"global": int, "local": int, "fields": {nr: wartość}}
##           if msg.is_empty(): break        # koniec danych albo błąd (dec.error)
##
## Wartości pól: int (typy całkowite, enum), float (float32/64), String (string), PackedByteArray
## (byte), Array (tablice), null (wartość nieprawidłowa / brak). uint64 > 2^63 wychodzi ujemny.
## Błędy struktury (ucięty plik, rekord bez definicji) przerywają odczyt i ustawiają error.
## Niezgodne CRC to tylko ostrzeżenie (patrz verify_file_crc i docs/plany-treningowe.md).

const BASE_ENUM := 0x00
const BASE_SINT8 := 0x01
const BASE_UINT8 := 0x02
const BASE_SINT16 := 0x83
const BASE_UINT16 := 0x84
const BASE_SINT32 := 0x85
const BASE_UINT32 := 0x86
const BASE_STRING := 0x07
const BASE_FLOAT32 := 0x88
const BASE_FLOAT64 := 0x89
const BASE_UINT8Z := 0x0A
const BASE_UINT16Z := 0x8B
const BASE_UINT32Z := 0x8C
const BASE_BYTE := 0x0D
const BASE_SINT64 := 0x8E
const BASE_UINT64 := 0x8F
const BASE_UINT64Z := 0x90

## Numer pola znacznika czasu (wspólny dla wszystkich wiadomości).
const FIELD_TIMESTAMP := 253
const MAX_FILE_BYTES := 4 * 1024 * 1024

# Tablice po numerze typu bazowego (bity 0–4 bajtu typu): rozmiar, czy ze znakiem,
# surowa wartość nieprawidłowa (dla 64-bitowych 0xFFFF... = -1 jako int64).
const _BASE_SIZE: Array[int] = [1, 1, 1, 2, 2, 4, 4, 1, 4, 8, 1, 2, 4, 1, 8, 8, 8]
const _BASE_SIGNED: Array[bool] = [false, true, false, true, false, true, false, false, false, false, false, false, false, false, true, false, false]
const _BASE_INVALID: Array[int] = [0xFF, 0x7F, 0xFF, 0x7FFF, 0xFFFF, 0x7FFFFFFF, 0xFFFFFFFF, 0, 0xFFFFFFFF, -1, 0, 0, 0, 0xFF, 0x7FFFFFFFFFFFFFFF, -1, 0]
const _NUM_STRING := 7
const _NUM_FLOAT32 := 8
const _NUM_FLOAT64 := 9
const _NUM_BYTE := 13

var error := ""
var warnings: Array[String] = []
var header_size := 0
var protocol_version := 0
var profile_version := 0
var data_size := 0
## "ok", "brak" (nagłówek 12 B albo CRC = 0) albo "błędne".
var header_crc_status := ""
## Pozycja sumy kontrolnej pliku (= koniec rekordów danych).
var data_end := 0

var _bytes := PackedByteArray()
var _pos := 0
var _defs := {}
var _last_timestamp := -1
var _warned := {}

static var _crc_table := PackedInt32Array()


## Sprawdza nagłówek i przygotowuje odczyt rekordów. false = błąd (opis w error).
func open(bytes: PackedByteArray) -> bool:
	_bytes = bytes
	_pos = 0
	_defs.clear()
	_last_timestamp = -1
	error = ""
	warnings.clear()
	_warned.clear()
	var size := bytes.size()
	if size > MAX_FILE_BYTES:
		return _fail("Plik FIT jest za duży jak na plan treningowy (%d kB)." % roundi(size / 1024.0))
	if size < 12:
		return _fail("Plik FIT jest za krótki (%d B) – to nie jest poprawny plik FIT." % size)
	header_size = bytes[0]
	if bytes.slice(8, 12).get_string_from_ascii() != ".FIT":
		return _fail("Brak sygnatury „.FIT” w nagłówku – to nie jest plik FIT.")
	if header_size < 12:
		return _fail("Nieprawidłowy rozmiar nagłówka FIT (%d B)." % header_size)
	if header_size > size:
		return _fail("Plik FIT jest ucięty (niepełny nagłówek).")
	protocol_version = bytes[1]
	profile_version = bytes.decode_u16(2)
	data_size = bytes.decode_u32(4)
	if protocol_version >> 4 > 2:
		_warn("Nowsza wersja protokołu FIT (%d.%d) – próbuję odczytać." % [protocol_version >> 4, protocol_version & 0x0F])
	header_crc_status = "brak"
	if header_size >= 14:
		var stored := bytes.decode_u16(12)
		if stored != 0:
			header_crc_status = "ok" if crc16(bytes, 0, 12) == stored else "błędne"
			if header_crc_status != "ok":
				_warn("Suma kontrolna nagłówka FIT się nie zgadza.")
	data_end = header_size + data_size
	if data_size == 0 and size > header_size + 2:
		# Plik zapisany strumieniowo bez uzupełnienia rozmiaru w nagłówku.
		data_end = size - 2
		_warn("Nagłówek FIT nie podaje rozmiaru danych – czytam do końca pliku.")
	if data_end > size:
		return _fail("Plik FIT jest ucięty (brakuje %d B danych)." % (data_end - size))
	if data_end + 2 > size:
		_warn("Brak sumy kontrolnej na końcu pliku FIT.")
	elif data_end + 2 < size:
		_warn("Za końcem danych FIT są dodatkowe bajty (%d B) – pominięte." % (size - data_end - 2))
	_pos = header_size
	return true


func at_end() -> bool:
	return error != "" or _pos >= data_end


## Następna wiadomość danych albo {} na końcu danych / przy błędzie (sprawdź error).
func next_message() -> Dictionary:
	while error == "" and _pos < data_end:
		var h := _bytes[_pos]
		_pos += 1
		if h & 0x80:
			# Nagłówek ze skompresowanym znacznikiem czasu: typ lokalny 0–3, przesunięcie 0–31 s.
			var local := (h >> 5) & 0x03
			if not _defs.has(local):
				_fail("Rekord danych FIT dla niezdefiniowanego typu lokalnego %d (bajt %d)." % [local, _pos - 1])
				return {}
			var msg := _read_data(_defs[local], local)
			if msg.is_empty():
				return {}
			var offset := h & 0x1F
			if _last_timestamp >= 0:
				var ts := (_last_timestamp & ~0x1F) + offset
				if offset < (_last_timestamp & 0x1F):
					ts += 0x20
				_last_timestamp = ts
				msg["fields"][FIELD_TIMESTAMP] = ts
			else:
				_warn_once("ts", "Skompresowany znacznik czasu bez wcześniejszego pełnego znacznika – pominięty.")
			msg["compressed_timestamp"] = true
			return msg
		if h & 0x40:
			if not _read_definition(h):
				return {}
			continue
		var local_type := h & 0x0F
		if not _defs.has(local_type):
			_fail("Rekord danych FIT dla niezdefiniowanego typu lokalnego %d (bajt %d)." % [local_type, _pos - 1])
			return {}
		var data := _read_data(_defs[local_type], local_type)
		if data.is_empty():
			return {}
		var stamp: Variant = data["fields"].get(FIELD_TIMESTAMP)
		if stamp is int:
			_last_timestamp = stamp
		return data
	return {}


## Wszystkie wiadomości naraz (wygodne w testach). {"messages": Array, "error": String, "warnings": Array[String]}
static func decode_all(bytes: PackedByteArray) -> Dictionary:
	var dec := FitDecoder.new()
	var messages: Array[Dictionary] = []
	if dec.open(bytes):
		while true:
			var msg := dec.next_message()
			if msg.is_empty():
				break
			messages.append(msg)
		if dec.error == "":
			dec.verify_file_crc()
	return {"messages": messages, "error": dec.error, "warnings": dec.warnings.duplicate()}


## Sprawdza CRC całego pliku (nagłówek + dane). Niezgodność -> ostrzeżenie, nie błąd:
## struktura rekordów i tak jest weryfikowana bajt po bajcie, a plan sprawdzamy później.
func verify_file_crc() -> bool:
	if data_end + 2 > _bytes.size():
		return false
	var ok := crc16(_bytes, 0, data_end) == _bytes.decode_u16(data_end)
	if not ok:
		_warn("Suma kontrolna pliku FIT się nie zgadza – plik mógł zostać uszkodzony, sprawdź plan.")
	return ok


## CRC-16 z FIT SDK (wielomian 0x8005 odbity = 0xA001, start 0) dla bajtów [from, to).
static func crc16(bytes: PackedByteArray, from: int = 0, to: int = -1) -> int:
	if _crc_table.is_empty():
		_crc_table.resize(256)
		for i in 256:
			var c := i
			for k in 8:
				c = (c >> 1) ^ 0xA001 if c & 1 else c >> 1
			_crc_table[i] = c
	var end := bytes.size() if to < 0 else mini(to, bytes.size())
	var crc := 0
	for i in range(maxi(from, 0), end):
		crc = (crc >> 8) ^ _crc_table[(crc ^ bytes[i]) & 0xFF]
	return crc


## Poprawne UTF-8 (bez „nadmiarowych” kodowań i surogatów). Dzięki temu nie wołamy
## get_string_from_utf8 na śmieciach (Godot wypisałby błędy do logu).
static func is_valid_utf8(bytes: PackedByteArray) -> bool:
	var i := 0
	var n := bytes.size()
	while i < n:
		var b := bytes[i]
		var extra := 0
		var min_code := 0
		if b < 0x80:
			i += 1
			continue
		elif b >= 0xC2 and b <= 0xDF:
			extra = 1
			min_code = 0x80
		elif b >= 0xE0 and b <= 0xEF:
			extra = 2
			min_code = 0x800
		elif b >= 0xF0 and b <= 0xF4:
			extra = 3
			min_code = 0x10000
		else:
			return false
		if i + extra >= n:
			return false
		var code := b & (0x3F >> extra)
		for k in range(1, extra + 1):
			var c := bytes[i + k]
			if c & 0xC0 != 0x80:
				return false
			code = (code << 6) | (c & 0x3F)
		if code < min_code or code > 0x10FFFF or (code >= 0xD800 and code <= 0xDFFF):
			return false
		i += extra + 1
	return true


func _fail(message: String) -> bool:
	if error == "":
		error = message
	return false


func _warn(message: String) -> void:
	warnings.append(message)


func _warn_once(key: String, message: String) -> void:
	if not _warned.has(key):
		_warned[key] = true
		_warn(message)


func _read_definition(h: int) -> bool:
	var local := h & 0x0F
	var has_dev := (h & 0x20) != 0
	if _pos + 5 > data_end:
		return _fail("Plik FIT jest ucięty (niepełny rekord definicji).")
	var arch := _bytes[_pos + 1]
	if arch > 1:
		return _fail("Uszkodzony rekord definicji FIT (architektura %d, bajt %d)." % [arch, _pos + 1])
	var big := arch == 1
	var global_num := _read_uint(_pos + 2, 2, big)
	var field_count := _bytes[_pos + 4]
	_pos += 5
	if _pos + field_count * 3 > data_end:
		return _fail("Plik FIT jest ucięty (niepełna lista pól definicji).")
	var fields: Array[PackedInt32Array] = []
	var total := 0
	for i in field_count:
		var num := _bytes[_pos]
		var size := _bytes[_pos + 1]
		var base_byte := _bytes[_pos + 2]
		_pos += 3
		var base_num := base_byte & 0x1F
		if base_num >= _BASE_SIZE.size():
			_warn_once("base", "Nieznany typ bazowy FIT (0x%02X) – pole czytane jako bajty." % base_byte)
			base_num = _NUM_BYTE
		elif size % _BASE_SIZE[base_num] != 0:
			_warn_once("size", "Rozmiar pola FIT niezgodny z typem – pole czytane jako bajty.")
			base_num = _NUM_BYTE
		fields.append(PackedInt32Array([num, size, base_num]))
		total += size
	var dev_size := 0
	if has_dev:
		if _pos + 1 > data_end:
			return _fail("Plik FIT jest ucięty (niepełna definicja pól deweloperskich).")
		var dev_count := _bytes[_pos]
		_pos += 1
		if _pos + dev_count * 3 > data_end:
			return _fail("Plik FIT jest ucięty (niepełna definicja pól deweloperskich).")
		for i in dev_count:
			dev_size += _bytes[_pos + 1]
			_pos += 3
	_defs[local] = {"global": global_num, "big": big, "fields": fields, "size": total + dev_size, "dev_size": dev_size}
	return true


func _read_data(def: Dictionary, local: int) -> Dictionary:
	var record_size: int = def["size"]
	if _pos + record_size > data_end:
		_fail("Plik FIT jest ucięty (niepełny rekord danych wiadomości %d)." % def["global"])
		return {}
	var big: bool = def["big"]
	var values := {}
	for f: PackedInt32Array in def["fields"]:
		values[f[0]] = _decode_field(_pos, f[1], f[2], big)
		_pos += f[1]
	# Pola deweloperskie (Connect IQ) pomijamy – ich rozmiar znamy z definicji.
	_pos += int(def["dev_size"])
	return {"global": def["global"], "local": local, "fields": values}


func _decode_field(offset: int, size: int, base_num: int, big: bool) -> Variant:
	if size == 0:
		return null
	if base_num == _NUM_STRING:
		var raw := _bytes.slice(offset, offset + size)
		var zero := raw.find(0)
		if zero >= 0:
			raw = raw.slice(0, zero)
		if raw.is_empty():
			return null
		if not is_valid_utf8(raw):
			_warn_once("utf8", "Tekst w pliku FIT nie jest poprawnym UTF-8 – pominięto niepoprawne znaki.")
			return raw.get_string_from_ascii()
		return raw.get_string_from_utf8()
	if base_num == _NUM_BYTE:
		var raw_bytes := _bytes.slice(offset, offset + size)
		for b in raw_bytes:
			if b != 0xFF:
				return raw_bytes
		return null
	var element := _BASE_SIZE[base_num]
	var count := floori(float(size) / element)
	if count == 1:
		return _decode_scalar(offset, element, base_num, big)
	var items: Array = []
	var any_valid := false
	for i in count:
		var v: Variant = _decode_scalar(offset + i * element, element, base_num, big)
		any_valid = any_valid or v != null
		items.append(v)
	return items if any_valid else null


func _decode_scalar(offset: int, size: int, base_num: int, big: bool) -> Variant:
	var raw := _read_uint(offset, size, big)
	if raw == _BASE_INVALID[base_num]:
		return null
	if base_num == _NUM_FLOAT32 or base_num == _NUM_FLOAT64:
		var buf := PackedByteArray()
		buf.resize(8)
		buf.encode_s64(0, raw)
		return buf.decode_float(0) if base_num == _NUM_FLOAT32 else buf.decode_double(0)
	if _BASE_SIGNED[base_num] and size < 8 and raw >= 1 << (size * 8 - 1):
		raw -= 1 << (size * 8)
	return raw


## Liczba bez znaku z size bajtów (dla 8 bajtów wynik może być ujemny – zawinięcie int64).
func _read_uint(offset: int, size: int, big: bool) -> int:
	var v := 0
	if big:
		for i in size:
			v = (v << 8) | _bytes[offset + i]
	else:
		for i in range(size - 1, -1, -1):
			v = (v << 8) | _bytes[offset + i]
	return v
