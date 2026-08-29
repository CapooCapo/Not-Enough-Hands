extends Node3D

## Presentation-only body for a player. Gameplay stays on Player so this scene
## can be hidden from the owning first-person camera and replicated later
## without making the imported Kenney rig part of the movement controller.

const IDLE_SCENE: PackedScene = preload("res://assets/player/Animations/idle.fbx")
const RUN_SCENE: PackedScene = preload("res://assets/player/Animations/run.fbx")
const JUMP_SCENE: PackedScene = preload("res://assets/player/Animations/jump.fbx")

@export var skin: Texture2D
@export var model_scale: float = 0.46
@export_range(0.4, 1.0) var crouch_height_ratio: float = 0.64
@export var crouch_visual_speed: float = 8.0
@export var show_local_body: bool = false

@onready var character: Node3D = $Character
@onready var body_mesh: MeshInstance3D = $Character/Root/Skeleton3D/characterMedium

var _animation_player: AnimationPlayer
var _current_animation: StringName = &""
var _player: CharacterBody3D


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	_apply_skin()
	_build_animation_player()
	_align_to_player_capsule()
	_update_local_render_mode()
	_play_animation(&"idle")


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	_update_crouch_visual(delta)
	_update_locomotion_animation()


func _apply_skin() -> void:
	if not body_mesh or not skin:
		return
	var material := StandardMaterial3D.new()
	material.albedo_texture = skin
	material.roughness = 0.9
	body_mesh.set_surface_override_material(0, material)


func _build_animation_player() -> void:
	_animation_player = AnimationPlayer.new()
	_animation_player.name = "CharacterAnimationPlayer"
	# The source FBX animation tracks target Root/Skeleton3D. Parenting the
	# player beside that Root preserves those paths without rewriting 40 tracks.
	character.add_child(_animation_player)

	var library := AnimationLibrary.new()
	_add_animation(library, IDLE_SCENE, &"Root|Idle", &"idle", true)
	_add_animation(library, RUN_SCENE, &"Root|Run", &"run", true)
	_add_animation(library, JUMP_SCENE, &"Root|Jump", &"jump", false)
	_animation_player.add_animation_library(&"", library)


func _add_animation(
	library: AnimationLibrary,
	source_scene: PackedScene,
	source_name: StringName,
	target_name: StringName,
	loop: bool
) -> void:
	var source_root := source_scene.instantiate()
	var source_player := source_root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if source_player and source_player.has_animation(source_name):
		var animation := source_player.get_animation(source_name).duplicate(true) as Animation
		animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		library.add_animation(target_name, animation)
	source_root.free()


func _align_to_player_capsule() -> void:
	var standing_height := 1.75
	if is_instance_valid(_player) and "standing_height" in _player:
		standing_height = _player.standing_height
	position.y = -standing_height * 0.5
	scale = Vector3.ONE * model_scale


func _update_local_render_mode() -> void:
	if not body_mesh or not is_instance_valid(_player):
		return
	var is_local_player := _player.is_multiplayer_authority()
	body_mesh.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if show_local_body or not is_local_player
		else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	)


func _update_crouch_visual(delta: float) -> void:
	var is_crouching: bool = "is_crouching" in _player and bool(_player.is_crouching)
	var target_y_scale := model_scale * (crouch_height_ratio if is_crouching else 1.0)
	scale.x = model_scale
	scale.y = move_toward(scale.y, target_y_scale, crouch_visual_speed * model_scale * delta)
	scale.z = model_scale


func _update_locomotion_animation() -> void:
	if not _animation_player:
		return
	var horizontal_speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	if not _player.is_on_floor() and absf(_player.velocity.y) > 0.1:
		_play_animation(&"jump")
		return
	if horizontal_speed > 0.18:
		_play_animation(&"run")
		var walk_speed := 4.0
		if "walk_speed" in _player:
			walk_speed = maxf(_player.walk_speed, 0.1)
		_animation_player.speed_scale = clampf(horizontal_speed / walk_speed, 0.65, 1.3)
		return
	_play_animation(&"idle")


func _play_animation(animation_name: StringName) -> void:
	if not _animation_player or not _animation_player.has_animation(animation_name):
		return
	if _current_animation == animation_name and _animation_player.is_playing():
		return
	_current_animation = animation_name
	_animation_player.speed_scale = 1.0
	_animation_player.play(animation_name, 0.15)
