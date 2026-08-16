class_name DoorGhostMinigame
extends CanvasLayer

signal minigame_started(door: Node)
signal attempt_failed(door: Node, repair_cap: float)
signal minigame_completed(door: Node)
signal minigame_closed()

enum Phase {
	INACTIVE,
	PLAYING,
	JUMPSCARE,
	RETRY_WAIT,
	SUCCESS,
}

@export_category("Rules")
@export var attempt_duration: float = 25.0
@export var progress_per_tick: float = 1.0
@export var progress_tick_interval: float = 0.1
@export var progress_tick_interval_mid: float = 0.085
@export var progress_tick_interval_late: float = 0.07
@export var relocate_after_progress: float = 15.0
@export var relocate_penalty: float = 3.0
@export var search_grace_duration: float = 1.0
@export var decay_tick_interval: float = 0.25
@export var decay_per_tick: float = 1.0
@export_range(0.0, 1.0, 0.01) var instant_dodge_chance_start: float = 0.18
@export_range(0.0, 1.0, 0.01) var instant_dodge_chance_end: float = 0.38
@export var instant_dodge_cooldown_after_relocate: float = 0.45

@export_category("Presentation")
@export var flashlight_radius_start: float = 125.0
@export var flashlight_radius_end: float = 90.0
@export var jumpscare_duration: float = 0.72
@export var retry_delay: float = 0.35
@export var success_duration: float = 0.62
@export var debug_show_progress: bool = false

@export_category("Development")
@export var dev_disable_other_ghost_attacks: bool = true

var active: bool = false
var phase: Phase = Phase.INACTIVE
var progress: float = 0.0
var time_remaining: float = 0.0
var current_door: Node
var owning_player: Node

var cursor_position: Vector2
var ghost_center: Vector2
var ghost_size: Vector2 = Vector2(210.0, 315.0)
var charge_since_relocation: float = 0.0
var charge_accumulator: float = 0.0
var decay_accumulator: float = 0.0
var time_since_lit: float = 0.0
var phase_timer: float = 0.0
var heartbeat_restart_timer: float = 0.0
var jitter_timer: float = 0.0
var jitter_offset: Vector2 = Vector2.ZERO
var jitter_rotation_offset: float = 0.0
var head_shake_time: float = 0.0
var face_was_lit: bool = false
var instant_dodge_cooldown: float = 0.0
var last_anchor_index: int = -1
var _rng := RandomNumberGenerator.new()
var _ghost_safety_acquired: bool = false
var _force_next_instant_dodge: bool = false

@onready var root: Control = $Root
@onready var black_background: ColorRect = $Root/BlackBackground
@onready var ghost: TextureRect = $Root/Ghost
@onready var darkness_mask: ColorRect = $Root/DarknessMask
@onready var cursor_dot: Control = $Root/CursorDot
@onready var debug_progress: ProgressBar = $Root/DebugProgress
@onready var music_audio: AudioStreamPlayer = $MusicAudio
@onready var drone_audio: AudioStreamPlayer = $DroneAudio
@onready var heartbeat_audio: AudioStreamPlayer = $HeartbeatAudio
@onready var whisper_audio: AudioStreamPlayer = $WhisperAudio
@onready var relocate_audio: AudioStreamPlayer = $RelocateAudio
@onready var bone_audio: AudioStreamPlayer = $BoneAudio
@onready var flashlight_audio: AudioStreamPlayer = $FlashlightAudio
@onready var success_audio: AudioStreamPlayer = $SuccessAudio
@onready var jumpscare_audio: AudioStreamPlayer = $JumpscareAudio


func _ready() -> void:
	_rng.randomize()
	visible = false
	debug_progress.visible = debug_show_progress
	_ensure_audio_bus()
	if music_audio.stream is AudioStreamOggVorbis:
		(music_audio.stream as AudioStreamOggVorbis).loop = true
	get_viewport().size_changed.connect(_on_viewport_size_changed)


func _exit_tree() -> void:
	if active and is_instance_valid(current_door) and current_door.has_method("cancel_exorcism"):
		current_door.call("cancel_exorcism")
	_release_ghost_safety()


