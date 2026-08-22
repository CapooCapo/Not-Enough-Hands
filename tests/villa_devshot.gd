extends SceneTree

## Diagnostic: what the dev toggles actually look like in the villa.

const OUT_DIR := "user://villa_shots"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var main_scene := (load("res://house3/villa_main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	for _f: int in 10:
		await process_frame

	var dev: DevTools = main_scene.get_node("DevTools")
	var player: Node3D = main_scene.get_node("Player")
	var camera: Camera3D = player.get_node("CameraPivot/Camera3D")
	camera.make_current()

	# Stand in the middle of the ring so several doors are in view at once.
	player.set_physics_process(false)
	_park(player)

	await _shot("dev_00_plain")
	dev.set_bright_vision_enabled(true)
	await _shot("dev_01_bright")
	dev.set_entrance_xray_enabled(true)
	for _f: int in 3:
		await process_frame
	await _shot("dev_02_bright_xray")
	dev.set_bright_vision_enabled(false)
	await _shot("dev_03_xray_dark")
	print("shots in %s" % ProjectSettings.globalize_path(OUT_DIR))
	quit()

func _park(player: Node3D) -> void:
	player.global_position = Vector3(46.0, 1.7, 6.0)
	player.rotation = Vector3(0.0, PI * 0.5, 0.0)
	(player.get_node("CameraPivot") as Node3D).rotation = Vector3.ZERO


func _shot(shot_name: String) -> void:
	_park(root.get_node("VillaMain/Player") as Node3D)
	for _f: int in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, shot_name])
	print("wrote %s" % shot_name)
