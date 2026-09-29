# The facility's journal: a timestamped line for everything worth knowing
# ("Hauler reached station 2", "Pod 14 pressure low"). It's how you debug
# robot behaviour, and it's where the "while you were away" report comes from.
class_name FacilityLog
extends RefCounted

## Oldest lines are dropped past this many.
const MAX_ENTRIES := 5000

# Each entry: {"t": facility seconds, "cat": category, "text": String}
var entries: Array[Dictionary] = []


func add(t: float, category: String, text: String) -> void:
	entries.append({"t": t, "cat": category, "text": text})
	if entries.size() > MAX_ENTRIES:
		entries = entries.slice(entries.size() - MAX_ENTRIES)


## Entries at or after facility time `t`.
func since(t: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in entries:
		if e.t >= t:
			out.append(e)
	return out


func tail(count: int) -> Array[Dictionary]:
	return entries.slice(maxi(0, entries.size() - count))


static func format_entry(e: Dictionary) -> String:
	return "%s  [%s] %s" % [FacilitySim.format_time(e.t), e.cat, e.text]


func to_data() -> Array:
	return entries.duplicate(true)


func from_data(d: Array) -> void:
	entries.clear()
	for e in d:
		entries.append({"t": float(e.t), "cat": str(e.cat), "text": str(e.text)})
