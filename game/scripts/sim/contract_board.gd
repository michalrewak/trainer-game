class_name ContractBoard
extends RefCounted
## Zlecenia: trzy krótkie cele na wyprawę, zawsze widoczne w HUD. Gracz w każdej chwili
## wie, do czego dąży, a nagroda przychodzi co kilka minut – to trzyma uwagę między
## większymi wydarzeniami. Zestaw: jedno zlecenie treningowe (widełki, strefa, praca),
## jedno zręcznościowe i jedno „duże” (konwój, osada) albo drugie zręcznościowe.
## Cele skalują się z długością wyprawy i FTP. Czysta logika.

signal completed(contract: Dictionary)
signal all_completed

enum Kind { SCRAP, RAIDERS, IN_BAND, ZONE, STREAK, NEAR_MISS, CONVOY, RAID, SPEED, KJ, WRECKS }

const ALL_DONE_FUEL := 1

## {"kind", "text", "goal", "progress", "reward_scrap", "reward_fuel", "done"}
var contracts: Array[Dictionary] = []
var done_count := 0


## opts: "combat", "convoys", "raids" (czy są włączone), "workout" (czy jedzie plan).
func setup(minutes: float, ftp_w: float, seed_value: int, opts: Dictionary = {}) -> void:
	contracts.clear()
	done_count = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 7717
	var combat := bool(opts.get("combat", true))
	var workout := bool(opts.get("workout", false))
	var reward := clampi(roundi(30.0 + 10.0 * minutes), 40, 150)
	var seconds := minutes * 60.0

	var training: Array[Dictionary] = [_make(Kind.IN_BAND, snappedf(seconds * 0.4, 10.0), reward, 0)]
	if not workout:
		training.append(_make(Kind.ZONE, snappedf(seconds * 0.2, 10.0), reward, 0))
		training.append(_make(Kind.KJ, maxf(5.0, roundf(ftp_w * 0.7 * seconds / 1000.0)), reward, 0))
	var action: Array[Dictionary] = [
		_make(Kind.SCRAP, maxf(10.0, roundf(minutes * 8.0)), reward, 0),
		_make(Kind.STREAK, 2.0 if minutes < 10.0 else 3.0, reward, 0),
		_make(Kind.NEAR_MISS, 2.0 + floorf(minutes / 6.0), reward, 0),
		_make(Kind.SPEED, 45.0, reward, 0),
	]
	if combat:
		action.append(_make(Kind.RAIDERS, maxf(1.0, roundf(minutes / 4.0)), reward, 0))
		action.append(_make(Kind.WRECKS, 2.0 + floorf(minutes / 5.0), reward, 0))
	var big: Array[Dictionary] = []
	if bool(opts.get("convoys", false)) and minutes >= 6.0:
		big.append(_make(Kind.CONVOY, 1.0, reward * 2, 1))
	if bool(opts.get("raids", false)) and minutes >= 8.0:
		big.append(_make(Kind.RAID, 1.0, reward * 2, 1))

	contracts.append(_take(training, rng))
	contracts.append(_take(action, rng))
	if not big.is_empty() and rng.randf() < 0.65:
		contracts.append(_take(big, rng))
	else:
		contracts.append(_take(action, rng))


## Dolicza postęp (sztuki, sekundy, kilodżule).
func add(kind: Kind, amount: float = 1.0) -> void:
	for c in contracts:
		if int(c["kind"]) == kind and not bool(c["done"]):
			c["progress"] = float(c["progress"]) + amount
			_check(c)


## Zlecenia „osiągnij wartość” (prędkość, próg passy): liczy się najlepszy wynik.
func raise(kind: Kind, value: float) -> void:
	for c in contracts:
		if int(c["kind"]) == kind and not bool(c["done"]) and value > float(c["progress"]):
			c["progress"] = value
			_check(c)


func is_all_done() -> bool:
	return not contracts.is_empty() and done_count >= contracts.size()


## Postęp do pokazania w HUD, np. "12/40", "1:20/3:00", "×1.2/×2.0".
static func progress_text(c: Dictionary) -> String:
	var p := minf(float(c["progress"]), float(c["goal"]))
	var g := float(c["goal"])
	match int(c["kind"]):
		Kind.IN_BAND, Kind.ZONE:
			return "%s/%s" % [_clock(p), _clock(g)]
		Kind.STREAK:
			return "×%.1f/×%.1f" % [Streak.tier_multiplier(roundi(p)), Streak.tier_multiplier(roundi(g))]
		Kind.SPEED:
			return "%d/%d" % [roundi(p), roundi(g)]
		Kind.CONVOY, Kind.RAID:
			return ""
	return "%d/%d" % [floori(p), roundi(g)]


func to_summary() -> Array:
	var out: Array = []
	for c in contracts:
		out.append({"text": c["text"], "done": c["done"], "reward_scrap": c["reward_scrap"]})
	return out


func _check(c: Dictionary) -> void:
	if float(c["progress"]) < float(c["goal"]) - 1e-6:
		return
	c["done"] = true
	done_count += 1
	completed.emit(c)
	if is_all_done():
		all_completed.emit()


func _take(pool: Array[Dictionary], rng: RandomNumberGenerator) -> Dictionary:
	var i := rng.randi_range(0, pool.size() - 1)
	var c := pool[i]
	pool.remove_at(i)
	return c


func _make(kind: Kind, goal: float, reward_scrap: int, reward_fuel: int) -> Dictionary:
	return {"kind": kind, "text": _text(kind, goal), "goal": goal, "progress": 0.0, "reward_scrap": reward_scrap, "reward_fuel": reward_fuel, "done": false}


static func _text(kind: Kind, goal: float) -> String:
	match kind:
		Kind.SCRAP:
			return "Zbierz %d zębatek" % roundi(goal)
		Kind.RAIDERS:
			return "Rozbij %d %s gangu" % [roundi(goal), "wóz" if roundi(goal) == 1 else "wozy"]
		Kind.IN_BAND:
			return "Jedź %s w widełkach celu" % _clock(goal)
		Kind.ZONE:
			return "Jedź %s w strefie Z3 lub wyżej" % _clock(goal)
		Kind.STREAK:
			return "Rozkręć passę do ×%.1f" % Streak.tier_multiplier(roundi(goal))
		Kind.NEAR_MISS:
			return "Omiń %d wraki o włos" % roundi(goal)
		Kind.CONVOY:
			return "Przejmij galerę z konwoju"
		Kind.RAID:
			return "Splądruj osadę"
		Kind.SPEED:
			return "Rozpędź się do %d km/h" % roundi(goal)
		Kind.KJ:
			return "Wykręć %d kJ pracy" % roundi(goal)
		Kind.WRECKS:
			return "Rozbij %d wraki (strzał, taran)" % roundi(goal)
	return ""


static func _clock(seconds: float) -> String:
	var s := maxi(0, floori(seconds))
	return "%d:%02d" % [s / 60, s % 60]
