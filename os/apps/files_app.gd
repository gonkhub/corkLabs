# Files: the corkLabs OS file system, point and click. The same files as the
# Terminal's ls / cat (VirtualFS), with the same rules: reading a file the
# first time costs facility time, reading former staff's files is a policy
# violation, encrypted files need a password, programs can be run.
#
# Hidden files ("." names) only show once the supervisor has found out they
# exist (ls -a in the Terminal): then a "Show hidden" box appears here.
class_name FilesApp
extends OSApp

var tree: Tree
var list: ItemList
var view: RichTextLabel
var path_label: Label
var hidden_box: CheckBox
var password: LineEdit
var action_row: HBoxContainer
var action_button: Button
var dir := VirtualFS.HOME
var file := ""
var _entries: Array[Dictionary] = []
var _tree_key := ""


func _init() -> void:
	app_id = "files"
	title = "Files"
	default_size = Vector2(860, 480)
	icon_text = "DIR"
	icon_color = Color("e8c872")


func build() -> void:
	var top := HBoxContainer.new()
	add_child(top)
	path_label = OSTheme.mono_label("", 13, OSTheme.ACCENT)
	path_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(path_label)
	hidden_box = CheckBox.new()
	hidden_box.text = "Show hidden"
	hidden_box.focus_mode = Control.FOCUS_NONE
	hidden_box.toggled.connect(func(_on): _fill_list())
	top.add_child(hidden_box)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	tree = Tree.new()
	tree.custom_minimum_size.x = 200
	tree.hide_root = false
	tree.item_selected.connect(_on_folder)
	split.add_child(tree)
	var right := VSplitContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	list = ItemList.new()
	list.custom_minimum_size.y = 120
	list.item_selected.connect(_on_file)
	list.item_activated.connect(_on_file)
	right.add_child(list)
	var col := VBoxContainer.new()
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(col)
	view = RichTextLabel.new()
	view.bbcode_enabled = true
	view.selection_enabled = true
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.add_theme_font_override("normal_font", Mono.font())
	view.add_theme_font_size_override("normal_font_size", 13)
	col.add_child(view)
	action_row = HBoxContainer.new()
	col.add_child(action_row)
	password = LineEdit.new()
	password.placeholder_text = "password"
	password.secret = true
	password.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	password.text_submitted.connect(func(_t): _action())
	action_row.add_child(password)
	action_button = Button.new()
	action_button.focus_mode = Control.FOCUS_NONE
	action_button.pressed.connect(_action)
	action_row.add_child(action_button)
	action_row.visible = false
	_fill_tree()
	_fill_list()


func save_state() -> Dictionary:
	return {"dir": dir}


func load_state(state: Dictionary) -> void:
	dir = str(state.get("dir", VirtualFS.HOME))
	if sim() and not Story.exists(sim(), dir):
		dir = VirtualFS.HOME
	_tree_key = ""
	refresh()


func refresh() -> void:
	if sim() == null or tree == null:
		return
	hidden_box.visible = Story.knows(sim(), "hidden_files")
	# Folders come and go (a purge, the maintenance account): rebuild when they do.
	var key := ",".join(_folders("/").map(func(e): return e.path))
	if key != _tree_key:
		_fill_tree()
		_fill_list()


func _folders(under: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in Story.list(sim(), under, false):
		if e.dir:
			out.append(e)
			out.append_array(_folders(e.path))
	return out


func _fill_tree() -> void:
	if sim() == null:
		return
	_tree_key = ",".join(_folders("/").map(func(e): return e.path))
	tree.clear()
	var root := tree.create_item()
	root.set_text(0, "/")
	root.set_metadata(0, "/")
	_add_folders(root, "/")
	if not Story.exists(sim(), dir):
		dir = VirtualFS.HOME


func _add_folders(parent: TreeItem, vdir: String) -> void:
	for e in Story.list(sim(), vdir, false):
		if not e.dir:
			continue
		var item := tree.create_item(parent)
		item.set_text(0, str(e.name))
		item.set_metadata(0, e.path)
		item.collapsed = not dir.begins_with(str(e.path))
		if e.path == dir:
			item.select(0)
		_add_folders(item, e.path)


func _on_folder() -> void:
	var item := tree.get_selected()
	if item == null:
		return
	dir = str(item.get_metadata(0))
	file = ""
	_fill_list()


func _fill_list() -> void:
	if sim() == null:
		return
	path_label.text = dir
	list.clear()
	_entries.clear()
	for e in Story.list(sim(), dir, hidden_box.button_pressed and hidden_box.visible):
		if e.dir:
			continue
		_entries.append(e)
		var label := str(e.name)
		if e.meta.has("exec"):
			label += "   (program)"
		elif Story.is_encrypted(sim(), e):
			label += "   (encrypted)"
		elif not Story.knows(sim(), "read:" + str(e.path)):
			label += "   ·"
		list.add_item(label)
	if _entries.is_empty():
		view.text = "[color=#%s](no files here)[/color]" % OSTheme.TEXT_DIM.to_html(false)
		action_row.visible = false


func _on_file(i: int) -> void:
	if i < 0 or i >= _entries.size():
		return
	open_file(str(_entries[i].path))


## Shows a file (reading it, with what that costs, the first time).
func open_file(vpath: String) -> void:
	file = vpath
	var e := Story.entry(sim(), vpath)
	password.visible = false
	action_row.visible = false
	if e.meta.has("exec"):
		view.text = "%s\n\n[color=#%s]A program.[/color]" % [_esc(str(e.body)), OSTheme.TEXT_DIM.to_html(false)]
		action_button.text = "Run"
		action_row.visible = true
		Story.learn(sim(), "cmd:run")
		return
	var r: Dictionary = Supervisor.read_file(vpath)
	if not r.ok:
		if r.get("encrypted", false):
			view.text = "[color=#%s]%s[/color]\n\n[color=#%s]Encrypted.[/color]" % [OSTheme.TEXT_DIM.to_html(false), _esc(str(r.text)), OSTheme.WARN.to_html(false)]
			password.visible = true
			password.text = ""
			action_button.text = "Decrypt"
			action_row.visible = true
		else:
			view.text = _esc(str(r.error))
		return
	var note := ""
	if r.first and float(r.minutes) > 0.0:
		note = "\n\n[color=#%s](%d min reading)[/color]" % [OSTheme.TEXT_DIM.to_html(false), int(r.minutes)]
	view.text = _esc(str(r.text)) + note
	_fill_list_keep()


func _fill_list_keep() -> void:
	var keep := file
	_fill_list()
	for i in _entries.size():
		if _entries[i].path == keep:
			list.select(i)


func _action() -> void:
	var e := Story.entry(sim(), file)
	if e.is_empty():
		return
	if e.meta.has("exec"):
		Story.learn(sim(), "app:" + str(e.meta.exec))
		desktop.open_app(str(e.meta.exec))
		return
	var r: Dictionary = Supervisor.decrypt(file, password.text)
	if r.ok:
		open_file(file)
	else:
		view.text += "\n[color=#%s]%s[/color]" % [OSTheme.WARN.to_html(false), _esc(str(r.text))]


static func _esc(t: String) -> String:
	return t.replace("[", "[lb]")
