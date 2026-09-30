# Units: one card per robot. What it's doing, its power and software
# stability (and how independent that's made it), its standing order, and
# what it's weighing up right now (its top utility scores and why). Orders
# from here cost facility time, and the robot answers on camera. Reboot needs
# the remote-reboot software package.
#
# Diagnose (10 min) reads a unit's state out properly and steadies it a
# little. Talk appears once the supervisor knows units CAN be talked to
# (the "talk" command): it opens the unit link in the Terminal.
class_name UnitsApp
extends OSApp

var row: HBoxContainer
var crate_row: HBoxContainer
var _crate_key := ""
var cards := {}   # robot_id -> {"name", "doing", "power", "power_txt", "stability", "stability_txt", "order", "think", "why", "reply", "reboot", "talk"}

## Facility minutes a diagnostic takes, and how much it steadies the unit.
const DIAGNOSE_MINUTES := 10.0
const DIAGNOSE_STEADY := 0.02


func _init() -> void:
	app_id = "units"
	title = "Units"
	default_size = Vector2(820, 430)
	icon_text = "BOT"
	icon_color = Color("c9b7ff")


func build() -> void:
	row = HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	crate_row = HBoxContainer.new()
	add_child(crate_row)
	if sim() == null:
		return
	for bot in FacilitySetup.robots(sim()):
		row.add_child(_card(bot))


# Crated units in stock (Requisitions), with an Activate button each.
func _refresh_crates() -> void:
	var req := sim().get_system("requisitions") as Requisitions
	var crated: Array = req.crated_units() if req else []
	var key := str(crated)
	if key == _crate_key:
		return
	_crate_key = key
	for c in crate_row.get_children():
		c.queue_free()
	crate_row.visible = not crated.is_empty()
	if crated.is_empty():
		return
	crate_row.add_child(OSTheme.label("Crated in the workshop:", 13, OSTheme.TEXT_DIM))
	for c in crated:
		var b := Button.new()
		b.text = "Activate %s (%d in stock, 30 min)" % [c.name, c.count]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func():
			var r: Dictionary = Supervisor.activate_unit(c.item)
			if not r.ok:
				b.text = r.text
			_crate_key = "")
		crate_row.add_child(b)


func _card(bot: RobotAgent) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", OSTheme.box(OSTheme.PANEL_LIGHT, OSTheme.LINE, 6, 12, 10))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var c := {}
	c.name = OSTheme.label(bot.display_name().to_upper(), 20, OSTheme.category_color(bot.robot_id))
	col.add_child(c.name)
	c.doing = OSTheme.label("", 14)
	c.doing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(c.doing)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	col.add_child(grid)
	grid.add_child(OSTheme.label("Power", 13, OSTheme.TEXT_DIM))
	c.power = OSTheme.bar(bot.power, 0.35, bot.traits.power_reserve)
	c.power.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(c.power)
	c.power_txt = OSTheme.mono_label("", 13)
	grid.add_child(c.power_txt)
	grid.add_child(OSTheme.label("Stability", 13, OSTheme.TEXT_DIM))
	c.stability = OSTheme.bar(bot.stability, 0.6, 0.35)
	c.stability.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.stability.tooltip_text = "Software stability. Low stability = independent, unpredictable, and eventually critical errors."
	grid.add_child(c.stability)
	c.stability_txt = OSTheme.mono_label("", 13)
	grid.add_child(c.stability_txt)
	c.order = OSTheme.label("", 13, OSTheme.WARN)
	col.add_child(c.order)
	col.add_child(OSTheme.label("Weighing up", 12, OSTheme.TEXT_DIM))
	c.think = OSTheme.mono_label("", 12)
	col.add_child(c.think)
	c.why = OSTheme.label("", 12, OSTheme.TEXT_DIM)
	c.why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(c.why)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	c.reply = OSTheme.label("", 12, OSTheme.TEXT_DIM)
	c.reply.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(c.reply)
	col.add_child(button_row([
		["Recharge", _order.bind(bot.robot_id, "recharge")],
		["Stand by", _order.bind(bot.robot_id, "standby")],
		["Cancel order", _order.bind(bot.robot_id, "cancel")],
		["Assign a job...", func(): desktop.open_app("work")],
	]))
	var row2 := HBoxContainer.new()
	col.add_child(row2)
	var diag := Button.new()
	diag.text = "Diagnose (%d min)" % int(DIAGNOSE_MINUTES)
	diag.focus_mode = Control.FOCUS_NONE
	diag.pressed.connect(_diagnose.bind(bot.robot_id))
	row2.add_child(diag)
	c.talk = Button.new()
	c.talk.text = "Talk"
	c.talk.focus_mode = Control.FOCUS_NONE
	c.talk.tooltip_text = "Open the unit link (in the Terminal). Conversing with units is against the Code of Conduct."
	c.talk.pressed.connect(_talk.bind(bot.robot_id))
	row2.add_child(c.talk)
	c.reboot = Button.new()
	c.reboot.text = "Remote reboot"
	c.reboot.focus_mode = Control.FOCUS_NONE
	c.reboot.pressed.connect(_reboot.bind(bot.robot_id))
	row2.add_child(c.reboot)
	cards[bot.robot_id] = c
	return panel


