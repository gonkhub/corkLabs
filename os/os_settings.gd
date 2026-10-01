# The corkLabs OS's own preferences (not the facility: nothing here is game
# state). Saved in user://os_settings.json:
#   ui_scale, fullscreen, boot animation, which pop-ups to show, robot voices,
#   camera feed sound (mute, volume),
#   and the window layout (which apps were open, where, and their view state)
#   so the desktop comes back the way you left it,
#   and the Notes app's text (the desk's notepad outlives any one facility).
class_name OSSettings
extends RefCounted

const PATH := "user://os_settings.json"
## What the Notes app's notepad says the first time: the last supervisor's leftovers.
const NOTES_LEFTOVER := """--- already on the notepad when you arrived ---

mornings (D.O.)
  - say good morning to Tinker (talk tinker)
  - morning report BEFORE Pell asks
  - look at pod 3's sync. 4 beats, 3 beats. every time.
  - do NOT let Pell see this notepad

the desk keeps what you write here. the facility doesn't.

--- your notes ---
"""
const DEFAULTS := {
	"devtools": false,
	"ui_scale": 1.0,
	"fullscreen": false,
	"boot_animation": true,
	"restore_windows": true,
	"toast_alarm": true,
	"toast_report": true,
	"voices": true,
	"voice_volume": 0.6,
	"feed_muted": false,
	"feed_volume": 1.0,
	"windows": {},     # app id -> {"rect": [x, y, w, h], "open": bool, "minimized": bool, "maximized": bool, "state": {...}}
	"notes": NOTES_LEFTOVER,   # the Notes app: the supervisor's own notepad (it's the desk: it survives new saves)
}

static var path := PATH
static var _data := {}


static func get_value(key: String) -> Variant:
	_ensure()
	return _data.get(key, DEFAULTS.get(key))


static func set_value(key: String, value: Variant) -> void:
	_ensure()
	_data[key] = value
	save()


static func windows() -> Dictionary:
	_ensure()
	if not _data.get("windows") is Dictionary:
		_data["windows"] = {}
	return _data["windows"]


static func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_data, "\t"))


## Switch to (and load) another settings file (tests use their own).
static func use_file(new_path := PATH) -> void:
	path = new_path
	_data = {}
	_ensure()


static func _ensure() -> void:
	if not _data.is_empty():
		return
	_data = DEFAULTS.duplicate(true)
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			for k in d:
				_data[k] = d[k]