func start(player: Node, door: Node) -> bool:
	if active or not is_instance_valid(door):
		return false

	active = true
	phase = Phase.PLAYING
	current_door = door
	owning_player = player
	visible = true
	root.modulate = Color.WHITE
	black_background.visible = true
	darkness_mask.visible = true
	cursor_dot.visible = true
	ghost.visible = true
	ghost.modulate = Color.WHITE
	ghost.scale = Vector2.ONE
	ghost.rotation = 0.0
	cursor_position = get_viewport().get_visible_rect().size * 0.5
	_acquire_ghost_safety()
	_begin_attempt()
	flashlight_audio.play()
	minigame_started.emit(door)
	return true


func cancel() -> void:
	if not active:
		return
	if is_instance_valid(current_door) and current_door.has_method("cancel_exorcism"):
		current_door.call("cancel_exorcism")
	_close()


func is_running() -> bool:
	return active


func get_hidden_progress() -> float:
	return progress


func get_attempt_time_remaining() -> float:
	return time_remaining


func set_random_seed(value: int) -> void:
	_rng.seed = value


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion:
		cursor_position += event.relative
		_clamp_cursor()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton or event is InputEventKey:
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not active:
		return
	if not is_instance_valid(current_door):
		_close()
		return

	_update_cursor_and_mask()
	match phase:
		Phase.PLAYING:
			_update_playing(delta)
		Phase.JUMPSCARE:
			_update_jumpscare(delta)
		Phase.RETRY_WAIT:
			_update_retry_wait(delta)
		Phase.SUCCESS:
			_update_success(delta)


func _begin_attempt() -> void:
	phase = Phase.PLAYING
	progress = 0.0
	time_remaining = attempt_duration
	charge_since_relocation = 0.0
	charge_accumulator = 0.0
	decay_accumulator = 0.0
	time_since_lit = 0.0
	heartbeat_restart_timer = 0.0
	jitter_timer = 0.0
	jitter_offset = Vector2.ZERO
	jitter_rotation_offset = 0.0
	head_shake_time = 0.0
	face_was_lit = false
	instant_dodge_cooldown = 0.0
	root.modulate = Color.WHITE
	black_background.visible = true
	darkness_mask.visible = true
	cursor_dot.visible = true
	ghost.visible = true
	ghost.modulate = Color.WHITE
	ghost.scale = Vector2.ONE
	ghost.rotation = 0.0
	_resize_ghost()
	_relocate_ghost(false)
	music_audio.pitch_scale = 0.96
	music_audio.volume_db = -20.0
	music_audio.play()
	drone_audio.pitch_scale = 0.92
	drone_audio.volume_db = -14.0
	drone_audio.play()
	heartbeat_audio.stop()
	whisper_audio.stop()
	debug_progress.value = progress


func _update_playing(delta: float) -> void:
	time_remaining -= delta
	if time_remaining <= 0.0:
		_begin_failure()
		return

	var ratio := clampf(progress / 100.0, 0.0, 1.0)
	instant_dodge_cooldown = maxf(instant_dodge_cooldown - delta, 0.0)
	_update_intensity_audio(delta, ratio)
	_update_ghost_jitter(delta, ratio)

	var face_is_lit := _flashlight_hits_face()
	if face_is_lit and not face_was_lit and _should_instant_dodge(ratio):
		_relocate_ghost(true)
		debug_progress.value = progress
		return
	face_was_lit = face_is_lit

	if face_is_lit:
		time_since_lit = 0.0
		decay_accumulator = 0.0
		charge_accumulator += delta
		var tick_interval := _current_progress_tick_interval()
		while charge_accumulator >= tick_interval and phase == Phase.PLAYING:
			charge_accumulator -= tick_interval
			progress = minf(progress + progress_per_tick, 100.0)
			charge_since_relocation += progress_per_tick
			if progress >= 100.0:
				_begin_success()
				break
			if charge_since_relocation >= relocate_after_progress:
				_relocate_ghost(true)
				break
	else:
		charge_accumulator = 0.0
		time_since_lit += delta
		if time_since_lit > search_grace_duration:
			decay_accumulator += delta
			while decay_accumulator >= decay_tick_interval:
				decay_accumulator -= decay_tick_interval
				progress = maxf(progress - decay_per_tick, 0.0)

	debug_progress.value = progress


