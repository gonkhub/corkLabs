# Events booked for exact moments of facility time ("at 03:40, the pipe in
# bay 2 starts leaking"). Events are plain data (a name + a Dictionary), so
# they can be saved and loaded; whoever cares about an event listens for its
# name when it fires.
#
# Two events at the same moment fire in the order they were booked, so a
# replay always plays out the same way.
class_name EventScheduler
extends RefCounted

# Each entry: {"id": int, "time": float, "seq": int, "name": String, "data": Dictionary}
var _entries: Array[Dictionary] = []
var _next_id := 1


## Books `event_name` at facility time `at` (seconds). Returns an id for cancel().
## A time already in the past fires on the next tick.
func schedule(at: float, event_name: String, data := {}) -> int:
	var e := {"id": _next_id, "time": at, "seq": _next_id, "name": event_name, "data": data}
	_next_id += 1
	# Keep sorted by (time, seq): insert after everything due at or before `at`.
	var i := _entries.size()
	while i > 0 and _entries[i - 1].time > at:
		i -= 1
	_entries.insert(i, e)
	return e.id


func cancel(id: int) -> bool:
	for i in _entries.size():
		if _entries[i].id == id:
			_entries.remove_at(i)
			return true
	return false


## Removes and returns every event due at or before `now`, in firing order.
func pop_due(now: float) -> Array[Dictionary]:
	var due: Array[Dictionary] = []
	while not _entries.is_empty() and _entries[0].time <= now:
		due.append(_entries.pop_front())
	return due


## The next `count` events, without removing them (for the dev overlay).
func peek(count := 5) -> Array[Dictionary]:
	return _entries.slice(0, count)


func size() -> int:
	return _entries.size()


func to_data() -> Dictionary:
	return {"next_id": _next_id, "entries": _entries.duplicate(true)}


func from_data(d: Dictionary) -> void:
	_next_id = int(d.get("next_id", 1))
	_entries.clear()
	for e in d.get("entries", []):
		_entries.append({"id": int(e.id), "time": float(e.time), "seq": int(e.seq),
			"name": str(e.name), "data": e.get("data", {})})
