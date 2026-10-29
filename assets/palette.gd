class_name Palette
extends RefCounted
## Global colour palette (PRD §11.1). Single source of truth for colours.

const INK := Color("#3A3550")
const WHITE := Color("#FFFDF8")
const BG_SKY := Color("#DCEBFF")
const BG_SKY_LOW := Color("#FFF0F5")
const UI_PANEL := Color(1.0, 1.0, 1.0, 0.85)
const UI_SHADOW := Color(0.22745098, 0.20784314, 0.31372549, 0.15)
const DANGER := Color("#FF6B6B")
const HEAL := Color("#FF8FA3")
const ARMOR := Color("#8EC9FF")
const GOLD := Color("#FFD36E")

## Player colours (PRD §6.2), index = colour id.
const PLAYER_COLORS: Array[Color] = [
	Color("#FF8FB1"),
	Color("#FFB26B"),
	Color("#FFE066"),
	Color("#8FD694"),
	Color("#6FD3C8"),
	Color("#7FB7FF"),
	Color("#B49CFF"),
	Color("#C49A7A"),
]

const PLAYER_COLOR_NAMES: PackedStringArray = [
	"Pink", "Orange", "Yellow", "Green", "Teal", "Blue", "Purple", "Cocoa",
]

const COLOR_COUNT := 8


static func player_color(color_id: int) -> Color:
	if color_id < 0 or color_id >= COLOR_COUNT:
		return WHITE
	return PLAYER_COLORS[color_id]
