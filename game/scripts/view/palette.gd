class_name Palette
extends RefCounted
## Wspólna paleta świata (pustynia po apokalipsie) i UI. Jedno źródło kolorów,
## żeby prymitywy i modele z paczek wyglądały spójnie.

# Świat
const SAND := Color("c98b56")
const SAND_DARK := Color("a86e43")
const ROAD := Color("4a403a")
const ROAD_CRACK := Color("3a322d")
const LANE_PAINT := Color("d8c9a8")
const ROCK_A := Color("a4512f")
const ROCK_B := Color("b8673a")
const ROCK_C := Color("8c4428")
const ROCK_D := Color("c27b4a")
const RUST := Color("6b3a26")
const RUST_LIGHT := Color("8a4f33")
const METAL_DARK := Color("3a3532")
const METAL := Color("6f6862")
const PAINT_TEAL := Color("4f7c7a")
const PAINT_MUSTARD := Color("b8913a")
const PAINT_RED := Color("8e3b30")
const BUGGY_FRAME := Color("2e2c2b")
const BUGGY_ACCENT := Color("f2a13a")
const TIRE := Color("1d1b1a")
const SCRAP_GLOW := Color("38e0d0")
const SCRAP_BIG_GLOW := Color("7cf5ff")
const GENERATOR_GLOW := Color("ff9a3c")
const FOG := Color("d9a877")
const SKY_TOP := Color("5d84a0")
const SKY_HORIZON := Color("eab57f")
const SUN := Color("ffe8c8")

# UI (OLED: zamiast czystej bieli lekko złamana biel – mniejsze ryzyko wypalenia)
const UI_TEXT := Color("ede6da")
const UI_DIM := Color("b9ae9d")
const UI_ACCENT := Color("ffb238")
const UI_SCRAP := Color("5ff0e0")
const UI_BAD := Color("ff5a4a")
const UI_GOOD := Color("8ee07a")
const UI_PANEL := Color(0.05, 0.04, 0.035, 0.55)
const UI_PANEL_STRONG := Color(0.05, 0.04, 0.035, 0.82)

static var _materials: Dictionary = {}


## Matowy materiał o danym kolorze (cache – wiele obiektów dzieli jeden materiał).
static func mat(color: Color, roughness: float = 0.92, metallic: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f" % [color.to_html(), roughness, metallic]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	_materials[key] = m
	return m


## Materiał świecący (złom, generator) – czytelny z daleka.
static func glow(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var key := "glow|%s|%.2f" % [color.to_html(), energy]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.4
	_materials[key] = m
	return m
