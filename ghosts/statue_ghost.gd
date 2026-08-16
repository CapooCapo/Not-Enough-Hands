extends CharacterBody3D

enum StatueState { DORMANT, FROZEN, STALKING, ATTACK_WINDUP, COOLDOWN }

signal observation_changed(is_observed: bool)
signal attack_started(target: Node3D)
signal attack_cancelled()

@export_category('Behavior')
@export var active: bool = true
@export var base_speed: float = 5.0
@export var maximum_speed: float = 7.2
@export var speed_per_breached_door: float = 0.32
@export_range(0, 7) var breached_door_count: int = 0
@export_range(0.0, 1.0) var night_aggression: float = 0.2
@export var acceleration: float = 22.0
@export var turn_speed: float = 9.0
@export var unseen_grace_time: float = 0.32
## Shorter grace period used when the statue lost sight of its target
## because that player's eyes involuntarily closed (blink), not because
## they looked away. Without this, unseen_grace_time (0.32s) outlasts the
## default forced_blink_duration (0.22s) and every automatic blink is a
## free no-op. Looking away still uses the full unseen_grace_time.
@export var blink_unseen_grace_time: float = 0.05

@export_category('Observation')
@export var observation_half_angle: float = 38.0
@export var observation_point_height: float = 1.55
@export var maximum_observation_distance: float = 32.0
@export_flags_3d_physics var sight_blocking_mask: int = 1

@export_category('Attack')
@export var attack_range: float = 1.15
@export var attack_windup: float = 0.48
@export var attack_cooldown: float = 1.4

@export_category('Movement Feel')
@export var movement_animation_speed: float = 13.0
@export var stuck_time_before_steering: float = 0.42
@export var steering_duration: float = 0.9
## How much the gait is quantised into stop-motion steps. 0 is a smooth walk.
@export_range(0.0, 1.0) var stop_motion_amount: float = 0.45

@export_category('Dread')
## Distance at which the statue starts visibly waking up: cracks glow, eyes burn.
@export var dread_radius: float = 10.0
## Re-pose the statue every time it is caught after moving unseen.
@export var pose_snap_on_freeze: bool = true
## Also snap to face the player when caught, so it is always staring at you.
@export var face_player_on_freeze: bool = true
@export var eye_calm_color: Color = Color(0.12, 0.17, 0.18)
@export var eye_hunt_color: Color = Color(0.95, 0.15, 0.05)

var state: StatueState = StatueState.DORMANT
var is_observed: bool = false
var current_target: CharacterBody3D
var unseen_time: float = 0.0
var attack_timer: float = 0.0
var cooldown_timer: float = 0.0
var target_refresh_timer: float = 0.0
var movement_phase: float = 0.0
var stuck_timer: float = 0.0
var steering_timer: float = 0.0
var steering_sign: float = 1.0
var last_position: Vector3
var gravity: float = ProjectSettings.get_setting('physics/3d/default_gravity')

var agitation: float = 0.0
var jaw_open: float = 0.0
var pose_index: int = -1
var presentation_time: float = 0.0
var stone_material: ShaderMaterial
var eye_material: StandardMaterial3D

@onready var visual_root: Node3D = $VisualRoot
@onready var torso_pivot: Node3D = $VisualRoot/TorsoPivot
@onready var head_pivot: Node3D = $VisualRoot/TorsoPivot/HeadPivot
@onready var jaw_pivot: Node3D = $VisualRoot/TorsoPivot/HeadPivot/JawPivot
@onready var eye_light: OmniLight3D = $VisualRoot/TorsoPivot/HeadPivot/EyeLight
@onready var eye_glow_left: MeshInstance3D = $VisualRoot/TorsoPivot/HeadPivot/EyeGlowLeft
@onready var skull: MeshInstance3D = $VisualRoot/TorsoPivot/HeadPivot/Skull
@onready var left_arm_pivot: Node3D = $VisualRoot/TorsoPivot/LeftArmPivot
@onready var left_forearm_pivot: Node3D = $VisualRoot/TorsoPivot/LeftArmPivot/ForearmPivot
@onready var right_arm_pivot: Node3D = $VisualRoot/TorsoPivot/RightArmPivot
@onready var right_forearm_pivot: Node3D = $VisualRoot/TorsoPivot/RightArmPivot/ForearmPivot
@onready var left_leg_pivot: Node3D = $VisualRoot/LeftLegPivot
@onready var left_shin_pivot: Node3D = $VisualRoot/LeftLegPivot/ShinPivot
@onready var right_leg_pivot: Node3D = $VisualRoot/RightLegPivot
@onready var right_shin_pivot: Node3D = $VisualRoot/RightLegPivot/ShinPivot
@onready var dust: GPUParticles3D = $VisualRoot/Dust