func _order(robot_id: String, kind: String) -> void:
	var bot := sim().get_system("robot_" + robot_id) as RobotAgent
	Supervisor.order(bot, kind)
	cards[robot_id].reply.text = "Order sent: %s. (Its answer is on camera.)" % Supervisor.describe_order(sim(), kind, -1)


func _diagnose(robot_id: String) -> void:
	var bot := sim().get_system("robot_" + robot_id) as RobotAgent
	sim().note("supervisor", "Runs diagnostics on %s" % bot.display_name())
	if not bot.offline():
		bot.stability = minf(bot.stability + DIAGNOSE_STEADY, 1.0)
	Facility.spend(DIAGNOSE_MINUTES * 60.0, "Supervisor runs diagnostics on %s" % bot.display_name())
	var power_left := bot.power * 100.0
	cards[robot_id].reply.text = "DIAG %s: power %d%%, stability %d%% (%s), independence %d%%, jobs done %d. %s" % [
		bot.display_name().to_upper(), roundi(power_left), roundi(bot.stability * 100.0), bot.stability_state,
		roundi(bot.independence() * 100.0), bot.jobs_done,
		"Firmware: knowledge filter active." if robot_id != "ogre" else "Firmware: no knowledge filter installed."]


func _talk(robot_id: String) -> void:
	var term = desktop.open_app("terminal") if desktop else null
	if term:
		term.start_talk(robot_id)


func _reboot(robot_id: String) -> void:
	var bot := sim().get_system("robot_" + robot_id) as RobotAgent
	if Supervisor.reboot(bot):
		cards[robot_id].reply.text = "Reboot sent. Offline for %d minutes." % int(RobotAgent.REBOOT_TIME / 60.0)


func refresh() -> void:
	if sim() == null:
		return
	_refresh_crates()
	# A unit activated from a crate gets its card.
	for bot in FacilitySetup.robots(sim()):
		if not cards.has(bot.robot_id):
			row.add_child(_card(bot))
	for bot in FacilitySetup.robots(sim()):
		var c: Dictionary = cards.get(bot.robot_id, {})
		if c.is_empty():
			continue
		var doing := bot.doing_text(sim())
		c.doing.text = doing.left(1).to_upper() + doing.substr(1)
		OSTheme.set_bar(c.power, bot.power, 0.35, bot.traits.power_reserve)
		c.power_txt.text = "%3d%%" % roundi(bot.power * 100.0)
		OSTheme.set_bar(c.stability, bot.stability, 0.6, 0.35)
		c.stability_txt.text = "%3d%% %s" % [roundi(bot.stability * 100.0), bot.stability_state.to_upper() if bot.stability < 0.35 else bot.stability_state]
		if bot.independence() > 0.2:
			c.stability_txt.text += "  (independent %d%%)" % roundi(bot.independence() * 100.0)
		c.talk.visible = Story.knows(sim(), "cmd:talk")
		var unlocked := Supervisor.has_software("remote-reboot")
		c.reboot.disabled = not unlocked or bot.offline()
		c.reboot.tooltip_text = "Offline %d min, restores stability" % int(RobotAgent.REBOOT_TIME / 60.0) if unlocked \
			else "Needs the remote-reboot software package"
		c.order.text = "" if bot.order.is_empty() else "Standing order: " + Supervisor.describe_order(sim(), bot.order.kind, int(bot.order.get("job", -1)))
		var lines := PackedStringArray()
		for o in bot.scores.slice(0, 3):
			lines.append("%.2f  %s" % [o.score, o.label])
		c.think.text = "\n".join(lines) if not lines.is_empty() else "(nothing yet)"
		c.why.text = ("Because: " + str(bot.scores[0].why)) if not bot.scores.is_empty() else ""