func _update_ghost_jitter(delta: float, ratio: float) -> void:
	head_shake_time += delta
	jitter_timer -= delta
	if jitter_timer <= 0.0:
		jitter_timer = lerpf(0.09, 0.026, ratio)
		var amplitude := lerpf(3.0, 24.0, ratio)
		jitter_offset = Vector2(
			_rng.randf_range(-amplitude, amplitude),
			_rng.randf_range(-amplitude, amplitude)
		)
		jitter_rotation_offset = deg_to_rad(
			_rng.randf_range(-2.5, 2.5) * lerpf(0.35, 2.4, ratio)
		)

	ghost.position = ghost_center - ghost_size * 0.5 + jitter_offset
	ghost.pivot_offset = ghost_size * 0.5
	var shake_rate := lerpf(6.5, 17.0, ratio)
	var shake_angle := deg_to_rad(lerpf(4.5, 17.0, ratio))
	var side_to_side := sin(head_shake_time * shake_rate) * shake_angle
	var secondary_snap := sin(head_shake_time * shake_rate * 2.73) * shake_angle * 0.28
	ghost.rotation = side_to_side + secondary_snap + jitter_rotation_offset
	var pulse := 1.0 + sin(Time.get_ticks_msec() * lerpf(0.009, 0.021, ratio)) * lerpf(0.006, 0.035, ratio)
	var distortion := sin(head_shake_time * shake_rate * 0.5) * lerpf(0.01, 0.055, ratio)
	ghost.scale = Vector2(pulse * (1.0 + distortion), pulse * (1.0 - distortion * 0.55))


func _should_instant_dodge(ratio: float) -> bool:
	if instant_dodge_cooldown > 0.0:
		return false
	if _force_next_instant_dodge:
		_force_next_instant_dodge = false
		return true
	return _rng.randf() < lerpf(
		instant_dodge_chance_start,
		instant_dodge_chance_end,
		ratio
	)


func _update_intensity_audio(delta: float, ratio: float) -> void:
	music_audio.pitch_scale = lerpf(0.96, 1.06, ratio)
	music_audio.volume_db = lerpf(-20.0, -13.0, ratio)
	if not music_audio.playing:
		music_audio.play()

	drone_audio.pitch_scale = lerpf(0.92, 1.08, ratio)
	drone_audio.volume_db = lerpf(-14.0, -8.0, ratio)
	if not drone_audio.playing:
		drone_audio.play()

	heartbeat_restart_timer -= delta
	if progress >= 25.0 and heartbeat_restart_timer <= 0.0:
		heartbeat_audio.pitch_scale = lerpf(0.86, 1.42, ratio)
		heartbeat_audio.volume_db = lerpf(-15.0, -5.0, ratio)
		heartbeat_audio.play()
		heartbeat_restart_timer = lerpf(2.1, 0.72, ratio)

	if progress >= 35.0 and not whisper_audio.playing:
		whisper_audio.pitch_scale = _rng.randf_range(0.88, 1.08)
		whisper_audio.volume_db = lerpf(-25.0, -13.0, ratio)
		whisper_audio.play()
	elif whisper_audio.playing:
		whisper_audio.volume_db = lerpf(-25.0, -13.0, ratio)


