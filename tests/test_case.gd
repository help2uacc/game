class_name TestCase
extends RefCounted
## Minimal assertion base class for the headless test runner (no addons).

var failures: PackedStringArray = []
var current_test: String = ""


func _fail(message: String) -> void:
	failures.append("%s: %s" % [current_test, message])


func assert_true(value: bool, message: String = "expected true") -> void:
	if not value:
		_fail(message)


func assert_false(value: bool, message: String = "expected false") -> void:
	if value:
		_fail(message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		_fail("expected <%s> got <%s> %s" % [str(expected), str(actual), message])


func assert_ne(actual: Variant, other: Variant, message: String = "") -> void:
	if typeof(actual) == typeof(other) and actual == other:
		_fail("did not expect <%s> %s" % [str(actual), message])


func assert_near(actual: float, expected: float, eps: float = 0.0001, message: String = "") -> void:
	if absf(actual - expected) > eps:
		_fail("expected ~%f got %f %s" % [expected, actual, message])
