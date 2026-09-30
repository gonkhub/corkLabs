# Work Orders: the job board. Pick a job to assign it to a robot (an order:
# it costs facility time, and the robot may push back) or change its
# priority.
class_name WorkApp
extends OSApp

var tree: Tree
var detail: Label
var reply: Label
var assign_buttons := {}   # robot_id -> Button
var up_button: Button
var down_button: Button
var show_done: CheckBox
var selected_job := -1
var _signature := ""


func _init() -> void:
	app_id = "work"
	title = "Work Orders"
	default_size = Vector2(840, 460)
	icon_text = "JOB"
	icon_color = OSTheme.WARN


func build() -> void:
	var top := HBoxContainer.new()
	add_child(top)
	var head := OSTheme.label("Open jobs", 15)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(head)
	show_done = CheckBox.new()
	show_done.text = "Show finished"
	show_done.focus_mode = Control.FOCUS_NONE
	show_done.toggled.connect(_on_show_done)
	top.add_child(show_done)

	tree = Tree.new()
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.columns = 7
	tree.column_titles_visible = true
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_ROW
	var cols := [["#", 44], ["Job", 0], ["Where", 110], ["Skill", 76], ["Priority", 84], ["Done", 60], ["Who", 90]]
	for i in cols.size():
		tree.set_column_title(i, cols[i][0])
		tree.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT)
		if cols[i][1] > 0:
			tree.set_column_expand(i, false)
			tree.set_column_custom_minimum_width(i, cols[i][1])
	tree.item_selected.connect(func():
		selected_job = int(tree.get_selected().get_metadata(0))
		_update_detail())
	add_child(tree)

	detail = OSTheme.label("Select a job.", 14)
	add_child(detail)
	var row := HBoxContainer.new()
	add_child(row)
	if sim():
		for bot in FacilitySetup.robots(sim()):
			var b := Button.new()
			b.text = "Order %s" % bot.display_name()
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(_assign.bind(bot.robot_id))
			row.add_child(b)
			assign_buttons[bot.robot_id] = b
	var gap := Control.new()
	gap.custom_minimum_size.x = 20
	row.add_child(gap)
	up_button = Button.new()
	up_button.text = "Priority +"
	up_button.focus_mode = Control.FOCUS_NONE
	up_button.pressed.connect(_bump.bind(1))
	row.add_child(up_button)
	down_button = Button.new()
	down_button.text = "Priority −"
	down_button.focus_mode = Control.FOCUS_NONE
	down_button.pressed.connect(_bump.bind(-1))
	row.add_child(down_button)
	reply = OSTheme.label("", 13, OSTheme.TEXT_DIM)
	reply.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(reply)


func _on_show_done(_on: bool) -> void:
	_signature = ""
	refresh()


func _board() -> WorkBoard:
	return sim().get_system("work") as WorkBoard if sim() else null


func _jobs() -> Array[Dictionary]:
	var board := _board()
	var none: Array[Dictionary] = []
	if board == null:
		return none
	if show_done.button_pressed:
		return board.jobs
	return board.open_jobs()


func refresh() -> void:
	var board := _board()
	if board == null:
		return
	var layout := sim().get_system("layout") as FacilityLayout
	var jobs := _jobs()
	# Only rebuild the list when something in it changed (keeps selection and scroll).
	var sig := PackedStringArray()
	for j in jobs:
		sig.append("%d%s%d%d%s" % [j.id, j.status, j.priority, int(board.fraction_done(j) * 100.0), j.claimed_by])
	var s := ",".join(sig)
	if s != _signature:
		_signature = s
		tree.clear()
		var root := tree.create_item()
		for j in jobs:
			var it := tree.create_item(root)
			it.set_metadata(0, j.id)
			it.set_text(0, str(j.id))
			it.set_text(1, j.title)
			it.set_text(2, layout.station(j.station).get("name", j.station))
			it.set_text(3, j.skill)
			it.set_text(4, WorkBoard.PRIORITY_NAMES[int(j.priority)])
			it.set_custom_color(4, [OSTheme.TEXT_DIM, OSTheme.TEXT, OSTheme.WARN, OSTheme.ALARM][int(j.priority)])
			it.set_text(5, "%d%%" % int(board.fraction_done(j) * 100.0))
			var who := "waiting"
			if j.status == "claimed":
				who = str(j.claimed_by).trim_prefix("robot_").capitalize()
			elif j.status != "open":
				who = j.status
			it.set_text(6, who)
			if j.status == "done" or j.status == "cancelled":
				for c in 7:
					it.set_custom_color(c, OSTheme.TEXT_DIM.darkened(0.2))
			if int(j.id) == selected_job:
				it.select(0)
	_update_detail()


func _update_detail() -> void:
	var board := _board()
	var j: Dictionary = board.get_job(selected_job) if board else {}
	var open: bool = not j.is_empty() and (j.status == "open" or j.status == "claimed")
	if j.is_empty():
		detail.text = "Select a job to assign it or change its priority."
	else:
		var st := (sim().get_system("layout") as FacilityLayout).station(j.station)
		detail.text = "#%d  %s  at %s  ·  %s work, %d units  ·  posted %s by %s" % [j.id, j.title, st.get("name", "?"),
			j.skill, int(j.work), FacilitySim.format_clock(float(j.posted)), str(j.source).split(":")[0] if str(j.source) != "" else "?"]
	for id in assign_buttons:
		var bot := sim().get_system("robot_" + id) as RobotAgent
		var b: Button = assign_buttons[id]
		b.disabled = not open or not Supervisor.can_reach(sim(), bot, j)
		b.tooltip_text = "" if not b.disabled or not open else "%s can't reach %s from its rail" % [bot.display_name(), j.get("station", "")]
	up_button.disabled = not open or int(j.get("priority", 3)) >= 3
	down_button.disabled = not open or int(j.get("priority", 0)) <= 0


func _assign(robot_id: String) -> void:
	var bot := sim().get_system("robot_" + robot_id) as RobotAgent
	var r := Supervisor.order(bot, "job", selected_job)
	reply.text = "%s: \"%s\"" % [bot.display_name(), r.reply]
	reply.add_theme_color_override("font_color", OSTheme.ACCENT if r.ok else OSTheme.WARN)
	_signature = ""
	refresh()


func _bump(step: int) -> void:
	var j := _board().get_job(selected_job)
	if j.is_empty():
		return
	Supervisor.set_priority(selected_job, int(j.priority) + step)
	_signature = ""
	refresh()
