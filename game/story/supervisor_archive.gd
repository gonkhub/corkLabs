# The supervisor's record across EVERY run (user://supervisor_archive.json),
# separate from the facility save: secrets ever found, endings seen, how many
# times they've been fired and for what. Wiping the facility doesn't wipe it,
# so the login screen can say "Personnel file: fired twice, 5 of 14 secrets".
#
# It never feeds back into a run's rules: what carries over between runs is
# what the PLAYER remembers (a command, a password), not what the game grants.
class_name SupervisorArchive
extends RefCounted

const PATH := "user://supervisor_archive.json"

static var path := PATH
static var _data := {}
static var _loaded := false


static func data() -> Dictionary:
	_ensure()
	return _data


static func found_secret(id: String) -> void:
	_ensure()
	var s: Array = _data.secrets
	if not s.has(id):
		s.append(id)
		save()


static func saw_ending(id: String) -> void:
	_ensure()
	var e: Array = _data.endings
	if not e.has(id):
		e.append(id)
	_data.completed = int(_data.completed) + 1
	save()


static func was_fired(kind: String) -> void:
	_ensure()
	_data.fired = int(_data.fired) + 1
	var by: Dictionary = _data.fired_by
	by[kind] = int(by.get(kind, 0)) + 1
	save()


static func shift_worked() -> void:
	_ensure()
	_data.shifts = int(_data.shifts) + 1
	save()


static func new_run() -> void:
	_ensure()
	_data.runs = int(_data.runs) + 1
	save()


## One line for the login screen ("" if there's no history yet).
static func summary() -> String:
	_ensure()
	if int(_data.runs) == 0 and int(_data.shifts) == 0:
		return ""
	var parts := PackedStringArray()
	parts.append("%d shift%s worked" % [int(_data.shifts), "" if int(_data.shifts) == 1 else "s"])
	if int(_data.fired) > 0:
		parts.append("dismissed %d time%s" % [int(_data.fired), "" if int(_data.fired) == 1 else "s"])
	parts.append("%d of %d secrets" % [(_data.secrets as Array).size(), Knowledge.secrets().size()])
	if int(_data.completed) > 0:
		parts.append("reached the end %d time%s" % [int(_data.completed), "" if int(_data.completed) == 1 else "s"])
	return "Personnel file: " + ", ".join(parts)


static func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_data, "\t"))


## Tests point this elsewhere.
static func use_file(new_path := PATH) -> void:
	path = new_path
	_loaded = false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_data = {}
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			_data = d
	for k in ["runs", "shifts", "fired", "completed"]:
		_data[k] = int(_data.get(k, 0))
	for k in ["secrets", "endings"]:
		if not (_data.get(k) is Array):
			_data[k] = []
	if not (_data.get("fired_by") is Dictionary):
		_data.fired_by = {}
