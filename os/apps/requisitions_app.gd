# Requisitions: order resources, replacement parts and new robot models from
# corporate, within the budget corporate sets from your performance (each
# shift's review). Placing an order is a choice (5 facility minutes); corkHQ
# confirms it and reports approval, shipping and delivery. The catalogue is
# game/corporate/catalog.txt.
#
# Repairs use parts from stock: a job with no part stops halfway and waits
# (WAITING FOR PARTS, at the top). Express shipping costs more and arrives
# in about a third of the time. Deliveries arrive as crates the units bring in.
class_name RequisitionsApp
extends OSApp

var funds_label: Label
var category := ""
var items: Tree
var detail: Label
var qty: SpinBox
var express: CheckBox
var waiting: Label
var order_button: Button
var reply: Label
var orders_tree: Tree
var stock: Label
var cat_buttons: Array[Button] = []
var selected_item := ""
var _sig := ""


func _init() -> void:
	app_id = "requisitions"
	title = "Requisitions"
	default_size = Vector2(900, 520)
	icon_text = "REQ"
	icon_color = Color("f0b447")


func build() -> void:
	var req := _req()
	var top := HBoxContainer.new()
	add_child(top)
	var group := ButtonGroup.new()
	if req:
		for c in req.categories():
			var b := Button.new()
			b.text = c
			b.toggle_mode = true
			b.button_group = group
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(_show_category.bind(c))
			top.add_child(b)
			cat_buttons.append(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	funds_label = OSTheme.mono_label("", 15, OSTheme.WARN)
	top.add_child(funds_label)
	waiting = OSTheme.label("", 13, OSTheme.ALARM)
	waiting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(waiting)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(left)
	items = _tree(["Item", "Stock", "Price", "Delivery", "Approval"], [0, 60, 80, 80, 80])
	items.item_selected.connect(func():
		selected_item = str(items.get_selected().get_metadata(0))
		_update_detail())
	left.add_child(items)
	detail = OSTheme.label("Select an item.", 13)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size.y = 40
	left.add_child(detail)
	var row := HBoxContainer.new()
	left.add_child(row)
	row.add_child(OSTheme.label("Quantity", 13, OSTheme.TEXT_DIM))
	qty = SpinBox.new()
	qty.min_value = 1
	qty.max_value = 20
	qty.value = 1
	qty.value_changed.connect(func(_v): _update_detail())
	row.add_child(qty)
	express = CheckBox.new()
	express.text = "Express"
	express.focus_mode = Control.FOCUS_NONE
	express.tooltip_text = "Costs %d%% more, arrives in about a third of the time." % roundi((Requisitions.EXPRESS_COST - 1.0) * 100.0)
	express.toggled.connect(func(_on): _update_detail())
	row.add_child(express)
	order_button = Button.new()
	order_button.text = "Submit requisition"
	order_button.focus_mode = Control.FOCUS_NONE
	order_button.pressed.connect(_order)
	row.add_child(order_button)
	reply = OSTheme.label("", 12, OSTheme.TEXT_DIM)
	reply.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(reply)

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 340
	split.add_child(right)
	right.add_child(OSTheme.label("Your requisitions", 13, OSTheme.TEXT_DIM))
	orders_tree = _tree(["#", "Item", "Status", "Arrives"], [36, 0, 84, 60])
	right.add_child(orders_tree)
	right.add_child(OSTheme.label("In stock", 13, OSTheme.TEXT_DIM))
	stock = OSTheme.mono_label("", 12)
	stock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(stock)
	if req and not req.categories().is_empty():
		var first := req.categories().find("Parts")   # what you'll need most
		first = maxi(first, 0)
		cat_buttons[first].button_pressed = true
		_show_category(req.categories()[first])


func _tree(cols: Array, widths: Array) -> Tree:
	var t := Tree.new()
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	t.columns = cols.size()
	t.column_titles_visible = true
	t.hide_root = true
	t.select_mode = Tree.SELECT_ROW
	for i in cols.size():
		t.set_column_title(i, cols[i])
		t.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT)
		if widths[i] > 0:
			t.set_column_expand(i, false)
			t.set_column_custom_minimum_width(i, widths[i])
	return t


