class_name BlinkComponent
extends Node

signal eyes_closed_changed(closed: bool)

@export_category("Blink Settings")
@export var automatic_blink_enabled: bool = true
@export var blink_interval: float = 7.0
@export var forced_blink_duration: float = 0.22
@export var eyelid_transition_speed: float = 16.0

@export_category("UI References")
@export var blink_overlay: ColorRect
@export var blink_bar: ProgressBar

var eyes_closed: bool = false
var blink_time_remaining: float
var forced_blink_remaining: float = 0.0
var eyelid_closure: float = 0.0
var is_active: bool = true

func _ready() -> void:
	blink_time_remaining = blink_interval

func _process(delta: float) -> void:
	if not is_active:
		return
		
	var was_closed := eyes_closed
	var manual_close := Input.is_action_pressed("blink")

	if manual_close:
		eyes_closed = true
		blink_time_remaining = blink_interval
	elif forced_blink_remaining > 0.0:
		eyes_closed = true
		forced_blink_remaining = maxf(forced_blink_remaining - delta, 0.0)
	else:
		eyes_closed = false
		if automatic_blink_enabled:
			blink_time_remaining -= delta
			if blink_time_remaining <= 0.0:
				forced_blink_remaining = forced_blink_duration
				blink_time_remaining = blink_interval
				eyes_closed = true

	var target_closure := 1.0 if eyes_closed else 0.0
	eyelid_closure = move_toward(eyelid_closure, target_closure, eyelid_transition_speed * delta)
	
	if blink_overlay and blink_overlay.material:
		var eyelid_material := blink_overlay.material as ShaderMaterial
		eyelid_material.set_shader_parameter("closure", eyelid_closure)

	if blink_bar:
		blink_bar.value = clampf(blink_time_remaining / maxf(blink_interval, 0.01), 0.0, 1.0) * 100.0

	if was_closed != eyes_closed:
		eyes_closed_changed.emit(eyes_closed)

func force_blink(duration: float = -1.0) -> void:
	forced_blink_remaining = forced_blink_duration if duration < 0.0 else duration
	blink_time_remaining = blink_interval
	if not eyes_closed and is_active:
		eyes_closed = true
		eyes_closed_changed.emit(true)

func _open_eyes() -> void:
	var was_closed := eyes_closed
	forced_blink_remaining = 0.0
	eyes_closed = false
	eyelid_closure = 0.0
	if blink_overlay and blink_overlay.material:
		var eyelid_material := blink_overlay.material as ShaderMaterial
		eyelid_material.set_shader_parameter("closure", 0.0)
	if was_closed:
		eyes_closed_changed.emit(false)