# Frozen silhouettes, in degrees. The statue snaps between these the instant it
# is caught, so it is never in the same shape twice when you look back at it.
const IDLE_POSES: Array[Dictionary] = [
	{ # Vigil - dead straight, arms at its sides, staring right through you.
		'torso': Vector3(-8.0, 0.0, 1.0),
		'head': Vector3(2.0, 0.0, -2.0),
		'jaw': 0.24,
		'left_arm': Vector3(-3.0, 0.0, -4.0), 'left_forearm': Vector3(6.0, 0.0, 0.0),
		'right_arm': Vector3(-5.0, 0.0, 5.0), 'right_forearm': Vector3(9.0, 0.0, 0.0),
		'left_leg': Vector3(1.0, 0.0, 0.0), 'left_shin': Vector3(-3.0, 0.0, 0.0),
		'right_leg': Vector3(-2.0, 0.0, 0.0), 'right_shin': Vector3(-2.0, 0.0, 0.0),
	},
	{ # Mourning - folded over, head bowed under its own weight.
		'torso': Vector3(-27.0, 3.0, -2.0),
		'head': Vector3(-33.0, -6.0, 5.0),
		'jaw': 0.1,
		'left_arm': Vector3(-24.0, 0.0, -8.0), 'left_forearm': Vector3(16.0, 0.0, 0.0),
		'right_arm': Vector3(-28.0, 0.0, 9.0), 'right_forearm': Vector3(11.0, 0.0, 0.0),
		'left_leg': Vector3(4.0, 0.0, 0.0), 'left_shin': Vector3(-9.0, 0.0, 0.0),
		'right_leg': Vector3(-3.0, 0.0, 0.0), 'right_shin': Vector3(-4.0, 0.0, 0.0),
	},
	{ # Reaching - one hand already out for your throat, caught mid-step.
		'torso': Vector3(-19.0, -10.0, 3.0),
		'head': Vector3(6.0, 12.0, -9.0),
		'jaw': 0.34,
		'left_arm': Vector3(-36.0, 0.0, -12.0), 'left_forearm': Vector3(28.0, 0.0, 0.0),
		'right_arm': Vector3(84.0, 14.0, 16.0), 'right_forearm': Vector3(10.0, 0.0, -6.0),
		'left_leg': Vector3(-11.0, 0.0, 0.0), 'left_shin': Vector3(-6.0, 0.0, 0.0),
		'right_leg': Vector3(13.0, 0.0, 0.0), 'right_shin': Vector3(-17.0, 0.0, 0.0),
	},
	{ # Listening - head cocked at an angle no neck should manage.
		'torso': Vector3(-12.0, 8.0, -4.0),
		'head': Vector3(-4.0, -21.0, 35.0),
		'jaw': 0.18,
		'left_arm': Vector3(46.0, -8.0, -22.0), 'left_forearm': Vector3(94.0, 0.0, 12.0),
		'right_arm': Vector3(-15.0, 0.0, 6.0), 'right_forearm': Vector3(8.0, 0.0, 0.0),
		'left_leg': Vector3(2.0, 0.0, 0.0), 'left_shin': Vector3(-5.0, 0.0, 0.0),
		'right_leg': Vector3(-6.0, 0.0, 0.0), 'right_shin': Vector3(-3.0, 0.0, 0.0),
	},
	{ # Silent scream - arched back, jaw torn open, arms flung behind it.
		'torso': Vector3(-31.0, 0.0, 0.0),
		'head': Vector3(27.0, 0.0, 2.0),
		'jaw': 1.0,
		'left_arm': Vector3(-48.0, -10.0, -16.0), 'left_forearm': Vector3(42.0, 0.0, 0.0),
		'right_arm': Vector3(-52.0, 10.0, 17.0), 'right_forearm': Vector3(38.0, 0.0, 0.0),
		'left_leg': Vector3(7.0, 0.0, 0.0), 'left_shin': Vector3(-15.0, 0.0, 0.0),
		'right_leg': Vector3(-8.0, 0.0, 0.0), 'right_shin': Vector3(-6.0, 0.0, 0.0),
	},
]


