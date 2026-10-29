extends TestCase


func test_damage_hits_armor_first() -> void:
	assert_eq(Rules.apply_damage(100, 50, 30), Vector2i(100, 20))
	assert_eq(Rules.apply_damage(100, 50, 50), Vector2i(100, 0))
	assert_eq(Rules.apply_damage(100, 20, 50), Vector2i(70, 0))


func test_damage_without_armor_and_overkill() -> void:
	assert_eq(Rules.apply_damage(100, 0, 18), Vector2i(82, 0))
	assert_eq(Rules.apply_damage(10, 0, 70), Vector2i(0, 0))
	assert_eq(Rules.apply_damage(50, 5, 0), Vector2i(50, 5))


func test_heal_and_armor_caps() -> void:
	assert_eq(Rules.heal(80, 40), 100)
	assert_eq(Rules.heal(30, 40), 70)
	assert_eq(Rules.add_armor(10, 50), 50)
	assert_eq(Rules.add_armor(0, 50), 50)


func test_rounds_clamp() -> void:
	assert_eq(Rules.clamp_rounds(12), 12)
	assert_eq(Rules.clamp_rounds(3), 4)
	assert_eq(Rules.clamp_rounds(-5), 4)
	assert_eq(Rules.clamp_rounds(100), 99)
	assert_eq(Rules.clamp_rounds(99), 99)
	assert_eq(Rules.clamp_rounds(4), 4)
	assert_eq(GameConfig.DEFAULT_ROUNDS, 12)


func test_round_end_conditions() -> void:
	assert_true(Rules.should_round_end(1, 120.0), "one alive ends round")
	assert_true(Rules.should_round_end(0, 120.0), "zero alive ends round")
	assert_false(Rules.should_round_end(2, 120.0), "two alive continues")
	assert_true(Rules.should_round_end(5, 0.0), "timer zero ends round")
	assert_true(Rules.should_round_end(5, -0.1), "timer below zero ends round")


func test_round_winner_single() -> void:
	var w: Array[int] = Rules.top_scorers({1: 2, 2: 5, 3: 1})
	assert_eq(w, [2] as Array[int])
	assert_false(Rules.is_draw(w))


func test_round_draw_including_zero() -> void:
	var w: Array[int] = Rules.top_scorers({1: 0, 2: 0, 3: 0})
	assert_eq(w.size(), 3)
	assert_true(Rules.is_draw(w))
	var w2: Array[int] = Rules.top_scorers({4: 3, 2: 3, 1: 1})
	assert_eq(w2, [2, 4] as Array[int])
	assert_true(Rules.is_draw(w2))


func test_match_winner_by_total_kills() -> void:
	var totals: Dictionary = {1: 10, 2: 12, 3: 12, 4: 0}
	var w: Array[int] = Rules.top_scorers(totals)
	assert_eq(w, [2, 3] as Array[int])
	assert_true(Rules.is_draw(w))
	totals[3] = 11
	w = Rules.top_scorers(totals)
	assert_eq(w, [2] as Array[int])
	assert_false(Rules.is_draw(w))


func test_color_auto_assignment() -> void:
	var taken: Array[int] = []
	assert_eq(Rules.first_free_color(taken), 0)
	taken = [0, 1, 3]
	assert_eq(Rules.first_free_color(taken), 2)
	taken = [0, 1, 2, 3, 4, 5, 6, 7]
	assert_eq(Rules.first_free_color(taken), -1)


func test_color_uniqueness() -> void:
	var others: Array[int] = [0, 4]
	assert_false(Rules.can_take_color(0, others))
	assert_false(Rules.can_take_color(4, others))
	assert_true(Rules.can_take_color(5, others))
	assert_false(Rules.can_take_color(8, others))
	assert_false(Rules.can_take_color(-1, others))


func test_player_names() -> void:
	assert_true(Rules.is_valid_name("Joe"))
	assert_true(Rules.is_valid_name("A_b-c 12"))
	assert_false(Rules.is_valid_name(""))
	assert_false(Rules.is_valid_name("   "))
	assert_false(Rules.is_valid_name("ThirteenChars"))
	assert_false(Rules.is_valid_name("bad!"))
	assert_eq(Rules.sanitize_name("Jo!e", "X"), "Joe")
	assert_eq(Rules.sanitize_name("!!!", "X"), "X")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var n: String = Rules.default_player_name(rng)
	assert_true(n.begins_with("Player") and n.length() == 10, n)


func test_falloff_damage() -> void:
	assert_eq(Rules.falloff_damage(0.0, 3.0, 60.0, 20.0), 60)
	assert_eq(Rules.falloff_damage(3.0, 3.0, 60.0, 20.0), 20)
	assert_eq(Rules.falloff_damage(1.5, 3.0, 60.0, 20.0), 40)
	assert_eq(Rules.falloff_damage(3.1, 3.0, 60.0, 20.0), 0)
	assert_eq(Rules.falloff_damage(0.0, 3.5, 70.0, 15.0), 70)


func test_weighted_pick_respects_zero_weights() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i: int in range(50):
		var k: Variant = Rules.weighted_pick({"a": 0, "b": 5}, rng)
		assert_eq(k, "b")
