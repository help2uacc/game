extends TestCase


func _ids() -> Array[String]:
	var ids: Array[String] = []
	for i: int in range(12):
		ids.append("map_%d" % i)
	return ids


func test_first_cycle_uses_every_map_once() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var rot := MapRotation.new(_ids(), rng)
	var seen: Dictionary = {}
	for i: int in range(12):
		seen[rot.next()] = true
	assert_eq(seen.size(), 12)


func test_no_immediate_repeat_on_reshuffle() -> void:
	for s: int in range(200):
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var rot := MapRotation.new(_ids(), rng)
		var last: String = ""
		for i: int in range(99):
			var m: String = rot.next()
			assert_ne(m, last, "seed %d round %d" % [s, i])
			last = m


func test_each_cycle_is_a_permutation() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var rot := MapRotation.new(_ids(), rng)
	for cycle: int in range(5):
		var seen: Dictionary = {}
		for i: int in range(12):
			seen[rot.next()] = true
		assert_eq(seen.size(), 12, "cycle %d" % cycle)
