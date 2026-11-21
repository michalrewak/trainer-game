class_name CampaignCatalog
extends RefCounted
## Kampanie treningowe: czterotygodniowe bloki po trzy sesje w tygodniu, złożone z prawdziwych,
## sprawdzonych protokołów (słodki punkt, 2×20 na progu, nad-i-pod progiem, 4×4, 4×8 Seilera,
## 30/15 Rønnestada). Sesje jedzie się po kolei. Dwie sesje w kampanii to BOSSOWIE – machiny
## Barona Smalca, które rozbija się trzymaniem mocy w interwałach – a ostatnia to TEST FTP
## („Rytuał Progu”, test narastający), który ustawia nowe FTP i rangę.
##
## Każda sesja ma dwa warianty: PEŁNY (35–72 min) i KRÓTKI (26–40 min). Krótki trzyma te
## same intensywności i układ interwałów, ma mniejszą objętość i krótszą rozgrzewkę.
## Postęp kampanii jest wspólny – sesja liczy się w obu wariantach.
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
const EASY_SHORT := "wu4 24@68 cd4"
const OPENERS := "wu5 15@60 3x(1@100 r2) 5@60 cd5"
const OPENERS_SHORT := "wu5 8@60 3x(1@100 r2) cd4"
const TEST_STORY := "Test na oczach całej osady: co minutę ciężej, aż nogi powiedzą dość. Wynik ustawi twoje FTP."

