extends SceneTree
## Headless test runner: godot --headless -s tests/run_tests.gd
## Runs every test_*() method of every res://tests/test_*.gd script.
## Exit code 0 = all passed, 1 = failures.

var _started: bool = false


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	_run.call_deferred()
	return false


func _run() -> void:
	var files: PackedStringArray = []
	var dir := DirAccess.open("res://tests")
	if dir == null:
		printerr("Cannot open res://tests")
		quit(1)
		return
	for f: String in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			files.append(f)
	files.sort()
	var total: int = 0
	var failed: int = 0
	for f: String in files:
		var script: GDScript = load("res://tests/" + f)
		if script == null:
			printerr("FAILED to load %s" % f)
			failed += 1
			continue
		var methods: Array[String] = []
		for m: Dictionary in script.get_script_method_list():
			var mname: String = m["name"]
			if mname.begins_with("test_") and not methods.has(mname):
				methods.append(mname)
		methods.sort()
		for mname: String in methods:
			var inst: TestCase = script.new()
			inst.current_test = "%s::%s" % [f.get_basename(), mname]
			# Tests may be coroutines (await physics frames); awaiting a plain
			# return value is a no-op.
			await inst.call(mname)
			inst.cleanup()
			total += 1
			if inst.failures.is_empty():
				print("  PASS %s" % inst.current_test)
			else:
				failed += 1
				for msg: String in inst.failures:
					printerr("  FAIL %s" % msg)
	print("Tests: %d run, %d failed" % [total, failed])
	# Release static caches / audio so nothing is reported as leaked at exit.
	MaterialCache.clear()
	WeaponDB.clear()
	var audio: Node = root.get_node_or_null("AudioManager")
	if audio != null:
		audio.call("release_all")
	# Let the audio server retire stopped playbacks before exiting.
	await create_timer(0.25).timeout
	quit(1 if failed > 0 else 0)
