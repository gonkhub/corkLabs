@tool
extends EditorPlugin

var dock: Control


func _enter_tree() -> void:
	dock = preload("res://addons/corklabs_pipeline/takes_dock.gd").new()
	dock.name = "Takes"
	add_control_to_dock(DOCK_SLOT_LEFT_UR, dock)


func _exit_tree() -> void:
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null
