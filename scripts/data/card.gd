class_name Card
extends RefCounted
const SchedulerScript := preload("res://scripts/data/scheduler.gd")

## One card: a question, an answer, and the files they live beside. A card is
## a folder -- front.md, back.md, and any media the markdown names -- so a
## deck is a set of folders that any editor can read, write and diff.

var id := ""  # the folder name, e.g. "001"
var front := ""
var back := ""
var folder := ""  # absolute path, so media resolves next to the markdown
var media: Dictionary = {}  # name -> absolute path
var state: Dictionary = {}  # scheduling state; see the Scheduler

func _init(p_id := "", p_folder := "") -> void:
	id = p_id
	folder = p_folder
	state = SchedulerScript.new_state()

func media_path(name: String) -> String:
	return str(media.get(name, ""))
