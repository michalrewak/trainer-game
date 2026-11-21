class_name CampaignCatalog
extends RefCounted
## Kampanie treningowe: czterotygodniowe bloki po trzy sesje w tygodniu, złożone z prawdziwych,
## sprawdzonych protokołów (słodki punkt, 2×20 na progu, nad-i-pod progiem, 4×4, 4×8 Seilera,
## 30/15 Rønnestada). Sesje jedzie się po kolei. Dwie sesje w kampanii to BOSSOWIE – machiny
## Barona Smalca, które rozbija się trzymaniem mocy w interwałach – a ostatnia to TEST FTP
## („Rytuał Progu”, test narastający), który ustawia nowe FTP i rangę.
##
## Trening jest zapisany krótkim opisem:
##   wu10            rozgrzewka 10 min (50→75% FTP)
##   cd8             schłodzenie 8 min (60→45%)
##   r5              regeneracja 5 min (55%)
##   12@90           12 min na 90% FTP;  30s@120 = 30 sekund na 120%
##   3x(12@90 r5)    powtórzenia; można je zagnieżdżać: 3x(13x(30s@120 15s@50) r3)
## Czysta logika – z opisu powstaje zwykły WorkoutPlan.

enum Kind { RIDE, BOSS, TEST }

const PROG := "prog"
const KUZNIA := "kuznia"
const BAZA := "baza"
const ORDER: Array[String] = [BAZA, PROG, KUZNIA]
const SESSIONS_PER_WEEK := 3

## Test narastający: start od tylu FTP, co minutę o tyle więcej, najwyżej tyle stopni.
const RAMP_START := 0.5
const RAMP_STEP := 0.075
const RAMP_STEPS := 28
const RAMP_WARMUP_MIN := 5.0

const EASY_45 := "wu5 40@68 cd5"
const EASY_50 := "wu5 45@68 cd5"
const OPENERS := "wu5 15@60 3x(1@100 r2) 5@60 cd5"

