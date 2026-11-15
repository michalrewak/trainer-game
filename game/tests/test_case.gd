class_name TestCase
extends RefCounted
## Minimalna baza testów (bez zewnętrznych dodatków). Każda metoda test_* to jeden test.
## Asercje zbierają błędy zamiast przerywać, runner raportuje je po teście.

var failures: Array[String] = []
var _current := ""


func begin(test_name: String) -> void:
	_current = test_name
	failures.clear()


func fail(message: String) -> void:
	failures.append(message)


func assert_true(condition: bool, message: String = "oczekiwano true") -> void:
	if not condition:
		fail(message)


func assert_false(condition: bool, message: String = "oczekiwano false") -> void:
	if condition:
		fail(message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		fail("%s oczekiwano %s, jest %s" % [message, var_to_str(expected), var_to_str(actual)])


func assert_near(actual: float, expected: float, tolerance: float, message: String = "") -> void:
	if absf(actual - expected) > tolerance:
		fail("%s oczekiwano %.4f ± %.4f, jest %.4f" % [message, expected, tolerance, actual])


func assert_between(actual: float, low: float, high: float, message: String = "") -> void:
	if actual < low or actual > high:
		fail("%s oczekiwano w [%.3f, %.3f], jest %.3f" % [message, low, high, actual])
