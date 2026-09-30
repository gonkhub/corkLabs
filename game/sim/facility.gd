# Autoload "Facility": holds the FacilitySim for a game session and saves it.
#
# Facility time NEVER moves on its own (like Disco Elysium's clock). It only
# advances when the player does something: reading a new line of dialogue,
# making a choice, triggering an interaction or event. Each of those calls
#     Facility.spend(Facility.COST.dialogue_line, "Tinker: status report")
# and the simulation (robots, scheduled events, shifts...) plays out through
# exactly that much facility time. Animations keep playing in real time, but
# the state of the facility waits for the player.
#
# Closing the game saves; opening it resumes at exactly the saved moment, and
# the corkLabs OS clock shows facility time, not the real clock.
#
# Gameplay scenes do:
#     Facility.start_session([their systems...])   # load the save, or start a new facility
# Scenes that don't (the VR recorder, Robot Lab) leave the facility untouched.
extends Node

signal session_started
signal session_ended
## Facility time moved forward because of `cause`.
signal time_spent(from_time: float, to_time: float, cause: String)

const SAVE_PATH := "user://facility_save.json"

## Facility seconds each kind of player action costs. Tune freely.
const COST := {
	"dialogue_line": 60.0,     # reading a new line: 1 minute
	"choice": 120.0,           # picking a reply or giving an order: 2 minutes
	"interaction": 300.0,      # opening a feed, inspecting something: 5 minutes
	"task": 900.0,             # an action that takes a while: 15 minutes
}

var sim: FacilitySim
var running := false
var save_path := SAVE_PATH


## Opens the facility: adds `systems`, then loads the save (or starts a new
## facility if there isn't one). Facility time resumes from the saved moment.
func start_session(systems: Array = [], path := SAVE_PATH, seed_value := -1) -> void:
	save_path = path
	sim = FacilitySim.new()
	for s in systems:
		sim.add_system(s)
	var data := _read_save(path)
	if data.is_empty():
		sim.new_game(seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system()))
		for s in systems:
			if s.has_method("sim_start"):
				s.sim_start(sim)
	else:
		sim.load_data(data)
	running = true
	save()
	session_started.emit()


func end_session() -> void:
	if not running:
		return
	save()
	running = false
	session_ended.emit()


## The one way facility time moves: the player did something that takes
## `seconds` of facility time. Robots and events play out through it.
## `cause` is written to the journal ("dialogue: Tinker asks about pod 14").
func spend(seconds: float, cause: String) -> void:
	if not running or seconds <= 0.0:
		return
	var from := sim.time()
	sim.note("time", "+%s  %s" % [_short(seconds), cause])
	sim.advance(seconds)
	save()
	time_spent.emit(from, sim.time(), cause)


## spend() by action kind: Facility.act("dialogue_line", "Tinker: hello").
func act(kind: String, cause: String) -> void:
	spend(float(COST.get(kind, 60.0)), cause)


## The facility clock as the corkLabs OS shows it ("06:42").
func clock_text() -> String:
	return FacilitySim.format_clock(sim.time()) if sim else "--:--"


func save() -> void:
	if sim == null:
		return
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_error("Facility: can't write save %s" % save_path)
		return
	f.store_string(JSON.stringify(sim.save_data(), "\t"))


## Deletes the save so the next session starts a brand-new facility (dev tool).
func wipe_save(path := SAVE_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		end_session()


static func _short(seconds: float) -> String:
	if seconds < 60.0:
		return "%ds" % int(seconds)
	if seconds < 3600.0:
		return "%dm" % int(seconds / 60.0)
	return "%.1fh" % (seconds / 3600.0)


func _read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and int(parsed.get("version", 0)) == FacilitySim.SAVE_VERSION:
		return parsed
	push_warning("Facility: save %s unreadable or old version; starting a new facility" % path)
	return {}
