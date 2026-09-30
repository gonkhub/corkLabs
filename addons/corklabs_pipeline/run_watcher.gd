# Tells the plugin when a game run launched from the editor ends (you press
# Stop, or close the game window), so it can offer to name new takes.
@tool
extends EditorDebuggerPlugin

signal run_stopped


func _setup_session(session_id: int) -> void:
	var session := get_session(session_id)
	session.stopped.connect(func(): run_stopped.emit())
