# DevTools: full control over the running facility, for testing. Hidden:
# the Terminal's secret "dev" command puts it on the desktop (and "dev off"
# takes it away); the choice is kept with the OS settings, not the save.
#
# Nothing here is part of the game: it pokes the systems directly (time,
# shifts, faults, units, corporate, stock, story) so a tester can get to any
# situation fast. Each button says what it does; the log underneath keeps
# a record of what was done this session.
class_name DevToolsApp
extends OSApp

var status: Label
var log_view: RichTextLabel
var device_pick: OptionButton
var unit_pick: OptionButton
var event_pick: OptionButton
var directive_pick: OptionButton
var immune_box: CheckBox
var _devices: Array[String] = []
var _events: Array = []

const DIRECTIVES := ["report", "inspect", "diagnose", "output", "explain", "uplink"]


func _init() -> void:
	app_id = "devtools"
	title = "DevTools"
	default_size = Vector2(760, 620)
	icon_text = "DEV"
	icon_color = Color("ff6ad5")


func build() -> void:
	status = OSTheme.mono_label("", 12, OSTheme.ACCENT)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	scroll.add_child(col)
	if sim() == null:
		return

	_section(col, "Time and shifts")
	_row(col, [
		["+10 min", func(): _spend(600.0)],
		["+1 h", func(): _spend(3600.0)],
		["+4 h", func(): _spend(14400.0)],
		["End the shift now", _end_shift],
		["Skip the night", _skip_night],
		["Clock in", func(): _do("clock in", func(): desktop.clock_in())],
		["Finish errands", func(): _do("errands finished", func(): Facility.finish_errands())],
	])

	_section(col, "Corporate")
	immune_box = CheckBox.new()
	immune_box.text = "Never fired (this session)"
	immune_box.focus_mode = Control.FOCUS_NONE
	immune_box.toggled.connect(_set_immune)
	col.add_child(immune_box)
	_row(col, [
		["Standing +20", func(): _oversight(func(o): o.standing = clampf(o.standing + 20.0, 0.0, 100.0))],
		["Standing -20", func(): _oversight(func(o): o.standing = clampf(o.standing - 20.0, 0.0, 100.0))],
		["Suspicion 0", func(): _oversight(func(o): o.suspicion = 0.0)],
		["Suspicion +20", func(): _oversight(func(o): o.suspicion = clampf(o.suspicion + 20.0, 0.0, 100.0))],
		["Clear strikes", func(): _oversight(func(o): o.strikes = 0)],
		["Audit now", func(): _do("audit: %s" % Story.oversight(sim()).audit(sim(), 0.0), func(): pass)],
		["Funds +1000", _add_funds],
	])
	directive_pick = _options(col, DIRECTIVES)
	_row(col, [["Issue that directive (30 min)", _issue_directive]])

	_section(col, "Plant")
	var plant := sim().get_system("plant") as FacilityPlant
	_devices = plant.device_ids()
	device_pick = _options(col, _devices.map(func(i): return "%s  (%s)" % [i, plant.device(i).name]))
	_row(col, [
		["Break it", _break_device],
		["Fix it now", _fix_device],
		["Wear it to 20%", func(): _device(func(d): d.value = 0.2)],
	])
	_row(col, [
		["Heal the facility", _heal],
		["Coolant 100%", func(): _do("coolant 100%", func(): plant.coolant = 1.0)],
		["Coolant 10%", func(): _do("coolant 10%", func(): plant.coolant = 0.1)],
		["Pod waste full", func(): _do("pod waste full", func(): plant.devices.pod_waste.value = 0.0)],
		["Compactor full", func(): _do("compactor full", func(): plant.devices.compactor.value = 0.0)],
		["Uplink: cut", func(): _do("uplink cut", func(): plant.set_uplink_disabled(sim(), true))],
		["Uplink: restore", func(): _do("uplink restored", func(): plant.set_uplink_disabled(sim(), false))],
	])

	_section(col, "Units")
	unit_pick = _options(col, FacilitySetup.robots(sim()).map(func(b): return b.robot_id))
	_row(col, [
		["Seize", func(): _unit(func(b): b.seize(sim()))],
		["Free it", func(): _unit(func(b): b.activity = {"kind": "idle"})],
		["Power 100%", func(): _unit(func(b): b.power = 1.0)],
		["Power 5%", func(): _unit(func(b): b.power = 0.05)],
		["Stability 100%", func(): _unit(func(b): b.stability = 1.0)],
		["Stability 20%", func(): _unit(func(b): b.stability = 0.2)],
		["Wear 0", func(): _unit(func(b): b.wear = 0.0)],
		["Wear 70%", func(): _unit(func(b): b.wear = 0.7)],
		["Trust +1", func(): _unit(func(b): Story.knowledge(sim()).add_value("trust:" + b.robot_id, 1.0))],
		["Break its core", func(): _unit(func(b): b.break_down(sim(), "core regulator failure (dev)"))],
		["Repair it", func(): _unit(func(b): b.repair(sim()))],
		["Make it ask", func(): _unit(func(b): (sim().get_system("requests") as UnitRequests).ask(sim(), b.robot_id, "service",
			"(dev) Book me a service?", ["Book a service", "Not now"], 1))],
	])

	_section(col, "Stock and software")
	_row(col, [
		["+5 of every part", _stock_up],
		["Empty the stock", _empty_stock],
		["Install every package", _install_all],
		["A crated Tinker", _crate_tinker],
	])

	_section(col, "Story")
	_row(col, [
		["Learn every command", _learn_commands],
		["Learn every secret", _learn_secrets],
		["Purge Okafor now", func(): _do("purged:dokafor", func(): Story.learn(sim(), "purged:dokafor"))],
	])
	var camp := Story.campaign(sim())
	_events = camp._events if camp else []
	event_pick = _options(col, _events.map(func(e): return "S%s %s  %s %s" % [e.shift, e.at, e.action, str(e.args).left(60)]))
	_row(col, [["Run that event now", _run_event]])

	_section(col, "Log")
	log_view = RichTextLabel.new()
	log_view.fit_content = true
	log_view.scroll_active = false
	col.add_child(log_view)