func _ready() -> void:
	last_position = global_position
	_prepare_materials()
	_apply_idle_pose(randi() % IDLE_POSES.size())
	state = StatueState.FROZEN if active else StatueState.DORMANT


func _physics_process(delta: float) -> void:
	if not active:
		state = StatueState.DORMANT
		velocity = Vector3.ZERO
		return

	target_refresh_timer -= delta
	if target_refresh_timer <= 0.0 or not is_instance_valid(current_target):
		current_target = _find_closest_living_player()
		target_refresh_timer = 0.2

	var observed_now := _is_observed_by_any_player()
	if observed_now != is_observed:
		is_observed = observed_now
		if is_observed:
			_on_caught_in_the_open()
		observation_changed.emit(is_observed)

	if is_observed:
		_freeze_statue(delta)
	else:
		_update_unseen_behavior(delta)

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.15

	move_and_slide()
	_update_stuck_state(delta)
	_update_player_threat()
	_update_presentation(delta)


func _freeze_statue(delta: float) -> void:
	if state == StatueState.ATTACK_WINDUP:
		attack_cancelled.emit()
	state = StatueState.FROZEN
	unseen_time = 0.0
	attack_timer = 0.0
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta * 2.0)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta * 2.0)


func _update_unseen_behavior(delta: float) -> void:
	unseen_time += delta

	if state == StatueState.COOLDOWN:
		cooldown_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		_animate_motion(delta, 0.22)
		if cooldown_timer <= 0.0:
			state = StatueState.STALKING
		return

	if state == StatueState.ATTACK_WINDUP:
		_update_attack_windup(delta)
		return

	var effective_grace_time := unseen_grace_time
	if is_instance_valid(current_target) and 'eyes_closed' in current_target and current_target.eyes_closed:
		effective_grace_time = minf(unseen_grace_time, blink_unseen_grace_time)

	if unseen_time < effective_grace_time or not is_instance_valid(current_target):
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		return

	var target_offset := current_target.global_position - global_position
	target_offset.y = 0.0
	if target_offset.length() <= attack_range:
		_begin_attack()
		return

	state = StatueState.STALKING
	_stalk_target(delta, target_offset)


func _stalk_target(delta: float, target_offset: Vector3) -> void:
	var direction := target_offset.normalized()
	if steering_timer > 0.0:
		steering_timer -= delta
		var sideways := Vector3(-direction.z, 0.0, direction.x) * steering_sign
		direction = (direction + sideways * 0.82).normalized()

	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(turn_speed * delta, 1.0))

	var speed := base_speed + speed_per_breached_door * breached_door_count
	speed += lerpf(0.0, 1.5, night_aggression)
	speed = minf(speed, maximum_speed)
	var burst := lerpf(0.82, 1.18, sin(movement_phase * 0.63) * 0.5 + 0.5)
	var desired_velocity := direction * speed * burst
	velocity.x = move_toward(velocity.x, desired_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired_velocity.z, acceleration * delta)
	_animate_motion(delta, speed / maxf(base_speed, 0.1))


func _begin_attack() -> void:
	state = StatueState.ATTACK_WINDUP
	attack_timer = attack_windup
	velocity.x = 0.0
	velocity.z = 0.0
	attack_started.emit(current_target)


func _update_attack_windup(delta: float) -> void:
	attack_timer -= delta
	var progress := 1.0 - clampf(attack_timer / maxf(attack_windup, 0.01), 0.0, 1.0)
	_apply_attack_pose(progress)
	velocity.x = 0.0
	velocity.z = 0.0

	if attack_timer > 0.0:
		return

	if is_instance_valid(current_target) and current_target.has_method('kill_by_ghost'):
		current_target.kill_by_ghost(self)

	state = StatueState.COOLDOWN
	cooldown_timer = attack_cooldown