const DEFS := {
	BAZA: {
		"name": "Baza Pustkowi",
		"goal": "Fundament: wytrzymałość i tempo. Dobra na początek albo po przerwie.",
		"boss": "Karawana Smalca",
		"sessions": [
			["Wytrzymałość 40", "wu5 35@66 cd5", Kind.RIDE, "Długi, równy kurs. Uczysz nogi palić mało i jechać długo."],
			["Tempo 3×8", "wu8 3x(8@80 r4) cd6", Kind.RIDE, "Trzy odcinki w tempie karawany. Równo, bez szarpania."],
			["Kadencja 6×1", "wu8 20@65 6x(1@85 r2) 5@65 cd5", Kind.RIDE, "Brat Obrót patrzy: sześć minut na wysokich obrotach."],
			["Wytrzymałość 50", EASY_50, Kind.RIDE, "Kurs do dalszej osady. Spokojnie, cały czas w drugiej strefie."],
			["Tempo 3×10", "wu8 3x(10@82 r4) cd6", Kind.RIDE, "Dłuższe odcinki tempa. Karawana Smalca jest już blisko."],
			["Karawana Smalca: 2×20 pod progiem", "wu8 2x(20@88 r5) cd6", Kind.BOSS, "Dogoniłeś karawanę. Dwa razy po 20 minut tuż pod progiem i wozy są twoje."],
			["Wytrzymałość 55", "wu5 50@67 cd5", Kind.RIDE, "Odwozisz uwolnionych do osady. Długo i równo."],
			["Słodki punkt 2×12", "wu10 2x(12@90 r5) cd8", Kind.RIDE, "Pierwszy raz tuż pod progiem. Tu rośnie FTP."],
			["Tempo z przyspieszeniami", "wu8 3x(8@80 1@100 r4) cd6", Kind.RIDE, "Tempo, a na końcu każdego odcinka minuta na progu."],
			["Brama Twierdzy: słodki punkt 3×12", "wu10 3x(12@90 r5) cd8", Kind.BOSS, "Brama twierdzy Barona. Trzy natarcia po 12 minut tuż pod progiem."],
			["Rozruch przed rytuałem", OPENERS, Kind.RIDE, "Lekko, trzy krótkie przebudzenia nóg. Jutro rytuał."],
			["Rytuał Progu", "", Kind.TEST, "Test na oczach całej osady: co minutę ciężej, aż nogi powiedzą dość. Wynik ustawi twoje FTP."],
		],
	},
	PROG: {
		"name": "Droga do Progu",
		"goal": "Wyższe FTP: słodki punkt i długie odcinki na progu (klasyczne 2×20).",
		"boss": "Walec Smalca",
		"sessions": [
			["Słodki punkt 3×10", "wu10 3x(10@90 r5) cd8", Kind.RIDE, "Zaczynamy spokojnie: trzy równe pociągnięcia tuż pod progiem."],
			["Wytrzymałość 45", EASY_45, Kind.RIDE, "Dzień na długi, lekki kurs. Nogi mają odpocząć w ruchu."],
			["Próg 3×8", "wu10 3x(8@98 r4) cd8", Kind.RIDE, "Trzy razy po osiem minut na samym progu. Tak jeździ Walec."],
			["Słodki punkt 3×12", "wu10 3x(12@90 r5) cd8", Kind.RIDE, "Dłuższe odcinki. Baron już wie, że ktoś za nim jedzie."],
			["Tempo 2×15", "wu10 2x(15@83 r5) cd8", Kind.RIDE, "Spokojniejszy dzień przed walką. Równe tempo."],
			["Walec Smalca: 2×15 na progu", "wu10 2x(15@97 r8) cd6", Kind.BOSS, "Walec toczy się przed tobą. Dwa razy po kwadrans na progu i pęknie mu oś."],
			["Nad i pod progiem 3×12", "wu10 3x(4x(2@95 1@105) r5) cd8", Kind.RIDE, "Dwie minuty pod progiem, minuta nad. Uczysz się jechać, gdy piecze."],
			["Wytrzymałość 50", EASY_50, Kind.RIDE, "Długi kurs z łupem z Walca. Lekko."],
			["Słodki punkt 2×20", "wu10 2x(20@90 r5) cd8", Kind.RIDE, "Dwa razy po 20 minut. Próba generalna przed twierdzą."],
			["Twierdza Barona: 2×20 na progu", "wu10 2x(20@98 r8) cd6", Kind.BOSS, "Klasyka: dwa razy po 20 minut na progu. Tyle trzeba, żeby wyważyć bramę."],
			["Rozruch przed rytuałem", OPENERS, Kind.RIDE, "Lekko, trzy krótkie przebudzenia nóg. Jutro rytuał."],
			["Rytuał Progu", "", Kind.TEST, "Test na oczach całej osady: co minutę ciężej, aż nogi powiedzą dość. Wynik ustawi twoje FTP."],
		],
	},
	KUZNIA: {
		"name": "Kuźnia VO2",
		"goal": "Wyższy pułap: krótkie, bardzo mocne interwały (4×4, 4×8, 30/15).",
		"boss": "Młot Barona",
		"sessions": [
			["Pułap 5×3", "wu12 5x(3@115 r3) cd8", Kind.RIDE, "Pięć razy po trzy minuty powyżej progu. Kuźnia rozpala piec."],
			["Wytrzymałość 45", EASY_45, Kind.RIDE, "Lekki kurs między ciężkimi dniami."],
			["Zrywy 2×10×30/15", "wu12 2x(10x(30s@120 15s@50) r4) cd8", Kind.RIDE, "Trzydzieści sekund ognia, piętnaście oddechu. Dziesięć razy, dwie serie."],
			["Norweskie 4×4", "wu12 4x(4@110 r3) cd8", Kind.RIDE, "Cztery razy po cztery minuty. Stara szkoła z północy."],
			["Wytrzymałość 50", EASY_50, Kind.RIDE, "Długo i lekko. Jutro Młot."],
			["Młot Barona: 3×13×30/15", "wu12 3x(13x(30s@120 15s@50) r3) cd8", Kind.BOSS, "Młot bije co 45 sekund. Trzy serie po trzynaście uderzeń – oddaj każde."],
			["Seiler 4×8", "wu12 4x(8@105 r2) cd8", Kind.RIDE, "Cztery razy po osiem minut tuż nad progiem. Najwięcej czasu przy pułapie."],
			["Wytrzymałość 45", EASY_45, Kind.RIDE, "Lekki kurs. Piec ma ostygnąć."],
			["Pułap 6×3", "wu12 6x(3@115 r3) cd8", Kind.RIDE, "Sześć razy po trzy minuty. O jedno więcej niż na początku."],
			["Kuźnia w ogniu: 5×5", "wu12 5x(5@108 r3) cd8", Kind.BOSS, "Serce kuźni Barona. Pięć razy po pięć minut i piec gaśnie na dobre."],
			["Rozruch przed rytuałem", OPENERS, Kind.RIDE, "Lekko, trzy krótkie przebudzenia nóg. Jutro rytuał."],
			["Rytuał Progu", "", Kind.TEST, "Test na oczach całej osady: co minutę ciężej, aż nogi powiedzą dość. Wynik ustawi twoje FTP."],
		],
	},
}


static func has(id: String) -> bool:
	return DEFS.has(id)


static func display_name(id: String) -> String:
	return str(DEFS[id]["name"])


static func goal(id: String) -> String:
	return str(DEFS[id]["goal"])


static func boss_name(id: String) -> String:
	return str(DEFS[id]["boss"])


