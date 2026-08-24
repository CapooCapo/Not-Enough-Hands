class_name ToiletGhostCaught
extends CanvasLayer

## Brief "you got caught" beat shown alongside the existing death flow (see
## ToiletMinigame._on_toilet_ghost_caught() - Sprint 10) - not a replacement
## for it. Purely a visual/audio reaction: no HP, no death logic, no ghost
## or minigame control. Self-contained: plays its own animation, notifies
## the caller when done, and removes itself.

signal sequence_finished

const CAUGHT_ANIMATION := &"caught"

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var audio: AudioStreamPlayer = $AudioStreamPlayer


func _ready() -> void:
	if audio.stream:
		audio.play()
	animation_player.animation_finished.connect(_on_animation_finished)
	animation_player.play(CAUGHT_ANIMATION)


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name != CAUGHT_ANIMATION:
		return
	sequence_finished.emit()
	queue_free()