## Sesja: [tytuł, opis treningu, rodzaj, wprowadzenie, tytuł krótkiego wariantu, opis krótkiego].
const DEFS := {
	BAZA: {
		"name": "Baza Pustkowi",
		"goal": "Fundament: wytrzymałość i tempo. Dobra na początek albo po przerwie.",
		"boss": "Karawana Smalca",
		"sessions": [
			["Wytrzymałość 40", "wu5 35@66 cd5", Kind.RIDE, "Długi, równy kurs. Uczysz nogi palić mało i jechać długo.", "Wytrzymałość 30", "wu4 22@66 cd4"],
			["Tempo 3×8", "wu8 3x(8@80 r4) cd6", Kind.RIDE, "Odcinki w tempie karawany. Równo, bez szarpania.", "Tempo 2×8", "wu6 2x(8@80 r3) cd4"],
			["Kadencja 6×1", "wu8 20@65 6x(1@85 r2) 5@65 cd5", Kind.RIDE, "Brat Obrót patrzy: minutowe odcinki na wysokich obrotach.", "Kadencja 5×1", "wu6 8@65 5x(1@85 r2) cd4"],
			["Wytrzymałość 50", EASY_50, Kind.RIDE, "Kurs do dalszej osady. Spokojnie, cały czas w drugiej strefie.", "Wytrzymałość 32", EASY_SHORT],
			["Tempo 3×10", "wu8 3x(10@82 r4) cd6", Kind.RIDE, "Dłuższe odcinki tempa. Karawana Smalca jest już blisko.", "Tempo 2×10", "wu6 2x(10@82 r3) cd4"],
			["Karawana Smalca: 2×20 pod progiem", "wu8 2x(20@88 r5) cd6", Kind.BOSS, "Dogoniłeś karawanę. Dwa natarcia tuż pod progiem i wozy są twoje.", "Karawana Smalca: 2×11 pod progiem", "wu6 2x(11@88 r4) cd4"],
			["Wytrzymałość 55", "wu5 50@67 cd5", Kind.RIDE, "Odwozisz uwolnionych do osady. Długo i równo.", "Wytrzymałość 36", "wu4 28@67 cd4"],
			["Słodki punkt 2×12", "wu10 2x(12@90 r5) cd8", Kind.RIDE, "Pierwszy raz tuż pod progiem. Tu rośnie FTP.", "Słodki punkt 2×9", "wu6 2x(9@90 r4) cd4"],
			["Tempo z przyspieszeniami 3×9", "wu8 3x(8@80 1@100 r4) cd6", Kind.RIDE, "Tempo, a na końcu każdego odcinka minuta na progu.", "Tempo z przyspieszeniami 2×9", "wu6 2x(8@80 1@100 r3) cd4"],
			["Brama Twierdzy: słodki punkt 3×12", "wu10 3x(12@90 r5) cd8", Kind.BOSS, "Brama twierdzy Barona. Trzy natarcia tuż pod progiem.", "Brama Twierdzy: słodki punkt 3×7", "wu6 3x(7@90 r3) cd4"],
			["Rozruch przed rytuałem", OPENERS, Kind.RIDE, "Lekko, trzy krótkie przebudzenia nóg. Jutro rytuał.", "Rozruch przed rytuałem", OPENERS_SHORT],
			["Rytuał Progu", "", Kind.TEST, TEST_STORY, "Rytuał Progu", ""],
		],
	},
	PROG: {
		"name": "Droga do Progu",
		"goal": "Wyższe FTP: słodki punkt i długie odcinki na progu (klasyczne 2×20).",
		"boss": "Walec Smalca",
		"sessions": [
			["Słodki punkt 3×10", "wu10 3x(10@90 r5) cd8", Kind.RIDE, "Zaczynamy spokojnie: równe pociągnięcia tuż pod progiem.", "Słodki punkt 2×10", "wu6 2x(10@90 r4) cd4"],
			["Wytrzymałość 45", EASY_45, Kind.RIDE, "Dzień na długi, lekki kurs. Nogi mają odpocząć w ruchu.", "Wytrzymałość 32", EASY_SHORT],
			["Próg 3×8", "wu10 3x(8@98 r4) cd8", Kind.RIDE, "Trzy odcinki na samym progu. Tak jeździ Walec.", "Próg 3×5", "wu6 3x(5@98 r3) cd4"],
			["Słodki punkt 3×12", "wu10 3x(12@90 r5) cd8", Kind.RIDE, "Dłuższe odcinki. Baron już wie, że ktoś za nim jedzie.", "Słodki punkt 2×11", "wu6 2x(11@90 r4) cd4"],
			["Tempo 2×15", "wu10 2x(15@83 r5) cd8", Kind.RIDE, "Spokojniejszy dzień przed walką. Równe tempo.", "Tempo 2×10", "wu6 2x(10@83 r3) cd4"],
			["Walec Smalca: 2×15 na progu", "wu10 2x(15@97 r8) cd6", Kind.BOSS, "Walec toczy się przed tobą. Dwa natarcia na progu i pęknie mu oś.", "Walec Smalca: 2×9 na progu", "wu6 2x(9@97 r5) cd4"],
			["Nad i pod progiem 3×12", "wu10 3x(4x(2@95 1@105) r5) cd8", Kind.RIDE, "Dwie minuty pod progiem, minuta nad. Uczysz się jechać, gdy piecze.", "Nad i pod progiem 2×9", "wu6 2x(3x(2@95 1@105) r4) cd4"],
			["Wytrzymałość 50", EASY_50, Kind.RIDE, "Długi kurs z łupem z Walca. Lekko.", "Wytrzymałość 32", EASY_SHORT],
			["Słodki punkt 2×20", "wu10 2x(20@90 r5) cd8", Kind.RIDE, "Długie odcinki pod progiem. Próba generalna przed twierdzą.", "Słodki punkt 1×22", "wu6 22@90 cd4"],
			["Twierdza Barona: 2×20 na progu", "wu10 2x(20@98 r8) cd6", Kind.BOSS, "Klasyka: dwa długie natarcia na progu. Tyle trzeba, żeby wyważyć bramę.", "Twierdza Barona: 2×10 na progu", "wu6 2x(10@98 r5) cd4"],
			["Rozruch przed rytuałem", OPENERS, Kind.RIDE, "Lekko, trzy krótkie przebudzenia nóg. Jutro rytuał.", "Rozruch przed rytuałem", OPENERS_SHORT],
			["Rytuał Progu", "", Kind.TEST, TEST_STORY, "Rytuał Progu", ""],
		],
	},
	KUZNIA: {
		"name": "Kuźnia VO2",
		"goal": "Wyższy pułap: krótkie, bardzo mocne interwały (4×4, 4×8, 30/15).",
		"boss": "Młot Barona",
		"sessions": [
			["Pułap 5×3", "wu12 5x(3@115 r3) cd8", Kind.RIDE, "Trzyminutowe odcinki powyżej progu. Kuźnia rozpala piec.", "Pułap 4×3", "wu8 4x(3@115 r3) cd4"],
			["Wytrzymałość 45", EASY_45, Kind.RIDE, "Lekki kurs między ciężkimi dniami.", "Wytrzymałość 32", EASY_SHORT],
			["Zrywy 2×10×30/15", "wu12 2x(10x(30s@120 15s@50) r4) cd8", Kind.RIDE, "Trzydzieści sekund ognia, piętnaście oddechu. Dwie serie.", "Zrywy 2×8×30/15", "wu8 2x(8x(30s@120 15s@50) r3) cd4"],
			["Norweskie 4×4", "wu12 4x(4@110 r3) cd8", Kind.RIDE, "Czterominutowe odcinki. Stara szkoła z północy.", "Norweskie 3×4", "wu8 3x(4@110 r3) cd4"],
			["Wytrzymałość 50", EASY_50, Kind.RIDE, "Długo i lekko. Jutro Młot.", "Wytrzymałość 32", EASY_SHORT],
			["Młot Barona: 3×13×30/15", "wu12 3x(13x(30s@120 15s@50) r3) cd8", Kind.BOSS, "Młot bije co 45 sekund. Oddaj każde uderzenie.", "Młot Barona: 2×13×30/15", "wu8 2x(13x(30s@120 15s@50) r3) cd4"],
			["Seiler 4×8", "wu12 4x(8@105 r2) cd8", Kind.RIDE, "Długie odcinki tuż nad progiem. Najwięcej czasu przy pułapie.", "Seiler 3×6", "wu8 3x(6@105 r2) cd4"],
			["Wytrzymałość 45", EASY_45, Kind.RIDE, "Lekki kurs. Piec ma ostygnąć.", "Wytrzymałość 32", EASY_SHORT],
			["Pułap 6×3", "wu12 6x(3@115 r3) cd8", Kind.RIDE, "Trzyminutowe odcinki, o jeden więcej niż na początku.", "Pułap 5×3", "wu8 5x(3@115 r2) cd4"],
			["Kuźnia w ogniu: 5×5", "wu12 5x(5@108 r3) cd8", Kind.BOSS, "Serce kuźni Barona. Wytrzymaj wszystkie natarcia i piec gaśnie na dobre.", "Kuźnia w ogniu: 3×5", "wu8 3x(5@108 r3) cd4"],
			["Rozruch przed rytuałem", OPENERS, Kind.RIDE, "Lekko, trzy krótkie przebudzenia nóg. Jutro rytuał.", "Rozruch przed rytuałem", OPENERS_SHORT],
			["Rytuał Progu", "", Kind.TEST, TEST_STORY, "Rytuał Progu", ""],
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


## Sesja kampanii: {"index", "week", "title", "spec", "kind", "story", "short"}; {} gdy brak.
## short = true daje krótki wariant (inny tytuł i opis treningu, ta sama sesja).
static func session(id: String, index: int, short: bool = false) -> Dictionary:
	if not DEFS.has(id) or index < 0 or index >= session_count(id):
		return {}
	var s: Array = DEFS[id]["sessions"][index]
	return {
		"index": index, "week": floori(index / float(SESSIONS_PER_WEEK)) + 1,
		"title": s[4] if short else s[0], "spec": s[5] if short else s[1],
		"kind": s[2], "story": s[3], "short": short,
	}


## Plan treningowy sesji (dla testu FTP – plan testu narastającego, taki sam w obu wariantach).
static func plan(id: String, index: int, short: bool = false) -> WorkoutPlan:
	var s := session(id, index, short)
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
