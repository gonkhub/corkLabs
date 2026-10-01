# corkHQ: corporate (sim_id "hq"). It tells the supervisor what to do and
# judges them. Everything it says lands in `messages`, which the corkHQ panel
# on the desktop shows (and which the player can't close, mute or move).
#
#   - a welcome at the start (including how to reach the software server)
#   - a directive at every shift start (the throughput target)
#   - a REVIEW at every shift end: a grade A-F from the shift's throughput,
#     which sets next shift's budget (Requisitions) and moves the supervisor's
#     software clearance (SoftwareLibrary)
#   - hourly checks: nags when throughput is below target, or units sit idle
#   - reactions: unit crashes, anomalous damage (sabotage)
#   - feedback from the other corporate systems: requisition confirmations
#     and status, software request approvals (with install codes)
#
# Lines come from game/corporate/hq_lines.txt (trigger | condition | sender | text).
class_name CorkHQ
extends RefCounted

const LINES_PATH := "res://game/corporate/hq_lines.txt"
const MESSAGES_KEPT := 80
const CHECK_EVERY := 3600.0
## Throughput the facility is expected to hold.
const TARGET := 0.85
const GRADES := ["A", "B", "C", "D", "F"]
## Where approved software comes from (IT tells the player in the welcome).
const SERVER := "cork://pkg.corklabs.int"

var sim_id := "hq"
## Newest last: {"n", "t", "sender", "kind", "text", "code"}
## kind: "directive", "review", "notice", "order", "software", "warning"
var messages: Array[Dictionary] = []
## How many messages have ever been posted (the panel watches this).
var posted := 0
## The last shift's grade ("" before the first review).
var grade := ""
var rng := RandomNumberGenerator.new()

var _lines: Array[Dictionary] = []
var _acc := 0.0


func _init() -> void:
	_lines = DataTable.read(LINES_PATH, PackedStringArray(["trigger", "condition", "sender", "text"]))


## Posts a message. Other systems call this for their feedback.
func post(sim: FacilitySim, sender: String, kind: String, text: String, code := "") -> void:
	posted += 1
	messages.append({"n": posted, "t": sim.time(), "sender": sender, "kind": kind, "text": text, "code": code})
	if messages.size() > MESSAGES_KEPT:
		messages.pop_front()
	sim.note("hq", "%s: %s" % [sender, text])


## Posts a line from hq_lines.txt for this trigger (and condition), with placeholders filled.
func say(sim: FacilitySim, trigger: String, kind: String, ctx := {}, condition := "") -> void:
	var options := _lines.filter(func(l): return l.trigger == trigger and (l.condition == condition or l.condition == ""))
	var exact := options.filter(func(l): return l.condition == condition)
	if not exact.is_empty():
		options = exact
	if options.is_empty():
		return
	var line: Dictionary = options[rng.randi() % options.size()]
	var text: String = line.text
	for k in ctx:
		text = text.replace("{%s}" % k, str(ctx[k]))
	text = text.replace("{target}", "%d%%" % roundi(TARGET * 100.0)).replace("{server}", SERVER)
	post(sim, line.sender, kind, text)


