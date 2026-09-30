# The screens between shifts, over the whole desktop. Which one shows
# follows the Campaign's state:
#
#   pre        the BRIEF: what corporate wants today, what happened overnight,
#              today's duties. "Clock in" spends the few minutes to 06:00.
#   on_duty    nothing (the desktop is yours)
#   off_duty   END OF SHIFT: the review, your standing, duties done.
#              "Clock out" lets the night pass, a chunk per frame, while the
#              facility runs without you; then the next brief.
#   fired      NOTICE OF DISMISSAL: why. Retry the shift from its start (the
#              checkpoint saved at its brief), or start over on a new save.
#   complete   THE ENDING, what you found this run (and hints for what you
#              didn't), and "Start over".
#
# While it's up, the desktop underneath takes no clicks or keys.
class_name ShiftScreen
extends Control

## Facility seconds the night passes per frame (16 h in about 2 s of frames).
const NIGHT_STEP := 1800.0

var desktop: Node
var card: PanelContainer
var body: VBoxContainer
var _shown := ""
var _night := false
var _night_label: Label
var _night_bar: ProgressBar
var _night_from := 0.0


func _ready() -> void:
	name = "ShiftScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.045, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", OSTheme.box(OSTheme.PANEL, OSTheme.LINE, 8, 32, 24))
	card.custom_minimum_size = Vector2(720, 0)
	center.add_child(card)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	card.add_child(body)
	visible = false


## Is it covering the desktop?
func blocking() -> bool:
	return visible


func _process(_delta: float) -> void:
	if not Facility.running:
		visible = false
		return
	var camp := Story.campaign(Facility.sim)
	if camp == null:
		visible = false
		return
	if _night:
		_night_step(camp)
		return
	var want := camp.state + ":%d" % camp.shift
	if want != _shown:
		_shown = want
		_build(camp)


func _build(camp: Campaign) -> void:
	for c in body.get_children():
		c.queue_free()
	visible = camp.state != "on_duty"
	if not visible:
		return
	get_parent().move_child(self, -1)
	match camp.state:
		"pre": _build_brief(camp)
		"off_duty": _build_end(camp)
		"fired": _build_fired(camp)
		"complete": _build_ending(camp)


# --- The brief -------------------------------------------------------------------------

func _build_brief(camp: Campaign) -> void:
	# Every brief is a checkpoint: a dismissal during this shift comes back here.
	Facility.checkpoint()
	var sim := Facility.sim
	_heading(camp.title().to_upper(), FacilitySim.format_time(sim.time()))
	_text(camp.brief())
	if not camp.overnight.is_empty():
		_section("OVERNIGHT, WHILE YOU WERE AWAY")
		for line in camp.overnight:
			body.add_child(OSTheme.mono_label("  " + line, 12, OSTheme.TEXT_DIM))
	_section("TODAY'S DUTIES")
	for d in camp.duties:
		var when := ""
		if not str(d.after).is_empty():
			when = "  from %s" % d.after
		var cost := "  %d min" % int(d.minutes) if float(d.minutes) > 0.0 else ""
		body.add_child(OSTheme.label("  ·  %s%s%s" % [d.title, when, cost], 13))
	_buttons([["Clock in", _clock_in]])


func _clock_in() -> void:
	if desktop:
		desktop.clock_in()
	_shown = ""


# --- End of shift ------------------------------------------------------------------------

func _build_end(camp: Campaign) -> void:
	var sim := Facility.sim
	var hq := sim.get_system("hq") as CorkHQ
	var o := Story.oversight(sim)
	_heading("%s: OVER" % camp.title().to_upper(), FacilitySim.format_time(sim.time()))
	var review := hq.messages.filter(func(m): return m.kind == "review") if hq else []
	if not review.is_empty():
		_text(str(review.back().text))
	if o:
		_text("Standing with the Directorate: %d/100%s" % [roundi(o.standing), ("   Formal warnings: %d" % o.strikes) if o.strikes > 0 else ""])
	_text("Duties done: %d of %d" % [camp.duties_done(), camp.duties.size()])
	var k := Story.knowledge(sim)
	if k:
		var found := k.with_prefix("secret:").size()
		if found > 0:
			_text("Things corporate would rather you hadn't found: %d" % found, OSTheme.WARN)
	_text("The facility runs without a supervisor overnight. Your next shift starts at 06:00.", OSTheme.TEXT_DIM)
	_buttons([["Clock out", _clock_out]])


