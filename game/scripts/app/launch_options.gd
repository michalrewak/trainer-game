class_name LaunchOptions
extends RefCounted
## Opcje uruchomienia przekazywane po "--", np.:
##   Godot.exe --path game -- --minutes=2 --autostart
## Dostępne:
##   --minutes=N        długość wyprawy w minutach (domyślnie 15)
##   --test             skrót dla --minutes=2
##   --autostart        od razu startuj wyprawę (bez menu)
##   --autopilot        jazda automatyczna (moc ze skryptu, omijanie wraków) – testy/demo
##   --time-scale=K     przyspieszenie czasu gry (testy dymne)
##   --seed=N           stałe ziarno trasy
##   --quit-on-finish   zamknij grę po zapisaniu wyniku (testy dymne)
##   --save=ŚCIEŻKA     inny plik postępu (np. user://smoke.json)
##   --screenshots=KAT  zapisuj zrzuty ekranu do katalogu (tylko z renderowaniem)
##   --shot-times=a,b   sekundy wyprawy, w których robić zrzuty (domyślnie 4,12)
##   --combat-test      pierwsza potyczka z gangiem już po 6 s (testy walki)
##   --no-combat        wyprawa bez gangów
##   --trainer          moc z trenażera przez mostek (ws://127.0.0.1:8765, etap 5)
##   --plan=ŚCIEŻKA     trening z planu (np. res://plans/kanion_4x4.json; .json/.zwo/.fit)
##   --time=PORA        pora: cycle (zmienna), day, dusk, night, storm (testy wyglądu)
##   --bridge-port=N    port mostka (domyślnie 8765; zapamiętywany)
##   --challenge-test   pierwsze wyzwanie trybu wolnego już po 8 s
##   --no-challenges    jazda swobodna bez wyzwań
##   --terrain=ID       wymuś teren (canyon/city) – testy, z pominięciem wymagań
##   --all-upgrades     jazda z wszystkimi modułami na maks. (podgląd; zapis bez zmian)

const DEFAULT_MINUTES := 15.0
const TEST_MINUTES := 2.0

var minutes := DEFAULT_MINUTES
var minutes_from_cli := false
var autostart := false
var autopilot := false
var time_scale := 1.0
var seed_value := -1
var quit_on_finish := false
var save_path := "user://progress.json"
var screenshot_dir := ""
var shot_times: Array[float] = [4.0, 12.0]
var combat_test := false
var no_combat := false
var terrain := ""
var all_upgrades := false
var challenge_test := false
var no_challenges := false
var trainer := false
var plan_path := ""
var bridge_port := 0
var time_mode := ""


static func parse(args: PackedStringArray) -> LaunchOptions:
	var o := LaunchOptions.new()
	for raw in args:
		var arg := raw.strip_edges()
		var key := arg
		var value := ""
		var eq := arg.find("=")
		if eq >= 0:
			key = arg.substr(0, eq)
			value = arg.substr(eq + 1)
		match key:
			"--minutes":
				if value.is_valid_float() and value.to_float() > 0.0:
					o.minutes = value.to_float()
					o.minutes_from_cli = true
			"--test":
				o.minutes = TEST_MINUTES
				o.minutes_from_cli = true
			"--autostart":
				o.autostart = true
			"--autopilot":
				o.autopilot = true
			"--time-scale":
				if value.is_valid_float():
					o.time_scale = clampf(value.to_float(), 0.1, 50.0)
			"--seed":
				if value.is_valid_int():
					o.seed_value = value.to_int()
			"--quit-on-finish":
				o.quit_on_finish = true
			"--save":
				if value != "":
					o.save_path = value
			"--screenshots":
				o.screenshot_dir = value
			"--combat-test":
				o.combat_test = true
			"--no-combat":
				o.no_combat = true
			"--terrain":
				o.terrain = value
			"--all-upgrades":
				o.all_upgrades = true
			"--challenge-test":
				o.challenge_test = true
			"--no-challenges":
				o.no_challenges = true
			"--trainer":
				o.trainer = true
			"--plan":
				o.plan_path = value
			"--time":
				if value in ["cycle", "day", "dusk", "night", "storm"]:
					o.time_mode = value
			"--bridge-port":
				if value.is_valid_int():
					o.bridge_port = clampi(value.to_int(), 1, 65535)
			"--shot-times":
				var times: Array[float] = []
				for part in value.split(",", false):
					if part.strip_edges().is_valid_float():
						times.append(part.strip_edges().to_float())
				o.shot_times = times
	return o


func duration_s() -> float:
	return minutes * 60.0