func _relocate_ghost(apply_penalty: bool) -> void:
	if apply_penalty:
		progress = maxf(progress - relocate_penalty, 0.0)
		relocate_audio.pitch_scale = _rng.randf_range(0.82, 1.18)
		bone_audio.pitch_scale = _rng.randf_range(0.86, 1.14)
		relocate_audio.play()
		bone_audio.play()

	charge_since_relocation = 0.0
	charge_accumulator = 0.0
	decay_accumulator = 0.0
	time_since_lit = 0.0
	face_was_lit = false
	instant_dodge_cooldown = maxf(instant_dodge_cooldown_after_relocate, 0.0)
	var viewport_size := get_viewport().get_visible_rect().size
	var anchors: Array[Vector2] = [
		Vector2(0.15, 0.22), Vector2(0.5, 0.2), Vector2(0.85, 0.22),
		Vector2(0.15, 0.5), Vector2(0.85, 0.5),
		Vector2(0.15, 0.78), Vector2(0.5, 0.8), Vector2(0.85, 0.78),
	]
	var candidates: Array[int] = []
	var minimum_cursor_distance := minf(viewport_size.x, viewport_size.y) * 0.22
	for index: int in anchors.size():
		if index == last_anchor_index:
			continue
		if (anchors[index] * viewport_size).distance_to(cursor_position) >= minimum_cursor_distance:
			candidates.append(index)
	if candidates.is_empty():
		for index: int in anchors.size():
			if index != last_anchor_index:
				candidates.append(index)
	last_anchor_index = candidates[_rng.randi_range(0, candidates.size() - 1)]
	ghost_center = anchors[last_anchor_index] * viewport_size
	jitter_offset = Vector2.ZERO
	ghost.position = ghost_center - ghost_size * 0.5


func _flashlight_hits_face() -> bool:
	var radii := Vector2(ghost_size.x * 0.36, ghost_size.y * 0.39)
	var normalized := (cursor_position - ghost_center) / radii
	return normalized.length_squared() <= 1.0


func _current_progress_tick_interval() -> float:
	if progress >= 80.0:
		return progress_tick_interval_late
	if progress >= 50.0:
		return progress_tick_interval_mid
	return progress_tick_interval


func _begin_failure() -> void:
	phase = Phase.JUMPSCARE
	phase_timer = jumpscare_duration
	music_audio.stop()
	drone_audio.stop()
	heartbeat_audio.stop()
	whisper_audio.stop()
	darkness_mask.visible = false
	cursor_dot.visible = false
	var viewport_size := get_viewport().get_visible_rect().size
	ghost_size = Vector2(viewport_size.y * 0.67, viewport_size.y)
	ghost.size = ghost_size
	ghost_center = viewport_size * 0.5
	ghost.position = ghost_center - ghost_size * 0.5
	ghost.pivot_offset = ghost_size * 0.5
	ghost.rotation = deg_to_rad(_rng.randf_range(-4.0, 4.0))
	ghost.scale = Vector2(0.74, 0.74)
	jumpscare_audio.pitch_scale = _rng.randf_range(0.94, 1.04)
	jumpscare_audio.play()

	var cap := 0.0
	if current_door.has_method("apply_exorcism_failure"):
		cap = float(current_door.call("apply_exorcism_failure"))
	attempt_failed.emit(current_door, cap)


func _update_jumpscare(delta: float) -> void:
	phase_timer -= delta
	var completion := 1.0 - clampf(phase_timer / maxf(jumpscare_duration, 0.01), 0.0, 1.0)
	var shake := lerpf(8.0, 34.0, completion)
	ghost.position = ghost_center - ghost_size * 0.5 + Vector2(
		_rng.randf_range(-shake, shake),
		_rng.randf_range(-shake, shake)
	)
	ghost.scale = Vector2.ONE * lerpf(0.74, 1.34, ease(completion, -1.8))
	root.modulate = Color(1.0, lerpf(1.0, 0.55, completion), lerpf(1.0, 0.55, completion), 1.0)
	if phase_timer <= 0.0:
		phase = Phase.RETRY_WAIT
		phase_timer = retry_delay
		ghost.visible = false
		root.modulate = Color.WHITE


func _update_retry_wait(delta: float) -> void:
	phase_timer -= delta
	if phase_timer <= 0.0:
		_begin_attempt()


func _begin_success() -> void:
	phase = Phase.SUCCESS
	phase_timer = success_duration
	music_audio.stop()
	drone_audio.stop()
	heartbeat_audio.stop()
	whisper_audio.stop()
	relocate_audio.stop()
	darkness_mask.visible = false
	cursor_dot.visible = false
	success_audio.play()
	if current_door.has_method("complete_exorcism"):
		current_door.call("complete_exorcism")
	minigame_completed.emit(current_door)


func _update_success(delta: float) -> void:
	phase_timer -= delta
	var completion := 1.0 - clampf(phase_timer / maxf(success_duration, 0.01), 0.0, 1.0)
	ghost.rotation += delta * lerpf(2.0, 13.0, completion)
	ghost.scale = Vector2.ONE * lerpf(1.0, 0.05, ease(completion, 1.8))
	ghost.modulate.a = 1.0 - completion
	if phase_timer <= 0.0:
		_close()