func _clock_out() -> void:
	_night = true
	_night_from = Facility.sim.time()
	for c in body.get_children():
		c.queue_free()
	_heading("OFF DUTY", "")
	_text("The facility runs without you.", OSTheme.TEXT_DIM)
	_night_label = OSTheme.mono_label("", 16, OSTheme.ACCENT)
	body.add_child(_night_label)
	_night_bar = OSTheme.bar(0.0, 0.0, 0.0)
	_night_bar.custom_minimum_size = Vector2(600, 14)
	body.add_child(_night_bar)


func _night_step(camp: Campaign) -> void:
	var sim := Facility.sim
	var until := camp.night_until()
	var left := until - sim.time()
	if left > 0.0:
		Facility.spend(minf(NIGHT_STEP, left), "The night passes", false)
		_night_label.text = FacilitySim.format_time(sim.time())
		_night_bar.value = clampf((sim.time() - _night_from) / maxf(until - _night_from, 1.0), 0.0, 1.0)
		return
	_night = false
	camp.night_over(sim)
	Facility.save()
	_shown = ""


# --- Dismissal ----------------------------------------------------------------------------

func _build_fired(camp: Campaign) -> void:
	var o := Story.oversight(Facility.sim)
	_heading("NOTICE OF DISMISSAL", FacilitySim.format_time(Facility.sim.time()), OSTheme.ALARM)
	var kind: String = {"performance": "Unsatisfactory performance", "misconduct": "Gross misconduct",
		"catastrophe": "Catastrophic failure on your watch"}.get(o.fired_kind if o else "", "Dismissed")
	_section(kind.to_upper(), OSTheme.ALARM)
	_text(o.fired_reason if o else "")
	_text("Your access to facility C-7 ends now. You will be informed of your transfer in due course.", OSTheme.TEXT_DIM)
	var archive := SupervisorArchive.summary()
	if not archive.is_empty():
		_text(archive, OSTheme.TEXT_DIM)
	_buttons([["Retry %s from its start" % camp.title().get_slice(":", 0), _retry], ["Start over (new save)", _start_over]])


func _retry() -> void:
	_shown = ""
	if desktop:
		desktop.retry_shift()


func _start_over() -> void:
	_shown = ""
	if desktop:
		desktop.start_over()


# --- The ending ---------------------------------------------------------------------------

func _build_ending(camp: Campaign) -> void:
	var info := camp.ending_info()
	_heading("ENDING: %s" % str(info.title).to_upper(), FacilitySim.format_time(Facility.sim.time()), OSTheme.WARN)
	_text(str(info.text))
	var k := Story.knowledge(Facility.sim)
	var secrets := Knowledge.secrets()
	var found := k.with_prefix("secret:") if k else []
	_section("FOUND THIS RUN: %d OF %d" % [found.size(), secrets.size()])
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	body.add_child(grid)
	for s in secrets:
		var have: bool = found.has(s.id)
		var l := OSTheme.label(("✓  " + s.title) if have else ("·  " + s.hint), 12, OSTheme.ACCENT if have else OSTheme.TEXT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 320
		grid.add_child(l)
	var archive := SupervisorArchive.summary()
	if not archive.is_empty():
		_text(archive, OSTheme.TEXT_DIM)
	_buttons([["Start over (new save)", _start_over], ["Log off", func(): desktop.log_off()]])


# --- Building blocks ------------------------------------------------------------------------

func _heading(text: String, right: String, color := OSTheme.ACCENT) -> void:
	var row := HBoxContainer.new()
	body.add_child(row)
	var h := OSTheme.label(text, 24, color)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(h)
	row.add_child(OSTheme.mono_label(right, 13, OSTheme.TEXT_DIM))
	body.add_child(HSeparator.new())


func _section(text: String, color := OSTheme.TEXT_DIM) -> void:
	var l := OSTheme.label(text, 12, color)
	body.add_child(l)


func _text(text: String, color := OSTheme.TEXT) -> void:
	var l := OSTheme.label(text, 15, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 660
	body.add_child(l)


func _buttons(buttons: Array) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)
	for b in buttons:
		var btn := Button.new()
		btn.name = str(b[0]).split(" ")[0]
		btn.text = b[0]
		btn.custom_minimum_size = Vector2(180, 38)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(b[1])
		row.add_child(btn)
