class_name PlayerInput
extends RefCounted
## One frame of player input (PRD §5.6). Edge-triggered flags ("pressed")
## are latched by the sender until acknowledged.

var seq: int = 0
var move_x: float = 0.0
var down: bool = false
var jump_pressed: bool = false
var jump_held: bool = false
var attack_held: bool = false
var pickup_pressed: bool = false
var throw_pressed: bool = false


func copy_from(o: PlayerInput) -> void:
	seq = o.seq
	move_x = o.move_x
	down = o.down
	jump_pressed = o.jump_pressed
	jump_held = o.jump_held
	attack_held = o.attack_held
	pickup_pressed = o.pickup_pressed
	throw_pressed = o.throw_pressed


func clear() -> void:
	seq = 0
	move_x = 0.0
	down = false
	jump_pressed = false
	jump_held = false
	attack_held = false
	pickup_pressed = false
	throw_pressed = false


## Packs into a compact array for the unreliable_ordered input RPC.
func pack() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(6)
	b.encode_u32(0, seq & 0xFFFFFFFF)
	b.encode_s8(4, clampi(int(round(move_x * 127.0)), -127, 127))
	var flags: int = 0
	if down:
		flags |= 1
	if jump_pressed:
		flags |= 2
	if jump_held:
		flags |= 4
	if attack_held:
		flags |= 8
	if pickup_pressed:
		flags |= 16
	if throw_pressed:
		flags |= 32
	b.encode_u8(5, flags)
	return b


static func unpack(b: PackedByteArray) -> PlayerInput:
	var i := PlayerInput.new()
	if b.size() < 6:
		return i
	i.seq = b.decode_u32(0)
	i.move_x = clampf(float(b.decode_s8(4)) / 127.0, -1.0, 1.0)
	var flags: int = b.decode_u8(5)
	i.down = flags & 1 != 0
	i.jump_pressed = flags & 2 != 0
	i.jump_held = flags & 4 != 0
	i.attack_held = flags & 8 != 0
	i.pickup_pressed = flags & 16 != 0
	i.throw_pressed = flags & 32 != 0
	return i
