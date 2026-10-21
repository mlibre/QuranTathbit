class_name CopyChip
extends Button
const ThemeScript := preload("res://scripts/ui/theme.gd")
const I18nScript := preload("res://scripts/ui/i18n.gd")

## The copy a selection is owed. A hand that chooses words on a phone has
## nothing to carry them with: Android's own copy toolbar stands only over
## the system's real text fields, never over the ink the app draws itself;
## no keyboard hangs over a drawn verse; and the engine's own label menu
## asks for a right-click a finger never makes. So the app offers the copy
## itself -- one small gold pill standing over the very label that holds
## the choice, on every platform (a phone browser has no Ctrl+C either).
## It is furniture that exists only while a choice does: nothing shows at
## rest, and it leaves the moment the selection does.

## The pill's own breathing room, and how long it says "Copied" before the
## gold wash goes quiet and the choice is let go.
const MARGIN := 8.0
const CLEAR_AFTER := 0.9

## What was carried away, told to whoever is listening (the tests are).
signal copied(text: String)

## Every label the app makes selectable is told here, at the moment it is
## made so -- one list for the whole app, wherever the label ends up
## living, pruned as labels leave the tree.
static var _watched: Array = []


static func watch(label: RichTextLabel) -> void:
        if label == null:
                return
        _watched.append(label)

var _label: RichTextLabel = null  # whose choice the pill is standing over
var _clearing := false  # a copy has landed; the pill is saying so
var _clear_gen := 0  # each copy's quiet beat answers only its own timer

func _ready() -> void:
        name = "CopyChip"
        # A press must never take the focus: the focus leaving a label is
        # what ends its selection, and the chosen words are still wanted
        # through the beat that follows the copy.
        focus_mode = Control.FOCUS_NONE
        mouse_filter = Control.MOUSE_FILTER_STOP
        ThemeScript.dress_ghost(self, ThemeScript.GOLD_DEEP, 36, 18)
        text = I18nScript.t("Copy")
        tooltip_text = I18nScript.t("Copy the chosen words")
        visible = false
        pressed.connect(_copy)

## The whole life of the pill, asked every frame: find the one label
## holding a choice, stand over it, and leave when the choice is gone.
## RichTextLabel tells no one when its selection changes -- there is no
## signal to hear -- so the pill looks for itself, the same quiet polling
## the page's clipboard half already does.
func _process(_delta: float) -> void:
        var found: RichTextLabel = null
        var alive := []
        for entry in _watched:
                if not is_instance_valid(entry):
                        continue
                alive.append(entry)
                if found != null:
                        continue
                var label := entry as RichTextLabel
                if not label.is_visible_in_tree():
                        continue
                # The engine tells no one when a label's selection changes
                # (no signal exists), and its only honest tell is the
                # selection's own edge: -1 is "nothing chosen".
                if label.get_selection_from() < 0:
                        continue
                if label.get_selected_text().strip_edges().is_empty():
                        continue
                found = label
        _watched = alive
        if found == null:
                # The beat that follows a copy keeps its place even after
                # the choice is gone; everything else hides at once.
                if not _clearing:
                        _hide()
                return
        if _clearing:
                # The beat plays on, but the pill is already following the
                # newer choice: its next copy answers what it stands over.
                _label = found
                _place(found)
                return
        if _label != found:
                _label = found
                text = I18nScript.t("Copy")
        if not visible:
                visible = true
                ThemeScript.settle_in(self, 0.0, 0.15)
        _place(found)

## Over the label's own head, centred on its width; under it when the head
## stands past the page's top edge, the way a long verse does when it is
## scrolled mid-read. Never past the page's own edges.
func _place(label: RichTextLabel) -> void:
        var rect := label.get_global_rect()
        # The pill hangs from the window, not from any container, so it
        # sizes itself: the measured minimum of the words it carries, taken
        # anew each time (the words change with the tongue and with the
        # beat that follows a copy).
        var own := get_combined_minimum_size()
        if size != own:
                size = own
        var page := get_viewport_rect().size
        var x := rect.get_center().x - own.x * 0.5
        var y := rect.position.y - own.y - MARGIN
        if y < MARGIN:
                y = rect.end.y + MARGIN
        x = clampf(x, MARGIN, maxf(MARGIN, page.x - own.x - MARGIN))
        y = clampf(y, MARGIN, maxf(MARGIN, page.y - own.y - MARGIN))
        position = Vector2(x, y)

## The words leave for the clipboard, the pill says so, and a quiet beat
## later the gold wash goes and the choice is let go.
func _copy() -> void:
        if _label == null or not is_instance_valid(_label):
                return
        var chosen := _label.get_selected_text()
        if chosen.strip_edges().is_empty():
                return
        _write(chosen)
        copied.emit(chosen)
        text = I18nScript.t("Copied")
        _clearing = true
        _clear_gen += 1
        var gen := _clear_gen
        get_tree().create_timer(CLEAR_AFTER).timeout.connect(func() -> void:
                _finish_clear(gen)
        )

func _finish_clear(gen: int) -> void:
        if gen != _clear_gen:
                return  # a later copy owns the beat now
        _clearing = false
        if _label != null and is_instance_valid(_label):
                _label.deselect()
        if not visible:
                text = I18nScript.t("Copy")

func _hide() -> void:
        visible = false
        _label = null

## Where the words go: on the web, the page's own writer carries them --
## the same path the fields' Ctrl+C rides, with the hidden-field fallback
## behind it -- and the engine's own set rides along too, two writers of
## the same words so the browser honours whichever it will. Everywhere
## else, the engine's clipboard is the only one, and it answers.
func _write(chosen: String) -> void:
        var bridge: Object = _page()
        if bridge != null:
                bridge.call(
                        "eval",
                        "if(window.__qtCopyText){window.__qtCopyText(" + JSON.stringify(chosen) + ")}"
                )
                _engine_clipboard(chosen)
        else:
                _engine_clipboard(chosen)


## A headless run has no clipboard to carry anything, and asking for one
## only cries into the log; every machine a reader holds has its own.
func _engine_clipboard(chosen: String) -> void:
        if DisplayServer.get_name() == "headless":
                return
        DisplayServer.clipboard_set(chosen)

## The page's bridge to the engine, read at runtime rather than by name: on
## every other platform there is none, and the same line then reads as
## "not here" instead of refusing to load.
func _page() -> Object:
        if not OS.has_feature("web"):
                return null
        return Engine.get_singleton("JavaScriptBridge")
