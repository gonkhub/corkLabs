# One live security-camera feed: its own SubViewport looking into the
# desktop's hidden facility world, through a camera that copies one of the
# SecurityCameras every frame, with the CCTV look and an on-screen caption.
#
# Interactive feeds drive the camera's pan/tilt/zoom head:
#   drag            pan / tilt
#   scroll wheel    zoom
#   double-click    back to the home view
# All free: pointing a camera is only looking.
class_name CCTVFeed
extends Control

signal clicked(feed: CCTVFeed)

const FEED_SHADER := preload("res://os/cctv_feed.gdshader")

## Index into FacilityWorld.cameras.
var cam := 0
## Mouse drives the camera (single view) or just selects it (grid view).
var interactive := true
var world: FacilityWorld

var screen: SubViewportContainer
var viewport: SubViewport
var eye: Camera3D
var caption: Label
var ptz_label: Label
var _material: ShaderMaterial
var _dragging := false


func setup(facility_world: FacilityWorld, world_viewport: SubViewport, cam_index: int, is_interactive: bool) -> void:
	world = facility_world
	cam = cam_index
	interactive = is_interactive
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_MOVE if interactive else Control.CURSOR_POINTING_HAND

	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	screen = SubViewportContainer.new()
	screen.stretch = true
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = FEED_SHADER
	screen.material = _material
	add_child(screen)
	viewport = SubViewport.new()
	viewport.handle_input_locally = false
	viewport.gui_disable_input = true
	if world_viewport:
		viewport.world_3d = world_viewport.find_world_3d()
	screen.add_child(viewport)
	eye = Camera3D.new()
	eye.current = true
	viewport.add_child(eye)

	caption = OSTheme.mono_label("", 14, Color(0.85, 1.0, 0.9))
	caption.position = Vector2(12, 8)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)
	ptz_label = OSTheme.mono_label("", 12, Color(0.85, 1.0, 0.9, 0.8))
	ptz_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ptz_label.position = Vector2(12, -24)
	ptz_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ptz_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ptz_label)


func set_filter(on: bool) -> void:
	screen.material = _material if on else null


func camera() -> SecurityCamera:
	return world.cameras[cam] if world and cam < world.cameras.size() else null


func _process(_delta: float) -> void:
	var src := camera()
	if src == null or not is_visible_in_tree():
		return
	eye.global_transform = src.global_transform
	eye.fov = src.fov
	var clock := FacilitySim.format_time(Facility.sim.time()) if Facility.running else ""
	caption.text = "CAM %02d  %s\n%s  ● REC" % [cam + 1, src.display_name.to_upper(), clock]
	ptz_label.position.y = size.y - 24
	var ptz := "AUTO-TRACK" if src.auto_track else "PAN %+4d°  TILT %+3d°" % [roundi(src.pan), roundi(src.tilt)]
	ptz_label.text = "%s   ZOOM %.1fx" % [ptz, src.zoom_level()]


func _gui_input(event: InputEvent) -> void:
	var src := camera()
	if src == null:
		return
	if event is InputEventMouseButton:
		if not interactive:
			if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				clicked.emit(self)
			return
		match event.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				_dragging = event.pressed
				if event.pressed and event.double_click:
					src.reset_view()
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					src.zoom_by(0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					src.zoom_by(1.0 / 0.9)
		accept_event()
	elif event is InputEventMouseMotion and _dragging and interactive:
		# Drag the picture: degrees per pixel follow the zoom, so it feels the same zoomed in.
		var deg_per_px := src.fov / maxf(size.y, 1.0)
		src.nudge(event.relative.x * deg_per_px, event.relative.y * deg_per_px)
		accept_event()
