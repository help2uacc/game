extends SceneTree
## Prints an override.cfg that escalates every GDScript warning that is
## enabled by default (level WARN) to ERROR. Used by tools/check.sh so that
## warnings fail the headless checks (Godot does not print them headless).


func _initialize() -> void:
	var lines: PackedStringArray = ["[debug]", ""]
	for p: Dictionary in ProjectSettings.get_property_list():
		var n: String = p["name"]
		if not n.begins_with("debug/gdscript/warnings/"):
			continue
		var v: Variant = ProjectSettings.get_setting(n)
		if typeof(v) == TYPE_INT and int(v) == 1:
			lines.append("%s=2" % n.trim_prefix("debug/"))
	print("\n".join(lines))
	quit()
