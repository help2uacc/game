class_name TestCase
extends RefCounted
## Minimal assertion base class for the headless test runner (no addons).

var failures: PackedStringArray = []
var current_test: String = ""
var _nodes: Array[Node] = []


func tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## Adds a node to the scene tree for the duration of the test.
func add_node(n: Node) -> Node:
	tree().root.add_child(n)
	_nodes.append(n)
	return n


func cleanup() -> void:
	for n: Node in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()


func physics_frames(count: int) -> void:
	for i: int in range(count):
		await tree().physics_frame


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
