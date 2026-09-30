# Keeps Ogre's light cone in step with its eye spotlight: the cone brightens
# and dims with the light's energy (which the rig drives, and the baker
# records), so blinks, the lid and B/Y flashes all show in the beam.
# It also scales the light's reach with the robot's size.
extends MeshInstance3D

## The eye's spotlight.
@export var light_path := NodePath("../Glow")
## Light energy at which the cone is at full strength.
@export var full_energy := 8.0

var _light: SpotLight3D
var _range := 0.0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		# No renderer (tests, baking): nothing to show, and the headless
		# renderer complains about the beam's shader every frame.
		set_process(false)
		material_override = null
		return
	_light = get_node_or_null(light_path) as SpotLight3D
	if _light:
		_range = _light.spot_range


func _process(_delta: float) -> void:
	if _light:
		# Lights ignore node scale (Godot keeps them at scale 1), so stretch the
		# range by the cone's own scale: a robot drawn 8x big still lights the
		# floor its beam lands on.
		_light.spot_range = _range * global_transform.basis.get_scale().x
		set_instance_shader_parameter(&"strength", clampf(_light.light_energy / full_energy, 0.0, 2.5))
