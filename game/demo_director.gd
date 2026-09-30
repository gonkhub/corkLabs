# Runs the demo facility: the standard facility simulation (FacilitySetup)
# shown through security cameras, with a bare-bones supervisor console.
# The robots decide for themselves (see game/sim/robot_agent.gd); you can
# give orders, and every order or wait spends facility time.
#
# Keys:
#   Tab / 1 2 3     switch camera
#   Q               select the other robot
#   O               order it to take the most urgent job it can reach
#   R / S           order it to recharge / to stand by
#   X               cancel its order
#   W               wait and watch (5 facility minutes pass)
#   C               toggle the CCTV filter
#   F1 / F2         dev panel / its pages      F9 post a random job (dev)
extends Node3D

const JOURNAL_LINES := 7

## Separate save from the real game, so demo poking never touches it.
@export var save_path := "user://demo_facility_save.json"

@onready var cameras: Array[Camera3D] = [$Cameras/Cam1, $Cameras/Cam2, $Cameras/Cam3]
@onready var cctv: CanvasItem = $Overlay/CCTV
@onready var cam_label: Label = $Overlay/CamLabel
@onready var help_label: Label = $Overlay/Help
@onready var tinker: RobotActor = $TinkerRail/Rider/Swing/Tinker
@onready var tinker_rider: RailRider = $TinkerRail/Rider
@onready var hauler: RobotActor = $HaulerRail/Rider/Swing/Hauler
@onready var hauler_rider: RailRider = $HaulerRail/Rider

var cam_index := 0
var selected := "tinker"
var last_reply := ""


func _ready() -> void:
	if FlatScreen.relaunch_if_xr(self):
		return
	Facility.start_session(FacilitySetup.systems(), save_path)
	for pair in [["tinker", tinker_rider, tinker], ["hauler", hauler_rider, hauler]]:
		var view := RobotView.new()
		view.setup(pair[0], pair[1], pair[2])
		add_child(view)
	_use_camera(0)
	help_label.add_theme_font_override("font", Mono.font())


func _process(_delta: float) -> void:
	# The corkLabs clock shows facility time, not the real clock.
	cam_label.text = "CAM %02d  %s   %s   REC" % [
		cam_index + 1, cameras[cam_index].name.to_upper(), FacilitySim.format_time(Facility.sim.time())]
	help_label.text = _console_text()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var bot := _selected_agent()
	match event.keycode:
		KEY_TAB:
			_use_camera((cam_index + 1) % cameras.size())
		KEY_1, KEY_2, KEY_3:
			_use_camera(event.keycode - KEY_1)
		KEY_Q:
			selected = "hauler" if selected == "tinker" else "tinker"
		KEY_O:
			var job := _most_urgent_job(bot)
			if job.is_empty():
				last_reply = "No open job %s can reach." % bot.display_name()
			else:
				_order(bot, "job", int(job.id), "take job #%d %s" % [job.id, job.title])
		KEY_R:
			_order(bot, "recharge", -1, "recharge")
		KEY_S:
			_order(bot, "standby", -1, "stand by")
		KEY_X:
			_order(bot, "cancel", -1, "cancel its order")
		KEY_W:
			Facility.act("interaction", "Supervisor watches the feeds")
		KEY_C:
			cctv.visible = not cctv.visible
		_:
			return
	get_viewport().set_input_as_handled()


# Giving an order is a choice: it costs facility time, and the robot answers.
func _order(bot: RobotAgent, kind: String, job_id: int, what: String) -> void:
	var r := bot.give_order(Facility.sim, kind, job_id)
	last_reply = "%s: \"%s\"" % [bot.display_name(), r.reply]
	Facility.act("choice", "Supervisor orders %s to %s" % [bot.display_name(), what])


func _selected_agent() -> RobotAgent:
	return Facility.sim.get_system("robot_" + selected) as RobotAgent


# Highest priority first, then the oldest, among jobs on the robot's rail
# that nobody else has claimed.
func _most_urgent_job(bot: RobotAgent) -> Dictionary:
	var board := Facility.sim.get_system("work") as WorkBoard
	var layout := Facility.sim.get_system("layout") as FacilityLayout
	var best := {}
	for j in board.open_jobs():
		if layout.station(j.station).get("rail", "") != bot.rail:
			continue
		if j.status == "claimed" and j.claimed_by != bot.sim_id:
			continue
		if best.is_empty() or int(j.priority) > int(best.priority):
			best = j
	return best


func _console_text() -> String:
	var lines := PackedStringArray()
	for bot in FacilitySetup.robots(Facility.sim):
		var ord := "" if bot.order.is_empty() else "   [order: %s]" % (
			"job #%d" % int(bot.order.job) if bot.order.kind == "job" else str(bot.order.kind))
		lines.append("%s %-7s %-44s power %3d%%   %s%s" % [">" if bot.robot_id == selected else " ",
			bot.display_name().to_upper(), bot.doing_text(Facility.sim), roundi(bot.power * 100.0),
			bot.mood, ord])
	if not last_reply.is_empty():
		lines.append("  " + last_reply)
	lines.append("")
	var recent := Facility.sim.journal.tail(60).filter(func(e): return e.cat != "time")
	for e in recent.slice(maxi(0, recent.size() - JOURNAL_LINES)):
		lines.append("  %s  %s" % [FacilitySim.format_clock(e.t), e.text])
	lines.append("")
	lines.append("Q select robot   O order: most urgent job   R recharge   S stand by   X cancel   W wait 5 min   Tab/1-3 camera   C filter   F1 dev")
	return "\n".join(lines)


func _use_camera(i: int) -> void:
	cam_index = clampi(i, 0, cameras.size() - 1)
	cameras[cam_index].make_current()
