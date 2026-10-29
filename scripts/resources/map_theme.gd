class_name MapTheme
extends Resource
## Per-map pastel theme (PRD §10.2). Instances in res://data/themes/*.tres.

@export var id: String = ""
@export var primary: Color = Color.WHITE
@export var secondary: Color = Color.WHITE
@export var platform: Color = Color.WHITE
@export var lava: Color = Color("#FF9F5A")
@export var crate: Color = Color("#E2B07A")
@export var bg_top: Color = Color("#DCEBFF")
@export var bg_bottom: Color = Color("#FFF0F5")
@export var decor_a: Color = Color.WHITE
@export var decor_b: Color = Color.WHITE
## Extra colours for rainbow themes (decorative variation of `%` cells).
@export var accents: Array[Color] = []
