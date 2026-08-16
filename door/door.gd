extends Node3D

enum DoorState { CLOSED, OPENING, OPEN, CLOSING }
var state: DoorState = DoorState.CLOSED

@export var interaction_range: float = 3.0
@export var open_angle: float = 90.0 # Degrees
@export var open_duration: float = 0.5
@export var close_duration: float = 0.5
@export var hinge_direction: int = 1

@onready var hinge: AnimatableBody3D = $Hinge
var tween: Tween

func interact(player: Node3D = null) -> void:
	if state == DoorState.OPENING or state == DoorState.CLOSING:
		return
		
	if state == DoorState.CLOSED:
		state = DoorState.OPENING
		
		# Determine player side relative to door's local Z-axis (FORWARD)
		var local_player_pos := Vector3(0.0, 0.0, 1.0)
		if player:
			local_player_pos = to_local(player.global_position)
		# local_player_pos.z > 0 means the player is in front of the door's original Z axis.
		var dot := local_player_pos.z
		
		# If dot < 0 (player is behind), open towards +Z (target_sign = -1)
		# If dot > 0 (player is in front), open towards -Z (target_sign = 1)
		var target_sign = -1 if dot < 0 else 1
		var target_rot_y = deg_to_rad(open_angle) * target_sign * hinge_direction
		
		if tween and tween.is_running():
			tween.kill()
		tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tween.tween_property(hinge, "rotation:y", target_rot_y, open_duration)
		tween.tween_callback(func(): state = DoorState.OPEN)
		
	elif state == DoorState.OPEN:
		state = DoorState.CLOSING
		if tween and tween.is_running():
			tween.kill()
		tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tween.tween_property(hinge, "rotation:y", 0.0, close_duration)
		tween.tween_callback(func(): state = DoorState.CLOSED)
