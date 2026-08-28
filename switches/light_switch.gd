extends StaticBody3D

@export var lock_duration: float = 0.3
@export_range(0.5, 10.0, 0.1) var interaction_range: float = 2.0
## Drag the light/device carrying ElectricalDevice into this field in Inspector.
@export_node_path("Node") var controlled_device: NodePath
## Preferred for generated maps: stable across rebuilds (for example R_LIVING).
@export var controlled_device_id: StringName

var interactable: Interactable
var _controlled_device: ElectricalDevice
var _power_manager: PowerManager
var _unlock_timer: Timer


func _ready() -> void:
	interactable = get_node_or_null("Interactable") as Interactable
	if not interactable:
		interactable = Interactable.new()
		interactable.name = "Interactable"
		add_child(interactable)
	interactable.interaction_range = interaction_range
	interactable.interacted.connect(_on_interacted)
	_try_bind_controlled_device()
	if not _controlled_device and controlled_device_id.is_empty():
		push_warning(name + ": assign an ElectricalDevice in controlled_device")
	_unlock_timer = Timer.new()
	_unlock_timer.one_shot = true
	_unlock_timer.wait_time = lock_duration
	_unlock_timer.timeout.connect(interactable.unlock)
	add_child(_unlock_timer)
	_update_prompt()


func _on_interacted(_player: Node) -> void:
	if not _controlled_device:
		return
	interactable.lock()
	_controlled_device.toggle()
	_unlock_timer.start()


func _on_device_state_changed(_device_is_on: bool) -> void:
	_update_prompt()


func _try_bind_controlled_device() -> void:
	var target := get_node_or_null(controlled_device)
	var device := target as ElectricalDevice
	if not device and target:
		device = target.get_node_or_null("ElectricalDevice") as ElectricalDevice
	if not device and not controlled_device_id.is_empty():
		_power_manager = get_tree().get_first_node_in_group("power_manager") as PowerManager
		if _power_manager:
			device = _power_manager.get_device_by_id(controlled_device_id)
			if not _power_manager.device_registered.is_connected(_on_device_registered):
				_power_manager.device_registered.connect(_on_device_registered)
	_bind_device(device)


func _on_device_registered(device: ElectricalDevice) -> void:
	if not _controlled_device and device.device_id == controlled_device_id:
		_bind_device(device)


func _bind_device(device: ElectricalDevice) -> void:
	if not device or device == _controlled_device:
		return
	if _controlled_device and _controlled_device.state_changed.is_connected(_on_device_state_changed):
		_controlled_device.state_changed.disconnect(_on_device_state_changed)
	_controlled_device = device
	_controlled_device.state_changed.connect(_on_device_state_changed)
	_update_prompt()


func _update_prompt() -> void:
	if not _controlled_device:
		interactable.prompt_text = (
			"ĐANG KẾT NỐI"
			if not controlled_device_id.is_empty()
			else "CHƯA GÁN THIẾT BỊ"
		)
	elif _controlled_device.is_forced_off():
		interactable.prompt_text = "MẤT ĐIỆN"
	else:
		interactable.prompt_text = "TẮT ĐÈN" if _controlled_device.is_on else "BẬT ĐÈN"
