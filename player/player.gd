extends CharacterBody3D

signal eyes_closed_changed(closed: bool)
signal killed_by_ghost(ghost: Node3D)

@export var walk_speed: float = 3.4
@export var crouch_speed: float = 1.8
@export var jump_velocity: float = 4.2
@export var player_radius: float = 0.32
@export var crouch_height: float = 1.05
@export var standing_height: float = 1.75
@export var crouch_camera_height: float = 0.05
@export var standing_camera_height: float = 0.62
@export var crouch_transition_speed: float = 10.0
@export var max_step_height: float = 0.35
@export var step_floor_margin: float = 0.08

@export_category("Camera Feel")
@export var head_bob_frequency: float = 10.0
@export var head_bob_horizontal: float = 0.018
@export var head_bob_vertical: float = 0.028

@export_category('Blink')
@export var automatic_blink_enabled: bool = true
@export var blink_interval: float = 7.0
@export var forced_blink_duration: float = 0.22
@export var eyelid_transition_speed: float = 16.0

var is_crouching: bool = false
@export var max_stamina: float = 100.0
@export var sprint_stamina_drain: float = 20.0
@export var stamina_regen_idle: float = 20.0
@export var stamina_regen_moving: float = 5.0

var current_stamina: float = max_stamina
var head_bob_time: float = 0.0
var eyes_closed: bool = false
var is_alive: bool = true
var blink_time_remaining: float = blink_interval
var forced_blink_remaining: float = 0.0
var statue_threat: float = 0.0
var eyelid_closure: float = 0.0
@export var mouse_sensitivity: float = 0.002
@export var max_interaction_range: float = 10.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var interact_ray: RayCast3D = $CameraPivot/Camera3D/InteractRay
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var blink_overlay: ColorRect = $BlinkOverlay/Eyelids
@onready var blink_bar: ProgressBar = $BlinkUI/BlinkContainer/VBoxContainer/BlinkBar
@onready var horror_overlay_rect: ColorRect = $HorrorOverlay/VignetteAndGrain
@onready var death_ui: CanvasLayer = $DeathUI

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	current_stamina = max_stamina
	blink_time_remaining = blink_interval
	var shape := collision_shape.shape as CapsuleShape3D
	shape.radius = player_radius
	shape.height = standing_height
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if interact_ray:
		interact_ray.target_position = Vector3(0, 0, -max_interaction_range)

func _unhandled_input(event: InputEvent) -> void:
	if not is_alive:
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Rotate player horizontally
		rotate_y(-event.relative.x * mouse_sensitivity)
		
		# Rotate camera vertically
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		
		# Clamp vertical rotation (-90 to 90 degrees)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -PI/2, PI/2)
		
	if event.is_action_pressed("interact"):
		_try_interact()


func get_interaction_target() -> Node:
	if not interact_ray or not interact_ray.is_colliding():
		return null

	var target := interact_ray.get_collider() as Node
	while target and target != get_tree().root:
		if target.has_method("interact"):
			return target
		target = target.get_parent()

	return null


func can_interact_with(target: Node) -> bool:
	if not target or not interact_ray.is_colliding():
		return false

	var allowed_range: float = target.interaction_range if "interaction_range" in target else 2.5
	var hit_distance := interact_ray.global_position.distance_to(interact_ray.get_collision_point())
	return hit_distance <= minf(allowed_range, max_interaction_range)


func _try_interact() -> void:
	interact_ray.force_raycast_update()
	var target := get_interaction_target()
	if target and can_interact_with(target):
		target.interact(self)

func _physics_process(delta: float) -> void:
	_update_blink(delta)
	if not is_alive:
		velocity = Vector3.ZERO
		return

	var was_on_floor := is_on_floor()

	# Add the gravity.
	if not was_on_floor:
		velocity.y -= gravity * delta

	# Handle Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		if is_crouching:
			if _can_stand():
				_stand_up()
				velocity.y = jump_velocity
		else:
			velocity.y = jump_velocity

	# Handle Crouch
	if Input.is_action_pressed("crouch"):
		if not is_crouching:
			_crouch()
	else:
		if is_crouching:
			if _can_stand():
				_stand_up()

	# Get the input direction and handle the movement/deceleration.
	# Input.get_vector automatically normalizes diagonal input
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var is_sprinting = false
	if direction != Vector3.ZERO and Input.is_action_pressed("run") and current_stamina > 0.0 and not is_crouching:
		is_sprinting = true

	var current_speed = walk_speed
	
	if is_sprinting:
		current_speed = walk_speed * 1.3
		current_stamina -= sprint_stamina_drain * delta
	else:
		if is_crouching:
			current_speed = crouch_speed
			
		if direction == Vector3.ZERO:
			current_stamina += stamina_regen_idle * delta
		else:
			current_stamina += stamina_regen_moving * delta
			
	current_stamina = clamp(current_stamina, 0.0, max_stamina)

	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	_update_camera_motion(delta)

	if was_on_floor and velocity.y <= 0.0:
		var horizontal_motion := Vector3(velocity.x, 0.0, velocity.z) * delta
		_try_step_up(horizontal_motion)

	move_and_slide()


