# The 3D facility: rooms, rails, robots, pods, props and security cameras.
# It shows whatever Facility session is running (robots follow their sim
# selves via RobotView, props show the plant), but never starts one: the
# scene that uses it does (the demo, the corkLabs desktop).
#
# Used by game/demo_facility.tscn (full screen, with a console), and by the
# corkLabs OS camera app (rendered into feeds through SubViewports).
class_name FacilityWorld
extends Node3D

@onready var tinker: RobotActor = $TinkerRail/Rider/Swing/Tinker
@onready var tinker_rider: RailRider = $TinkerRail/Rider
@onready var hauler: RobotActor = $HaulerRail/Rider/Swing/Hauler
@onready var hauler_rider: RailRider = $HaulerRail/Rider
@onready var cameras: Array[Camera3D] = [$Cameras/Cam1, $Cameras/Cam2, $Cameras/Cam3]

var props: FacilityProps
var views: Array[RobotView] = []


func _ready() -> void:
	for pair in [["tinker", tinker_rider, tinker], ["hauler", hauler_rider, hauler]]:
		var view := RobotView.new()
		view.setup(pair[0], pair[1], pair[2])
		add_child(view)
		views.append(view)
	props = FacilityProps.new()
	props.name = "Props"
	add_child(props)
	props.build({FacilitySetup.TINKER_RAIL: $TinkerRail, FacilitySetup.HAULER_RAIL: $HaulerRail}, $Pods)


## Display names for the security cameras, same order as `cameras`.
func camera_names() -> PackedStringArray:
	return PackedStringArray(["Floor overview", "Pod row", "Hauler bays"])
