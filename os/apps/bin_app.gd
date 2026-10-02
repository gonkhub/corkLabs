# Recycle Bin: the Files app, opened on /trash, where deleted files wait.
# Former supervisors deleted things; corporate deletes things; nobody ever
# emptied it. Emptying it (for good, this run) is the tidy thing to do, and
# corporate likes a tidy terminal.
class_name BinApp
extends FilesApp

var empty_button: Button


func _init() -> void:
	super()
	app_id = "bin"
	title = "Recycle Bin"
	icon_text = "BIN"
	icon_color = Color("9fb3ad")
	default_size = Vector2(760, 440)
	dir = "/trash"


func build() -> void:
	super.build()
	empty_button = Button.new()
	empty_button.text = "Empty the Recycle Bin"
	empty_button.focus_mode = Control.FOCUS_NONE
	empty_button.tooltip_text = "Deletes everything in it for good."
	empty_button.pressed.connect(func():
		if Supervisor.empty_bin():
			file = ""
			view.text = "[color=#%s]The Recycle Bin is empty.[/color]" % OSTheme.TEXT_DIM.to_html(false)
		_fill_list())
	add_child(empty_button)


func load_state(_state: Dictionary) -> void:
	dir = "/trash"   # it always opens on the bin
	refresh()


func refresh() -> void:
	super.refresh()
	if empty_button and sim():
		empty_button.disabled = Story.knows(sim(), "bin_emptied")
