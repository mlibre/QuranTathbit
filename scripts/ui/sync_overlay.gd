class_name SyncOverlay
extends ColorRect
const ThemeScript := preload("res://scripts/ui/theme.gd")
const I18nScript := preload("res://scripts/ui/i18n.gd")

## What sync looks like while it happens: a quiet card over a dimmed screen
## that says plainly which phase is running, how far through it is, and that
## the deck itself is safe on this machine whatever the network does. The
## engine speaks in short phrases -- "signing in", "uploading" -- and this
## screen turns them into words a person reads once and understands.

## The engine's phases, each in plain words. The keys are the engine's own
## phrases; the values are the English the table translates from, looked
## up at the moment they are said, so the overlay speaks whatever tongue
## the app is speaking.
const PHRASES := {
        "signing in": "Signing in to GitHub",
        "reading repo": "Reading your repo",
        "downloading": "Fetching what changed",
        "uploading": "Sending your cards",
        "merging progress": "Merging your progress",
        "saving": "Saving to your repo",
}

var _phase: Label
var _count: Label
var _bar: ProgressBar
var _sweep: Tween
var _mark: ThemeScript.SyncMark
var _panel: PanelContainer

func _ready() -> void:
        color = Color(0.10, 0.14, 0.11, 0.0)
        mouse_filter = Control.MOUSE_FILTER_STOP
        set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        resized.connect(_layout)
        call_deferred("_layout")
        # The dim arrives with the card on it, not before it: a screen that
        # darkens before it has anything to say reads as a freeze.
        var dim := create_tween()
        dim.tween_property(self, "color:a", 0.45, 0.18)

        var center := CenterContainer.new()
        center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        center.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(center)

        var panel := PanelContainer.new()
        panel.name = "Panel"
        panel.add_theme_stylebox_override("panel", ThemeScript.card_stylebox())
        center.add_child(panel)
        _panel = panel

        var pad := MarginContainer.new()
        for side in ["left", "right"]:
                pad.add_theme_constant_override("margin_" + side, 26)
        for side in ["top", "bottom"]:
                pad.add_theme_constant_override("margin_" + side, 22)
        panel.add_child(pad)

        var box := VBoxContainer.new()
        box.add_theme_constant_override("separation", 10)
        pad.add_child(box)

        # The two circular arrows, at rest above the words: what is happening,
        # before a single line is read. While work is under way the mark
        # turns, slowly -- the shape of something in motion, and the same
        # honesty as the recitation's breathing bars.
        var mark_row := CenterContainer.new()
        _mark = ThemeScript.SyncMark.new(ThemeScript.GREEN)
        _mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
        mark_row.add_child(_mark)
        box.add_child(mark_row)

        var title := Label.new()
        title.text = I18nScript.t("Syncing")
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        ThemeScript.dress(title, ThemeScript.TITLE, ThemeScript.GREEN_DEEP, true)
        box.add_child(title)

        _phase = Label.new()
        _phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _phase.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        ThemeScript.dress(_phase, ThemeScript.BODY, ThemeScript.INK)
        # What it says before anything has reported: the first thing sync
        # actually does is sign in, so that is the first thing a person reads.
        _phase.text = I18nScript.t(str(PHRASES["signing in"])) + "…"
        box.add_child(_phase)

        _bar = ProgressBar.new()
        _bar.show_percentage = false
        _bar.custom_minimum_size = Vector2(0, 10)
        _bar.add_theme_stylebox_override("background", _track_stylebox())
        _bar.add_theme_stylebox_override("fill", _fill_stylebox())
        box.add_child(_bar)

        _count = Label.new()
        _count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        ThemeScript.dress(_count, ThemeScript.CAPTION, ThemeScript.INK_SOFT)
        box.add_child(_count)

        var reassurance := Label.new()
        reassurance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        reassurance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        reassurance.text = I18nScript.t("Your cards stay on this device — sync only shares them.")
        ThemeScript.dress(reassurance, ThemeScript.CAPTION, ThemeScript.INK_SOFT)
        box.add_child(reassurance)

        _start_sweep()
        ThemeScript.settle_in(panel, 0.0, 0.3)


## The card answers the window: capped at its own measure, never wider
## than what a phone can hold.
func _layout() -> void:
        if size.x <= 0.0 or _panel == null:
                return
        var avail := minf(360.0, size.x - 48.0)
        _panel.custom_minimum_size = Vector2(avail, 0)


## The engine's progress, made visible: a phase in plain words, and a bar
## that either knows how far it is or gently says "working on it".
func report(text: String, done: int, total: int) -> void:
        if _phase == null:
                return
        _phase.text = I18nScript.t(str(PHRASES.get(text, text.capitalize()))) + "…"
        if total > 0:
                _stop_sweep()
                _count.text = I18nScript.f("%d of %d", [done, total])
                _bar.value = 100.0 * float(done) / float(total)
        else:
                _count.text = ""
                _start_sweep()


## The last thing the overlay says before it goes: one calm beat of outcome.
func finish(ok: bool) -> void:
        if _phase == null:
                return
        _stop_sweep()
        _count.text = ""
        if ok:
                _bar.value = 100.0
                _phase.text = I18nScript.t("Up to date")
        else:
                _phase.text = I18nScript.t("Sync could not finish")


func _start_sweep() -> void:
        if _sweep != null and _sweep.is_valid():
                return
        if _bar == null:
                return
        if _mark != null:
                _mark.set_working(true)
        _bar.value = 0.0
        _sweep = create_tween()
        _sweep.set_loops()
        _sweep.tween_property(_bar, "value", 100.0, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
        _sweep.tween_property(_bar, "value", 0.0, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


func _stop_sweep() -> void:
        if _sweep != null and _sweep.is_valid():
                _sweep.kill()
        _sweep = null
        if _mark != null:
                _mark.set_working(false)


func _track_stylebox() -> StyleBoxFlat:
        var box := StyleBoxFlat.new()
        box.bg_color = ThemeScript.LINE
        box.set_corner_radius_all(5)
        return box


func _fill_stylebox() -> StyleBoxFlat:
        var box := StyleBoxFlat.new()
        box.bg_color = ThemeScript.GREEN
        box.set_corner_radius_all(5)
        return box
