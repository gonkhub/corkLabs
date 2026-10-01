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
# ERRANDS are the one exception, and they're still the player's doing: when
# the supervisor sends a unit to do a job (order maintenance), the order
# costs nothing up front. Instead the facility runs on fast-forward while
# you watch: the unit rides to the job (about ERRAND_TRAVEL real seconds),
# works (about ERRAND_WORK real seconds: its work clip plays), and the job's
# done. The clock stops again when it is. So the time passes as the job
# completes, not when it was ordered. finish_errands() runs them out at once.
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

## Facility seconds each kind of player action costs. Tune freely. (A shift
## is 480 minutes: these are set so a shift holds a couple of dozen real
## actions, and nobody sees everything in one day.)
const COST := {
	"dialogue_line": 180.0,    # reading a new line: 3 minutes
	"choice": 300.0,           # picking a reply or giving an order: 5 minutes
	"interaction": 900.0,      # searching, inspecting something: 15 minutes
	"task": 2700.0,            # an action that takes a while: 45 minutes
}

var sim: FacilitySim
var running := false
var save_path := SAVE_PATH

## Real seconds an errand's trip and its work take to watch.
const ERRAND_TRAVEL := 3.0
const ERRAND_WORK := 2.5
## Facility seconds per real second, at least (so nothing crawls).
const ERRAND_MIN_RATE := 30.0
## An errand gives up after this much facility time (the unit never got there).
const ERRAND_LIMIT := 4.0 * 3600.0
## Running errands: [{"job", "unit" (sim id), "cause", "spent", "phase", "rate"}].
var errands: Array[Dictionary] = []
var _errand_from := -1.0


## Sends the clock on fast-forward until this unit has done this job.
func start_errand(job_id: int, unit_sim_id: String, cause: String) -> void:
	if not running:
		return
	if errands.is_empty():
		_errand_from = sim.time()
	errands.append({"job": job_id, "unit": unit_sim_id, "cause": cause, "spent": 0.0, "phase": "", "rate": ERRAND_MIN_RATE})


func errand_running() -> bool:
	return not errands.is_empty()


## Runs every errand to its end right away (tests; skipping the wait).
func finish_errands() -> void:
	var guard := 0
	while not errands.is_empty() and guard < 2000:
		_errand_step(60.0)
		guard += 1


func _process(delta: float) -> void:
	if errands.is_empty() or not running:
		return
	var rate := ERRAND_MIN_RATE
	for e in errands:
		_errand_pace(e)
		rate = maxf(rate, float(e.rate))
	_errand_step(minf(rate * delta, 900.0))


# How fast this errand wants the clock to run: set at the start of each phase
# (the trip, the work) so that phase takes about its real seconds.
func _errand_pace(e: Dictionary) -> void:
	var bot := sim.get_system(str(e.unit)) as RobotAgent
	if bot == null:
		return
	var est := bot.errand_estimate(sim, int(e.job))
	if est.phase != e.phase:
		e.phase = est.phase
		var real: float = ERRAND_WORK if est.phase == "work" else ERRAND_TRAVEL
		e.rate = maxf(float(est.left) / real, ERRAND_MIN_RATE)


func _errand_step(seconds: float) -> void:
	sim.advance(seconds)
	for e in errands.duplicate():
		e.spent = float(e.spent) + seconds
		var board := sim.get_system("work") as WorkBoard
		var job: Dictionary = board.get_job(int(e.job)) if board else {}
		var bot := sim.get_system(str(e.unit)) as RobotAgent
		var camp := sim.get_system("campaign") as Campaign
		var over := not WorkBoard.active(job) or bot == null or bot.offline() or float(e.spent) >= ERRAND_LIMIT \
			or (camp != null and not camp.on_duty())
		if over:
			errands.erase(e)
	if errands.is_empty():
		var from := _errand_from
		sim.note("time", "+%s  errand done" % _short(sim.time() - from))
		save()
		time_spent.emit(from, sim.time(), "errand")
	else:
		time_spent.emit(sim.time() - seconds, sim.time(), "errand")


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
## `journal` false skips the "+1m cause" line (for a long wait passed in
## steps, which journals itself once).
func spend(seconds: float, cause: String, journal := true) -> void:
	if not running or seconds <= 0.0:
		return
	var from := sim.time()
	if journal:
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


## Deletes the save (and its shift checkpoint) so the next session starts a
## brand-new facility.
func wipe_save(path := SAVE_PATH) -> void:
	for p in [path, checkpoint_path(path)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


# --- Shift checkpoints ------------------------------------------------------------
# The save as it was at the start of the current shift (its brief). Being
# dismissed sends the supervisor back here: "retry the shift".

static func checkpoint_path(path := SAVE_PATH) -> String:
	return path.get_basename() + "_checkpoint.json"


## Saves, and keeps a copy as the shift's checkpoint.
func checkpoint() -> void:
	if sim == null:
		return
	save()
	var f := FileAccess.open(checkpoint_path(save_path), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(sim.save_data(), "\t"))


func has_checkpoint(path := SAVE_PATH) -> bool:
	return FileAccess.file_exists(checkpoint_path(path))


## Puts the checkpoint back as the save (call with the session closed).
## Returns false if there isn't one.
func restore_checkpoint(path := SAVE_PATH) -> bool:
	if running or not has_checkpoint(path):
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(FileAccess.get_file_as_string(checkpoint_path(path)))
	return true


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
