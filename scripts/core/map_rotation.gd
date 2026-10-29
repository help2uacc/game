class_name MapRotation
extends RefCounted
## Shuffled map queue (§4.5). Server only.

var _all: Array[String] = []
var _queue: Array[String] = []
var _last: String = ""
var _rng: RandomNumberGenerator


func _init(map_ids: Array[String], rng: RandomNumberGenerator) -> void:
	_all = map_ids.duplicate()
	_rng = rng
	_refill()


func _shuffle(arr: Array[String]) -> void:
	for i: int in range(arr.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: String = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _refill() -> void:
	_queue = _all.duplicate()
	_shuffle(_queue)
	# Ensure the first map of the new queue differs from the last map played.
	if _queue.size() > 1 and _queue[0] == _last:
		var swap_index: int = _rng.randi_range(1, _queue.size() - 1)
		var tmp: String = _queue[0]
		_queue[0] = _queue[swap_index]
		_queue[swap_index] = tmp


func next() -> String:
	if _queue.is_empty():
		_refill()
	_last = _queue.pop_front()
	return _last


func remaining() -> int:
	return _queue.size()
