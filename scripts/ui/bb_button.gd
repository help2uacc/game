class_name BBButton
extends Button
## Themed button: press = scale 0.95 + click SFX (PRD §9).

@export var click_sfx: String = "ui_click"


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	button_down.connect(_on_down)
	button_up.connect(_on_up)
	resized.connect(_update_pivot)


func _update_pivot() -> void:
	pivot_offset = size * 0.5


func _on_down() -> void:
	_update_pivot()
	scale = Vector2(0.95, 0.95)
	if not click_sfx.is_empty():
		AudioManager.play_ui(click_sfx)


func _on_up() -> void:
	scale = Vector2.ONE