## Messages posted after number `mark`.
func since(mark: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in messages:
		if int(m.n) > mark:
			out.append(m)
	return out


static func grade_for(throughput: float) -> String:
	if throughput >= TARGET + 0.05:
		return "A"
	if throughput >= TARGET:
		return "B"
	if throughput >= TARGET - 0.1:
		return "C"
	if throughput >= TARGET - 0.2:
		return "D"
	return "F"


# --- System ------------------------------------------------------------------------------

func sim_start(sim: FacilitySim) -> void:
	rng.seed = sim.rng.randi()
	var req := sim.get_system("requisitions") as Requisitions
	for i in 3:
		var lines := _lines.filter(func(l): return l.trigger == "welcome")
		if i < lines.size():
			var text: String = lines[i].text.replace("{funds}", "%d cr" % (req.funds if req else 0)) \
				.replace("{target}", "%d%%" % roundi(TARGET * 100.0)).replace("{server}", SERVER)
			post(sim, lines[i].sender, "directive", text)


func sim_tick(sim: FacilitySim, dt: float) -> void:
	var camp := sim.get_system("campaign") as Campaign
	if camp and not camp.on_duty():
		return   # nobody to nag between shifts
	_acc += dt
	if _acc < CHECK_EVERY - 0.001:
		return
	_acc = 0.0
	var plant := sim.get_system("plant") as FacilityPlant
	if plant and plant.throughput < TARGET - 0.05:
		say(sim, "check", "warning", {"throughput": "%d%%" % roundi(plant.throughput * 100.0)}, "low")
	var idle := FacilitySetup.robots(sim).filter(func(r): return r.activity.kind == "idle")
	if not idle.is_empty() and idle.size() == FacilitySetup.robots(sim).size() and rng.randf() < 0.5:
		say(sim, "idle_units", "warning")


func sim_event(sim: FacilitySim, event_name: String, data: Dictionary) -> void:
	match event_name:
		"shift_start":
			var shifts := sim.get_system("shifts") as ShiftSchedule
			say(sim, "shift_start", "directive", {"shift": shifts.names[int(data.index)] if shifts else "A"})
		"shift_end":
			_review(sim)
		"alarm":
			var camp := sim.get_system("campaign") as Campaign
			if camp and not camp.on_duty():
				return   # nobody at the desk to tell
			if data.has("robot"):
				var bot := sim.get_system("robot_" + str(data.robot)) as RobotAgent
				if bot and bot.activity.kind == "crashed":
					say(sim, "crash", "warning", {"robot": bot.display_name()})


# End of shift: grade, budget, clearance.
func _review(sim: FacilitySim) -> void:
	var plant := sim.get_system("plant") as FacilityPlant
	if plant == null:
		return
	var st: Dictionary = plant.shift_stats
	var avg := float(st.output_sum) / maxf(float(st.samples), 1.0)
	grade = grade_for(avg)
	var budget := 0
	var req := sim.get_system("requisitions") as Requisitions
	if req:
		budget = req.allocate(sim, grade)
	say(sim, "review", "review", {"grade": grade, "throughput": "%d%%" % roundi(avg * 100.0), "budget": "%d cr" % budget}, grade)
	var sw := sim.get_system("software") as SoftwareLibrary
	if sw:
		sw.review(sim, grade)


## Something suspicious (sabotage) was logged: corporate may notice.
func noticed_damage(sim: FacilitySim, robot: RobotAgent) -> void:
	var camp := sim.get_system("campaign") as Campaign
	if camp and not camp.on_duty():
		return
	if rng.randf() < 0.5:
		say(sim, "sabotage", "warning", {"robot": robot.display_name()})


# --- Save --------------------------------------------------------------------------------

func sim_save() -> Dictionary:
	return {"messages": messages.duplicate(true), "posted": posted, "grade": grade, "acc": _acc,
		"rng_seed": str(rng.seed), "rng_state": str(rng.state)}


func sim_load(d: Dictionary) -> void:
	messages.clear()
	for m in d.get("messages", []):
		var msg: Dictionary = m.duplicate()
		msg.n = int(msg.n)
		msg.t = float(msg.t)
		messages.append(msg)
	posted = int(d.get("posted", 0))
	grade = str(d.get("grade", ""))
	_acc = float(d.get("acc", 0.0))
	rng.seed = int(str(d.get("rng_seed", "0")))
	rng.state = int(str(d.get("rng_state", "0")))


func sim_describe(_sim: FacilitySim) -> PackedStringArray:
	var lines := PackedStringArray(["CORKHQ  last grade %s   %d messages" % [grade if grade != "" else "-", posted]])
	for m in messages.slice(maxi(0, messages.size() - 3)):
		lines.append("  %s  %s: %s" % [FacilitySim.format_clock(m.t), m.sender, m.text])
	return lines
