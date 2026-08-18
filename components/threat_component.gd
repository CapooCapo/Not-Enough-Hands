class_name ThreatComponent
extends Node

signal killed_by_ghost(ghost: Node3D)
signal hunter_trap_changed(trapped: bool)
signal minigame_safety_ended()

@export_category("Threat UI")
@export var horror_overlay_rect: ColorRect
@export var death_ui: CanvasLayer

@export_category("Ghost Safety")
@export var minigame_ghost_resume_grace: float = 1.5

var statue_threat: float = 0.0
var threat_sources: Dictionary = {}

var dev_invincible: bool = false
var _minigame_ghost_safety_locks: int = 0
var _minigame_ghost_release_remaining: float = 0.0

var hunter_trap_source: Node3D
var is_alive: bool = true

func _process(delta: float) -> void:
	if _minigame_ghost_safety_locks > 0 or _minigame_ghost_release_remaining <= 0.0:
		return
	_minigame_ghost_release_remaining = maxf(_minigame_ghost_release_remaining - delta, 0.0)
	if _minigame_ghost_release_remaining <= 0.0:
		get_tree().call_group("hostile_ghosts", "set_dev_attack_suspended", false)
		minigame_safety_ended.emit()

func set_statue_threat(amount: float) -> void:
	set_threat_from(&"statue", amount)

func set_threat_from(source: StringName, amount: float) -> void:
	if is_protected_from_ghost_attacks():
		amount = 0.0
	var clamped := clampf(amount, 0.0, 1.0)
	if clamped <= 0.0:
		threat_sources.erase(source)
	else:
		threat_sources[source] = clamped

	statue_threat = 0.0
	for value: float in threat_sources.values():
		statue_threat = maxf(statue_threat, value)

	if horror_overlay_rect and horror_overlay_rect.material:
		var overlay_material := horror_overlay_rect.material as ShaderMaterial
		overlay_material.set_shader_parameter("threat_strength", statue_threat)

func kill_by_ghost(ghost: Node3D) -> void:
	if not is_alive or is_protected_from_ghost_attacks():
		return
	is_alive = false
	if death_ui:
		if death_ui.has_method("show_jumpscare"):
			death_ui.call("show_jumpscare", ghost)
		else:
			death_ui.visible = true
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	killed_by_ghost.emit(ghost)

func acquire_minigame_ghost_safety() -> void:
	_minigame_ghost_safety_locks += 1
	_minigame_ghost_release_remaining = 0.0
	if _minigame_ghost_safety_locks == 1:
		get_tree().call_group("hostile_ghosts", "set_dev_attack_suspended", true)
	_clear_all_ghost_threat()

func release_minigame_ghost_safety() -> void:
	_minigame_ghost_safety_locks = maxi(_minigame_ghost_safety_locks - 1, 0)
	if _minigame_ghost_safety_locks == 0:
		_minigame_ghost_release_remaining = maxf(minigame_ghost_resume_grace, 0.0)
		if _minigame_ghost_release_remaining <= 0.0:
			get_tree().call_group("hostile_ghosts", "set_dev_attack_suspended", false)
			minigame_safety_ended.emit()

func is_protected_from_ghost_attacks() -> bool:
	return dev_invincible \
		or _minigame_ghost_safety_locks > 0 \
		or _minigame_ghost_release_remaining > 0.0

func can_be_targeted_by_ghosts() -> bool:
	return is_alive and not is_protected_from_ghost_attacks()

func apply_hunter_trap(source: Node3D) -> bool:
	if not is_alive or is_protected_from_ghost_attacks() or is_trapped_by_hunter():
		return false
	hunter_trap_source = source
	hunter_trap_changed.emit(true)
	return true

func release_from_hunter_trap(source: Node3D = null) -> void:
	if not is_instance_valid(hunter_trap_source):
		hunter_trap_source = null
		return
	if is_instance_valid(source) and hunter_trap_source != source:
		return
	hunter_trap_source = null
	hunter_trap_changed.emit(false)

func is_trapped_by_hunter() -> bool:
	if is_instance_valid(hunter_trap_source) and hunter_trap_source.is_inside_tree():
		return true
	if hunter_trap_source != null:
		hunter_trap_source = null
		hunter_trap_changed.emit(false)
	return false

func set_dev_invincible(enabled: bool) -> void:
	dev_invincible = enabled
	if enabled:
		_clear_all_ghost_threat()

func _clear_all_ghost_threat() -> void:
	threat_sources.clear()
	statue_threat = 0.0
	if horror_overlay_rect and horror_overlay_rect.material:
		var overlay_material := horror_overlay_rect.material as ShaderMaterial
		overlay_material.set_shader_parameter("threat_strength", 0.0)
