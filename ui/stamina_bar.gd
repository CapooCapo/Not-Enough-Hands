extends ProgressBar

@export var player_path: NodePath
var player: CharacterBody3D


func _ready() -> void:
	if not player_path.is_empty():
		player = get_node_or_null(player_path) as CharacterBody3D
	_sync_from_player()


func _process(_delta: float) -> void:
	_sync_from_player()


func _sync_from_player() -> void:
	if not is_instance_valid(player):
		return
	max_value = maxf(float(player.get("max_stamina")), 1.0)
	value = clampf(float(player.get("current_stamina")), 0.0, max_value)
