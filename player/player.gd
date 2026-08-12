extends CharacterBody3D

@export var walk_speed: float = 5.0
@export var crouch_speed: float = 2.5
@export var jump_velocity: float = 4.5
@export var crouch_height: float = 1.0
@export var standing_height: float = 2.0
@export var crouch_camera_height: float = -0.2
@export var standing_camera_height: float = 0.8
@export var crouch_transition_speed: float = 10.0

var is_crouching: bool = false
@export var max_stamina: float = 100.0
@export var sprint_stamina_drain: float = 20.0
@export var stamina_regen_idle: float = 20.0
@export var stamina_regen_moving: float = 5.0

var current_stamina: float = max_stamina
@export var mouse_sensitivity: float = 0.002
@export var max_interaction_range: float = 10.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var interact_ray: RayCast3D = $CameraPivot/Camera3D/InteractRay
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	current_stamina = max_stamina
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if interact_ray:
		interact_ray.target_position = Vector3(0, 0, -max_interaction_range)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Rotate player horizontally
		rotate_y(-event.relative.x * mouse_sensitivity)
		
		# Rotate camera vertically
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		
		# Clamp vertical rotation (-90 to 90 degrees)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -PI/2, PI/2)
		
	if event.is_action_pressed("interact"):
		if interact_ray and interact_ray.is_colliding():
			var collider = interact_ray.get_collider()
			var interact_target = collider
			if collider and not collider.has_method("interact"):
				interact_target = collider.get_parent()
				
			if interact_target and interact_target.has_method("interact"):
				var dist = global_position.distance_to(interact_target.global_position)
				var allowed_range = interact_target.interaction_range if "interaction_range" in interact_target else 2.5
				if dist <= allowed_range:
					if interact_target.get_method_argument_count("interact") > 0:
						interact_target.interact(self)
					else:
						interact_target.interact()

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
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

	# Smooth Camera Transition
	var target_cam_y = crouch_camera_height if is_crouching else standing_camera_height
	camera_pivot.position.y = lerp(camera_pivot.position.y, target_cam_y, crouch_transition_speed * delta)

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

	move_and_slide()

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
