# One live security-camera feed: its own SubViewport looking into the
# desktop's hidden facility world, through a camera that copies one of the
# SecurityCameras every frame, with the CCTV look and an on-screen caption.
#
# Interactive feeds drive the camera's pan/tilt/zoom head:
#   drag            pan / tilt
#   scroll wheel    zoom
#   double-click    back to the home view
# All free: pointing a camera is only looking.
#
# They also let you point at things. Hovering a robot or a device outlines
# it (FacilityWorld.pick / highlight) and shows what it is; a left CLICK
# (no drag) emits object_clicked, and the Cameras app opens that thing's
# menu at the cursor (ObjectMenu). A dead feed (NO SIGNAL) clicks as its own
# camera, so you can still send someone to fix it.
#
# Robots' speech (SpeechDirector) floats over them as coloured text in any
# feed whose camera is in the same room and can see them.
#
# Sound: the feed you're `listening` to is the facility's 3D audio listener
# (its camera is the microphone), so FacilitySounds are panned and attenuated
# from that camera's point of view. The Cameras app picks which feed listens.
#
# Night vision: the facility has no lights, so every camera also has an
# infrared mode. The feed's camera swaps to an Environment that floods the
# scene with flat "IR" light, fading into black fog with distance (the
# illuminator's reach), and the shader turns it green and grainy. Machine
# lights and robot LEDs bloom out. Like panning, it's only looking.
#
# Frame rate: feeds are locked to FEED_FPS, whatever the desktop runs at.
# The viewport renders once per tick and holds the picture in between; the
# shader's grain and rolling band step on the same clock.
class_name CCTVFeed
extends Control

signal clicked(feed: CCTVFeed)
## The mouse went onto / off this feed (the grid listens to the one you point at).
signal hovered(feed: CCTVFeed, on: bool)
## A left click on something in the picture (id from FacilityWorld.pick; "" = nothing).
signal object_clicked(feed: CCTVFeed, id: String, at: Vector2)

## A press that moves less than this (pixels) is a click, not a drag.
const CLICK_SLOP := 5.0

const FEED_SHADER := preload("res://os/cctv_feed.gdshader")
## Locked feed frame rate.
const FEED_FPS := 30.0

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
## Speech: one label per robot, reused.
var speech: SpeechDirector
var _speech_labels := {}
var _speech_layer: Control
## Text size for speech (grid feeds use smaller text).
var speech_font_size := 16
var night_vision := false
## This feed is the audio listener (see the header).
var listening := false
var _material: ShaderMaterial
var _dragging := false
var _press_at := Vector2.ZERO
var _moved := false
## What the mouse is over right now ("" = nothing), and its label.
var hover_id := ""
var hover_label: Label
## The hover card (a richer read-out than the label: ObjectMenu.info).
var hover_card: PanelContainer
## Gives the hover label its text (set by the Cameras app: ObjectMenu.describe).
var describe: Callable
## Gives the hover card its contents (ObjectMenu.info), if set.
var info: Callable
var no_signal: Label
var _frame_clock := 0.0     # time since the last rendered frame
var _feed_time := 0.0       # the feed's own clock, in whole frames
static var _ir_env: Environment


func setup(facility_world: FacilityWorld, world_viewport: SubViewport, cam_index: int, is_interactive: bool) -> void:
	world = facility_world
	cam = cam_index
	interactive = is_interactive
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_MOVE if interactive else Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func(): hovered.emit(self, true))
	mouse_exited.connect(func(): hovered.emit(self, false))

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
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE   # then once per feed frame, from _process
	viewport.handle_input_locally = false
	viewport.gui_disable_input = true
	if world_viewport:
		viewport.world_3d = world_viewport.find_world_3d()
	screen.add_child(viewport)
	eye = Camera3D.new()
	eye.current = true
	if world:
		eye.cull_mask = world.feed_cull_mask(cam)
	viewport.add_child(eye)

	caption = OSTheme.mono_label("", 14, Color(0.85, 1.0, 0.9))
	caption.position = Vector2(12, 8)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)
	_speech_layer = Control.new()
	_speech_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_speech_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_speech_layer)
	speech_font_size = 16 if interactive else 12

	ptz_label = OSTheme.mono_label("", 12, Color(0.85, 1.0, 0.9, 0.8))
	ptz_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ptz_label.position = Vector2(12, -24)
	ptz_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ptz_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ptz_label)
	no_signal = OSTheme.mono_label("NO SIGNAL", 28 if interactive else 16, Color(0.9, 0.95, 0.92, 0.85))
	no_signal.set_anchors_preset(Control.PRESET_FULL_RECT)
	no_signal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	no_signal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	no_signal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	no_signal.visible = false
	add_child(no_signal)
	hover_label = OSTheme.label("", 13, Color(1.0, 0.85, 0.45))
	hover_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	hover_label.add_theme_constant_override("outline_size", 6)
	hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_label.visible = false
	add_child(hover_label)
	hover_card = PanelContainer.new()
	hover_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_card.add_theme_stylebox_override("panel", OSTheme.box(Color(0.04, 0.07, 0.08, 0.92), Color(1.0, 0.8, 0.3, 0.6), 4, 10, 8))
	hover_card.visible = false
	add_child(hover_card)
	mouse_exited.connect(func(): _set_hover(""))


