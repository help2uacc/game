extends SceneTree
## Loads every GDScript in the project so parse errors (including warnings
## escalated to errors by override.cfg) are reported. Exit 1 on failure.


func _collect(path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for d: String in dir.get_directories():
		if d.begins_with("."):
			continue
		_collect(path.path_join(d), out)
	for f: String in dir.get_files():
		if f.ends_with(".gd"):
			out.append(path.path_join(f))


func _initialize() -> void:
	var files: PackedStringArray = []
	_collect("res://", files)
	var failed: int = 0
	for f: String in files:
		if f == get_script().resource_path:
			continue
		var s: Script = ResourceLoader.load(f, "", ResourceLoader.CACHE_MODE_IGNORE)
		if s == null or not s.can_instantiate() and not (s as GDScript).is_abstract():
			printerr("LINT FAIL: %s" % f)
			failed += 1
	print("lint: %d scripts, %d failed" % [files.size(), failed])
	quit(1 if failed > 0 else 0)
