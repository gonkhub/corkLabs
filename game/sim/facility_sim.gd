# The facility simulation: its own clock, scheduled events, seeded
# randomness, a journal, and the systems (robots, pipes, pods...) that
# update on each tick.
#
# Facility time is separate from real time and only moves when the player
# acts (Facility.spend: a dialogue line, a choice, an interaction). It's saved
# when the game closes and resumes at exactly the saved moment. The corkLabs
# OS clock shows facility time, not the real clock.
#
# It's built to be repeatable: every tick is exactly TICK facility seconds,
# systems update in a fixed order, and all randomness comes from `rng`. The
# same save + the same inputs always produce the same facility, which makes
# bugs reproducible.
#
# A "system" is any object with:
#   var sim_id: String                     unique, also its save key
#   func sim_tick(sim: FacilitySim, dt: float) -> void
#   func sim_start(sim: FacilitySim) -> void   (optional: brand-new facility only)
#   func sim_save() -> Dictionary          (optional)
#   func sim_load(data: Dictionary) -> void  (optional)
#   func sim_event(sim: FacilitySim, name: String, data: Dictionary) -> void  (optional)
class_name FacilitySim
extends RefCounted

## Length of one simulation step, in facility seconds (10 steps per second).
const TICK := 0.1
## Where a brand-new facility's clock starts: Day 1, 05:55 (the first shift
## starts at 06:00).
const START_TIME := 5 * 3600 + 55 * 60
const SAVE_VERSION := 4   # 3: robots, work board. 4: plant

signal ticked(tick: int)
signal event_fired(event_name: String, data: Dictionary)

var tick := 0
var rng := RandomNumberGenerator.new()
var scheduler := EventScheduler.new()
var journal := FacilityLog.new()

var _systems := {}
var _order: Array[String] = []
var _carry := 0.0   # leftover time smaller than one tick


func new_game(seed_value: int) -> void:
	tick = int(START_TIME / TICK)
	_carry = 0.0
	rng.seed = seed_value
	scheduler = EventScheduler.new()
	journal = FacilityLog.new()
	note("facility", "Facility online (seed %d)" % seed_value)


## Facility time in seconds since Day 1 00:00.
func time() -> float:
	return tick * TICK


func note(category: String, text: String) -> void:
	journal.add(time(), category, text)


# --- Systems -------------------------------------------------------------------

func add_system(system: Object) -> void:
	var id: String = system.get("sim_id")
	assert(not id.is_empty(), "system needs a sim_id")
	_systems[id] = system
	_order.assign(_systems.keys())
	_order.sort()   # fixed update order, whatever order they were added in


func remove_system(id: String) -> void:
	_systems.erase(id)
	_order.erase(id)


func get_system(id: String) -> Object:
	return _systems.get(id)


func system_ids() -> Array[String]:
	return _order.duplicate()


# --- Time ------------------------------------------------------------------------

## One tick: due events fire first, then every system updates.
func step() -> void:
	tick += 1
	if scheduler.has_due(time()):
		for e in scheduler.pop_due(time()):
			_fire(e)
	for id in _order:
		var s: Object = _systems.get(id)
		if s:
			s.sim_tick(self, TICK)
	ticked.emit(tick)


## Runs the simulation forward by `seconds` of facility time. Time smaller
## than a tick is carried over to the next call. Returns ticks run.
func advance(seconds: float) -> int:
	var total := _carry + maxf(seconds, 0.0)
	var n := int(floor(total / TICK + 1e-6))
	_carry = maxf(total - n * TICK, 0.0)
	for i in n:
		step()
	return n


func schedule(at: float, event_name: String, data := {}) -> int:
	return scheduler.schedule(at, event_name, data)


## Books an event `delay` facility seconds from now.
func schedule_in(delay: float, event_name: String, data := {}) -> int:
	return scheduler.schedule(time() + delay, event_name, data)


func _fire(e: Dictionary) -> void:
	event_fired.emit(e.name, e.data)
	for id in _order:
		var s: Object = _systems.get(id)
		if s and s.has_method("sim_event"):
			s.sim_event(self, e.name, e.data)


# --- Save / load -----------------------------------------------------------------

func save_data() -> Dictionary:
	var systems := {}
	for id in _order:
		var s: Object = _systems[id]
		if s.has_method("sim_save"):
			systems[id] = s.sim_save()
	return {
		"version": SAVE_VERSION,
		"tick": tick,
		"carry": _carry,
		"rng_seed": str(rng.seed),     # 64-bit numbers saved as text so JSON can't round them
		"rng_state": str(rng.state),
		"scheduler": scheduler.to_data(),
		"journal": journal.to_data(),
		"systems": systems,
	}


## Restores a save. Add systems BEFORE loading so they get their data back.
func load_data(d: Dictionary) -> void:
	tick = int(d.get("tick", 0))
	_carry = float(d.get("carry", 0.0))
	rng.seed = int(str(d.get("rng_seed", "0")))
	rng.state = int(str(d.get("rng_state", "0")))
	scheduler.from_data(d.get("scheduler", {}))
	journal.from_data(d.get("journal", []))
	var systems: Dictionary = d.get("systems", {})
	for id in _order:
		var s: Object = _systems[id]
		if systems.has(id) and s.has_method("sim_load"):
			s.sim_load(systems[id])


# --- Formatting --------------------------------------------------------------------

## 97327.4 -> "Day 2  03:02:07"
static func format_time(t: float) -> String:
	var total := int(floor(t))
	var day := total / 86400 + 1
	var h := (total % 86400) / 3600
	var m := (total % 3600) / 60
	var s := total % 60
	return "Day %d  %02d:%02d:%02d" % [day, h, m, s]


## Just the clock part: 97327.4 -> "03:02"
static func format_clock(t: float) -> String:
	var total := int(floor(t))
	return "%02d:%02d" % [(total % 86400) / 3600, (total % 3600) / 60]
