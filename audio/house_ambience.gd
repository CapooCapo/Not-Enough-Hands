class_name HouseAmbience
extends Node

## Interior ambience director. It deliberately fades every bed back to actual
## silence instead of maintaining a permanent horror drone.

enum AmbienceState {
	SILENCE,
	FADING_IN,
	HOLDING,
	FADING_OUT,
}

const HOUSE_TONE := preload("res://assets/audio/ambient_house_tone.mp3")
const WINDOW_WIND := preload("res://assets/audio/ambient_window_wind.mp3")
const DISTANT_NIGHT := preload("res://assets/audio/ambient_distant_night.mp3")
const CREAK_SINGLE := preload("res://assets/audio/house_creak_single.mp3")
const CREAKS_SLOW := preload("res://assets/audio/house_creaks_slow.mp3")
const FLOOR_CREAKS := preload("res://assets/audio/house_floor_creaks.mp3")

const OUTSIDE_BUS := &"MuffledOutside"
const SILENT_DB := -60.0
const EXPECTED_ENTRANCE_COUNT := 7.0

@export_category("Ambient beds")
@export var initial_silence_min: float = 5.0
@export var initial_silence_max: float = 11.0
@export var silence_min: float = 7.0
@export var silence_max: float = 20.0
@export var bed_duration_min: float = 18.0
@export var bed_duration_max: float = 42.0
@export var fade_duration_min: float = 4.0
@export var fade_duration_max: float = 8.0
@export var house_tone_db: float = -32.0
@export var window_wind_db: float = -35.0
@export var distant_night_db: float = -40.0

@export_category("Old house events")
@export var event_delay_min: float = 14.0
@export var event_delay_max: float = 42.0
@export_range(0.0, 1.0, 0.01) var silence_event_skip_chance: float = 0.78
@export var event_distance_min: float = 5.0
@export var event_distance_max: float = 13.0

@onready var ambient_player: AudioStreamPlayer = $AmbientBed
@onready var event_player: AudioStreamPlayer3D = $HouseEvent

var _ambient_streams: Array[AudioStream] = [HOUSE_TONE, WINDOW_WIND, DISTANT_NIGHT]
var _event_streams: Array[AudioStream] = [CREAK_SINGLE, CREAKS_SLOW, FLOOR_CREAKS]
var _rng := RandomNumberGenerator.new()
var _state: AmbienceState = AmbienceState.SILENCE
var _state_time: float = 0.0
var _fade_duration: float = 1.0
var _ambient_target_db: float = -34.0
var _last_ambient_index: int = -1
var _last_event_index: int = -1
var _event_time: float = 0.0
var _event_stop_time: float = 0.0
var _breach_scan_time: float = 0.0
var _breached_door_count: int = 0


func _ready() -> void:
	_rng.randomize()
	_ensure_outside_bus()
	_enter_silence(true)
	_schedule_house_event()
	_scan_breached_doors()


func _process(delta: float) -> void:
	_breach_scan_time -= delta
	if _breach_scan_time <= 0.0:
		_scan_breached_doors()
		_breach_scan_time = 1.0

	_update_ambient(delta)
	_update_house_events(delta)


func get_breached_door_count() -> int:
	return _breached_door_count


func _update_ambient(delta: float) -> void:
	_state_time -= delta
	match _state:
		AmbienceState.SILENCE:
			if _state_time <= 0.0:
				_begin_ambient_bed()
		AmbienceState.FADING_IN:
			var fade_progress := 1.0 - maxf(_state_time, 0.0) / _fade_duration
			ambient_player.volume_db = lerpf(SILENT_DB, _ambient_target_db, fade_progress)
			_restart_bed_if_needed()
			if _state_time <= 0.0:
				_state = AmbienceState.HOLDING
				_state_time = _rng.randf_range(bed_duration_min, bed_duration_max)
		AmbienceState.HOLDING:
			_restart_bed_if_needed()
			if _state_time <= 0.0:
				_state = AmbienceState.FADING_OUT
				_fade_duration = _rng.randf_range(fade_duration_min, fade_duration_max)
				_state_time = _fade_duration
		AmbienceState.FADING_OUT:
			var fade_progress := maxf(_state_time, 0.0) / _fade_duration
			ambient_player.volume_db = lerpf(SILENT_DB, _ambient_target_db, fade_progress)
			if _state_time <= 0.0:
				ambient_player.stop()
				_enter_silence(false)


func _begin_ambient_bed() -> void:
	var selected_index := _choose_ambient_index()
	_last_ambient_index = selected_index
	var stream := _ambient_streams[selected_index].duplicate() as AudioStream
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	ambient_player.stream = stream
	ambient_player.bus = &"Master" if selected_index == 0 else OUTSIDE_BUS
	_ambient_target_db = _get_ambient_base_db(selected_index) + minf(_breached_door_count * 1.15, 7.0)
	ambient_player.volume_db = SILENT_DB
	ambient_player.pitch_scale = _rng.randf_range(0.97, 1.015)
	ambient_player.play()
	_state = AmbienceState.FADING_IN
	_fade_duration = _rng.randf_range(fade_duration_min, fade_duration_max)
	_state_time = _fade_duration


