# Modele Kenney (CC0)

Modele low-poly z paczek [Kenney](https://www.kenney.nl) na licencji **CC0 1.0**
(domena publiczna: wolno używać, zmieniać i rozpowszechniać, także komercyjnie, bez
zgody i bez obowiązku podawania autora). Kredyt „Kenney (www.kenney.nl)” jest mile
widziany, ale nie wymagany. Oryginalny tekst licencji leży w `<paczka>/License.txt`.

Gra używa ich przez `scripts/view/kenney_models.gd` (klasa `KenneyModels`), która
przefarbowuje je na paletę pustkowia. Gdy pliku brakuje, funkcje zwracają `null`,
a gra rysuje prymitywy (WreckFactory / TrackView / BuggyView).
Podgląd wszystkich modeli: `godot --path game res://tools/preview_assets.tscn`.

## Źródło

Statyczne kopie wgrane na OpenGameArt przez konto Kenney (nie z kenney.nl, który
celowo blokuje automatyczne pobieranie). Pobrane 2026-11-15.

| Paczka | Wersja (License.txt) | Plik | Rozmiar [B] | SHA-256 |
|---|---|---|---|---|
| Car Kit | 3.1 (02-04-2026) | https://opengameart.org/sites/default/files/kenney_car-kit_3.1.zip | 4 814 237 | `fac7dacac5c7874348cf19729af3ef205f3d366493edaf0a827d93f4fdf3d0c4` |
| Survival Kit | 2.0 (03-04-2024) | https://opengameart.org/sites/default/files/kenney_survival-kit.zip | 1 948 174 | `c3586341b5932c87eb43d75d915434f47daed168b17ed36a03e8ca9977c7443e` |
| Modular Cave Kit | 1.0 (10-07-2026) | https://opengameart.org/sites/default/files/kenney_modular-cave-kit_1.0.zip | 7 025 078 | `48f37a6d4f241124cd7da17da1c6d4ed1bf1820bb149dcb233fbd5ebdd8ba996` |
| Factory Kit | 3.0 (01-05-2026) | https://opengameart.org/sites/default/files/kenney_factory-kit_3.0.zip | 4 511 890 | `7e31fb2308e90304672bd15cd18fa9d9f02c03731a8cbc57a8e3e1c181dfb0a7` |

## Co skopiowano

Tylko używane modele z `Models/GLB format/` (bez FBX/OBJ i podglądów), ich
`Textures/colormap.png` oraz `License.txt`:

- `car-kit/` – wraki: sedan, sedan-sports, suv, van, truck, truck-flat, taxi, police,
  hatchback-sports; buggy: wheel-tractor-back (koło), kart-oozi (kierowca – używamy
  tylko węzła `character`), debris-plate-a / -b / -small-a (pancerz).
- `survival-kit/` – barrel, barrel-open, rock-sand-a/b/c, signpost, signpost-single,
  metal-panel, metal-panel-screws, metal-panel-narrow, structure-metal-roof, tent-canvas.
- `cave-kit/` – template-wall, template-wall-detail-a, template-wall-half (ściany
  kanionu), template-detail (skalne słupy).
- `factory-kit/` – cog-a … cog-e (złom).

## Import w Godot

- GLB-y nie mają osadzonych obrazów – odwołują się do `Textures/colormap.png` (URI),
  więc folder `Textures/` musi leżeć obok plików `.glb`. Dzięki temu import nie
  „wyciąga” dodatkowych PNG.
- `*.glb.import`: `meshes/generate_lods=false` (proste siatki low-poly, bez
  przeskakiwania LOD); reszta domyślna. Materiały z importu i tak są nadpisywane
  w `KenneyModels` (`material_override`).
- `Textures/colormap.png.import`: bezstratnie, z mipmapami, `detect_3d/compress_to=0`
  (edytor nie przestawi tekstury na kompresję VRAM przy pierwszym użyciu w 3D).
- Nowy model: skopiuj `.glb` do folderu paczki, uruchom
  `godot --headless --path game --import`, w powstałym `.glb.import` ustaw
  `meshes/generate_lods=false`, usuń `game/.godot/imported` (wymusza ponowny import)
  i zaimportuj jeszcze raz. Commituj `.glb` razem z `.glb.import`.

## Przefarbowanie

`KenneyModels.material(paczka, styl)` tworzy wspólny `StandardMaterial3D` na paczkę
i styl: kolormapa paczki odbarwiona i przyciemniona `Image.adjust_bcs` (raz, przy
pierwszym użyciu), przemnożona przez odcień (`rust`, `burnt`, `faded`, `dust`,
`buggy`, `rider`, `rock`, `canvas`, `canyon_a/b/c`), szorstkość 0,85–0,97, bez
metaliczności. Złom ma osobny materiał świecący w kolorach `Palette.SCRAP_GLOW` /
`Palette.SCRAP_BIG_GLOW`.
