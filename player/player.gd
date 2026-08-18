extends CharacterBody3D

signal door_minigame_started(door: Node)
signal door_minigame_finished()

@export var walk_speed: float = 2.45
@export var crouch_speed: float = 1.35
@export var sprint_speed_multiplier: float = 1.22
@export var jump_velocity: float = 4.2
@export var player_radius: float = 0.32
@export var crouch_height: float = 1.05
@export var standing_height: float = 1.75
@export var crouch_camera_height: float = 0.05
@export var standing_camera_height: float = 0.62
@export var crouch_transition_speed: float = 10.0
@export var max_step_height: float = 0.6
@export var step_floor_margin: float = 0.08
@export var step_probe_distance: float = 0.3

@export_category("Camera Feel")
@export var head_bob_frequency: float = 8.0
@export var head_bob_horizontal: float = 0.012
@export var head_bob_vertical: float = 0.018

var is_crouching: bool = false
@export var max_stamina: float = 100.0

var yaw_clamp_active: bool = false
var yaw_clamp_min: float = 0.0
var yaw_clamp_max: float = 0.0
var accumulated_yaw: float = 0.0
var pitch_clamp_min: float = -PI/2
var pitch_clamp_max: float = PI/2
@export var sprint_stamina_drain: float = 20.0
@export var stamina_regen_idle: float = 20.0
@export var stamina_regen_moving: float = 5.0

var current_stamina: float = max_stamina

var head_bob_time: float = 0.0
var is_alive: bool = true

@export var max_health: float = 100.0
var current_health: float = max_health
signal health_changed(current: float, max: float)

@export var mouse_sensitivity: float = 0.002

@export_category("Development")
@export var dev_speed_multiplier: float = 3.0

var dev_fast_movement: bool = false

@onready var camera_pivot: Node3D = $CameraPivot
@onready var first_person_holder: Node3D = $CameraPivot/Camera3D/FirstPersonItemHolder
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

@onready var door_minigame: CanvasLayer = get_node_or_null("DoorGhostMinigame") as CanvasLayer

@onready var bladder: Node = $BladderComponent
@onready var carry_slots: Node = $CarrySlotsComponent
@onready var blink_comp: BlinkComponent = $BlinkComponent
@onready var threat_comp: ThreatComponent = $ThreatComponent
@onready var footstep_comp: FootstepComponent = $FootstepComponent
@onready var interact_comp: InteractionController = $InteractionController

var current_held_node: Node3D = null
var is_held_item_hidden: bool = false

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	current_stamina = max_stamina
	var shape := collision_shape.shape as CapsuleShape3D
	shape.radius = player_radius
	shape.height = standing_height
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		
	if carry_slots:
		carry_slots.selected_slot_changed.connect(_on_selected_slot_changed)
		carry_slots.slots_changed.connect(_update_held_item)
		call_deferred("_update_held_item")

	if threat_comp:
		threat_comp.killed_by_ghost.connect(func(_g): is_alive = false)
		threat_comp.minigame_safety_ended.connect(func(): door_minigame_finished.emit())

func _on_selected_slot_changed(_idx: int) -> void:
	_update_held_item()

func _update_held_item() -> void:
	if current_held_node:
		current_held_node.queue_free()
		current_held_node = null
		
	if not carry_slots: return
	var item = carry_slots.call("get_selected_item")
	if not item: return
	
	if item.held_scene:
		current_held_node = item.held_scene.instantiate()
		first_person_holder.add_child(current_held_node)
	else:
		var mesh_inst = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.1, 0.1, 0.2)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.5, 0.0)
		box.material = mat
		mesh_inst.mesh = box
		current_held_node = mesh_inst
		first_person_holder.add_child(current_held_node)
		
	current_held_node.visible = not is_held_item_hidden

func set_held_item_visibility(vis: bool) -> void:
	is_held_item_hidden = not vis
	if current_held_node:
		current_held_node.visible = vis

func _unhandled_input(event: InputEvent) -> void:
	if not is_alive:
		return
	if _is_alt_toggle_event(event):
		toggle_mouse_capture()
		get_viewport().set_input_as_handled()
		return
	if is_door_minigame_active():
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var yaw_delta = -event.relative.x * mouse_sensitivity
		if yaw_clamp_active:
			var new_yaw = clamp(accumulated_yaw + yaw_delta, yaw_clamp_min, yaw_clamp_max)
			yaw_delta = new_yaw - accumulated_yaw
			accumulated_yaw = new_yaw
		rotate_y(yaw_delta)
		
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, pitch_clamp_min, pitch_clamp_max)
		
	if is_physics_processing():
		if event.is_action_pressed("interact"):
			if interact_comp:
				interact_comp.handle_interact_input()
				
		if carry_slots:
			if event.is_action_pressed("select_slot_1"):
				carry_slots.call("select_slot", 0)
			elif event.is_action_pressed("select_slot_2"):
				carry_slots.call("select_slot", 1)
			elif event.is_action_pressed("quick_slot_next"):
				carry_slots.call("next_slot")
			elif event.is_action_pressed("quick_slot_previous"):
				carry_slots.call("previous_slot")
			elif event.is_action_pressed("drop_item"):
				if not is_held_item_hidden:
					carry_slots.call("drop_selected")

func toggle_mouse_capture() -> void:
	Input.set_mouse_mode(get_toggled_mouse_mode(Input.get_mouse_mode()))

