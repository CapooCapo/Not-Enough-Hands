class_name InteractionController
extends Node

signal interact_target_changed(interactable: Interactable3D)

@export var max_interaction_range: float = 10.0
@export var interact_ray: RayCast3D
@export var player_node: Node3D

var current_interactable: Interactable3D = null
var is_active: bool = true

func _ready() -> void:
	if interact_ray:
		interact_ray.target_position = Vector3(0, 0, -max_interaction_range)

func _process(_delta: float) -> void:
	if not is_active:
		return
	_update_interact_target()

func handle_interact_input() -> void:
	if is_active and current_interactable and player_node:
		current_interactable.interact(player_node)

func _update_interact_target() -> void:
	if not interact_ray: 
		return
	
	var new_target: Interactable3D = null
	
	if interact_ray.is_colliding():
		var collider = interact_ray.get_collider()
		var candidate = _resolve_interactable(collider)
		if candidate and player_node:
			var dist = player_node.global_position.distance_to(candidate.global_position)
			if dist <= candidate.interaction_range:
				new_target = candidate
				
	if new_target != current_interactable:
		current_interactable = new_target
		interact_target_changed.emit(current_interactable)

func _resolve_interactable(node: Node) -> Interactable3D:
	if not node: return null
	
	if node is Interactable3D:
		return node
		
	for child in node.get_children():
		if child is Interactable3D:
			return child
			
	var parent = node.get_parent()
	if parent:
		if parent is Interactable3D:
			return parent
		for child in parent.get_children():
			if child is Interactable3D:
				return child
				
	return null