func _choose_ambient_index() -> int:
	# More broken entrances means exterior air leaks into the house more often.
	var breach_ratio := clampf(_breached_door_count / EXPECTED_ENTRANCE_COUNT, 0.0, 1.0)
	var house_weight := lerpf(0.62, 0.35, breach_ratio)
	var wind_weight := lerpf(0.25, 0.48, breach_ratio)
	var roll := _rng.randf()
	var selected := 0
	if roll >= house_weight + wind_weight:
		selected = 2
	elif roll >= house_weight:
		selected = 1
	if selected == _last_ambient_index and _rng.randf() < 0.65:
		selected = (selected + _rng.randi_range(1, 2)) % _ambient_streams.size()
	return selected


func _get_ambient_base_db(index: int) -> float:
	match index:
		1:
			return window_wind_db
		2:
			return distant_night_db
		_:
			return house_tone_db


func _enter_silence(is_initial: bool) -> void:
	_state = AmbienceState.SILENCE
	ambient_player.stop()
	var breach_ratio := clampf(_breached_door_count / EXPECTED_ENTRANCE_COUNT, 0.0, 1.0)
	var minimum := initial_silence_min if is_initial else silence_min
	var maximum := initial_silence_max if is_initial else silence_max
	# Even at maximum pressure there is always a real pause before the next bed.
	minimum = lerpf(minimum, 3.5, breach_ratio)
	maximum = lerpf(maximum, 10.0, breach_ratio)
	_state_time = _rng.randf_range(minimum, maximum)
	ambient_player.volume_db = SILENT_DB


func _restart_bed_if_needed() -> void:
	if ambient_player.stream and not ambient_player.playing:
		ambient_player.play()


func _update_house_events(delta: float) -> void:
	if _event_stop_time > 0.0:
		_event_stop_time -= delta
		if _event_stop_time <= 0.0:
			event_player.stop()

	_event_time -= delta
	if _event_time > 0.0:
		return
	if _state == AmbienceState.SILENCE and _rng.randf() < silence_event_skip_chance:
		_schedule_house_event()
		return
	_play_house_event()
	_schedule_house_event()


func _play_house_event() -> void:
	var selected_index := _rng.randi_range(0, _event_streams.size() - 1)
	if selected_index == _last_event_index:
		selected_index = (selected_index + 1) % _event_streams.size()
	_last_event_index = selected_index

	var player := get_tree().get_first_node_in_group("players") as Node3D
	if player:
		var angle := _rng.randf_range(0.0, TAU)
		var distance := _rng.randf_range(event_distance_min, event_distance_max)
		event_player.global_position = player.global_position + Vector3(
			cos(angle) * distance,
			_rng.randf_range(-0.8, 2.8),
			sin(angle) * distance
		)

	event_player.stream = _event_streams[selected_index]
	event_player.pitch_scale = _rng.randf_range(0.91, 1.045)
	event_player.volume_db = _rng.randf_range(-15.5, -10.5) + minf(_breached_door_count * 0.35, 2.0)
	var stream_length := event_player.stream.get_length()
	var audible_duration := minf(stream_length, _rng.randf_range(2.5, 5.8))
	var start_offset := 0.0
	if stream_length > audible_duration + 0.25:
		start_offset = _rng.randf_range(0.0, stream_length - audible_duration - 0.1)
	event_player.play(start_offset)
	_event_stop_time = audible_duration


func _schedule_house_event() -> void:
	var breach_ratio := clampf(_breached_door_count / EXPECTED_ENTRANCE_COUNT, 0.0, 1.0)
	var minimum := lerpf(event_delay_min, 7.0, breach_ratio)
	var maximum := lerpf(event_delay_max, 23.0, breach_ratio)
	_event_time = _rng.randf_range(minimum, maximum)


func _scan_breached_doors() -> void:
	var count := 0
	for door: Node in get_tree().get_nodes_in_group("defense_doors"):
		if "attack_phase" in door and int(door.get("attack_phase")) == 4:
			count += 1
	_breached_door_count = count


func _ensure_outside_bus() -> void:
	var bus_index := AudioServer.get_bus_index(OUTSIDE_BUS)
	if bus_index < 0:
		AudioServer.add_bus()
		bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, OUTSIDE_BUS)
		var low_pass := AudioEffectLowPassFilter.new()
		low_pass.cutoff_hz = 1450.0
		low_pass.resonance = 0.12
		AudioServer.add_bus_effect(bus_index, low_pass)
	AudioServer.set_bus_send(bus_index, &"Master")
