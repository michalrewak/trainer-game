class_name Palette
extends RefCounted
## Wspólna paleta świata i UI oraz fabryka materiałów. Wszystkie materiały świata używają
## shadera world.gdshader: kolor z palety × tekstura trójplanarna (zdjęcia CC0) i wyginanie
## trasy (zakręty, wzniesienia). Jedno źródło kolorów – spójny wygląd całej gry.

## Rodzaj powierzchni = która tekstura detalu i jak mocno.
enum Kind { WORN, SAND, ROCK, ROAD, PLAIN }

# Świat
const SAND := Color("d98a48")
const SAND_DARK := Color("b56a34")
const ROAD := Color("6a5a50")
const ROAD_CRACK := Color("3a322d")
const LANE_PAINT := Color("d8c9a8")
const ROCK_A := Color("b4532c")
const ROCK_B := Color("c9683a")
const ROCK_C := Color("96432a")
const ROCK_D := Color("d27e4c")
const RUST := Color("7a3f26")
const RUST_LIGHT := Color("9a5632")
const METAL_DARK := Color("3a3532")
const METAL := Color("7a726a")
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

const TEX_DIR := "res://assets/textures/"
## Kind -> [plik bez sufiksu, powtórzeń na metr, siła detalu, wzmocnienie jasności, siła normalnych]
const DETAIL := {
	Kind.WORN: ["rusty_metal_02", 0.45, 0.75, 2.6, 0.7],
	Kind.SAND: ["sand_01", 0.2, 1.0, 1.9, 1.0],
	Kind.ROCK: ["rock_face_03", 0.1, 1.0, 2.4, 1.3],
	Kind.ROAD: ["asphalt_03", 0.2, 1.0, 3.2, 1.0],
}

static var _materials: Dictionary = {}
static var _shader: Shader
static var _shader_double: Shader
static var _shader_alpha: Shader
static var _textures: Dictionary = {}


## Matowy materiał o danym kolorze (cache – wiele obiektów dzieli jeden materiał).
static func mat(color: Color, roughness: float = 0.92, metallic: float = 0.0, kind: Kind = Kind.WORN) -> ShaderMaterial:
	var key := "%s|%.2f|%.2f|%d" % [color.to_html(), roughness, metallic, kind]
	if _materials.has(key):
		return _materials[key]
	var m := _new_material(kind, false)
	m.set_shader_parameter("tint", color)
	m.set_shader_parameter("roughness", roughness)
	m.set_shader_parameter("metallic", metallic)
	_materials[key] = m
	return m


static func sand(color: Color = SAND, dunes: float = 0.0) -> ShaderMaterial:
	var key := "sand|%s|%.2f" % [color.to_html(), dunes]
	if _materials.has(key):
		return _materials[key]
	var m := mat(color, 0.95, 0.0, Kind.SAND).duplicate() as ShaderMaterial
	m.set_shader_parameter("dune_amount", dunes)
	_materials[key] = m
	return m


static func rock(color: Color) -> ShaderMaterial:
	return mat(color, 0.95, 0.0, Kind.ROCK)


static func road(color: Color = ROAD) -> ShaderMaterial:
	return mat(color, 0.9, 0.0, Kind.ROAD)


## Materiał świecący (złom, generator, pociski) – czytelny z daleka i w nocy.
static func glow(color: Color, energy: float = 2.0) -> ShaderMaterial:
	var key := "glow|%s|%.2f" % [color.to_html(), energy]
	if _materials.has(key):
		return _materials[key]
	var m := _new_material(Kind.PLAIN, false)
	m.set_shader_parameter("tint", color)
	m.set_shader_parameter("roughness", 0.4)
	m.set_shader_parameter("emission", color)
	m.set_shader_parameter("emission_energy", energy)
	_materials[key] = m
	return m


static func set_glow_energy(m: ShaderMaterial, energy: float) -> void:
	m.set_shader_parameter("emission_energy", energy)


## Materiał z teksturą UV (modele Kenney): kolormapa × odcień × brud.
static func textured(texture: Texture2D, tint: Color, roughness: float, double_sided: bool, detail_strength: float = 0.6) -> ShaderMaterial:
	var m := _new_material(Kind.WORN, double_sided)
	m.set_shader_parameter("uv_tex", texture)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("roughness", roughness)
	m.set_shader_parameter("detail_strength", detail_strength)
	return m


## Półprzezroczysty, nieoświetlony materiał wyginany z trasą (słupy światła).
static func translucent(color: Color) -> ShaderMaterial:
	if _shader_alpha == null:
		_shader_alpha = load("res://shaders/world_alpha.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _shader_alpha
	m.set_shader_parameter("color", color)
	return m


static func _new_material(kind: Kind, double_sided: bool) -> ShaderMaterial:
	if _shader == null:
		_shader = load("res://shaders/world.gdshader")
		_shader_double = load("res://shaders/world_double.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _shader_double if double_sided else _shader
	if DETAIL.has(kind):
		var d: Array = DETAIL[kind]
		var diff := _texture(str(d[0]) + "_diff_1k.jpg")
		var nor := _texture(str(d[0]) + "_nor_gl_1k.jpg")
		if diff != null:
			m.set_shader_parameter("detail_tex", diff)
			m.set_shader_parameter("detail_scale", float(d[1]))
			m.set_shader_parameter("detail_strength", float(d[2]))
			m.set_shader_parameter("detail_gain", float(d[3]))
		else:
			m.set_shader_parameter("detail_strength", 0.0)
		if nor != null:
			m.set_shader_parameter("detail_nor", nor)
			m.set_shader_parameter("normal_strength", float(d[4]))
		else:
			m.set_shader_parameter("normal_strength", 0.0)
	else:
		m.set_shader_parameter("detail_strength", 0.0)
		m.set_shader_parameter("normal_strength", 0.0)
	return m


static func _texture(file: String) -> Texture2D:
	if _textures.has(file):
		return _textures[file]
	var path := TEX_DIR + file
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_textures[file] = tex
	return tex
