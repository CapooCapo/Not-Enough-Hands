extends Node3D

enum DoorState { CLOSED, OPENING, OPEN, CLOSING }
var state: DoorState = DoorState.CLOSED

@export var open_angle: float = 90.0 # Degrees
@export var open_duration: float = 0.5
@export var close_duration: float = 0.5
@export var hinge_direction: int = 1

## Loudness of working a door, on the crawler's 0-1 hearing scale. Well above a
## sprint: shutting a door behind you buys cover from the thing that hunts by
## sight and hands your position to the thing that hunts by sound.
@export_range(0.0, 1.0) var noise_loudness: float = 0.7

@onready var hinge: AnimatableBody3D = $Hinge
@onready var interactable: Interactable3D = $Hinge/Interactable3D
var tween: Tween


func _ready() -> void:
	interactable.interacted.connect(_on_interact)
	interactable.set_prompt("Mở cửa")


func _on_interact(player: Node3D) -> void:
	if state == DoorState.OPENING or state == DoorState.CLOSING:
		return

	_report_noise()

	if state == DoorState.CLOSED:
		_open_door(player)
	elif state == DoorState.OPEN:
		_close_door()


func _open_door(player: Node3D) -> void:
	state = DoorState.OPENING
	interactable.lock_interaction()
	interactable.set_prompt("Đang mở...")

	var target_rot_y := _calculate_open_rotation(player)
	_start_tween("rotation:y", target_rot_y, open_duration, func():
		state = DoorState.OPEN
		interactable.unlock_interaction()
		interactable.set_prompt("Đóng cửa")
	)


func _close_door() -> void:
	state = DoorState.CLOSING
	interactable.lock_interaction()
	interactable.set_prompt("Đang đóng...")

	_start_tween("rotation:y", 0.0, close_duration, func():
		state = DoorState.CLOSED
		interactable.unlock_interaction()
		interactable.set_prompt("Mở cửa")
	)


## Determines the hinge rotation so the door swings away from the player.
func _calculate_open_rotation(player: Node3D) -> float:
	var local_player_pos := Vector3(0.0, 0.0, 1.0)
	if player:
		local_player_pos = to_local(player.global_position)
	# Positive Z = player is in front → open towards -Z (sign = 1)
	# Negative Z = player is behind → open towards +Z (sign = -1)
	var target_sign := -1 if local_player_pos.z < 0 else 1
	return deg_to_rad(open_angle) * target_sign * hinge_direction


func _start_tween(property: String, target_value: float, duration: float, on_complete: Callable) -> void:
	if tween and tween.is_running():
		tween.kill()
	tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(hinge, property, target_value, duration)
	tween.tween_callback(on_complete)


func _report_noise() -> void:
	get_tree().call_group(
		'crawler_ghosts',
		'report_noise',
		global_position,
		noise_loudness,
		self
	)