func _find_closest_living_player() -> CharacterBody3D:
	var closest_player: CharacterBody3D
	var closest_distance := INF
	for node: Node in get_tree().get_nodes_in_group('players'):
		var player := node as CharacterBody3D
		if not player:
			continue
		if 'is_alive' in player and not player.is_alive:
			continue
		var distance := global_position.distance_squared_to(player.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_player = player
	return closest_player


func _is_observed_by_any_player() -> bool:
	var observation_point := global_position + Vector3.UP * observation_point_height
	for node: Node in get_tree().get_nodes_in_group('players'):
		var player := node as CharacterBody3D
		if not player:
			continue
		if 'is_alive' in player and not player.is_alive:
			continue
		if 'eyes_closed' in player and player.eyes_closed:
			continue

		var camera := player.get_node_or_null('CameraPivot/Camera3D') as Camera3D
		if camera and _camera_can_see_point(camera, player, observation_point):
			return true
	return false


func _camera_can_see_point(camera: Camera3D, player: CharacterBody3D, point: Vector3) -> bool:
	var offset := point - camera.global_position
	var distance := offset.length()
	if distance <= 0.01 or distance > maximum_observation_distance:
		return false

	var look_dot := (-camera.global_basis.z).dot(offset / distance)
	if look_dot < cos(deg_to_rad(observation_half_angle)):
		return false
	if not camera.is_position_in_frustum(point):
		return false

	var query := PhysicsRayQueryParameters3D.create(
		camera.global_position,
		point,
		sight_blocking_mask,
		[player.get_rid()]
	)
	query.hit_from_inside = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty()


func _update_stuck_state(delta: float) -> void:
	var moved_distance := Vector2(
		global_position.x - last_position.x,
		global_position.z - last_position.z
	).length()
	last_position = global_position

	if state != StatueState.STALKING:
		stuck_timer = 0.0
		return

	if moved_distance < 0.006:
		stuck_timer += delta
	else:
		stuck_timer = maxf(stuck_timer - delta * 2.0, 0.0)

	if stuck_timer >= stuck_time_before_steering:
		stuck_timer = 0.0
		steering_timer = steering_duration
		steering_sign *= -1.0


func _update_player_threat() -> void:
	for node: Node in get_tree().get_nodes_in_group('players'):
		var player := node as CharacterBody3D
		if not player or not player.has_method('set_statue_threat'):
			continue
		var distance := global_position.distance_to(player.global_position)
		var amount := clampf(1.0 - distance / 12.0, 0.0, 1.0)
		if is_observed:
			amount *= 0.45
		player.set_statue_threat(amount)


# --- Presentation -------------------------------------------------------------


## Give this statue its own copy of the stone and eye materials so several
## statues can glow independently instead of sharing one scene sub-resource.
func _prepare_materials() -> void:
	var stone_source: Material = _primitive_material(skull)
	var eye_source: Material = _primitive_material(eye_glow_left)
	if stone_source is ShaderMaterial:
		stone_material = (stone_source as ShaderMaterial).duplicate()
	if eye_source is StandardMaterial3D:
		eye_material = (eye_source as StandardMaterial3D).duplicate()

	for node: Node in visual_root.find_children('*', 'MeshInstance3D', true, false):
		var mesh_instance := node as MeshInstance3D
		var material := _primitive_material(mesh_instance)
		if material == null:
			continue
		if material == stone_source and stone_material:
			mesh_instance.material_override = stone_material
		elif material == eye_source and eye_material:
			mesh_instance.material_override = eye_material


func _primitive_material(mesh_instance: MeshInstance3D) -> Material:
	var primitive := mesh_instance.mesh as PrimitiveMesh
	return primitive.material if primitive else null


## Caught in the open: snap into a brand new shape, facing whoever spotted it.
## The player never sees the transition, only that it is different now.
func _on_caught_in_the_open() -> void:
	if unseen_time < 0.25:
		return
	if pose_snap_on_freeze:
		_apply_idle_pose(_pick_new_pose_index())
	if face_player_on_freeze:
		_crane_head_toward_target()


## Only the head turns, never the body. Snapping the body would also hand the
## statue a free turn and make it reach the player sooner, so the neck does the
## work instead - which looks worse anyway.
func _crane_head_toward_target() -> void:
	if not is_instance_valid(current_target):
		return
	var local_target := to_local(current_target.global_position)
	local_target.y = 0.0
	if local_target.length_squared() < 0.0001:
		return
	var yaw := atan2(-local_target.x, -local_target.z) - torso_pivot.rotation.y
	head_pivot.rotation.y = clampf(wrapf(yaw, -PI, PI), deg_to_rad(-78.0), deg_to_rad(78.0))


func _pick_new_pose_index() -> int:
	if IDLE_POSES.size() <= 1:
		return 0
	var next_index := randi() % IDLE_POSES.size()
	if next_index == pose_index:
		next_index = (next_index + 1) % IDLE_POSES.size()
	return next_index


func _apply_idle_pose(index: int) -> void:
	pose_index = clampi(index, 0, IDLE_POSES.size() - 1)
	var pose: Dictionary = IDLE_POSES[pose_index]
	visual_root.position = Vector3.ZERO
	visual_root.rotation = Vector3.ZERO
	torso_pivot.rotation = _degrees(pose['torso'])
	head_pivot.rotation = _degrees(pose['head'])
	left_arm_pivot.rotation = _degrees(pose['left_arm'])
	left_forearm_pivot.rotation = _degrees(pose['left_forearm'])
	right_arm_pivot.rotation = _degrees(pose['right_arm'])
	right_forearm_pivot.rotation = _degrees(pose['right_forearm'])
	left_leg_pivot.rotation = _degrees(pose['left_leg'])
	left_shin_pivot.rotation = _degrees(pose['left_shin'])
	right_leg_pivot.rotation = _degrees(pose['right_leg'])
	right_shin_pivot.rotation = _degrees(pose['right_shin'])
	jaw_open = pose['jaw']
	_apply_jaw()
	# Deliberately does NOT touch movement_phase: _stalk_target derives its
	# speed burst from it, so resetting it here would make re-posing change
	# how fast the statue moves.


func _degrees(angles: Vector3) -> Vector3:
	return Vector3(deg_to_rad(angles.x), deg_to_rad(angles.y), deg_to_rad(angles.z))


func _apply_jaw() -> void:
	# Negative pitch drops the front of the jaw, so the mouth tears open.
	jaw_pivot.rotation.x = deg_to_rad(-jaw_open * 36.0)


func _animate_motion(delta: float, speed_scale: float) -> void:
	movement_phase += delta * movement_animation_speed * speed_scale

	# Quantising the phase turns the walk into stop-motion: it arrives in
	# stutters rather than gliding, which reads as wrong long before you can
	# say why.
	var quantised := floorf(movement_phase / (PI / 5.0)) * (PI / 5.0)
	var phase := lerpf(movement_phase, quantised, stop_motion_amount)

	var stride := sin(phase)
	var counter_stride := sin(phase + PI)
	var twitch := sin(phase * 2.73) * 0.06

	visual_root.position.y = absf(sin(phase * 2.0)) * 0.05
	visual_root.position.z = 0.0
	visual_root.rotation.z = sin(phase * 0.47) * 0.1

	# Hunched low and shoulder-first, like something too tall for the house.
	torso_pivot.rotation.x = deg_to_rad(-32.0) + absf(stride) * 0.1
	torso_pivot.rotation.y = sin(phase * 0.41) * 0.09
	torso_pivot.rotation.z = twitch

	head_pivot.rotation.x = deg_to_rad(26.0) - absf(counter_stride) * 0.14
	head_pivot.rotation.y = sin(phase * 0.31) * 0.24
	head_pivot.rotation.z = sin(phase * 1.9) * 0.07
	jaw_open = lerpf(jaw_open, 0.55 + absf(stride) * 0.25, minf(delta * 6.0, 1.0))
	_apply_jaw()

	left_arm_pivot.rotation.x = deg_to_rad(-16.0) + stride * 0.72
	left_arm_pivot.rotation.z = deg_to_rad(-16.0) + counter_stride * 0.2
	left_forearm_pivot.rotation.x = deg_to_rad(24.0) + maxf(stride, 0.0) * 0.55
	right_arm_pivot.rotation.x = deg_to_rad(-16.0) + counter_stride * 0.72
	right_arm_pivot.rotation.z = deg_to_rad(16.0) + stride * 0.2
	right_forearm_pivot.rotation.x = deg_to_rad(24.0) + maxf(counter_stride, 0.0) * 0.55

	left_leg_pivot.rotation.x = stride * 0.46
	left_shin_pivot.rotation.x = deg_to_rad(-10.0) - maxf(stride, 0.0) * 0.7
	right_leg_pivot.rotation.x = counter_stride * 0.46
	right_shin_pivot.rotation.x = deg_to_rad(-10.0) - maxf(counter_stride, 0.0) * 0.7


func _apply_attack_pose(progress: float) -> void:
	var reach := ease(progress, -1.6)
	# Rear back, then throw both arms forward with the jaw already open.
	visual_root.position.z = lerpf(visual_root.position.z, -0.14, reach)
	torso_pivot.rotation.x = lerpf(torso_pivot.rotation.x, deg_to_rad(-42.0), reach)
	torso_pivot.rotation.z = lerpf(torso_pivot.rotation.z, 0.0, reach)
	head_pivot.rotation.x = lerpf(head_pivot.rotation.x, deg_to_rad(24.0), reach)
	head_pivot.rotation.y = lerpf(head_pivot.rotation.y, 0.0, reach)
	head_pivot.rotation.z = lerpf(head_pivot.rotation.z, deg_to_rad(9.0), reach)
	left_arm_pivot.rotation.x = lerpf(left_arm_pivot.rotation.x, deg_to_rad(98.0), reach)
	right_arm_pivot.rotation.x = lerpf(right_arm_pivot.rotation.x, deg_to_rad(98.0), reach)
	left_arm_pivot.rotation.z = lerpf(left_arm_pivot.rotation.z, deg_to_rad(-22.0), reach)
	right_arm_pivot.rotation.z = lerpf(right_arm_pivot.rotation.z, deg_to_rad(22.0), reach)
	left_forearm_pivot.rotation.x = lerpf(left_forearm_pivot.rotation.x, deg_to_rad(14.0), reach)
	right_forearm_pivot.rotation.x = lerpf(right_forearm_pivot.rotation.x, deg_to_rad(14.0), reach)
	jaw_open = maxf(jaw_open, reach)
	_apply_jaw()


## Drives everything that makes the statue feel awake: glowing fractures,
## burning sockets and the dust shaking loose off its shoulders.
func _update_presentation(delta: float) -> void:
	presentation_time += delta

	var proximity := 0.0
	if is_instance_valid(current_target):
		var distance := global_position.distance_to(current_target.global_position)
		proximity = clampf(1.0 - distance / maxf(dread_radius, 0.01), 0.0, 1.0)

	var target_agitation := proximity * 0.6
	match state:
		StatueState.STALKING:
			target_agitation = maxf(proximity, 0.5)
		StatueState.ATTACK_WINDUP:
			target_agitation = 1.0
		StatueState.COOLDOWN:
			target_agitation = maxf(proximity, 0.7)
		StatueState.DORMANT:
			target_agitation = 0.0
	agitation = move_toward(agitation, target_agitation, delta * 2.6)

	if stone_material:
		stone_material.set_shader_parameter('agitation', agitation)

	# Never a steady glow - the sockets breathe, and now and then they simply
	# stop being lit for a moment.
	var flicker := 1.0 + sin(presentation_time * 17.3) * 0.06 + sin(presentation_time * 3.1) * 0.11
	if fmod(presentation_time, 4.7) < 0.06:
		flicker *= 0.12
	var eye_color := eye_calm_color.lerp(eye_hunt_color, agitation)
	if eye_material:
		eye_material.albedo_color = eye_color
		eye_material.emission = eye_color
		eye_material.emission_energy_multiplier = lerpf(1.1, 7.5, agitation) * flicker
	eye_light.light_color = eye_color
	eye_light.light_energy = lerpf(0.16, 1.35, agitation) * flicker

	var shedding := 0.24
	if state == StatueState.STALKING or state == StatueState.COOLDOWN:
		shedding = 0.85
	elif state == StatueState.ATTACK_WINDUP:
		shedding = 1.0
	dust.amount_ratio = lerpf(dust.amount_ratio, shedding, minf(delta * 4.0, 1.0))