func _show_category(c: String) -> void:
	category = c
	items.clear()
	var root := items.create_item()
	for it in _req().catalog:
		if it.category != c:
			continue
		var row := items.create_item(root)
		row.set_metadata(0, it.id)
		row.set_text(0, it.name)
		var have := int(_req().inventory.get(it.id, 0))
		row.set_text(1, str(have) if str(it.effect) == "inventory" or str(it.effect).begins_with("robot:") else "-")
		if have == 0 and Requisitions.used_for_repairs(it.id):
			row.set_custom_color(1, OSTheme.ALARM)
		row.set_text(2, "%d cr" % it.price)
		row.set_text(3, "%s h" % str(it.hours))
		row.set_text(4, "needed" if it.approval else "-")
		if it.approval:
			row.set_custom_color(4, OSTheme.WARN)
	selected_item = ""
	_update_detail()


func _update_detail() -> void:
	var req := _req()
	var it: Dictionary = req.item(selected_item) if req else {}
	if it.is_empty():
		detail.text = "Select an item."
		order_button.disabled = true
		return
	var fast := express.button_pressed
	var cost: int = roundi(it.price * int(qty.value) * (Requisitions.EXPRESS_COST if fast else 1.0))
	detail.text = "%s: %s\n%d cr for %d  ·  delivery %.1f h%s  ·  in stock %d" % [it.name, it.description, cost, int(qty.value),
		float(it.hours) * (Requisitions.EXPRESS_TIME if fast else 1.0), "  ·  corporate must approve it" if it.approval else "",
		int(req.inventory.get(it.id, 0))]
	order_button.disabled = cost > req.funds
	order_button.tooltip_text = "Not enough funds" if cost > req.funds else ""


func _order() -> void:
	var r := Supervisor.requisition(selected_item, int(qty.value), express.button_pressed)
	reply.text = r.text
	reply.add_theme_color_override("font_color", OSTheme.ACCENT if r.ok else OSTheme.ALARM)
	_sig = ""
	refresh()


func refresh() -> void:
	var req := _req()
	if req == null:
		return
	funds_label.text = "BUDGET %d cr" % req.funds
	_update_detail()
	var board := sim().get_system("work") as WorkBoard
	var need := {}
	if board:
		for j in board.waiting_jobs():
			need[j.part] = int(need.get(j.part, 0)) + 1
	var parts := PackedStringArray()
	for k in need:
		parts.append("%s (%d job%s)" % [req.item(k).get("name", k), need[k], "" if need[k] == 1 else "s"])
	waiting.text = ("WAITING FOR PARTS: " + ", ".join(parts)) if not parts.is_empty() else ""
	waiting.visible = not parts.is_empty()
	var sig := str(req.orders.map(func(o): return [o.id, o.status])) + str(req.inventory)
	if sig == _sig:
		return
	_sig = sig
	if not category.is_empty():
		var keep := selected_item
		_show_category(category)
		selected_item = keep
		_update_detail()
	orders_tree.clear()
	var root := orders_tree.create_item()
	var list := req.orders.duplicate()
	list.reverse()
	for o in list:
		var it := req.item(o.item)
		var row := orders_tree.create_item(root)
		row.set_text(0, str(o.id))
		row.set_text(1, "%dx %s" % [o.qty, it.get("name", o.item)])
		row.set_text(2, o.status)
		row.set_custom_color(2, {"pending": OSTheme.WARN, "denied": OSTheme.ALARM, "in transit": OSTheme.INFO,
			"delivered": OSTheme.ACCENT, "crated": OSTheme.INFO, "unpacked": OSTheme.ACCENT}.get(o.status, OSTheme.TEXT))
		row.set_text(3, FacilitySim.format_clock(o.eta) if float(o.eta) >= 0.0 and o.status == "in transit" else "")
	var lines := PackedStringArray()
	for k in req.inventory:
		lines.append("%dx %s" % [req.inventory[k], req.item(k).get("name", k)])
	stock.text = "\n".join(lines) if not lines.is_empty() else "Nothing yet."


func _req() -> Requisitions:
	return sim().get_system("requisitions") as Requisitions if sim() else null
