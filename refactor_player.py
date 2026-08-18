import re

def process_file():
    with open('player/player.gd', 'r') as f:
        content = f.read()

    # 1. Signals
    content = re.sub(r'signal eyes_closed_changed\(closed: bool\)\n', '', content)
    content = re.sub(r'signal killed_by_ghost\(ghost: Node3D\)\n', '', content)
    content = re.sub(r'signal hunter_trap_changed\(trapped: bool\)\n', '', content)

    # 2. Blink exports
    content = re.sub(r'@export_category\(\'Blink\'\).*?eyelid_transition_speed: float = 16\.0\n', '', content, flags=re.DOTALL)

    # 3. State variables
    content = re.sub(r'var eyes_closed: bool = false\n', '', content)
    content = re.sub(r'var blink_time_remaining: float = blink_interval\n', '', content)
    content = re.sub(r'var forced_blink_remaining: float = 0\.0\n', '', content)
    content = re.sub(r'var statue_threat: float = 0\.0\n', '', content)
    content = re.sub(r'var threat_sources: Dictionary = \{\}\n', '', content)
    content = re.sub(r'var eyelid_closure: float = 0\.0\n', '', content)

    # 4. Interact variables
    content = re.sub(r'signal interact_target_changed\(interactable: Interactable3D\)\n', '', content)
    content = re.sub(r'var current_interactable: Interactable3D = null\n', '', content)
    content = re.sub(r'@export var max_interaction_range: float = 10\.0\n', '', content)

    # 5. Development variables
    content = re.sub(r'@export var minigame_ghost_resume_grace: float = 1\.5\n', '', content)
    content = re.sub(r'var dev_invincible: bool = false\n', '', content)
    content = re.sub(r'var hunter_trap_source: Node3D\n', '', content)

    # 6. Nodes & Footstep variables
    content = re.sub(r'@onready var interact_ray: RayCast3D = \$CameraPivot/Camera3D/InteractRay\n', '', content)
    content = re.sub(r'@onready var blink_overlay: ColorRect = \$BlinkOverlay/Eyelids\n', '', content)
    content = re.sub(r'@onready var blink_bar: ProgressBar = \$BlinkUI/BlinkContainer/VBoxContainer/BlinkBar\n', '', content)
    content = re.sub(r'@onready var horror_overlay_rect: ColorRect = \$HorrorOverlay/VignetteAndGrain\n', '', content)
    content = re.sub(r'@onready var death_ui: CanvasLayer = \$DeathUI\n', '', content)
    content = re.sub(r'@onready var footstep_players: Array\[AudioStreamPlayer3D\] = \[\$FootstepA, \$FootstepB\]\n', '', content)

    # Replace Bladder & carry slots to also include new components
    comp_str = """@onready var bladder: Node = $BladderComponent
@onready var carry_slots: Node = $CarrySlotsComponent
@onready var blink_comp: BlinkComponent = $BlinkComponent
@onready var threat_comp: ThreatComponent = $ThreatComponent
@onready var footstep_comp: FootstepComponent = $FootstepComponent
@onready var interact_comp: InteractionController = $InteractionController"""
    content = re.sub(r'@onready var bladder: Node = \$BladderComponent\n@onready var carry_slots: Node = \$CarrySlotsComponent', comp_str, content)

    # Minigame ghost locks
    content = re.sub(r'var _minigame_ghost_safety_locks: int = 0\nvar _minigame_ghost_release_remaining: float = 0\.0\n', '', content)

    # Footstep offsets
    content = re.sub(r'var _footstep_offsets:.*?var _footstep_rng := RandomNumberGenerator\.new\(\)\n', '', content, flags=re.DOTALL)

    # _ready
    content = re.sub(r'\t_footstep_rng\.randomize\(\)\n', '', content)
    content = re.sub(r'\tblink_time_remaining = blink_interval\n', '', content)
    content = re.sub(r'\tif interact_ray:\n\t\tinteract_ray\.target_position = Vector3\(0, 0, -max_interaction_range\)\n', '', content)

    # _unhandled_input
    interact_block = """\t\tif event.is_action_pressed("interact"):
\t\t\tinteract_comp.handle_interact_input()"""
    content = re.sub(r'\t\tif event\.is_action_pressed\("interact"\):\n\t\t\tif current_interactable:\n\t\t\t\tcurrent_interactable\.interact\(self\)', interact_block, content)

    # _physics_process
    content = re.sub(r'\t_update_interact_target\(\)\n\t_update_minigame_ghost_safety\(delta\)\n', '', content)
    content = re.sub(r'\t\t_open_eyes_for_minigame\(\)\n', '\t\tblink_comp._open_eyes()\n', content)
    content = re.sub(r'\t\t_stop_footsteps\(\)\n', '\t\tfootstep_comp.stop_footsteps()\n', content)
    content = re.sub(r'\t_update_blink\(delta\)\n', '', content)
    content = re.sub(r'\tif is_trapped_by_hunter\(\):\n', '\tif threat_comp.is_trapped_by_hunter():\n', content)
    
    footstep_update = """\tvar h_speed = Vector2(get_real_velocity().x, get_real_velocity().z).length()
\tfootstep_comp.update_footsteps(delta, h_speed, was_on_floor, is_sprinting, is_crouching)"""
    content = re.sub(r'\t_update_footsteps\(delta, is_sprinting\)', footstep_update, content)

    # Delete large chunks
    content = re.sub(r'func _update_blink\(delta: float\) -> void:.*?func _stop_footsteps\(\) -> void:.*?_was_walking_on_floor = false\n\n\n', '', content, flags=re.DOTALL)

    # _update_interact_target
    content = re.sub(r'func _update_interact_target\(\) -> void:.*?return null\n\n', '', content, flags=re.DOTALL)

    # threat wave in camera bob
    content = re.sub(r'statue_threat', 'threat_comp.statue_threat', content)

    with open('player/player.gd', 'w') as f:
        f.write(content)

if __name__ == "__main__":
    process_file()
