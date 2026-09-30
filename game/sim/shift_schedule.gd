# Facility shifts: books "shift_start" / "shift_end" events on a fixed
# rota, forever. A first real system, and a template for writing others.
#
# Default rota: three 8-hour shifts a day starting 06:00, 14:00, 22:00.
class_name ShiftSchedule
extends RefCounted

var sim_id := "shifts"
## Hours of the day shifts start at.
var starts: Array[float] = [6.0, 14.0, 22.0]
var shift_hours := 8.0
## Shift names, same order as `starts`.
var names: Array[String] = ["Day", "Swing", "Night"]

var current := -1          # index into starts, -1 = before the first shift
var shift_number := 0      # counts every shift since the facility came online


func sim_start(sim: FacilitySim) -> void:
	_book_next(sim, sim.time())


func sim_tick(_sim: FacilitySim, _dt: float) -> void:
	pass   # everything happens through events


func sim_event(sim: FacilitySim, event_name: String, data: Dictionary) -> void:
	match event_name:
		"shift_start":
			current = int(data.index)
			shift_number += 1
			sim.note("shift", "%s shift #%d begins" % [names[current], shift_number])
			sim.schedule(data.at + shift_hours * 3600.0, "shift_end", {"index": current})
			_book_next(sim, data.at + 1.0)
		"shift_end":
			sim.note("shift", "%s shift #%d ends" % [names[int(data.index)], shift_number])


func current_name() -> String:
	return names[current] if current >= 0 else "(none)"


# Books the next shift start after facility time `after`.
func _book_next(sim: FacilitySim, after: float) -> void:
	var day := floorf(after / 86400.0)
	for d in 2:
		for i in starts.size():
			var at: float = (day + d) * 86400.0 + starts[i] * 3600.0
			if at >= after:
				sim.schedule(at, "shift_start", {"index": i, "at": at})
				return


func sim_save() -> Dictionary:
	return {"current": current, "shift_number": shift_number}


func sim_load(d: Dictionary) -> void:
	current = int(d.get("current", -1))
	shift_number = int(d.get("shift_number", 0))