func refresh() -> void:
	if sim() == null or status == null:
		return
	var camp := Story.campaign(sim())
	var o := Story.oversight(sim())
	var plant := sim().get_system("plant") as FacilityPlant
	var req := sim().get_system("requisitions") as Requisitions
	status.text = "%s   %s (%s)   standing %d   suspicion %d   strikes %d   funds %d   coolant %d%%   output %d%%   uplink %s   errands %d" % [
		FacilitySim.format_time(sim().time()), camp.title() if camp else "", camp.state if camp else "", roundi(o.standing), roundi(o.suspicion), o.strikes,
		req.funds if req else 0, roundi(plant.coolant * 100.0), roundi(plant.throughput * 100.0),
		"DOWN" if o.uplink_down(sim()) else "up", Facility.errands.size()]
	if immune_box:
		immune_box.set_pressed_no_signal(o.immune)


# --- Actions ---------------------------------------------------------------------------

func _spend(seconds: float) -> void:
	Facility.spend(seconds, "dev: time")
	_log("+%d min" % roundi(seconds / 60.0))


func _end_shift() -> void:
	var camp := Story.campaign(sim())
	if camp == null or not camp.on_duty():
		_log("not on duty")
		return
	Facility.spend(camp.shift_end_time() - sim().time() + 2.0, "dev: end of shift")
	_log("shift ended")


func _skip_night() -> void:
	var camp := Story.campaign(sim())
	if camp == null or camp.state != "off_duty":
		_log("not off duty (end the shift first)")
		return
	Facility.spend(camp.night_until() - sim().time(), "dev: the night", false)
	camp.night_over(sim())
	Facility.save()
	_log("night skipped: %s brief" % camp.title())


func _issue_directive() -> void:
	var kind: String = DIRECTIVES[directive_pick.selected]
	var target := ""
	match kind:
		"inspect": target = "pipe_1"
		"diagnose": target = "tinker"
		"output": target = "85"
		"explain": target = "files"
	(sim().get_system("directives") as Directives).issue(sim(), kind, target, 30.0, "(dev) %s %s" % [kind, target])
	_after("directive issued: " + kind)


func _break_device() -> void:
	var id := _devices[device_pick.selected]
	sim().schedule_in(0.0, "plant_fault", {"device": id})
	sim().advance(0.2)
	_after("broke " + id)