func get_toggled_mouse_mode(current_mode: Input.MouseMode) -> Input.MouseMode:
	return Input.MOUSE_MODE_VISIBLE if current_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

func _is_alt_toggle_event(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ALT or event.physical_keycode == KEY_ALT)

func _physics_process(delta: float) -> void:
	if is_door_minigame_active():
		if blink_comp: blink_comp._open_eyes()
		velocity = Vector3.ZERO
		if footstep_comp: footstep_comp.stop_footsteps()
		return

	if not is_alive:
		velocity = Vector3.ZERO
		if footstep_comp: footstep_comp.stop_footsteps()
		return

	var was_on_floor := is_on_floor()
	if threat_comp and threat_comp.is_trapped_by_hunter():
		velocity.x = 0.0
		velocity.z = 0.0
		if not was_on_floor:
			velocity.y -= gravity * delta
		elif velocity.y < 0.0:
			velocity.y = 0.0
		move_and_slide()
		if footstep_comp: footstep_comp.stop_footsteps()
		return

	if not was_on_floor:
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		if is_crouching:
			if _can_stand():
				_stand_up()
				velocity.y = jump_velocity
		else:
			velocity.y = jump_velocity

	if Input.is_action_pressed("crouch"):
		if not is_crouching:
			_crouch()
	else:
		if is_crouching:
			if _can_stand():
				_stand_up()

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var is_sprinting = false
	if direction != Vector3.ZERO and Input.is_action_pressed("run") and current_stamina > 0.0 and not is_crouching:
		is_sprinting = true

	var current_speed = walk_speed
	
	if is_sprinting:
		current_speed = walk_speed * sprint_speed_multiplier
		current_stamina -= sprint_stamina_drain * delta
	else:
		if is_crouching:
			current_speed = crouch_speed
			
		if direction == Vector3.ZERO:
			current_stamina += stamina_regen_idle * delta
		else:
			current_stamina += stamina_regen_moving * delta

	if dev_fast_movement:
		current_speed *= maxf(dev_speed_multiplier, 1.0)
		current_stamina = max_stamina
			
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
	
	if footstep_comp:
		var h_speed = Vector2(get_real_velocity().x, get_real_velocity().z).length()
		footstep_comp.update_footsteps(delta, h_speed, is_on_floor(), is_sprinting, is_crouching)

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
	var threat_wave := sin(Time.get_ticks_msec() * 0.019) * (threat_comp.statue_threat if threat_comp else 0.0)
	target_position.x += threat_wave * 0.008
	var blend := minf(crouch_transition_speed * delta, 1.0)
	camera_pivot.position = camera_pivot.position.lerp(target_position, blend)
	camera_pivot.rotation.z = lerpf(camera_pivot.rotation.z, threat_wave * 0.006, blend)

func _try_step_up(horizontal_motion: Vector3) -> void:
	if horizontal_motion.is_zero_approx():
		return
	if is_on_floor() and get_floor_normal().dot(up_direction) < 0.98:
		return

	var forward_collision := KinematicCollision3D.new()
	if not test_move(global_transform, horizontal_motion, forward_collision, safe_margin, false):
		return
	if forward_collision.get_normal().dot(up_direction) >= cos(floor_max_angle):
		return

	var available_step_height := max_step_height
	var up_collision := KinematicCollision3D.new()
	var requested_step_up := Vector3.UP * max_step_height
	if test_move(global_transform, requested_step_up, up_collision, safe_margin, false):
		available_step_height = up_collision.get_travel().y
	if available_step_height <= 0.02:
		return
	var step_up := Vector3.UP * available_step_height

	var probe_motion := horizontal_motion
	if probe_motion.length() < step_probe_distance:
		probe_motion = probe_motion.normalized() * step_probe_distance

	var raised_transform := global_transform
	raised_transform.origin += step_up
	if test_move(raised_transform, probe_motion):
		return

	var forward_transform := raised_transform
	forward_transform.origin += probe_motion
	var down_collision := KinematicCollision3D.new()
	var down_motion := Vector3.DOWN * (available_step_height + step_floor_margin)
	if not test_move(forward_transform, down_motion, down_collision):
		return
	if down_collision.get_normal().dot(up_direction) < 0.65:
		return

	var landing_y := forward_transform.origin.y + down_collision.get_travel().y
	var step_height := landing_y - global_position.y
	if step_height > 0.02 and step_height <= available_step_height + step_floor_margin:
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
	
	return space_state.intersect_shape(query).is_empty()

func start_door_minigame(door: Node) -> bool:
	if not is_alive or not door_minigame or is_door_minigame_active() or not is_instance_valid(door):
		return false
	if not door.has_method("begin_exorcism") or not bool(door.call("begin_exorcism")):
		return false
	if not door_minigame.has_method("start") or not bool(door_minigame.call("start", self, door)):
		door.call("cancel_exorcism")
		return false
	door_minigame_started.emit(door)
	return true

func is_door_minigame_active() -> bool:
	return door_minigame != null and door_minigame.has_method("is_running") and bool(door_minigame.call("is_running"))

func take_damage(amount: float) -> void:
	if amount <= 0: return
	current_health = clamp(current_health - amount, 0.0, max_health)
	health_changed.emit(current_health, max_health)
	if current_health <= 0:
		print("Player has died!")
