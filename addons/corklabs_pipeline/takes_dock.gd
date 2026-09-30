# The "Takes" panel in the editor (top-left dock, next to Scene and Import).
#
#   - lists every take under res://takes/
#   - pick one to set its robot, clip name, loop and cleanup settings
#   - Bake / Bake all turn takes into clips in res://animations/<robot>/
#
# Baking runs in a separate headless Godot process using tools/bake_all.gd,
# so it's exactly the same code as baking from the command line.
@tool
extends VBoxContainer

const TAKES_DIR := "res://takes"
const ROBOTS_DIR := "res://robots"

var tree: Tree
var robot_pick: OptionButton
var clip_edit: LineEdit
var note_edit: LineEdit
var loop_check: CheckBox
var fps_spin: SpinBox
var smooth_spin: SpinBox
var trim_start_spin: SpinBox
var trim_end_spin: SpinBox
var stop_reach_check: CheckBox
var log_box: TextEdit
var detail_box: Control

## Set by the plugin: opens the "Name your new takes" window.
var open_naming: Callable

var robot_ids := PackedStringArray()
var selected_path := ""
var selected: Resource


func _ready() -> void:
	custom_minimum_size = Vector2(260, 400)
	_build_ui()
	refresh()


func _build_ui() -> void:
	var bar := HBoxContainer.new()
	add_child(bar)
	_button(bar, "Refresh", refresh)
	_button(bar, "Name takes...", _name_takes)
	_button(bar, "Bake all", _bake_all)
	_button(bar, "Open game", _open_demo)

	tree = Tree.new()
	tree.columns = 4
	tree.column_titles_visible = true
	tree.set_column_title(0, "Take")
	tree.set_column_title(1, "Robot")
	tree.set_column_title(2, "Clip")
	tree.set_column_title(3, "Len")
	tree.set_column_expand_ratio(0, 3)
	tree.set_column_expand(1, false)
	tree.set_column_custom_minimum_width(1, 60)
	tree.set_column_expand_ratio(2, 2)
	tree.set_column_expand(3, false)
	tree.set_column_custom_minimum_width(3, 48)
	tree.hide_root = true
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.custom_minimum_size.y = 180
	tree.item_selected.connect(_on_selected)
	add_child(tree)

	detail_box = VBoxContainer.new()
	add_child(detail_box)
	var grid := GridContainer.new()
	grid.columns = 2
	detail_box.add_child(grid)
	robot_pick = OptionButton.new()
	_row(grid, "Robot", robot_pick)
	clip_edit = LineEdit.new()
	clip_edit.placeholder_text = "(file name)  e.g. idle_scan, act_weld"
	_row(grid, "Clip name", clip_edit)
	note_edit = LineEdit.new()
	_row(grid, "Note", note_edit)
	loop_check = CheckBox.new()
	loop_check.text = "seamless loop (idles)"
	_row(grid, "Loop", loop_check)
	fps_spin = _spin(10, 120, 1)
	_row(grid, "FPS", fps_spin)
	smooth_spin = _spin(0.0, 0.3, 0.005)
	_row(grid, "Smoothing (s)", smooth_spin)
	trim_start_spin = _spin(0.0, 600.0, 0.05)
	_row(grid, "Trim start (s)", trim_start_spin)
	trim_end_spin = _spin(0.0, 600.0, 0.05)
	_row(grid, "Trim end (s)", trim_end_spin)
	stop_reach_check = CheckBox.new()
	stop_reach_check.text = "cut reach for MENU"
	_row(grid, "Stop reach", stop_reach_check)

	var actions := HBoxContainer.new()
	detail_box.add_child(actions)
	_button(actions, "Save", _save_selected)
	_button(actions, "Save + Bake", _bake_selected)
	_button(actions, "Inspector", _inspect_selected)
	detail_box.visible = false

	log_box = TextEdit.new()
	log_box.editable = false
	log_box.custom_minimum_size.y = 110
	log_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	add_child(log_box)


