# Notes: the desk's notepad. Whatever's written here stays on the desk, not
# in the facility: it survives logging off, retrying a shift, even starting
# over on a new save (it lives in OSSettings). A good place to keep a
# password. Somebody else already has: the notepad came with notes in it.
#
# Writing costs no facility time.
class_name NotesApp
extends OSApp

var edit: TextEdit
var _dirty := 0.0


func _init() -> void:
	app_id = "notes"
	title = "Notes"
	default_size = Vector2(520, 420)
	icon_text = "TXT"
	icon_color = Color("f5e6a8")


func build() -> void:
	edit = TextEdit.new()
	edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.add_theme_font_override("font", Mono.font())
	edit.add_theme_font_size_override("font_size", 14)
	edit.add_theme_color_override("font_color", Color("2b2616"))
	edit.add_theme_color_override("caret_color", Color("2b2616"))
	edit.add_theme_stylebox_override("normal", OSTheme.box(Color("f5e6a8"), Color("c9b56a"), 2, 12, 10))
	edit.add_theme_stylebox_override("focus", OSTheme.box(Color("f5e6a8"), Color("c9b56a"), 2, 12, 10))
	edit.text = str(OSSettings.get_value("notes"))
	edit.text_changed.connect(func(): _dirty = 1.0)
	add_child(edit)
	add_child(OSTheme.label("Notes stay on the desk, whatever happens to the facility.", 11, OSTheme.TEXT_DIM))


func _process(delta: float) -> void:
	# Save a second after the last keystroke.
	if _dirty > 0.0:
		_dirty -= delta
		if _dirty <= 0.0:
			OSSettings.set_value("notes", edit.text)


func key_input(_event: InputEventKey) -> bool:
	return edit != null and edit.has_focus()


func _exit_tree() -> void:
	if edit and _dirty > 0.0:
		OSSettings.set_value("notes", edit.text)