static func session_count(id: String) -> int:
	return (DEFS[id]["sessions"] as Array).size()


static func weeks(id: String) -> int:
	return ceili(session_count(id) / float(SESSIONS_PER_WEEK))


## Sesja kampanii: {"index", "week", "title", "spec", "kind", "story"}; {} gdy brak.
static func session(id: String, index: int) -> Dictionary:
	if not DEFS.has(id) or index < 0 or index >= session_count(id):
		return {}
	var s: Array = DEFS[id]["sessions"][index]
	return {"index": index, "week": floori(index / float(SESSIONS_PER_WEEK)) + 1, "title": s[0], "spec": s[1], "kind": s[2], "story": s[3]}


## Plan treningowy sesji (dla testu FTP – plan testu narastającego).
static func plan(id: String, index: int) -> WorkoutPlan:
	var s := session(id, index)
	if s.is_empty():
		return null
	var p := ramp_test_plan() if int(s["kind"]) == Kind.TEST else parse_spec(str(s["spec"]))
	p.name = str(s["title"])
	p.description = str(s["story"])
	p.source_format = "campaign"
	return p


## Test narastający: krótka rozgrzewka, potem co minutę wyższy stopień. Plan jest „na zapas”
## (do 250% FTP) – grę kończy RampTest, gdy zawodnik nie utrzyma stopnia.
static func ramp_test_plan() -> WorkoutPlan:
	var p := WorkoutPlan.new()
	p.add_step(WorkoutStep.new(WorkoutStep.Kind.WARMUP, RAMP_WARMUP_MIN * 60.0, 0.45, RAMP_START, 0.0, "Rozgrzewka"))
	for i in RAMP_STEPS:
		p.add_step(WorkoutStep.new(WorkoutStep.Kind.WORK, 60.0, RAMP_START + RAMP_STEP * i, -1.0, 0.0, "Stopień %d" % (i + 1)))
	return p


## Buduje plan z krótkiego opisu (patrz nagłówek pliku). Błędny opis daje pusty plan.
static func parse_spec(spec: String) -> WorkoutPlan:
	var p := WorkoutPlan.new()
	var pos := [0]
	for step in _parse_sequence(spec, pos):
		p.add_step(step)
	return p


static func _parse_sequence(text: String, pos: Array) -> Array[WorkoutStep]:
	var out: Array[WorkoutStep] = []
	while pos[0] < text.length():
		var c := text[pos[0]]
		if c == " ":
			pos[0] += 1
			continue
		if c == ")":
			pos[0] += 1
			return out
		var start: int = pos[0]
		while pos[0] < text.length() and text[pos[0]] != " " and text[pos[0]] != "(" and text[pos[0]] != ")":
			pos[0] += 1
		var token := text.substr(start, pos[0] - start)
		if pos[0] < text.length() and text[pos[0]] == "(":
			# Powtórzenia: "3x(" – wnętrze czytamy raz i powielamy.
			pos[0] += 1
			var inner := _parse_sequence(text, pos)
			for i in maxi(1, int(token.trim_suffix("x"))):
				for s in inner:
					out.append(s.copy())
		else:
			var step := _parse_token(token)
			if step != null:
				out.append(step)
	return out


static func _parse_token(token: String) -> WorkoutStep:
	if token.begins_with("wu"):
		return WorkoutStep.new(WorkoutStep.Kind.WARMUP, float(token.substr(2)) * 60.0, 0.5, 0.75, 0.0, "Rozgrzewka")
	if token.begins_with("cd"):
		return WorkoutStep.new(WorkoutStep.Kind.COOLDOWN, float(token.substr(2)) * 60.0, 0.6, 0.45, 0.0, "Schłodzenie")
	if token.begins_with("r") and not token.contains("@"):
		return WorkoutStep.new(WorkoutStep.Kind.RECOVERY, float(token.substr(1)) * 60.0, 0.55, -1.0, 0.0, "Regeneracja")
	var parts := token.split("@")
	if parts.size() != 2:
		return null
	var seconds := float(parts[0].trim_suffix("s")) if parts[0].ends_with("s") else float(parts[0]) * 60.0
	var fraction := float(parts[1]) / 100.0
	if seconds <= 0.0 or fraction <= 0.0:
		return null
	return WorkoutStep.new(WorkoutStep.kind_for_power(fraction, true), seconds, fraction, -1.0, 0.0, _label(seconds, fraction))


static func _label(seconds: float, fraction: float) -> String:
	if fraction >= 1.06:
		return "Zryw" if seconds <= 45.0 else "Pułap"
	if fraction >= 0.95:
		return "Próg"
	if fraction >= 0.88:
		return "Słodki punkt"
	if fraction >= 0.76:
		return "Tempo"
	if fraction >= 0.56:
		return "Wytrzymałość"
	return "Oddech"
