extends ProgressBar

@export var player_path: NodePath
var player: CharacterBody3D

func _ready() -> void:
    if not player_path.is_empty():
        player = get_node(player_path)
        if player:
            max_value = player.max_stamina
            value = player.current_stamina

func _process(_delta: float) -> void:
    if player:
        if value != player.current_stamina:
            value = player.current_stamina
