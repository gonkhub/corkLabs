# A fixed security camera. Aims at a point, or slowly tracks a node like a
# motorised CCTV head.
extends Camera3D

## Point to aim at (world space), used when there's no target.
@export var look_point := Vector3.ZERO
## Optional node to track.
@export var target: Node3D
## How quickly it pans to follow the target (per second).
@export var pan_speed := 1.5


func _ready() -> void:
	look_at(target.global_position if target else look_point, Vector3.UP)


func _process(delta: float) -> void:
	if target == null:
		return
	var want := global_transform.looking_at(target.global_position + Vector3(0, -0.6, 0), Vector3.UP)
	global_transform.basis = global_transform.basis.slerp(want.basis, clampf(pan_speed * delta, 0.0, 1.0)).orthonormalized()
