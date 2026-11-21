class_name Streak
extends RefCounted
## Passa: seria udanych akcji bez wpadki podbija mnożnik zbieranego złomu.
## Punkty passy dają: zębatka (+1), duży złom i kanister (+2), unik o włos (+3), rozbity
## wrak (+2), rozbity wóz gangu (+5), skrzynia (+2). Każdy punkt odnawia zegar; gdy zegar
## dobiegnie zera, passa spada o jeden próg. Zderzenie, rabunek albo mina zerują ją.
## To klasyczny „haczyk” gier zręcznościowych: im dłużej jedziesz czysto, tym więcej
## masz do stracenia.

signal tier_changed(tier: int, up: bool)
signal broken(points: int)

## Progi: [punkty, mnożnik złomu].
const TIERS: Array = [[0, 1.0], [5, 1.2], [15, 1.5], [30, 2.0], [50, 2.5], [80, 3.0]]
const HOLD_S := 12.0

var points := 0
var left_s := 0.0
var best_tier := 0


func tier() -> int:
	var t := 0
	for i in TIERS.size():
		if points >= int(TIERS[i][0]):
			t = i
	return t


func multiplier() -> float:
	return float(TIERS[tier()][1])


static func tier_multiplier(index: int) -> float:
	return float(TIERS[clampi(index, 0, TIERS.size() - 1)][1])


## Postęp do następnego progu 0..1 (1 na najwyższym).
func progress_to_next() -> float:
	var t := tier()
	if t >= TIERS.size() - 1:
		return 1.0
	var from := int(TIERS[t][0])
	var to := int(TIERS[t + 1][0])
	return clampf(float(points - from) / float(to - from), 0.0, 1.0)


## Ile zegara zostało 0..1.
func time_ratio() -> float:
	return clampf(left_s / HOLD_S, 0.0, 1.0) if points > 0 else 0.0


func add(amount: int = 1) -> void:
	if amount <= 0:
		return
	var before := tier()
	points += amount
	left_s = HOLD_S
	var now := tier()
	if now > before:
		best_tier = maxi(best_tier, now)
		tier_changed.emit(now, true)


func step(delta: float) -> void:
	if points <= 0:
		return
	left_s -= delta
	if left_s > 0.0:
		return
	# Zegar minął: spadek na początek niższego progu (a z najniższego – do zera).
	var t := tier()
	if t == 0:
		points = 0
		left_s = 0.0
		return
	points = int(TIERS[t - 1][0])
	left_s = HOLD_S if points > 0 else 0.0
	tier_changed.emit(t - 1, false)


## Wpadka (zderzenie, rabunek, mina): passa przepada.
func reset() -> void:
	if points <= 0:
		return
	var lost := points
	var had_tier := tier() > 0
	points = 0
	left_s = 0.0
	if had_tier:
		broken.emit(lost)