## Is this camera broken (a "camera" fault in the plant)?
func signal_lost() -> bool:
	if not Facility.running:
		return false
	var plant := Facility.sim.get_system("plant") as FacilityPlant
	return plant != null and bool(plant.device("cam_%d" % (cam + 1)).get("fault", false))


## The CCTV artefacts (scanlines, grain, wash); night vision keeps its own look without them.
func set_filter(on: bool) -> void:
	_material.set_shader_parameter("cctv", 1.0 if on else 0.0)


func set_night_vision(on: bool) -> void:
	night_vision = on
	_material.set_shader_parameter("night_vision", on)
	eye.environment = ir_environment() if on else null


## What a camera sees by its own infrared light: everything lit evenly
## (no shadows, no colour), dark beyond the illuminator's reach.
static func ir_environment() -> Environment:
	if _ir_env == null:
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color.BLACK
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.8, 0.8, 0.8)
		e.ambient_light_energy = 1.0
		e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		e.fog_enabled = true
		e.fog_light_color = Color.BLACK
		e.fog_density = 0.03
		e.fog_sky_affect = 0.0
		e.glow_enabled = true
		e.glow_intensity = 1.2
		e.glow_bloom = 0.15
		e.glow_hdr_threshold = 0.8
		_ir_env = e
	return _ir_env


func camera() -> SecurityCamera:
	return world.cameras[cam] if world and cam < world.cameras.size() else null


func _process(delta: float) -> void:
	var src := camera()
	viewport.audio_listener_enable_3d = listening and src != null and is_visible_in_tree()
	if src == null or not is_visible_in_tree():
		return
	_frame_clock += delta
	if _frame_clock < 1.0 / FEED_FPS:
		return
	_frame_clock = fmod(_frame_clock, 1.0 / FEED_FPS)
	_feed_time += 1.0 / FEED_FPS
	var lost := signal_lost()
	no_signal.visible = lost
	screen.visible = not lost
	_speech_layer.visible = not lost
	if lost:
		caption.text = "CAM %02d  %s\n%s  NO SIGNAL" % [cam + 1, src.display_name.to_upper(),
			FacilitySim.format_time(Facility.sim.time()) if Facility.running else ""]
		return
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_material.set_shader_parameter("feed_time", _feed_time)
	eye.global_transform = src.global_transform
	eye.fov = src.fov
	var clock := FacilitySim.format_time(Facility.sim.time()) if Facility.running else ""
	caption.text = "CAM %02d  %s\n%s  ● REC%s%s" % [cam + 1, src.display_name.to_upper(), clock, "   IR" if night_vision else "", _asking_text()]
	ptz_label.position.y = size.y - 24
	var ptz := "AUTO-TRACK" if src.auto_track else "PAN %+4d°  TILT %+3d°" % [roundi(src.pan), roundi(src.tilt)]
	var audio := ""
	if listening:
		audio = "   AUDIO MUTED" if FeedAudio.is_muted() else "   AUDIO"
	ptz_label.text = "%s   ZOOM %.1fx%s" % [ptz, src.zoom_level(), audio]
	_draw_speech()


# "  ! TINKER ASKING" when a unit in this camera's room has a request.
func _asking_text() -> String:
	var reqs := Facility.sim.get_system("requests") as UnitRequests if Facility.running else null
	if reqs == null or world == null or cam >= world.camera_rooms.size():
		return ""
	var names := PackedStringArray()
	for q in reqs.requests:
		if world.robot_room(str(q.robot)) == world.camera_rooms[cam] and not names.has(str(q.robot).to_upper()):
			names.append(str(q.robot).to_upper())
	return "" if names.is_empty() else "   ! %s ASKING" % ", ".join(names)


# Floating words over each speaking robot this camera can see.
func _draw_speech() -> void:
	var shown := {}
	if speech and world:
		var cam_room: String = world.camera_rooms[cam] if cam < world.camera_rooms.size() else ""
		for b in speech.bubbles():
			var id: String = b.robot
			if world.robot_room(id) != cam_room:
				continue
			var at := world.speech_anchor(id)
			if eye.is_position_behind(at):
				continue
			var p := eye.unproject_position(at)
			if p.x < -50 or p.y < -50 or p.x > size.x + 50 or p.y > size.y + 50:
				continue
			speech.mark_seen(id)
			var l := _speech_label(id)
			l.text = b.text
			l.add_theme_color_override("font_color", b.color)
			l.modulate.a = (b.color as Color).a
			l.size = Vector2(l.custom_minimum_size.x, 0)   # fixed width, height fits the text
			l.position = Vector2(clampf(p.x - l.size.x * 0.5, 4.0, maxf(size.x - l.size.x - 4.0, 4.0)),
				clampf(p.y - l.size.y - 6.0, 4.0, maxf(size.y - l.size.y - 4.0, 4.0)))
			l.visible = true
			shown[id] = true
	for id in _speech_labels:
		if not shown.has(id):
			_speech_labels[id].visible = false


