@tool
extends EditorPlugin

var dock: Control
var naming: ConfirmationDialog
var watcher: EditorDebuggerPlugin


func _enter_tree() -> void:
	dock = preload("res://addons/corklabs_pipeline/takes_dock.gd").new()
	dock.name = "Takes"
	add_control_to_dock(DOCK_SLOT_LEFT_UR, dock)

	naming = preload("res://addons/corklabs_pipeline/name_takes_dialog.gd").new()
	EditorInterface.get_base_control().add_child(naming)
	naming.applied.connect(_on_names_applied)
	dock.open_naming = open_naming

	watcher = preload("res://addons/corklabs_pipeline/run_watcher.gd").new()
	watcher.run_stopped.connect(_on_run_stopped)
	add_debugger_plugin(watcher)


func _exit_tree() -> void:
	if watcher:
		remove_debugger_plugin(watcher)
		watcher = null
	if naming:
		naming.queue_free()
		naming = null
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null


# Opens the naming window. `only_if_new`: stay quiet when nothing's unnamed.
func open_naming(only_if_new := false) -> void:
	var count: int = naming.populate()
	if count == 0 and only_if_new:
		return
	naming.popup_centered()


func _on_run_stopped() -> void:
	# Give the game a moment to finish writing files.
	await get_tree().create_timer(0.5).timeout
	open_naming(true)


func _on_names_applied(lines: PackedStringArray) -> void:
	for l in lines:
		dock.log_line(l)
	dock.refresh()
