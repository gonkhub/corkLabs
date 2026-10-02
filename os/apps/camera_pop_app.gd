# One camera in its own window (Cameras: Pop out, or P): watch a room while
# you work in another. Everything the Cameras app does on a single feed works
# here too (hover, click menus, pan / tilt / zoom, night vision); requests and
# the unit link stay in the main Cameras window. Several can be open at once;
# they're remembered with the window layout ("cam_pop_<n>").
class_name CameraPopApp
extends CamerasApp

var pop_cam := 0


func _init() -> void:
	super._init()
	app_id = "cam_pop_0"
	title = "Camera"
	default_size = Vector2(560, 380)
	icon_text = "CAM"


## Which camera (0-based) this window shows.
func for_camera(i: int) -> CameraPopApp:
	pop_cam = i
	app_id = "cam_pop_%d" % i
	title = "CAM %02d" % (i + 1)
	return self


func build() -> void:
	super.build()
	cam = pop_cam
	grid_mode = false
	# Just this camera: no switching between them here.
	for b in cam_buttons:
		b.visible = false
	single_button.visible = false
	grid_button.visible = false
	view_sep.visible = false
	if pop_button:
		pop_button.visible = false
	var w := _world()
	if w and pop_cam < w.cameras.size():
		title = "CAM %02d  %s" % [pop_cam + 1, w.cameras[pop_cam].display_name]
	_rebuild()


func _check_requests() -> void:
	pass   # (the main Cameras window asks them)


func show_camera(_i: int) -> void:
	cam = pop_cam
	grid_mode = false
	_rebuild()


func set_grid(_on: bool) -> void:
	pass


func save_state() -> Dictionary:
	var s := super.save_state()
	s.pop_cam = pop_cam
	return s


func load_state(state: Dictionary) -> void:
	super.load_state(state)
	cam = pop_cam
	grid_mode = false
	_rebuild()
