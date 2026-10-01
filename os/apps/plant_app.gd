# Plant: the facility's vital signs. Throughput (the pods' average sync),
# coolant, heat, dock power, and every device's state with its open job.
# Pick a device to act on it:
#   Inspect (10 min)        how fast it's wearing, when it needs work, who's on it
#   Request maintenance     post the job before it becomes an alarm (5 min)
# Repairs use spare parts from Requisitions stock; a job with no part in
# stock stops halfway ("waiting for part").
class_name PlantApp
extends OSApp

var throughput: Label
var coolant: ProgressBar
var coolant_txt: Label
var heat: Label
var docks: Label
var tree: Tree
var detail: Label
var inspect_button: Button
var service_button: Button
var selected := ""
var _signature := ""
var _rebuilding := false


func _init() -> void:
	app_id = "plant"
	title = "Plant"
	default_size = Vector2(600, 500)
	icon_text = "PLT"
	icon_color = OSTheme.ACCENT


## Things broken right now (leaks, blown fuse, desynced pods): the alarm light.
static func active_faults(plant: FacilityPlant) -> int:
	var n := 0
	for id in plant.device_ids():
		var d := plant.device(id)
		if d.fault or (d.kind == "pod" and float(d.value) <= 0.0):
			n += 1
	return n


func build() -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	add_child(top)
	var left := VBoxContainer.new()
	top.add_child(left)
	left.add_child(OSTheme.label("THROUGHPUT", 12, OSTheme.TEXT_DIM))
	throughput = OSTheme.label("--%", 40, OSTheme.ACCENT)
	left.add_child(throughput)
	var right := GridContainer.new()
	right.columns = 3
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("h_separation", 10)
	top.add_child(right)
	right.add_child(OSTheme.label("Coolant", 13, OSTheme.TEXT_DIM))
	coolant = OSTheme.bar(1.0, 0.7, 0.4)
	coolant.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(coolant)
	coolant_txt = OSTheme.mono_label("", 13)
	right.add_child(coolant_txt)
	right.add_child(OSTheme.label("Heat", 13, OSTheme.TEXT_DIM))
	heat = OSTheme.mono_label("", 13)
	right.add_child(heat)
	right.add_child(Control.new())
	right.add_child(OSTheme.label("Dock power", 13, OSTheme.TEXT_DIM))
	docks = OSTheme.mono_label("", 13)
	right.add_child(docks)
	right.add_child(Control.new())

	tree = Tree.new()
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.columns = 3
	tree.column_titles_visible = true
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_ROW
	for i in 3:
		tree.set_column_title(i, ["Device", "State", "Job"][i])
		tree.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT)
	tree.set_column_expand(2, false)
	tree.set_column_custom_minimum_width(2, 80)
	tree.item_selected.connect(func():
		if _rebuilding:
			return
		selected = str(tree.get_selected().get_metadata(0))
		detail.text = ""
		_update_buttons())
	add_child(tree)
	detail = OSTheme.label("Select a device.", 13, OSTheme.TEXT_DIM)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(detail)
	var row := HBoxContainer.new()
	add_child(row)
	inspect_button = _button(row, "Inspect (30 min)", func(): detail.text = Supervisor.inspect_device(selected))
	service_button = _button(row, "Request maintenance (5 min)", func(): _result(Supervisor.request_maintenance(selected), "Maintenance requested."))
	_update_buttons()


func _button(row: HBoxContainer, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func():
		action.call()
		_signature = ""
		refresh())
	row.add_child(b)
	return b


func _result(why: String, ok_text: String) -> void:
	detail.text = ok_text if why.is_empty() else why


func _update_buttons() -> void:
	var none := selected.is_empty()
	for b in [inspect_button, service_button]:
		b.disabled = none
	if none or sim() == null:
		return
	var plant := sim().get_system("plant") as FacilityPlant
	var d := plant.device(selected)
	service_button.visible = FacilityPlant.KINDS.get(d.get("kind", ""), {}).has("drift")


func refresh() -> void:
	if sim() == null:
		return
	var plant := sim().get_system("plant") as FacilityPlant
	if plant == null:
		return
	throughput.text = "%d%%" % roundi(plant.throughput * 100.0)
	throughput.add_theme_color_override("font_color", _color(plant.throughput, 0.8, 0.6))
	OSTheme.set_bar(coolant, plant.coolant, 0.7, 0.4)
	coolant_txt.text = "%3d%%" % roundi(plant.coolant * 100.0)
	var h := plant.heat()
	heat.text = "%.1fx %s" % [h, "normal" if h < 1.4 else ("running warm" if h < 2.0 else "RUNNING HOT")]
	heat.add_theme_color_override("font_color", OSTheme.TEXT if h < 1.4 else (OSTheme.WARN if h < 2.0 else OSTheme.ALARM))
	docks.text = "%d%%%s" % [roundi(plant.charge_factor() * 100.0), "" if plant.charge_factor() >= 1.0 else "  (relay out)"]
	docks.add_theme_color_override("font_color", OSTheme.TEXT if plant.charge_factor() >= 1.0 else OSTheme.ALARM)

	var rows := []
	for id in plant.device_ids():
		var d := plant.device(id)
		if d.kind == "bay" and int(d.job) < 0:
			continue   # empty bays: nothing to show
		var text := plant.device_text(id)
		rows.append([d.name, text.substr(20).split("  job")[0].strip_edges(),
			("#%d" % int(d.job)) if int(d.job) >= 0 else "", _device_color(d), id])
	var sig := str(rows)
	if sig == _signature:
		return
	_signature = sig
	_rebuilding = true
	tree.clear()
	var root := tree.create_item()
	for r in rows:
		var it := tree.create_item(root)
		for c in 3:
			it.set_text(c, r[c])
		it.set_custom_color(1, r[3])
		it.set_metadata(0, r[4])
		if r[4] == selected:
			it.select(0)
	_rebuilding = false
	_update_buttons()


static func _color(v: float, warn: float, bad: float) -> Color:
	return OSTheme.ACCENT if v >= warn else (OSTheme.WARN if v >= bad else OSTheme.ALARM)


static func _device_color(d: Dictionary) -> Color:
	if d.fault or (d.kind == "bay" and int(d.job) >= 0):
		return OSTheme.ALARM if d.kind != "bay" else OSTheme.WARN
	if d.kind == "pod" or d.kind == "filter":
		return _color(float(d.value), 0.75, 0.45)
	return OSTheme.ACCENT
