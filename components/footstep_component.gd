class_name FootstepComponent
extends Node

@export_category("Movement Audio")
@export var walk_step_interval: float = 0.48
@export var sprint_step_interval: float = 0.34
@export var crouch_step_interval: float = 0.7
@export var footstep_slice_duration: float = 0.38

@export var footstep_players: Array[AudioStreamPlayer3D]

var _footstep_offsets: Array[float] = [
	1.6143, 6.6620, 7.7615, 9.4607, 10.0604, 11.1849, 11.7097, 12.3844,
	14.4834, 15.2081, 19.4062, 28.4271, 28.9019, 29.4766, 30.0264, 31.1509,
	32.2504, 33.3249,
]
var _footstep_stop_times: Array[float] = [0.0, 0.0]
var _footstep_time_remaining: float = 0.0
var _footstep_player_index: int = 0
var _last_footstep_offset_index: int = -1
var _was_walking_on_floor: bool = false
var _footstep_rng := RandomNumberGenerator.new()

func _ready() -> void:
	_footstep_rng.randomize()
	if _footstep_stop_times.size() != footstep_players.size():
		_footstep_stop_times.resize(footstep_players.size())
		_footstep_stop_times.fill(0.0)

func update_footsteps(delta: float, horizontal_speed: float, is_on_floor: bool, is_sprinting: bool, is_crouching: bool) -> void:
	for index: int in _footstep_stop_times.size():
		if _footstep_stop_times[index] <= 0.0:
			continue
		_footstep_stop_times[index] -= delta
		if _footstep_stop_times[index] <= 0.0:
			if index < footstep_players.size() and footstep_players[index]:
				footstep_players[index].stop()

	var walking_on_floor := is_on_floor and horizontal_speed > 0.25
	if not walking_on_floor:
		_was_walking_on_floor = false
		_footstep_time_remaining = 0.0
		return

	var interval := walk_step_interval
	if is_crouching:
		interval = crouch_step_interval
	elif is_sprinting:
		interval = sprint_step_interval

	if not _was_walking_on_floor:
		_play_wood_footstep(is_sprinting, is_crouching)
		_footstep_time_remaining = interval
	else:
		_footstep_time_remaining -= delta
		if _footstep_time_remaining <= 0.0:
			_play_wood_footstep(is_sprinting, is_crouching)
			_footstep_time_remaining += interval
	_was_walking_on_floor = true

func _play_wood_footstep(is_sprinting: bool, is_crouching: bool) -> void:
	if footstep_players.is_empty() or _footstep_offsets.is_empty():
		return
	var offset_index := _footstep_rng.randi_range(0, _footstep_offsets.size() - 1)
	if offset_index == _last_footstep_offset_index and _footstep_offsets.size() > 1:
		offset_index = (offset_index + 1) % _footstep_offsets.size()
	_last_footstep_offset_index = offset_index

	var player_index := _footstep_player_index
	_footstep_player_index = (_footstep_player_index + 1) % footstep_players.size()
	var audio_player := footstep_players[player_index]
	if not audio_player:
		return
		
	var movement_pitch := 0.93 if is_crouching else (1.035 if is_sprinting else 1.0)
	audio_player.pitch_scale = movement_pitch * _footstep_rng.randf_range(0.965, 1.035)
	audio_player.volume_db = (
		_footstep_rng.randf_range(-12.5, -10.0)
		if is_crouching
		else _footstep_rng.randf_range(-7.5, -4.5) + (1.2 if is_sprinting else 0.0)
	)
	audio_player.play(_footstep_offsets[offset_index])
	_footstep_stop_times[player_index] = footstep_slice_duration

func stop_footsteps() -> void:
	for audio_player in footstep_players:
		if audio_player:
			audio_player.stop()
	_footstep_stop_times.fill(0.0)
	_was_walking_on_floor = false
