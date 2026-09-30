# Duties: corporate's checklist for this shift (the Campaign's duties).
# Each duty takes facility time and pleases the Directorate; each one left
# undone when the shift ends costs standing. The good-supervisor path, and
# a steady way to spend a shift's hours.
class_name DutiesApp
extends OSApp

var header: Label
var standing: Label
var rows: VBoxContainer
var reply: Label
var _key := ""


func _init() -> void:
	app_id = "duties"
	title = "Duties"
	default_size = Vector2(620, 420)
	icon_text = "TODO"
	icon_color = Color("f0b447")


func build() -> void:
	header = OSTheme.label("", 18, OSTheme.WARN)
	add_child(header)
	standing = OSTheme.mono_label("", 12, OSTheme.TEXT_DIM)
	add_child(standing)
	add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 8)
	scroll.add_child(rows)
	reply = OSTheme.label("", 13, OSTheme.TEXT_DIM)
	reply.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(reply)


func refresh() -> void:
	var camp := Story.campaign(sim())
	if camp == null or header == null:
		return
	header.text = "%s   %s" % [camp.title(), FacilitySim.format_clock(sim().time())]
	var o := Story.oversight(sim())
	standing.text = "Duties done %d of %d.   Undone duties are noted on your record at 14:00." % [camp.duties_done(), camp.duties.size()]
	if o:
		standing.text += "   Standing %d/100" % roundi(o.standing)
	# Rebuild the rows only when something about them changed.
	var key := ""
	for d in camp.duties:
		key += "%s:%s:%s|" % [d.id, d.done, camp.duty_blocker(sim(), d)]
	if key == _key:
		return
	_key = key
	for c in rows.get_children():
		c.queue_free()
	for d in camp.duties:
		rows.add_child(_row(camp, d))


func _row(camp: Campaign, d: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", OSTheme.box(OSTheme.PANEL_LIGHT, OSTheme.ACCENT if d.done else OSTheme.LINE, 4, 10, 6))
	var row := HBoxContainer.new()
	panel.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(OSTheme.label(("✓  " if d.done else "") + str(d.title), 15, OSTheme.ACCENT if d.done else OSTheme.TEXT))
	var info := str(d.description)
	if not str(d.after).is_empty():
		info = "From %s. %s" % [d.after, info]
	var desc := OSTheme.label(info, 12, OSTheme.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(desc)
	if not d.done and float(d.minutes) > 0.0:
		var b := Button.new()
		b.name = "Do_" + str(d.id)
		b.text = "Do it (%d min)" % int(d.minutes)
		b.focus_mode = Control.FOCUS_NONE
		var why := camp.duty_blocker(sim(), d)
		b.disabled = not why.is_empty()
		b.tooltip_text = why
		b.pressed.connect(_do.bind(str(d.id)))
		row.add_child(b)
	return panel


func _do(id: String) -> void:
	var why: String = Supervisor.do_duty(id)
	var camp := Story.campaign(sim())
	reply.text = ("Done: %s." % camp.duty(id).title) if why.is_empty() else why
	_key = ""
	refresh()