func _speech_label(id: String) -> Label:
	if not _speech_labels.has(id):
		var l := Label.new()
		l.add_theme_font_size_override("font_size", speech_font_size)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", 6)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 300 if interactive else 200
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_speech_layer.add_child(l)
		_speech_labels[id] = l
	return _speech_labels[id]


# --- Pointing at things ----------------------------------------------------------------

## What's under a point of this feed ("" = nothing; a dead feed is its own camera).
func pick_at(pos: Vector2) -> String:
	if signal_lost():
		return "cam_%d" % (cam + 1)
	if world == null or not Facility.running:
		return ""
	var room: String = world.camera_rooms[cam] if cam < world.camera_rooms.size() else ""
	return world.pick(eye, pos * _pixel_scale(), room)


# Feed pixels per control pixel (the viewport can be a different size).
func _pixel_scale() -> Vector2:
	var vs := Vector2(viewport.size)
	return Vector2(vs.x / maxf(size.x, 1.0), vs.y / maxf(size.y, 1.0)) if vs.x > 0.0 else Vector2.ONE


func _set_hover(id: String, at := Vector2.ZERO) -> void:
	if id != hover_id and world:
		world.highlight(id)
	hover_id = id
	var card := info.is_valid() and not id.is_empty()
	hover_label.visible = not id.is_empty() and not card
	hover_card.visible = card
	if id.is_empty():
		mouse_default_cursor_shape = Control.CURSOR_MOVE if interactive else Control.CURSOR_POINTING_HAND
		return
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hover_label.text = describe.call(id) if describe.is_valid() else id
	var shown: Control = hover_label
	if card:
		_fill_card(info.call(id))
		shown = hover_card
	shown.reset_size()
	shown.position = Vector2(clampf(at.x + 18.0, 4.0, maxf(size.x - shown.size.x - 4.0, 4.0)),
		clampf(at.y + 16.0, 4.0, maxf(size.y - shown.size.y - 4.0, 4.0)))


# The hover card: title, status chips, lines, bars.
func _fill_card(d: Dictionary) -> void:
	for c in hover_card.get_children():
		hover_card.remove_child(c)
		c.queue_free()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_card.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	col.add_child(head)
	head.add_child(OSTheme.label(str(d.get("title", "")), 15, d.get("color", OSTheme.ACCENT)))
	for chip in d.get("chips", []):
		var tag := OSTheme.label(" %s " % chip[0], 10, Color.BLACK)
		var bg := StyleBoxFlat.new()
		bg.bg_color = chip[1]
		bg.set_corner_radius_all(3)
		tag.add_theme_stylebox_override("normal", bg)
		head.add_child(tag)
	for line in d.get("lines", []):
		var l := OSTheme.label(str(line), 12, OSTheme.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 240
		col.add_child(l)
	if not (d.get("bars", []) as Array).is_empty():
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 6)
		col.add_child(grid)
		for b in d.bars:
			grid.add_child(OSTheme.label(str(b[0]), 11, OSTheme.TEXT_DIM))
			var bar := ProgressBar.new()
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(130, 8)
			bar.max_value = 1.0
			bar.value = clampf(float(b[1]), 0.0, 1.0)
			var fill := StyleBoxFlat.new()
			fill.bg_color = b[2]
			bar.add_theme_stylebox_override("fill", fill)
			var back := StyleBoxFlat.new()
			back.bg_color = Color(1, 1, 1, 0.08)
			bar.add_theme_stylebox_override("background", back)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			grid.add_child(bar)
			grid.add_child(OSTheme.mono_label("%3d%%" % roundi(float(b[1]) * 100.0), 11, OSTheme.TEXT_DIM))


func _gui_input(event: InputEvent) -> void:
	var src := camera()
	if src == null:
		return
	if event is InputEventMouseButton:
		if not interactive:
			if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				clicked.emit(self)
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press_at = event.position
				_moved = false
			elif not _moved:
				var id := pick_at(event.position)
				object_clicked.emit(self, id, event.position)
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
		if not _moved and (event.position - _press_at).length() < CLICK_SLOP:
			return   # not a drag yet: maybe a click
		_moved = true
		_set_hover("")
		# Drag the picture: degrees per pixel follow the zoom, so it feels the same zoomed in.
		var deg_per_px := src.fov / maxf(size.y, 1.0)
		src.nudge(event.relative.x * deg_per_px, event.relative.y * deg_per_px)
		accept_event()
	elif event is InputEventMouseMotion and interactive:
		_set_hover(pick_at(event.position), event.position)