func _fix_device() -> void:
	var id := _devices[device_pick.selected]
	var plant := sim().get_system("plant") as FacilityPlant
	var board := sim().get_system("work") as WorkBoard
	var j := int(plant.device(id).job)
	if j >= 0:
		board.cancel(sim(), j, "dev")
	plant.devices[id].unpowered = false
	plant.devices[id].disabled = false
	plant._repaired(sim(), id, "dev")
	_after("fixed " + id)


func _heal() -> void:
	var plant := sim().get_system("plant") as FacilityPlant
	var board := sim().get_system("work") as WorkBoard
	var layout := sim().get_system("layout") as FacilityLayout
	for id in plant.device_ids():
		var d := plant.device(id)
		d.value = 1.0
		d.fault = false
		d.unpowered = false
		d.disabled = false
		if d.has("blocks"):
			layout.set_blocked(sim(), d.blocks, false)
	for j in board.open_jobs():
		board.cancel(sim(), int(j.id), "dev: healed")
	plant.coolant = 1.0
	_after("facility healed")


func _stock_up() -> void:
	var req := sim().get_system("requisitions") as Requisitions
	for it in req.catalog:
		if str(it.effect) == "inventory" or str(it.id) == "coolant_canister":
			req.inventory[it.id] = int(req.inventory.get(it.id, 0)) + 5
	_after("+5 of every part")


func _install_all() -> void:
	var sw := sim().get_system("software") as SoftwareLibrary
	for p in sw.packages:
		if not sw.installed_ids.has(str(p.id)):
			sw.installed_ids.append(str(p.id))
	_after("every package installed")


func _learn_commands() -> void:
	for c in TerminalApp.COMMANDS:
		if TerminalApp.COMMANDS[c][2] != "dev":
			Story.learn(sim(), "cmd:" + str(c))
	_after("every command learned")


func _run_event() -> void:
	if _events.is_empty():
		return
	var e: Dictionary = _events[event_pick.selected]
	Story.campaign(sim()).run_action(sim(), str(e.action), str(e.args))
	sim().advance(0.2)
	_after("ran event: %s %s" % [e.action, str(e.args).left(40)])


func _set_immune(on: bool) -> void:
	Story.oversight(sim()).immune = on
	_log("never fired: %s" % on)


func _add_funds() -> void:
	var req := sim().get_system("requisitions") as Requisitions
	req.funds += 1000
	_after("funds +1000")


func _learn_secrets() -> void:
	for s in Knowledge.secrets():
		Story.learn(sim(), "secret:" + str(s.id))
	_after("every secret learned")


func _crate_tinker() -> void:
	var req := sim().get_system("requisitions") as Requisitions
	req.inventory["robot_tinker"] = int(req.inventory.get("robot_tinker", 0)) + 1
	_after("a crated Tinker in stock")


func _empty_stock() -> void:
	var req := sim().get_system("requisitions") as Requisitions
	req.inventory.clear()
	_after("stock emptied")


# --- Helpers -----------------------------------------------------------------------------

func _do(what: String, action: Callable) -> void:
	action.call()
	_after(what)


func _after(what: String) -> void:
	Facility.save()
	if desktop and desktop.has_method("_refresh_all"):
		desktop._refresh_all()
	_log(what)


func _oversight(change: Callable) -> void:
	change.call(Story.oversight(sim()))
	_after("oversight changed")


func _unit(change: Callable) -> void:
	var bots := FacilitySetup.robots(sim())
	if unit_pick.selected < 0 or unit_pick.selected >= bots.size():
		return
	var bot: RobotAgent = bots[unit_pick.selected]
	change.call(bot)
	_after("%s changed" % bot.robot_id)


func _device(change: Callable) -> void:
	var plant := sim().get_system("plant") as FacilityPlant
	change.call(plant.devices[_devices[device_pick.selected]])
	_after(_devices[device_pick.selected] + " changed")


func _log(text: String) -> void:
	if log_view:
		log_view.append_text("%s  %s\n" % [FacilitySim.format_clock(sim().time()) if sim() else "", text.replace("[", "[lb]")])
	refresh()


func _section(col: VBoxContainer, text: String) -> void:
	col.add_child(OSTheme.label(text.to_upper(), 12, OSTheme.TEXT_DIM))


func _row(col: VBoxContainer, buttons: Array) -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	col.add_child(row)
	for b in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(b[1])
		row.add_child(btn)


func _options(col: VBoxContainer, items: Array) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	for t in items:
		o.add_item(str(t))
	col.add_child(o)
	return o
