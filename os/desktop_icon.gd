# A desktop icon: a tile with a short code ("CAM"), the app's name under it,
# and an optional unread badge. Double-click (or Enter) opens it.
class_name DesktopIcon
extends Control

signal opened

const SIZE := Vector2(86, 78)

var code := "APP"
var title := "App"
var color := OSTheme.ACCENT
var badge := 0:
	set(v):
		if v != badge:
			badge = v
			queue_redraw()

var _hover := false
var _selected := false


func setup(icon_code: String, app_title: String, icon_color: Color) -> void:
	code = icon_code
	title = app_title
	color = icon_color
	custom_minimum_size = SIZE
	tooltip_text = "%s (double-click to open)" % title
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))
	focus_mode = Control.FOCUS_CLICK
	focus_exited.connect(_deselect)


func _set_hover(on: bool) -> void:
	_hover = on
	queue_redraw()


func _deselect() -> void:
	_selected = false
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_selected = true
		queue_redraw()
		if event.double_click:
			opened.emit()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		opened.emit()


func _draw() -> void:
	var font := get_theme_default_font()
	if _hover or _selected:
		draw_style_box(OSTheme.box(Color(color, 0.12 if _hover else 0.2), Color(color, 0.4), 6), Rect2(Vector2.ZERO, size))
	var tile := Rect2(Vector2((size.x - 46) * 0.5, 6), Vector2(46, 40))
	draw_style_box(OSTheme.box(OSTheme.PANEL_LIGHT, color, 6), tile)
	var mono := Mono.font()
	var tw := mono.get_string_size(code, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(mono, tile.position + Vector2((tile.size.x - tw) * 0.5, 25), code, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
	var lw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(font, Vector2((size.x - lw) * 0.5, 64), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, OSTheme.TEXT)
	if badge > 0:
		var c := tile.position + Vector2(tile.size.x, 2)
		draw_circle(c, 9, OSTheme.ALARM)
		var t := str(mini(badge, 99))
		var bw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(font, c + Vector2(-bw * 0.5, 4), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
