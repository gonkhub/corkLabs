# Cameras: live security feeds of the 3D facility. The feed is its own
# SubViewport looking into the desktop's (hidden) facility world through a
# camera that copies the chosen security camera every frame.
class_name CamerasApp
extends OSApp

const FEED_SHADER := preload("res://os/cctv_feed.gdshader")

var cam := 0
var feed_vp: SubViewport
var feed_cam: Camera3D
var screen: SubViewportContainer
var overlay: Label
var cam_buttons: Array[Button] = []


func _init() -> void:
	app_id = "cameras"
	title = "Cameras"
	default_size = Vector2(760, 540)
	icon_text = "CAM"
	icon_color = OSTheme.INFO


func build() -> void:
	var world: FacilityWorld = desktop.world if desktop else null
	var row := HBoxContainer.new()
	add_child(row)
	var group := ButtonGroup.new()
	var names := world.camera_names() if world else PackedStringArray()
	for i in names.size():
		var b := Button.new()
		b.text = "CAM %d  %s" % [i + 1, names[i]]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = i == cam
		b.pressed.connect(func(): cam = i)
		row.add_child(b)
		cam_buttons.append(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var filt := CheckBox.new()
	filt.text = "CCTV filter"
	filt.button_pressed = true
	filt.focus_mode = Control.FOCUS_NONE
	row.add_child(filt)

	var holder := Control.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.clip_contents = true
	add_child(holder)
	screen = SubViewportContainer.new()
	screen.stretch = true
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = FEED_SHADER
	screen.material = mat
	holder.add_child(screen)
	filt.toggled.connect(func(on: bool): screen.material = mat if on else null)

	feed_vp = SubViewport.new()
	feed_vp.handle_input_locally = false
	if desktop and desktop.world_viewport:
		feed_vp.world_3d = desktop.world_viewport.find_world_3d()
	screen.add_child(feed_vp)
	feed_cam = Camera3D.new()
	feed_cam.current = true
	feed_vp.add_child(feed_cam)

	overlay = OSTheme.mono_label("", 15, Color(0.85, 1.0, 0.9))
	overlay.position = Vector2(14, 10)
	holder.add_child(overlay)


func _process(_delta: float) -> void:
	var world: FacilityWorld = desktop.world if desktop else null
	if world == null or feed_cam == null or not is_visible_in_tree():
		return
	var src: Camera3D = world.cameras[cam]
	feed_cam.global_transform = src.global_transform
	feed_cam.fov = src.fov
	var names := world.camera_names()
	var t := FacilitySim.format_time(Facility.sim.time()) if Facility.running else ""
	overlay.text = "CAM %02d  %s   %s   ● REC" % [cam + 1, names[cam].to_upper(), t]
