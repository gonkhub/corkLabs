# Forms: corporate's paperwork (Forms, game/story/forms.txt). The forms
# you've been issued (Liaison Pell issues them), their fields, and where each
# one stands (under review, returned and why, approved). Filling one in costs
# a big chunk of the shift (its minutes, when you file it); every answer
# must match corporate's records, so go and find them first (and write them
# down in Notes: next time it's quick).
class_name FormsApp
extends OSApp

var list: ItemList
var detail: VBoxContainer
var fields := {}   # label -> LineEdit
var result: Label
var selected := ""
var _key := ""


func _init() -> void:
	app_id = "forms"
	title = "Forms"
	default_size = Vector2(640, 440)
	icon_text = "FRM"
	icon_color = Color("e8c46a")


func build() -> void:
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(row)
	list = ItemList.new()
	list.custom_minimum_size = Vector2(220, 0)
	list.item_selected.connect(func(i: int):
		selected = str(list.get_item_metadata(i))
		_show())
	row.add_child(list)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	detail = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(detail)
	result = OSTheme.label("", 13, OSTheme.ACCENT)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(result)
	refresh()


func refresh() -> void:
	if sim() == null or list == null:
		return
	var forms := sim().get_system("forms") as Forms
	var avail := Forms.available(sim())
	var key := str(avail.map(func(d): return [d.id, forms.status(str(d.id)) if forms else ""]))
	if key == _key:
		return
	_key = key
	list.clear()
	for d in avail:
		var st := forms.status(str(d.id)) if forms else ""
		var i := list.add_item("%s%s" % [d.title.get_slice(":", 0), "" if st.is_empty() else "  (%s)" % st])
		list.set_item_metadata(i, str(d.id))
	if avail.is_empty():
		_clear()
		detail.add_child(OSTheme.label("No forms. Your liaison issues them (corkHQ: Reply).", 13, OSTheme.TEXT_DIM))
	elif selected.is_empty() or Forms.def(selected).is_empty():
		selected = str(avail[0].id)
		_show()
	else:
		_show()


func _clear() -> void:
	for c in detail.get_children():
		c.queue_free()
	fields.clear()


func _show() -> void:
	_clear()
	var d := Forms.def(selected)
	if d.is_empty():
		return
	var forms := sim().get_system("forms") as Forms
	var st := forms.status(selected) if forms else ""
	detail.add_child(OSTheme.label(str(d.title), 16, OSTheme.ACCENT))
	var about := OSTheme.label(str(d.description), 13, OSTheme.TEXT_DIM)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(about)
	for f in d.fields:
		detail.add_child(OSTheme.label(str(f.label), 13))
		var e := LineEdit.new()
		e.add_theme_font_override("font", Mono.font())
		e.editable = st != "review" and st != "approved"
		detail.add_child(e)
		fields[str(f.label)] = e
	var status_text: String = {"": "Not filed.", "review": "Filed: under review.", "returned": "RETURNED: the %s didn't match. Correct it and file it again." % str(forms.filed.get(selected, {}).get("why", "")).to_lower() if forms else "",
		"approved": "APPROVED."}.get(st, "")
	detail.add_child(OSTheme.label(status_text, 13, OSTheme.WARN if st == "returned" else OSTheme.TEXT))
	var file := Button.new()
	file.text = "File it (%d min)" % int(d.minutes)
	file.focus_mode = Control.FOCUS_NONE
	file.disabled = st == "review" or st == "approved"
	file.tooltip_text = "Filling in a form takes time. Make sure of your answers first."
	file.pressed.connect(_file)
	detail.add_child(file)


func _file() -> void:
	var answers := {}
	for label in fields:
		answers[label] = (fields[label] as LineEdit).text
	var why: String = Supervisor.file_form(selected, answers)
	result.text = why if not why.is_empty() else "Filed. Corporate will review it."
	_key = ""
	refresh()


## Fills in a field (tests).
func set_answer(label: String, text: String) -> void:
	if fields.has(label):
		(fields[label] as LineEdit).text = text
