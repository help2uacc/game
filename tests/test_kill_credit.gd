extends TestCase


func test_direct_kill_credits_attacker() -> void:
	var kc := KillCredit.new()
	kc.record_damage(2, 1, 10.0)
	assert_eq(kc.resolve(2, 1, 10.0), 1)


func test_direct_kill_credits_lethal_not_last() -> void:
	var kc := KillCredit.new()
	kc.record_damage(2, 3, 9.0)
	kc.record_damage(2, 1, 10.0)
	assert_eq(kc.resolve(2, 3, 10.0), 3)


func test_environmental_within_window() -> void:
	var kc := KillCredit.new()
	kc.record_damage(2, 1, 10.0)
	assert_eq(kc.resolve(2, KillCredit.NONE, 14.9), 1)
	assert_eq(kc.resolve(2, KillCredit.NONE, 15.0), 1)


func test_environmental_after_window() -> void:
	var kc := KillCredit.new()
	kc.record_damage(2, 1, 10.0)
	assert_eq(kc.resolve(2, KillCredit.NONE, 15.01), KillCredit.NONE)


func test_environmental_without_attacker() -> void:
	var kc := KillCredit.new()
	assert_eq(kc.resolve(2, KillCredit.NONE, 3.0), KillCredit.NONE)


func test_last_enemy_attacker_wins() -> void:
	var kc := KillCredit.new()
	kc.record_damage(2, 1, 10.0)
	kc.record_damage(2, 3, 11.0)
	assert_eq(kc.resolve(2, KillCredit.NONE, 12.0), 3)


func test_self_damage_never_credits_self() -> void:
	var kc := KillCredit.new()
	kc.record_damage(2, 2, 10.0)
	assert_eq(kc.resolve(2, 2, 10.0), KillCredit.NONE)


func test_self_damage_uses_last_enemy_rule() -> void:
	var kc := KillCredit.new()
	kc.record_damage(2, 1, 10.0)
	kc.record_damage(2, 2, 12.0)
	assert_eq(kc.resolve(2, 2, 12.0), 1, "enemy within 5 s gets credit")
	assert_eq(kc.resolve(2, 2, 16.0), KillCredit.NONE, "outside 5 s nobody")


func test_reset_and_forget() -> void:
	var kc := KillCredit.new()
	kc.record_damage(2, 1, 10.0)
	kc.forget(2)
	assert_eq(kc.resolve(2, KillCredit.NONE, 10.0), KillCredit.NONE)
	kc.record_damage(3, 1, 10.0)
	kc.reset()
	assert_eq(kc.resolve(3, KillCredit.NONE, 10.0), KillCredit.NONE)
