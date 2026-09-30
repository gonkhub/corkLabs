# A window on the corkLabs desktop: a title bar you drag, minimise /
# maximise / close buttons, a resize grip in the corner, and an app inside.
#
#   drag title bar          move (drag a maximised window to restore it)
#   drag to screen edge     snap: left/right edge = half screen, top = maximise
#   double-click title      maximise / restore
#
#     var win := OSWindow.new()
#     win.setup(app)            # app: an OSApp (its title and size are used)
#     desktop.window_layer.add_child(win)
class_name OSWindow
extends PanelContainer

signal focused(win: OSWindow)
signal closed(win: OSWindow)
signal minimized(win: OSWindow)
## While dragging the title bar: where the mouse is (window-layer coordinates).
signal dragging(win: OSWindow, mouse: Vector2)
signal drag_ended(win: OSWindow, mouse: Vector2)

const TITLE_HEIGHT := 28
const MIN_SIZE := Vector2(280, 160)

var app: OSApp
var title_bar: PanelContainer
var title_label: Label
var max_button: Button
var is_focused := false

var _dragging := false
var _style: StyleBoxFlat
var _title_style: StyleBoxFlat
## Size and place before maximising or snapping (empty = not maximised/snapped).
var _restore_rect := Rect2()
var _maximized := false


func setup(os_app: OSApp) -> void:
	app = os_app
	name = "Win_" + app.app_id
	custom_minimum_size = MIN_SIZE
	size = app.default_size
	mouse_filter = Control.MOUSE_FILTER_STOP

	_style = OSTheme.box(OSTheme.PANEL, OSTheme.LINE, 6)
	_style.shadow_color = Color(0, 0, 0, 0.45)
	_style.shadow_size = 10
	add_theme_stylebox_override("panel", _style)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	add_child(col)

	title_bar = PanelContainer.new()
	title_bar.custom_minimum_size.y = TITLE_HEIGHT
	_title_style = OSTheme.box(OSTheme.TITLE, Color(0, 0, 0, 0), 6, 10, 2)
	_title_style.corner_radius_bottom_left = 0
	_title_style.corner_radius_bottom_right = 0
	title_bar.add_theme_stylebox_override("panel", _title_style)
	title_bar.gui_input.connect(_on_title_input)
	col.add_child(title_bar)

	var row := HBoxContainer.new()
	title_bar.add_child(row)
	var badge := OSTheme.mono_label(app.icon_text, 11, app.icon_color)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(badge)
	title_label = OSTheme.label(app.title, 14)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(title_label)
	row.add_child(_title_button("–", "Minimise", func(): minimized.emit(self)))
	max_button = _title_button("□", "Maximise", toggle_maximize)
	row.add_child(max_button)
	row.add_child(_title_button("×", "Close", func(): close()))

	var margin := MarginContainer.new()
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	col.add_child(margin)
	app.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(app)

	var grip := _Grip.new()
	grip.window = self
	add_child(grip)


func _title_button(text: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.flat = true
	b.custom_minimum_size = Vector2(26, 22)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	return b


func set_focused(on: bool) -> void:
	is_focused = on
	_title_style.bg_color = OSTheme.TITLE_FOCUS if on else OSTheme.TITLE
	_style.border_color = OSTheme.ACCENT.darkened(0.35) if on else OSTheme.LINE


func close() -> void:
	closed.emit(self)
	queue_free()


func is_maximized() -> bool:
	return _maximized


func toggle_maximize() -> void:
	if _maximized:
		restore()
	else:
		maximize()


func maximize() -> void:
	snap_to(Rect2(Vector2.ZERO, get_parent_area_size()))
	_maximized = true
	max_button.text = "❐"
	max_button.tooltip_text = "Restore"


## Fills `rect` (a snap), remembering where it was so restore() goes back.
func snap_to(rect: Rect2) -> void:
	if _restore_rect.size == Vector2.ZERO:
		_restore_rect = Rect2(position, size)
	position = rect.position
	size = rect.size
	_maximized = false
	max_button.text = "□"
	max_button.tooltip_text = "Maximise"


func restore() -> void:
	if _restore_rect.size != Vector2.ZERO:
		position = _restore_rect.position
		size = _restore_rect.size
	_restore_rect = Rect2()
	_maximized = false
	max_button.text = "□"
	max_button.tooltip_text = "Maximise"


## The rect to remember for next session (the un-maximised one).
func normal_rect() -> Rect2:
	return _restore_rect if _restore_rect.size != Vector2.ZERO else Rect2(position, size)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		focused.emit(self)


func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			focused.emit(self)
			if event.double_click:
				toggle_maximize()
				_dragging = false
				return
		elif _dragging:
			drag_ended.emit(self, _mouse_in_layer())
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		if _restore_rect.size != Vector2.ZERO:
			# Pulling a maximised/snapped window off: restore it under the cursor.
			var grab: float = event.position.x / maxf(size.x, 1.0)
			restore()
			position = _mouse_in_layer() - Vector2(size.x * grab, TITLE_HEIGHT * 0.5)
		else:
			position += event.relative
		_keep_on_screen()
		dragging.emit(self, _mouse_in_layer())


func _mouse_in_layer() -> Vector2:
	var parent := get_parent() as Control
	return parent.get_local_mouse_position() if parent else get_global_mouse_position()


func _keep_on_screen() -> void:
	var area := get_parent_area_size()
	position.x = clampf(position.x, -size.x + 80.0, area.x - 80.0)
	position.y = clampf(position.y, 0.0, area.y - TITLE_HEIGHT)


func _resize_by(delta: Vector2) -> void:
	_restore_rect = Rect2()
	_maximized = false
	size = (size + delta).max(MIN_SIZE)


# The little triangle in the bottom-right corner that resizes the window.
class _Grip:
	extends Control
	var window: OSWindow
	var _drag := false

	func _ready() -> void:
		mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
		size_flags_horizontal = Control.SIZE_SHRINK_END
		size_flags_vertical = Control.SIZE_SHRINK_END
		custom_minimum_size = Vector2(14, 14)

	func _draw() -> void:
		var s := size
		draw_colored_polygon(PackedVector2Array([Vector2(s.x, 2), Vector2(s.x, s.y), Vector2(2, s.y)]), OSTheme.LINE)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_drag = event.pressed
		elif event is InputEventMouseMotion and _drag:
			window._resize_by(event.relative)
