extends SceneTree
const SettingsScript := preload("res://scripts/ui/settings_screen.gd")

## The device code stands across, not down. The report: the phone's
## photograph of the connect card showed the code a column of falling
## tiles -- one letter a line, nine lines tall, unreadable as a code.
## The cause was a kindness turned against itself: every line on the
## settings page wraps its words, and a wrapping label's least width is
## nothing at all, so the chip that shrinks to its child's least width
## stood one letter wide and let the wrap do the rest. A code is a
## ticket, not a paragraph: the wrap is off, the chip closes around the
## whole code, and the proof is the geometry -- one line, wider than
## tall, snug as a ticket in its sleeve.

var _failures := 0

func _init() -> void:
	_fresh_install()
	var settings := SettingsScript.new()
	settings.name = "Settings"
	settings.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(settings)
	if not settings.is_node_ready():
		await settings.ready
	await create_timer(0.3).timeout

	var flow: VBoxContainer = settings.get_node("Margin/Scroll/Wrap/Column/GitHub/Padding/Box/Flow")
	var chip: PanelContainer = flow.get_node("Code")
	var code_text: RichTextLabel = flow.get_node("Code/Pad/CodeText")
	# The shape GitHub hands the device flow: eight letters, a dash at
	# the middle -- what _pretty_code passes through untouched.
	code_text.text = "WDJB-MJHT"
	chip.visible = true
	flow.visible = true
	await create_timer(0.3).timeout

	_ok(code_text.get_line_count() == 1,
		"the code stands on one line, not a column of tiles")
	var rect := code_text.get_global_rect().size
	_ok(rect.x > rect.y,
		"the code reads across, not down (w %s, h %s)" % [rect.x, rect.y])
	# Snug as a ticket: the chip's own width is the code's width plus its
	# sleeve -- twenty a side, and nothing more to spare.
	_is(int(chip.size.x - rect.x), 40,
		"the chip closes around the code with only its sleeve to spare")
	# A second shape -- a bare code _pretty_code would dash itself --
	# keeps the same stance.
	code_text.text = "1A2B3C4D"
	await create_timer(0.2).timeout
	_ok(code_text.get_line_count() == 1,
		"an undashed code stands on one line too")
	rect = code_text.get_global_rect().size
	_ok(rect.x > rect.y,
		"the undashed code reads across, not down (w %s, h %s)" % [rect.x, rect.y])

	settings.queue_free()
	await create_timer(0.1).timeout
	_done()

func _done() -> void:
	if _failures > 0:
		print("device_code: %d FAILURE(S)" % _failures)
		quit(1)
	else:
		print("device_code: all checks passed")
		quit(0)

func _ok(condition: bool, what: String) -> void:
	if condition:
		print("  ok   %s" % what)
	else:
		_failures += 1
		print("  FAIL %s" % what)

func _is(got, want, what: String) -> void:
	_ok(str(got) == str(want), "%s (got %s, want %s)" % [what, str(got), str(want)])

func _fresh_install() -> void:
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