func _close() -> void:
	music_audio.stop()
	drone_audio.stop()
	heartbeat_audio.stop()
	whisper_audio.stop()
	relocate_audio.stop()
	bone_audio.stop()
	active = false
	phase = Phase.INACTIVE
	visible = false
	_release_ghost_safety()
	current_door = null
	owning_player = null
	minigame_closed.emit()


func _acquire_ghost_safety() -> void:
	if _ghost_safety_acquired or not dev_disable_other_ghost_attacks:
		return
	_ghost_safety_acquired = true
	if is_instance_valid(owning_player) and owning_player.has_method("acquire_minigame_ghost_safety"):
		owning_player.call("acquire_minigame_ghost_safety")


func _release_ghost_safety() -> void:
	if not _ghost_safety_acquired:
		return
	_ghost_safety_acquired = false
	if is_instance_valid(owning_player) and owning_player.has_method("release_minigame_ghost_safety"):
		owning_player.call("release_minigame_ghost_safety")


func _update_cursor_and_mask() -> void:
	_clamp_cursor()
	cursor_dot.position = cursor_position - cursor_dot.size * 0.5
	var viewport_size := get_viewport().get_visible_rect().size
	var material := darkness_mask.material as ShaderMaterial
	if material and viewport_size.x > 0.0 and viewport_size.y > 0.0:
		var ratio := clampf(progress / 100.0, 0.0, 1.0)
		var radius_pixels := lerpf(flashlight_radius_start, flashlight_radius_end, ratio)
		material.set_shader_parameter("light_position", cursor_position / viewport_size)
		material.set_shader_parameter("light_radius", radius_pixels / viewport_size.y)
		material.set_shader_parameter("viewport_aspect", viewport_size.x / viewport_size.y)
		material.set_shader_parameter("agitation", ratio)


func _resize_ghost() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var height := clampf(viewport_size.y * 0.43, 250.0, 430.0)
	ghost_size = Vector2(height * 0.8, height)
	ghost.size = ghost_size
	ghost.pivot_offset = ghost_size * 0.5


func _clamp_cursor() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	cursor_position.x = clampf(cursor_position.x, 4.0, maxf(viewport_size.x - 4.0, 4.0))
	cursor_position.y = clampf(cursor_position.y, 4.0, maxf(viewport_size.y - 4.0, 4.0))


func _on_viewport_size_changed() -> void:
	if not active:
		return
	_clamp_cursor()
	if phase == Phase.PLAYING:
		_resize_ghost()
		_relocate_ghost(false)


func _ensure_audio_bus() -> void:
	var bus_index := AudioServer.get_bus_index("DoorMinigame")
	if bus_index < 0:
		AudioServer.add_bus()
		bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, "DoorMinigame")
		AudioServer.set_bus_send(bus_index, "Master")
		var compressor := AudioEffectCompressor.new()
		compressor.threshold = -13.0
		compressor.ratio = 4.0
		AudioServer.add_bus_effect(bus_index, compressor)
		var limiter := AudioEffectLimiter.new()
		limiter.ceiling_db = -1.0
		AudioServer.add_bus_effect(bus_index, limiter)
	for audio_node: AudioStreamPlayer in [
		music_audio, drone_audio, heartbeat_audio, whisper_audio, relocate_audio, bone_audio,
		flashlight_audio, success_audio, jumpscare_audio,
	]:
		audio_node.bus = "DoorMinigame"


## Test hooks keep timing tests deterministic without exposing the hidden meter
## in the release UI.
func debug_place_flashlight_on_face() -> void:
	cursor_position = ghost_center


func debug_place_flashlight_away() -> void:
	cursor_position = Vector2(4.0, 4.0)


func debug_step_gameplay(delta: float) -> void:
	if active and phase == Phase.PLAYING:
		_update_playing(delta)


func debug_force_next_instant_dodge() -> void:
	_force_next_instant_dodge = true
	instant_dodge_cooldown = 0.0
