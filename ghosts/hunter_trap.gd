extends Node3D

signal player_caught(player: CharacterBody3D)
signal player_released(player: CharacterBody3D)
signal disarmed(player: CharacterBody3D)

@export var trap_duration: float = 8.0
@export var rescue_duration: float = 2.0
@export var interaction_range: float = 2.5
@export var rescue_break_distance: float = 3.0

var hunter: Node3D
var captured_player: CharacterBody3D
var rescuing_player: CharacterBody3D
var trap_time_remaining: float = 0.0
var rescue_progress: float = 0.0
var _spent: bool = false

@onready var trigger: Area3D = $Trigger
@onready var left_jaw: Node3D = $Visual/LeftJaw
@onready var right_jaw: Node3D = $Visual/RightJaw


func _ready() -> void:
	add_to_group('hunter_traps')
	trigger.body_entered.connect(_on_body_entered)


func set_hunter(source: Node3D) -> void:
	hunter = source


func _physics_process(delta: float) -> void:
	if not is_instance_valid(captured_player) or _spent:
		return
	if 'is_alive' in captured_player and not captured_player.is_alive:
		_release_player(false)
		return

	trap_time_remaining = maxf(trap_time_remaining - delta, 0.0)
	if trap_time_remaining <= 0.0:
		_release_player(false)
		return

	if not is_instance_valid(rescuing_player):
		rescuing_player = null
		rescue_progress = 0.0
		return
	if not _can_rescue(rescuing_player):
		rescuing_player = null
		rescue_progress = 0.0
		return

	rescue_progress += delta
	if rescue_progress >= maxf(rescue_duration, 0.0):
		_release_player(true)


func _on_body_entered(body: Node3D) -> void:
	if _spent or is_instance_valid(captured_player):
		return
	var player := body as CharacterBody3D
	if not player or not player.is_in_group('players'):
		return
	if player.has_method('can_be_targeted_by_ghosts') \
		and not bool(player.call('can_be_targeted_by_ghosts')):
		return
	if not player.has_method('apply_hunter_trap') \
		or not bool(player.call('apply_hunter_trap', self)):
		return

	captured_player = player
	trap_time_remaining = maxf(trap_duration, 0.0)
	rescuing_player = null
	rescue_progress = 0.0
	_set_closed_visual(true)
	player_caught.emit(player)
	if trap_time_remaining <= 0.0:
		_release_player(false)


func interact(player: Node3D = null) -> void:
	var rescuer := player as CharacterBody3D
	if not _can_rescue(rescuer):
		return
	if rescuing_player != rescuer:
		rescuing_player = rescuer
		rescue_progress = 0.0


func _can_rescue(player: CharacterBody3D) -> bool:
	if not is_instance_valid(captured_player) \
		or not is_instance_valid(player) \
		or player == captured_player \
		or not player.is_in_group('players'):
		return false
	if 'is_alive' in player and not player.is_alive:
		return false
	if player.has_method('is_trapped_by_hunter') \
		and bool(player.call('is_trapped_by_hunter')):
		return false
	return player.global_position.distance_to(global_position) <= rescue_break_distance


func get_interaction_prompt(interact_key_name: String) -> String:
	if not is_instance_valid(captured_player):
		return '[center]BAY SAN CUA HUNTER[/center]'
	if is_instance_valid(rescuing_player):
		var percent := int(clampf(rescue_progress / maxf(rescue_duration, 0.01), 0.0, 1.0) * 100.0)
		return '[center]DANG GO BAY... %d%%[/center]' % percent
	return '[center][b]%s[/b]  GO BAY CHO DONG DOI (2 GIAY)[/center]' % interact_key_name


func _release_player(was_rescued: bool) -> void:
	if _spent:
		return
	_spent = true
	var player := captured_player
	captured_player = null
	rescuing_player = null
	rescue_progress = 0.0
	if is_instance_valid(player) and player.has_method('release_from_hunter_trap'):
		player.call('release_from_hunter_trap', self)
	_set_closed_visual(false)
	if is_instance_valid(player):
		if was_rescued:
			disarmed.emit(player)
		else:
			player_released.emit(player)
	queue_free.call_deferred()


func _set_closed_visual(closed: bool) -> void:
	var target_angle := deg_to_rad(16.0) if closed else 0.0
	left_jaw.rotation.z = -target_angle
	right_jaw.rotation.z = target_angle


func _exit_tree() -> void:
	if is_instance_valid(captured_player) \
		and captured_player.has_method('release_from_hunter_trap'):
		captured_player.call('release_from_hunter_trap', self)