func _update_blink(delta: float) -> void:
	var was_closed := eyes_closed
	var manual_close := Input.is_action_pressed('blink') and is_alive

	if manual_close:
		eyes_closed = true
		blink_time_remaining = blink_interval
	elif forced_blink_remaining > 0.0:
		eyes_closed = true
		forced_blink_remaining = maxf(forced_blink_remaining - delta, 0.0)
	else:
		eyes_closed = false
		if automatic_blink_enabled and is_alive:
			blink_time_remaining -= delta
			if blink_time_remaining <= 0.0:
				forced_blink_remaining = forced_blink_duration
				blink_time_remaining = blink_interval
				eyes_closed = true

	var target_closure := 1.0 if eyes_closed else 0.0
	eyelid_closure = move_toward(
		eyelid_closure,
		target_closure,
		eyelid_transition_speed * delta
	)
	var eyelid_material := blink_overlay.material as ShaderMaterial
	if eyelid_material:
		eyelid_material.set_shader_parameter('closure', eyelid_closure)

	if blink_bar:
		blink_bar.value = clampf(blink_time_remaining / maxf(blink_interval, 0.01), 0.0, 1.0) * 100.0

	if was_closed != eyes_closed:
		eyes_closed_changed.emit(eyes_closed)


func force_blink(duration: float = -1.0) -> void:
	forced_blink_remaining = forced_blink_duration if duration < 0.0 else duration
	blink_time_remaining = blink_interval
	if not eyes_closed and is_alive:
		eyes_closed = true
		eyes_closed_changed.emit(true)


func set_statue_threat(amount: float) -> void:
	statue_threat = clampf(amount, 0.0, 1.0)
	var overlay_material := horror_overlay_rect.material as ShaderMaterial
	if overlay_material:
		overlay_material.set_shader_parameter('threat_strength', statue_threat)


func kill_by_ghost(ghost: Node3D) -> void:
	if not is_alive:
		return
	is_alive = false
	forced_blink_remaining = 0.0
	eyes_closed = false
	velocity = Vector3.ZERO
	death_ui.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	killed_by_ghost.emit(ghost)


func _update_camera_motion(delta: float) -> void:
	var target_height := crouch_camera_height if is_crouching else standing_camera_height
	var bob_offset := Vector2.ZERO
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()

	if is_on_floor() and horizontal_speed > 0.1:
		var speed_ratio := horizontal_speed / maxf(walk_speed, 0.1)
		head_bob_time += delta * head_bob_frequency * speed_ratio
		bob_offset.x = cos(head_bob_time * 0.5) * head_bob_horizontal
		bob_offset.y = sin(head_bob_time) * head_bob_vertical

	var target_position := Vector3(bob_offset.x, target_height + bob_offset.y, 0.0)
	var threat_wave := sin(Time.get_ticks_msec() * 0.019) * statue_threat
	target_position.x += threat_wave * 0.008
	var blend := minf(crouch_transition_speed * delta, 1.0)
	camera_pivot.position = camera_pivot.position.lerp(target_position, blend)
	camera_pivot.rotation.z = lerpf(camera_pivot.rotation.z, threat_wave * 0.006, blend)


func _try_step_up(horizontal_motion: Vector3) -> void:
	if horizontal_motion.is_zero_approx():
		return

	# Only step when the normal movement is blocked by a stair riser.
	if not test_move(global_transform, horizontal_motion):
		return

	var step_up := Vector3.UP * max_step_height
	if test_move(global_transform, step_up):
		return

	var raised_transform := global_transform
	raised_transform.origin += step_up
	if test_move(raised_transform, horizontal_motion):
		return

	# Find a walkable landing below the raised, forward position.
	var forward_transform := raised_transform
	forward_transform.origin += horizontal_motion
	var down_collision := KinematicCollision3D.new()
	var down_motion := Vector3.DOWN * (max_step_height + step_floor_margin)
	if not test_move(forward_transform, down_motion, down_collision):
		return
	if down_collision.get_normal().dot(up_direction) < 0.65:
		return

	var landing_y := forward_transform.origin.y + down_collision.get_travel().y
	var step_height := landing_y - global_position.y
	if step_height > 0.02 and step_height <= max_step_height + step_floor_margin:
		global_position.y += step_height

func _crouch() -> void:
	is_crouching = true
	var shape = collision_shape.shape as CapsuleShape3D
	shape.height = crouch_height
	collision_shape.position.y = (standing_height - crouch_height) / -2.0

func _stand_up() -> void:
	is_crouching = false
	var shape = collision_shape.shape as CapsuleShape3D
	shape.height = standing_height
	collision_shape.position.y = 0.0

func _can_stand() -> bool:
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	
	var shape = CapsuleShape3D.new()
	shape.radius = (collision_shape.shape as CapsuleShape3D).radius
	shape.height = standing_height
	
	query.shape = shape
	query.transform = global_transform
	query.exclude = [get_rid()]
	query.collision_mask = collision_mask
	
	var result = space_state.intersect_shape(query)
	return result.is_empty()