func refresh() -> void:
	robot_ids = PackedStringArray()
	for d in DirAccess.get_directories_at(ROBOTS_DIR):
		if FileAccess.file_exists("%s/%s/%s.tscn" % [ROBOTS_DIR, d, d]):
			robot_ids.append(d)
	robot_pick.clear()
	robot_pick.add_item("(none)")
	for id in robot_ids:
		robot_pick.add_item(id)

	tree.clear()
	var root := tree.create_item()
	var paths := PackedStringArray()
	_collect(TAKES_DIR, paths)
	paths.sort()
	for i in range(paths.size() - 1, -1, -1):   # newest first
		var take := ResourceLoader.load(paths[i], "", ResourceLoader.CACHE_MODE_REPLACE)
		if take == null or take.get("sample_times") == null:
			continue
		var item := tree.create_item(root)
		# "take_2026-09-29T14-05-33" -> "09-29 14:05:33"; hover for the full path.
		var label := paths[i].get_file().get_basename().trim_prefix("take_")
		if label.length() >= 19 and label[10] == "T":
			label = label.substr(5, 5) + " " + label.substr(11, 8).replace("-", ":")
		item.set_text(0, label)
		item.set_tooltip_text(0, paths[i])
		item.set_text(1, str(take.get("robot_id")))
		item.set_text(2, str(take.get("clip_name")))
		var times: PackedFloat32Array = take.get("sample_times")
		item.set_text(3, "%.1fs" % (times[times.size() - 1] if times.size() > 0 else 0.0))
		item.set_metadata(0, paths[i])
		if paths[i] == selected_path:
			item.select(0)
	_log("%d takes, robots: %s" % [paths.size(), ", ".join(robot_ids)])


func _collect(dir: String, out: PackedStringArray) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".res"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(d), out)


func _on_selected() -> void:
	var item := tree.get_selected()
	if item == null:
		return
	selected_path = item.get_metadata(0)
	selected = ResourceLoader.load(selected_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	detail_box.visible = selected != null
	if selected == null:
		return
	var id := str(selected.get("robot_id"))
	robot_pick.select(robot_ids.find(id) + 1 if robot_ids.has(id) else 0)
	clip_edit.text = str(selected.get("clip_name"))
	note_edit.text = str(selected.get("note"))
	var recipe: Resource = selected.get("recipe")
	var defaults := preload("res://pipeline/cleanup_recipe.gd").new()
	var r: Resource = recipe if recipe else defaults
	loop_check.button_pressed = r.get("loop")
	fps_spin.value = r.get("fps")
	smooth_spin.value = r.get("smoothing")
	trim_start_spin.value = r.get("trim_start")
	trim_end_spin.value = r.get("trim_end")
	stop_reach_check.button_pressed = r.get("trim_stop_reach")


func _save_selected() -> bool:
	if selected == null:
		return false
	var idx := robot_pick.selected
	selected.set("robot_id", robot_ids[idx - 1] if idx > 0 else "")
	selected.set("clip_name", clip_edit.text.strip_edges())
	selected.set("note", note_edit.text)
	var recipe: Resource = selected.get("recipe")
	if recipe == null:
		recipe = preload("res://pipeline/cleanup_recipe.gd").new()
		selected.set("recipe", recipe)
	recipe.set("loop", loop_check.button_pressed)
	recipe.set("fps", int(fps_spin.value))
	recipe.set("smoothing", smooth_spin.value)
	recipe.set("trim_start", trim_start_spin.value)
	recipe.set("trim_end", trim_end_spin.value)
	recipe.set("trim_stop_reach", stop_reach_check.button_pressed)
	var err := ResourceSaver.save(selected, selected_path)
	if err != OK:
		_log("Could not save %s (error %d)" % [selected_path, err])
		return false
	_log("Saved " + selected_path)
	refresh()
	return true


func _bake_selected() -> void:
	if not _save_selected():
		return
	if str(selected.get("robot_id")).is_empty():
		_log("Pick a robot first.")
		return
	_run_bake(["--take", selected_path])


func _name_takes() -> void:
	if open_naming.is_valid():
		open_naming.call()


func log_line(line: String) -> void:
	_log(line)


func _open_demo() -> void:
	EditorInterface.open_scene_from_path("res://os/desktop.tscn")


func _inspect_selected() -> void:
	if selected:
		EditorInterface.edit_resource(selected)


func _bake_all() -> void:
	_run_bake([])


func _run_bake(extra: Array) -> void:
	var args := ["--headless", "--xr-mode", "off", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tools/bake_all.gd", "--"]
	args.append_array(extra)
	var output := []
	_log("Baking...")
	var code := OS.execute(OS.get_executable_path(), PackedStringArray(args), output, true)
	for chunk in output:
		for line in str(chunk).split("\n"):
			if line.begins_with("BAKED") or line.begins_with("FAIL") or line.begins_with("SKIP") or line.contains("baked,"):
				_log(line)
	if code != 0:
		_log("Bake finished with errors (exit %d)." % code)
	EditorInterface.get_resource_filesystem().scan()


func _log(line: String) -> void:
	log_box.text += line + "\n"
	log_box.scroll_vertical = log_box.get_line_count()


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _row(grid: GridContainer, label: String, control: Control) -> void:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)


func _spin(lo: float, hi: float, step: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	return s
