# Units: one card per robot. What it's doing, its power and software
# stability (and how independent that's made it), its standing order, and
# what it's weighing up right now (its top utility scores and why). Orders
# from here cost facility time, and the robot answers on camera. Reboot needs
# the remote-reboot software package.
class_name UnitsApp
extends OSApp

var cards := {}   # robot_id -> {"name", "doing", "power", "power_txt", "stability", "stability_txt", "order", "think", "why", "reply", "reboot"}


func _init() -> void:
	app_id = "units"
	title = "Units"
	default_size = Vector2(820, 430)
	icon_text = "BOT"
	icon_color = Color("c9b7ff")


func build() -> void:
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	if sim() == null:
		return
	for bot in FacilitySetup.robots(sim()):
		row.add_child(_card(bot))


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
	c.reboot = Button.new()
	c.reboot.text = "Remote reboot"
	c.reboot.focus_mode = Control.FOCUS_NONE
	c.reboot.pressed.connect(_reboot.bind(bot.robot_id))
	col.add_child(c.reboot)
	cards[bot.robot_id] = c
	return panel


func _order(robot_id: String, kind: String) -> void:
	var bot := sim().get_system("robot_" + robot_id) as RobotAgent
	Supervisor.order(bot, kind)
	cards[robot_id].reply.text = "Order sent: %s. (Its answer is on camera.)" % Supervisor.describe_order(sim(), kind, -1)


func _reboot(robot_id: String) -> void:
	var bot := sim().get_system("robot_" + robot_id) as RobotAgent
	if Supervisor.reboot(bot):
		cards[robot_id].reply.text = "Reboot sent. Offline for %d minutes." % int(RobotAgent.REBOOT_TIME / 60.0)


func refresh() -> void:
	if sim() == null:
		return
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
