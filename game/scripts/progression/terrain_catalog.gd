class_name TerrainCatalog
extends RefCounted
## Tereny wypraw. Odblokowanie wymaga części (ulepszeń) i mocy (FTP) – postęp w grze
## odzwierciedla realną formę. Każdy teren zmienia wygląd i parametry trasy.

const CANYON := "canyon"
const CITY := "city"

const ORDER: Array[String] = [CANYON, CITY]

const DEFS := {
	CANYON: {
		"name": "Kanion Rdzy",
		"desc": "Stara autostrada w czerwonym kanionie. Spokojny start.",
		"requires": {},
		"scrap_mult": 1.0,
		"fuel_every_m": 420.0,
		"row_gap_mult": 1.0,
		"encounter_gap_mult": 1.0,
	},
	CITY: {
		"name": "Martwe Miasto",
		"desc": "Ruiny przedmieść: więcej złomu i paliwa, ale gangi atakują częściej.",
		"requires": {"part": [UpgradeCatalog.ARMOR, 1], "ftp": 150},
		"scrap_mult": 1.35,
		"fuel_every_m": 300.0,
		"row_gap_mult": 0.85,
		"encounter_gap_mult": 0.7,
	},
}


static func display_name(id: String) -> String:
	return str(DEFS.get(id, DEFS[CANYON])["name"])


static func description(id: String) -> String:
	return str(DEFS.get(id, DEFS[CANYON])["desc"])


static func params(id: String) -> Dictionary:
	return DEFS.get(id, DEFS[CANYON])


## Brakujące wymagania (pusta lista = odblokowany). Teksty po polsku do menu.
static func missing_requirements(id: String, loadout: Loadout, ftp_w: float) -> Array[String]:
	var out: Array[String] = []
	var req: Dictionary = params(id).get("requires", {})
	if req.has("part"):
		var part: Array = req["part"]
		if loadout.level(str(part[0])) < int(part[1]):
			out.append("%s poz. %d" % [UpgradeCatalog.display_name(str(part[0])), int(part[1])])
	if req.has("ftp") and ftp_w < float(req["ftp"]):
		out.append("FTP ≥ %d W" % int(req["ftp"]))
	return out


static func is_unlocked(id: String, loadout: Loadout, ftp_w: float) -> bool:
	return missing_requirements(id, loadout, ftp_w).is_empty()


## Parametry terenu wpływające na generowanie trasy i walkę.
static func apply_to(id: String, sim: RunSimulation) -> void:
	var p := params(id)
	var g := sim.generator
	g.scrap_gap_easy_m /= float(p["scrap_mult"])
	g.scrap_gap_hard_m /= float(p["scrap_mult"])
	g.row_gap_easy_m *= float(p["row_gap_mult"])
	g.row_gap_hard_m *= float(p["row_gap_mult"])
	g.fuel_every_m = float(p["fuel_every_m"])
	sim.combat.encounter_gap_easy_s *= float(p["encounter_gap_mult"])
	sim.combat.encounter_gap_hard_s *= float(p["encounter_gap_mult"])
	sim.terrain = id
