# Base for a corkLabs OS app: a Control that lives inside an OSWindow.
# Subclasses set their id/title/size/icon in _init(), build their UI in
# build(), and update it in refresh(), which the desktop calls when facility
# time moves and a couple of times a second.
class_name OSApp
extends VBoxContainer

## Unique id (one window per app).
var app_id := "app"
var title := "App"
var default_size := Vector2(560, 380)
## Short text for the desktop icon and title bar badge ("CAM", "LOG"...).
var icon_text := "APP"
var icon_color := OSTheme.ACCENT
## The desktop (for opening other apps, toasts, the 3D world).
var desktop: Node


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	build()
	refresh()


## Build the UI. Called once.
func build() -> void:
	pass


## Update from the running facility. Called often: keep it cheap.
func refresh() -> void:
	pass


func sim() -> FacilitySim:
	return Facility.sim if Facility.running else null


## A row of buttons: [["Label", callable], ...]
func button_row(buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	for b in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(b[1])
		row.add_child(btn)
	return row
