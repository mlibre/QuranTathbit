extends SceneTree

## QA scratch: drive one full session to its end and save the done screen,
## so the summary's arrival (and the page it stands on) is seen, not assumed.

const MainScript := preload("res://scripts/main.gd")

func _init() -> void:
	DirAccess.make_dir_recursive_absolute("/tmp/shots")
	_fresh_install()
	var main = (load("res://scripts/main.gd") as GDScript).new()
	main.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(main)
	await main.ready
	await create_timer(0.6).timeout
	main._start_session()
	await create_timer(0.6).timeout
	var study: Control = main.get_node("Study")
	# Answer every card: reveal, then grade good, one after another.
	for i in 20:
		study._reveal()
		await create_timer(0.35).timeout
		study._answer("good")
		await create_timer(0.6).timeout
	await create_timer(0.8).timeout
	await process_frame
	await process_frame
	var image := root.get_viewport().get_texture().get_image()
	image.save_png("/tmp/shots/study_done.png")
	print("done screen saved")
	quit(0)

func _fresh_install() -> void:
	_remove_tree("user://decks")
	_remove_tree("user://settings.json")

func _remove_tree(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		return
	if DirAccess.dir_exists_absolute(path):
		for entry in DirAccess.get_files_at(path):
			DirAccess.remove_absolute(path.path_join(entry))
		for entry in DirAccess.get_directories_at(path):
			_remove_tree(path.path_join(entry))
		DirAccess.remove_absolute(path)
