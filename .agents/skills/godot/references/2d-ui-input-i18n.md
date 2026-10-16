# 2D, UI, Input, and Localization

## 2D scene/rendering model

Use `Node2D` for positioned 2D world behavior and `CanvasItem` for drawing/custom rendering. `Control` is also a `CanvasItem` but follows UI layout rules.

- Default 2D content is in Canvas Layer 0 and follows the active `Camera2D`.
- Put camera-independent HUD/menus/overlays in a `CanvasLayer` with an appropriate layer/follow-viewport setting.
- `Node2D.position` is parent-relative; `global_position` is canvas-world position.
- `z_index` and `z_as_relative` control sibling draw order; `y_sort_enabled` can sort by Y where appropriate.
- `show_behind_parent` draws behind a parent CanvasItem.
- `CanvasItem` materials/modulate/self-modulate affect rendering but should not be confused with gameplay state.
- Keep pixel art crisp with nearest texture filtering/project settings; use linear filtering for scaled painted art. Do not globally choose one without checking assets.

### Coordinates and input

Useful conversions:

```gdscript
var canvas_position: Vector2 = get_global_transform() * local_position
var local_position: Vector2 = get_global_transform().affine_inverse() * canvas_position
var screen_position := get_viewport().get_screen_transform() * get_global_transform_with_canvas() * local_position
var event_local := make_input_local(event)
```

Prefer canvas/world coordinates for gameplay. Use screen-relative event properties (`screen_position`, `screen_relative`, `screen_velocity`) when UI/resolution independence matters. When synthesizing a mouse event, transform local coordinates to screen correctly before `Input.parse_input_event()`.

## Sprites, atlases, and texture filtering

- `Sprite2D`: one texture, optional region, frame count, centered/offset, flip, and material.
- `AnimatedSprite2D` + `SpriteFrames`: simple frame animations from images or sprite sheets.
- `TextureRect`: UI/source texture display with stretch modes.
- `AtlasTexture`: a region of a larger texture; use margins carefully.
- `NinePatchRect`/`StyleBoxFlat`: resizable panels that do not distort borders/content unexpectedly.
- `TextureButton` is a convenience Control; a Button with a normal/style-box theme is often more flexible.
- `CanvasItem.texture_filter` and project import/default filters affect magnified/minified art. Pixel art normally uses nearest; inspect seams/mipmaps rather than guessing.

For sprite sheets, keep frame dimensions and source separation consistent. `hframes`/`vframes` split one texture into a regular grid; `region_rect` selects an arbitrary atlas region.

## TileMapLayer (current) and TileMap (deprecated)

`TileMap` is deprecated in 4.7 — use one `TileMapLayer` node per layer. To convert, select the `TileMap`, open the TileMap bottom panel, and choose Extract TileMap layers as individual TileMapLayer nodes.

- A `TileSet` defines tile sources, atlases, alternate tiles, terrain sets, navigation polygons, custom data layers, and physics/material layers.
- A `TileMapLayer` owns cell data, enabled flags, navigation, collision, and rendering for one layer.
- Keep logical data (walkable, owner, objective) in custom data layers or parallel grid/resource data, not by reverse-engineering visual tiles.
- Use a navigation polygon in the TileSet for navigation baking when appropriate; collision polygons are independent.
- Use `TileMapLayer` events/signals for targeted gameplay instead of scanning all cells every frame.
- Large generated maps need chunking, deterministic seeds, and a stable cell-coordinate system.

## 2D cameras

`Camera2D` controls the 2D view. Choose one explicit style:

- `position_smoothing_enabled` for smooth follow.
- `drag_horizontal_enabled`/`drag_vertical_enabled` and limits for bounded maps.
- `zoom` values larger than 1 zoom in (Godot 4 behavior).
- `Camera2D.ignore_rotation` controls whether the camera rotates with its transform.
- `make_current()` or editor “Make Current” chooses the active camera; multiple cameras need a deliberate ownership rule.
- For UI, do not parent a camera-dependent world Control to a moving camera. Use CanvasLayer/anchors.
- Reset interpolation or explicitly handle camera snaps when changing world/level.

## Parallax

Use `Parallax2D`, not legacy `ParallaxBackground`/`ParallaxLayer`, for new work.

- `scroll_scale` below 1 moves more slowly/farther; 0 is fixed; above 1 moves faster/closer.
- `repeat_size` defines the infinite-repeat tile; textures should be seamless and cover the viewport within that tile.
- `repeat_times` adds extra copies for zoom-out/safety, but is not a substitute for correct sizing.
- `scroll_offset` changes the starting phase.
- Place content from the `(0,0)` crossing into positive repeat space; centering a texture at origin can leave gaps.
- Split-screen Parallax2D layers require separate SubViewports plus canvas visibility-layer culling; one world texture cannot be in two independent viewports without duplication.

## Custom 2D drawing

Override `CanvasItem._draw()` for lightweight immediate drawing:

```gdscript
func _draw() -> void:
    draw_line(Vector2.ZERO, Vector2(100, 0), Color.WHITE, 2.0, true)
    draw_circle(Vector2(50, 50), 20.0, Color.CORAL)
    draw_colored_polygon(PackedVector2Array([Vector2.ZERO, Vector2(20, 0), Vector2(0, 20)]), Color.GOLD)
```

- Call `queue_redraw()` only when drawing data changes; `_draw()` is not a per-frame update method.
- High-frequency dynamic geometry can be expensive and recreates command buffers. Use MultiMesh-like/batched/custom GPU approaches for large repeated geometry.
- `draw_*` coordinates are local CanvasItem coordinates.
- Godot 4.7 removed the old antialias feather behavior for lines; verify line width rather than compensating with duplicate lines.
- Prefer a dedicated shader/custom CanvasItem for complex or GPU-driven drawing.

## 2D lighting, meshes, and particles

- 2D lights affect CanvasItems only when the renderer/canvas settings and material/light modes permit it. Not every shader/BlendMode is compatible.
- `PointLight2D` has a texture-defined range; `DirectionalLight2D` affects an angle. Keep normal maps/textures appropriately sized and filtered.
- Light limits and per-item modes control 2D light-culling batches; excessive unique light/material combinations hurt batching.
- `MeshInstance2D` draws a mesh and can be useful for custom geometry/deformation, but custom `_draw()` is simpler for ordinary shapes.
- `CPUParticles2D`/`GPUParticles2D` are good for many identical effects. GPU particles are usually preferable for large counts but require target support and careful process material setup.
- Use `ParticleProcessMaterial` for reusable configuration; local/process space, amount, lifetime, randomness, collision, and trails determine behavior.
- Do not create a new particle node/material/mesh for every frequent hit if pooling/one-shot reuse is practical.

## Animation choices

- `AnimatedTexture`: texture resource with frame sequence; little runtime logic; useful in TileSet/batched contexts.
- `AnimatedSprite2D` + `SpriteFrames`: simple 2D frame animation.
- `AnimationPlayer`: sequences that animate arbitrary properties, transforms, sprites, audio, methods, and tracks.
- `AnimationTree`: state machines/blend spaces/control over many animations and parameters.

`AnimationPlayer.play()` may apply on the next processing tick; call `advance(0)` when an immediately visible update is required. Use a state machine/AnimationTree for locomotion blending rather than restarting overlapping `AnimationPlayer` clips manually.

## Responsive UI architecture

All UI is built from `Control` nodes:

- Content: Button, Label, LineEdit, TextEdit, TextureRect, ProgressBar, OptionButton, etc.
- Layout: MarginContainer, VBox/HBox/GridContainer, ScrollContainer, TabContainer, SplitContainer, Panel/anchors.

### Anchors and offsets

- Anchors are normalized references to parent edges/center; offsets are pixel distances from those anchors.
- Different left/right anchors make a Control resize with its parent.
- A full-rect root Control is the normal responsive UI root.
- Use MarginContainer for screen/section padding and Box/Grid containers for layout.
- A child of a Container is sorted by the Container; manual position/size is generally overwritten.
- Use anchors/offsets for edge-anchored HUD elements and simple overlays.
- Test minimum window size, aspect ratios, high text scale, localization expansion, and accessibility settings.

### Window stretch and the design canvas (verified 4.7.2)

With `window/stretch/mode = "canvas_items"` and `aspect = "expand"`, the engine picks `scale = min(window.width / base.width, window.height / base.height)` and hands the UI a design canvas of `window / scale` — never smaller than the base in either axis. Every layout decision the UI makes happens in those design units.

- **A desktop base resolution silently ruins phones.** Base 1280×800 on a 390×844 phone window gives scale 0.30 and a 1280×2770 canvas: the whole desktop layout drawn at a third size (18px body text renders ~5px), and every responsive branch written as `if size.x >= 620` never fires, because `Control.size` reports *design units* — on that phone the UI genuinely believes it is 1280 wide. The app looks "not tested on mobile at all" while every branch is technically correct. Verified: canvas `(1280, 2770)` at a 390×844 window.
- **Set the base to the smallest design canvas you support** — short side = the phone's width (e.g. 420×800) — and keep the desktop window with `window/size/window_width_override`/`_height_override` (e.g. 1280×800). Then a phone gets a 420-wide canvas at ~0.93 scale, a tablet gets an in-between canvas, and the desktop window gets *exactly the same canvas it always had*: for any window at least as wide as the old base aspect, the scale was already height-pinned, so desktop rendering is unchanged. Responsive code then reads the live control/viewport size and picks breakpoints between the phone and desktop canvases (e.g. 480/620 design units).
- **`Window.size` is physical pixels; the design canvas is `root.get_visible_rect().size`.** Control global rects and `custom_minimum_size` live in canvas units. Mixing the two in assertions compares different units and passes or fails meaninglessly — a 390×844 window with a 1280-wide canvas puts every control "inside the window" while nothing is legible. Assert the canvas first, then the rects.
- **Safe areas:** `DisplayServer.get_display_safe_area()` returns a screen-space `Rect2i`. The inset a window actually owes is how far the window extends *past* the safe area, directionally: top = `safe.position.y - window.position.y`, bottom = `(window.position.y + window.height) - (safe.position.y + safe.size.y)`, clamped at 0. Never `abs()` the difference — a desktop window sitting inside the safe area (the normal case) then gets a phantom inset the height of its margin from the screen edge. Convert px to design units with `canvas.height / window.height`. Desktops and bare X servers report the full screen, so the helpers return 0 there; re-apply on every resize (`resized` → layout) so rotation and fullscreen transitions stay honest.
- **Tooltips do not exist on touch.** `tooltip_text` needs a hover a fingertip never produces; state that rides only in a tooltip is invisible on every phone. Say it in the layout itself (a quiet caption line), keeping the tooltip as the desktop's shortcut.
- **Gate keyboard-only affordances on `DisplayServer.is_touchscreen_available()`** — key chips, shortcut hint rows, hover-only styling. Keep touch targets at least 44–48 design units tall; on a phone canvas the design unit and the physical pixel are close enough that the guideline transfers directly.
- **The Android back button arrives as `KEY_ESCAPE`.** Godot 4.7 has no `KEY_BACK` constant and no `NOTIFICATION_WM_GOBACK_REQUEST` (both are 3.x relics); handle Escape where "leave this screen" lives, and let `application/config/quit_on_go_back` decide the unhandled case. Lock `window/handheld/orientation` (portrait for a hand-held app) and mirror it in the web manifest (`"orientation": "portrait"`) so installed PWAs and the native build agree.

### Position, minimum size, and resize traps (verified 4.7.2)

These cause "the UI looks broken / never fits" reports. Each is a real engine behavior, not a preference.

- **`position` is absolute in parent coordinates once the node is in the tree.** Assigning a negative value does *not* mean "offset back from my anchor". The offset-from-anchor trick only appears to work while the node is still detached, because Godot then measures a zero-size parent. Repositioning an in-tree anchored control with the detached-node value throws it off-screen (a center-anchored 900×640 panel assigned `position = -size/2` lands at `(-450, -320)`). Center with `position = parent_size * 0.5 - size * 0.5`, and compute every HUD rect in real parent coordinates.
- **Prefer anchor centering for modals whose size settles late.** A one-shot `position = parent_size * 0.5 - size * 0.5` reads whatever `size` happens to be *now*; content that settles a layout pass later (a ScrollContainer bar appearing, wrapped text re-flowing) moves the card out from under the written position. Anchors `0.5` on all sides + `GROW_DIRECTION_BOTH` + zeroed offsets re-center on every pass instead. Assert centering from live rects at several viewport sizes.
- **An autowrapped `Label` with no width floor collapses its container.** `custom_minimum_size.x = 0` (or omitted) makes the minimum size "longest word" wide and one word per line tall — one short line measured **33×569**. Inside a `PanelContainer` that inflates the whole card past the window height. Give every autowrapped label a floor (`card_width - margins`) and re-apply it on resize.
- **`size` lags a `custom_minimum_size` change within the same frame.** Place neighbours from `get_combined_minimum_size()` (or call `reset_size()`), not from `size`; a child may still report its old height. For a `Control` parented directly to a plain `Control` (no Container sorting), changing `custom_minimum_size` never resizes it — call `reset_size()` explicitly or stale widths survive a window shrink.
- **Refit after building, not before.** A reflow pass that clamps content to the panel width is useless if it runs before the children are constructed. Build the panel, then reflow.
- **Measure the real inner width** (card size minus margins *and* the vertical scrollbar) when clamping rows, or content stays ~15px too wide.
- **Reflow the panel frame, not only its scrolling list.** Headings, separators, and closing buttons often live directly on the panel while only the rows sit inside the `ScrollContainer`; a pass that clamps just the list leaves an unwrapped heading forcing the whole card past the window. Recurse the clamp through the frame — the list inside is reached automatically.
- Pin two HUD cards so they cannot collide: side-by-side when the width allows, stacked below otherwise, and yield the corner to the minimap when the window is too short for either.
- **Never gate a layout reservation on `is_visible_in_tree()`.** It is false whenever *any* ancestor is hidden, and menus/pause/ending screens routinely hide the whole HUD. A reflow that runs underneath such a screen then believes a blocked corner is free, and the moment the HUD returns the control snaps back under whatever owns that corner. Read the control's own `visible` instead — it is the stable "does this exist on screen" predicate, and it stays testable (force it either way).
- **One screen corner, one positioning system.** Anchors and an absolute `position` reflow can each be correct on their own and still collide, because the anchor-derived rect of a freshly built child is unreliable in the frame it is constructed: `size` and `position` of bottom-anchored children under a just-created full-rect parent read as zero until the tree's first layout pass. Reserve the corner in the reflow pass, from `get_combined_minimum_size()`, and never from the authored anchor offsets (a 98px button whose label is 109px wide is wider than its `custom_minimum_size`). Note a reflow triggered only by `size_changed` leaves the initial guess in place until the player resizes — hook it to the state change that shows the UI too.
- **Button text makes buttons wider than their `custom_minimum_size`.** Measure live rects, not authored sizes, or collision checks pass while the buttons visibly overlap.
- **A `Button` never measures its child controls.** A button whose visible content is built from children (a drawn icon plus a `Label` in a centered row) sizes itself from its own *text* -- which is empty -- and collapses to a ~25px sliver while its children still render inside. Set `custom_minimum_size` by hand from `Font.get_string_size()` of the widest string the button will ever carry, including its other states ("Listen" must not be measured while "Fetching…" is possible).
- **`RichTextLabel` autowraps by default; `Label` does not.** A `RichTextLabel` with `fit_content` and `SIZE_SHRINK_CENTER` collapses to a one-character-wide column and stacks every glyph of its text on its own line (a seven-glyph line renders as seven stacked marks). Give content labels `SIZE_EXPAND_FILL` plus an explicit `autowrap_mode`, the pair every working label in a project shares.
- **A plain `Control` child of a container stretches to the column's full width.** A custom `_draw()` mark drawn at fixed local coordinates (a circle at the centre of its own 64x64 minimum) then lands at the *left edge* of the stretched control, not under its drawn centre. Set `SIZE_SHRINK_CENTER` on drawn-mark children so the control hugs the drawing.
- **Child order is z-order, in drawing *and* in hit-testing.** A later sibling sits above an earlier one, and a full-rect container added after a floating corner button eats the button's clicks even at `MOUSE_FILTER_PASS` — PASS hands the event to the *parent*, never to the lower sibling, so the button underneath never hears it. Add floating controls (corner buttons, overlays) *last*, and lock it in with a regression that walks the engine's own hit test by hand: children in reverse order, skip `!visible` and `MOUSE_FILTER_IGNORE`, `get_global_rect().has_point(point)`, recurse; assert the button is what the walk returns at its own centre. Injected input is no substitute: `push_input`/`parse_input_event` are dropped silently in `--headless`, and on a real display a press without a preceding hover can leave focus state wedged — build the regression on the walk, not on injected events.
- **`hint_tooltip` is Godot 3; 4.x renamed it `tooltip_text`.** Assigning the 3.x name is a *runtime* error on the exact line, which aborts a code-built `_build()` mid-way: every control after that line is missing, and the cascading "node not found" errors point at code that never ran. When a screen half-builds, look for the first SCRIPT ERROR, not the missing nodes.
- **A `ScrollContainer` with `horizontal_scroll_mode = SCROLL_MODE_DISABLED` stretches its child to the viewport's width**, whatever size flags the child carries. A capped, centred column (cards that keep a reader's measure on a desktop and fill a phone) needs a `CenterContainer` between the scroll and the column: the scroll stretches the wrapper, the wrapper centres the capped column.
- Assert layout in tests with real rects (`Rect2(position, size)`) against the parent rect at several viewport sizes — "children outside card: 0" and card-height-vs-window checks catch what eyeballing misses. Be aware `get_rect()` reflects anchors/offsets, so compare like with like.
- **Test the visibility that does not exist on your machine.** Touch/on-screen controls gated on `DisplayServer.is_touchscreen_available()` never appear in headless CI or on a desktop test machine, so a collision they cause is invisible to the default path. Force the flag on in the suite and assert against the forced state.
- **A modal overlay does not stop `_input` on the screen beneath it.** A later-added sibling's `_input` runs first and `set_input_as_handled()` stops that one event, but GUI-bound keys (typing Space into a `TextEdit`) pass through `_input` *before* the GUI: an unguarded study screen beneath an open editor answers a card on every spacebar. The screen under a modal must explicitly early-return while the overlay exists (`get_node_or_null("Editor") != null`), and the overlay itself consumes only Esc/Ctrl+Enter.
- A control that cannot be placed clear of its blockers should be hidden (and still left inside the window so later measurements stay valid), not drawn on top. Optional chrome yields; the blocker keeps its thumb-reachable corner.
- **`HFlowContainer` only wraps when its width is actually constrained.** A `SIZE_SHRINK_CENTER` flow is never narrower than its own single line, so it never wraps and silently overflows a phone instead. Give the flow `SIZE_FILL` with `alignment = ALIGNMENT_CENTER`: pairs sit together on a wide window, stack on a narrow one, each line centred.

### Containers

Understand size flags: Fill, Expand, and Shrink Begin/Center/End; stretch ratio distributes extra space. Nested containers should express hierarchy. Use ScrollContainer when content can exceed available space rather than shrinking controls below readability.

Do not put a fixed-size modal over the whole screen without checking smaller windows, TV overscan/safe areas, and touch/controller navigation.
- Centre short content inside a `ScrollContainer` with a filler `VBoxContainer` whose `custom_minimum_size.y` is pinned (on resize) to the scroll's own height: a short card then floats mid-page while a tall one still grows the scroll range. Without the floor, top-anchored content hugs the top of the viewport and the lower page reads as dead space.
- Press feedback that containers cannot fight: tween `scale` (with `pivot_offset` set on `resized`), never `position` -- containers re-assert child positions on every layout pass and a position tween snaps back mid-flight. `Button` in 4.7 has `button_down`/`button_up`/`pressed` but no `canceled` signal; wire the release path from `button_up`.
- **`Control.rotation` pivots at `pivot_offset`, which defaults to the top-left corner** (verified 4.7.2). A drawn mark that animates `rotation` in `_process` without setting `pivot_offset = size / 2.0` first swings out of its parent on a circular orbit -- a spinner that leaves its round button. Set the pivot every frame before incrementing (size settles after the first layout pass), or on `resized`.
- **`button.disabled = true` for even a moment wears the engine's default grey stylebox** (verified 4.7.2). A button disabled while a fetch runs flashes a grey rectangle where a themed pill stood. Either override the `disabled` stylebox to match the rest state, or keep the button enabled and guard re-entry with a plain boolean -- the guard is usually all that was wanted.
- **Fonts without an italic face get a *silent* upright fallback, not a synthesized oblique** (verified 4.7.2): with only `normal_font` overridden, RichTextLabel's `[i]` falls back to the upright normal face — emphasis that changes *nothing*, which is how a deck author's `*emphasis marks*` once vanished (they asked where their stars went). Faux-italic must be built by hand: a `FontVariation` with `base_font` set and `variation_transform = Transform2D(Vector2(1,0), Vector2(0.24,1), Vector2.ZERO)` (a shear, y-down canvas — top-right lean), cached per base font, installed as the `italics_font`/`bold_italics_font` overrides. Set all four `*_font_size` overrides too, or leaning runs shrink to the theme default size. The prior claim here — that the engine synthesizes oblique and it looks broken — was wrong: nothing leans unless you make it.

### Focus and navigation

- Every Control can hold focus, but only controls with focus mode All/Click should be meaningful targets.
- Built-in `ui_up`, `ui_down`, `ui_left`, `ui_right`, `ui_focus_next`, and `ui_focus_prev` are UI actions. Do not repurpose them for gameplay.
- Configure explicit focus neighbors for complex layouts; the engine otherwise guesses.
- Set initial focus after controls are ready: `$StartButton.grab_focus.call_deferred()`.
- Hidden controls lose focus. Pause/menu code must restore focus to a visible valid control.
- Test keyboard, controller, mouse, touch, and screen-reader/landmark behavior.

### Theme

Theme lookup considers local overrides, type variations/class hierarchy, ancestor themes, project theme, default theme, and fallback data. Use a project Theme resource for typography/colors/style consistency; use local overrides sparingly. Define type variations (for example a reusable `DangerButton`) rather than duplicating every control style.

Test contrast, focus visibility, disabled states, hover/pressed, high text scale, and color-blind usability. Godot 4.7 accessibility landmarks and live-region controls can improve screen-reader context, but verify the exact `AccessibilityServer` APIs and platform support.

- Verify theme item names against the installed default theme before overriding (`ThemeDB.get_default_theme().get_stylebox_list(type)` / `get_color_list(type)`). A wrong item name is a silent no-op with no warning: ScrollBar's 4.x style items are `scroll`, `scroll_focus`, `grabber`, `grabber_highlight`, `grabber_pressed` -- the 3.x names (`background`, `grabber_stylebox`) do nothing and leave the default grey bar on screen while the code looks correct.

### Rich text and dialogs

Use `RichTextLabel` for BBCode/styled text, not every label. Its image API changed in 4.7: use float dimensions and `ImageUnit` (`PIXEL`, `PERCENT`, `EM`). Use `Popup`/`PopupPanel`/`ConfirmationDialog`/`AcceptDialog` for modal workflows and parent them to the correct Window/UI root. Pause/process mode must match the desired modal behavior.

- `RichTextLabel.selection_enabled = true` makes static text selectable and copyable with the mouse (drag a range; desktop and web then offer Copy). A plain `Label` can never be selected, so any text a user may want to quote -- verses, licenses, paths, values shown as text -- belongs in a `RichTextLabel`.
- Turning `selection_enabled` on is only half the job: the default `selection_color` theme item is a hard blue (`Color(0.1, 0.1, 1.0, 0.8)` on RichTextLabel; flat grey on TextEdit/LineEdit). On any app with its own palette that reads as a spill from another program, and users will report it. `RichTextLabel`, `TextEdit`, `LineEdit`, and `CodeEdit` all accept an `add_theme_color_override("selection_color", ...)` -- set it to a translucent tint of the app's accent wherever selection is possible, in the one builder that dresses those controls.
- `[url=...]...[/url]` in BBCode fires `meta_clicked`; connect it to `OS.shell_open` so in-text links open in the browser. Keep the visible label meaningful (say where it goes), not a raw URL.

## Input design

### InputMap actions

Define semantic actions in **Project Settings → Input Map**, for example:

```text
move_left
move_right
move_forward
move_back
interact
jump
dash
pause
```

Use `StringName` actions. Gameplay should not depend on physical keys or a particular controller layout. Provide keyboard, mouse, and gamepad bindings; use deadzones tuned per stick; support remapping in user settings.

Built-in `ui_accept`, `ui_cancel`, and focus-navigation actions belong to UI navigation and should not be overloaded for unrelated actions.

### Polling versus events

Continuous state/movement:

```gdscript
var direction := Input.get_vector(
    &"move_left",
    &"move_right",
    &"move_forward",
    &"move_back",
)
```

> `Input.get_vector(neg_x, pos_x, neg_y, pos_y)` returns `y = -1` when the
> `neg_y` (forward/up) action is pressed and `y = +1` for `pos_y` (back/down).
> Map to 3D with the negated `y`: `wish = right * v.x + forward * -v.y`.
> Using `right * v.x + forward * v.y` inverts up/down — pressing Up walks
> toward the camera. The same rule applies to a fixed-isometric basis and to
> any custom touch stick, which must emit the same sign convention
> (`y = -1` for stick-up) so keyboard and stick stay consistent. Keep joystick
> knob drawing in the same space as the emitted value.

Discrete action:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed(&"dash"):
        dash()
```

- `_input()` receives events before GUI and is for rare deliberate global interception.
- GUI `_gui_input()` handles a focused/hovered Control; call `accept_event()` after handling.
- `_shortcut_input()` handles unhandled shortcuts.
- `_unhandled_key_input()` and `_unhandled_input()` are normal gameplay fallbacks.
- `get_viewport().set_input_as_handled()` stops normal propagation. Polled `Input` state is separate and is not changed merely because an event was accepted.
- Check event subtype before reading specific properties; `event is InputEventMouseButton`, `InputEventKey`, `InputEventJoypadButton`, etc.
- Ignore key echo where a held key should trigger once.

### Devices and platform input

- `Input.get_connected_joypads()`, joypad button/axis APIs, vibration, and device IDs are String/int based; verify exact methods.
- Godot 4.7 keyboard/mouse no longer use numeric device ID 0. Compare `InputEvent.DEVICE_ID_KEYBOARD`/`DEVICE_ID_MOUSE` or check event type.
- Use `screen_relative`/`screen_velocity` for resolution-independent mouse-look; under capture use `relative`/`velocity`.
- Touch can emulate mouse when enabled, but a good mobile game still needs explicit touch controls/safe areas. Godot 4.7 adds `VirtualJoystick` for fixed/dynamic/following on-screen sticks.
- **A touch release outside the control never reaches `_gui_input`.** A custom stick that captures the touch index on press must also watch `_input` for the matching release index and reset there, or the gesture sticks forever when the thumb lifts off-rect. (`_input` runs before `_gui_input`, so an inside release still resolves exactly once when the `_gui_input` branch re-checks the index.)
- Handle focus loss, controller disconnect, device reconnection, and remapping while gameplay is active.
- Runtime `InputMap` changes are not automatically saved; persist user remaps in `user://` and reapply them.

### Quit and window events

Use `_notification()`/`NOTIFICATION_WM_CLOSE_REQUEST` or `auto_accept_quit` policy deliberately. `get_tree().quit()` is immediate. On mobile/web, backgrounding and process suspension are not normal desktop cases; save state and avoid assuming timers keep running.

## Localization

### Project setup

- Import translations from CSV/spreadsheets or gettext `.po`.
- Add imported translations under **Project Settings → Localization → Translations**; importing alone is not enough.
- Use `TranslationServer.set_locale()` for runtime language changes.
- Default to `OS.get_locale_language()` only as an initial preference; allow explicit user choice and configure fallback.
- A locale can be language/region/script/variant (`en`, `en_GB`, `sr_Latn`, etc.).

### Translation calls

```gdscript
text = tr("START_GAME")
text = tr("Close", "Actions")
text = tr_n("There is %d item", "There are %d items", count) % count
text = tr("{player} found {item}").format({
    "player": player_name,
    "item": item_name,
})
```

Use named placeholders and translator context. `tr_n` is for nonnegative integer counts; languages can have more than two plural forms. Some text-bearing properties auto-translate; disable auto translation for user-generated names/content and use `NO_TRANSLATE`/`TRANSLATORS:` hints in extraction where appropriate.

### Fonts, shaping, RTL, and text server data

- Use a font covering every intended script; configure fallbacks.
- Dynamic-font fallback is preferable for arbitrary user-language text and multiplayer chat.
- Enable **Include Text Server Data** for exported word/line-breaking dictionaries for languages without spaces; it adds several MB.
- When two scripts share an alphabet (Arabic and Persian share all but a handful of letters), classify lines by the letters only one script writes -- but know what the *body* of the text is, and add a second tell for the ambiguous middle. A bare line of only shared letters, no tell either way, is not "default to the more famous script": in a bilingual Quran deck it is the Persian translation ("بنام خداوند بخشنده مهربان" carries no Persian-only letter at all), while every verse is reliably vocalised -- so harakat as a second tell separates the two where letters cannot (bare shared text = the translation, vocalised text = scripture). Meanwhile lines that are references *by construction* (surah names, ranges) want their own classifier that leans Arabic whatever the letters carry, or a bare name like قريش flips faces between screens.
- Measure perceived centering with pixels before chasing it. A vision critique can call a centered RTL line "slightly shifted" while the bounding-box measurement says one pixel: crop the card, threshold the text rows, and compare each line's bbox centre with the card's centre before spending a fix on it.
- Godot automatically mirrors many UI anchors/margins, container order, text alignment, and internal control elements for RTL. Coordinate systems and non-UI nodes are not mirrored.
- Override `text_direction`, `layout_direction`, or structured-text BiDi handling for files, URLs, code, and other high-level order cases.
- Use localized number formatting/parsing through `TextServer` for non-Western digits.
- Pseudolocalization catches untranslated strings, missing glyphs, and insufficient space; it is not a complete CJK/RTL test.
- Verify glyph coverage before typing a symbol into any string. Frequently used UI glyphs (`▶` `●` `♪` `✓`) are missing from many text fonts -- Vazirmatn and Amiri carry none of the four -- and the engine renders a missing glyph as a tofu box without any warning. Inspect the font's cmap (fontTools `getBestCmap()`) or test-render every non-alphanumeric symbol you ship.
- A font family's cuts are not interchangeable when the text is small and every mark matters. Amiri's harakat are drawn small and tight: at 12 px a damma (a round curl) renders as a 3-pixel smudge that reads as a fatha (a flat stroke) -- a real user learning the vowels made exactly that mistake. Amiri Quran, the same family's mushaf cut, draws the marks larger and rounder and stays legible at the same sizes. When a script carries meaning in its diacritics, test the *smallest* size the app draws it at (list rows, previews, captions), not only the hero size, and pick the cut for the smallest first.
- An explicit `add_theme_font_size_override` replaces the drawn size entirely -- a helper that "loads the font at size+8" is silently defeated by any override that names the base size. If a font needs script-dependent compensation (Amiri next to Vazirmatn wants roughly +8 px to match apparent size), the *override* must carry the compensated number, computed from the script, or the compensation never happens anywhere. Render the smallest real text and measure it before trusting that a size helper applied.
- When a font lacks an icon, draw it (`draw_colored_polygon`, `draw_arc`, `draw_polyline` inside a `_draw()` override) instead of hunting for a covering font or shipping an icon font for three shapes.
- Test with `godot --language <locale> --path <project>` and reset any committed locale test override.

- `TextEdit` cannot align its lines at all -- not by property (no `alignment`/`horizontal_alignment` exists; LineEdit and RichTextLabel have it, TextEdit does not), not by theme item, and the engine's own proposal queue has carried the gap for years. `text_direction = TEXT_DIRECTION_RTL` only sets the BiDi base and caret logic; rendering stays flush-left (verified pixel-wise on 4.7: AUTO and RTL draw identical flush-left ink). An RTL writing field needs the mirror-field pattern: a fully transparent `TextEdit` (font_color, caret_color, selection_color at alpha 0, `StyleBoxEmpty` for normal/focus/read_only) as the real input engine underneath, and one `RichTextLabel` per visual line above it showing the words flush right -- the engine's own `get_line_wrapped_text()` gives the visual lines (and their logical column offsets via `line.find(part, offset)`), `get_line_width(line, wrap_index)` gives each laid-out line's width, and `get_rect_at_line_column()` gives the caret's place inside the flush-left layout; slide both by `inner_width - line_width` to land at the right edge. The transparent editor must keep the same font, font size, and `line_spacing` as the mirror or the two layers drift apart.
- `RichTextLabel`'s alignment is relative to its base direction: under `TEXT_DIRECTION_RTL` the alignments are mirrored (RIGHT lands flush-LEFT), while under `TEXT_DIRECTION_AUTO` an RTL first strong letter makes RIGHT alignment flush-right (verified: Arabic AUTO+RIGHT = flush right, Arabic RTL+RIGHT = flush left). And AUTO is per *document*, not per paragraph -- a document mixing an Arabic verse, a Latin filename, and a Persian translation under one label resolves them all against one base. The mirror field therefore uses one label per visual line, each AUTO+RIGHT: every line takes its direction from its own first strong letter and still hugs the right edge, so a Latin `![002006.mp3](002006.mp3)` line inside an Arabic paragraph reads LTR inside a right-flush block.
- `TextEdit`'s caret geometry APIs are the contract that makes a mirror field honest: `get_rect_at_line_column(line, col)` returns the caret rect in the flush-left layout, `get_line_wrap_index_at_column()` maps a column to its visual wrap, and `get_line_wrapped_text()` returns logical-order chunks that concatenate (minus wrapped whitespace) back into the line. A selection maps by clamping its from/to columns into each visual chunk's [start, start+len) range.
- Escaping user text for RichTextLabel bbcode with `[lb]`/`[rb]` is a double-replace trap: `text.replace("[", "[lb]")` produces `[lb]` whose own `]` is then replaced again into `[lb[rb]`, and the mark renders literally. Replace through sentinel characters that cannot appear in the text (`\u0001`/`\u0002`), then swap the sentinels for the tags.
- Godot 4's `Container` has no `_sort_children` virtual (that is Godot 3); the fitting hook is the `sort_children` **signal** -- `container.sort_children.connect(_my_sort)` -- and `fit_child_in_rect(child, rect)` places children. `Control._get_minimum_size()` *is* a virtual that containers use for their minimum. A custom container that must react to its own size changes should also wire `resized`.
- A `ScrollContainer`'s minimum size includes its content's minimum in the axes where scrolling is disabled (`horizontal_scroll_mode = SCROLL_MODE_DISABLED` makes min width = content min width). That is how a centred, max-measure list inside a scroll still forces the scroll (and its whole ancestor chain) at least as wide as the list's measure.

## Official sources

- 2D: <https://docs.godotengine.org/en/4.7/tutorials/2d/index.html>
- 2D transforms: <https://docs.godotengine.org/en/4.7/tutorials/2d/2d_transforms.html>
- 2D parallax: <https://docs.godotengine.org/en/4.7/tutorials/2d/2d_parallax.html>
- 2D sprite animation: <https://docs.godotengine.org/en/4.7/tutorials/2d/2d_sprite_animation.html>
- TileMaps: <https://docs.godotengine.org/en/4.7/tutorials/2d/using_tilemaps.html>
- UI: <https://docs.godotengine.org/en/4.7/tutorials/ui/index.html>
- Anchors: <https://docs.godotengine.org/en/4.7/tutorials/ui/size_and_anchors.html>
- Containers: <https://docs.godotengine.org/en/4.7/tutorials/ui/gui_containers.html>
- Focus: <https://docs.godotengine.org/en/4.7/tutorials/ui/gui_navigation.html>
- Theming: <https://docs.godotengine.org/en/4.7/tutorials/ui/gui_skinning.html>
- Input: <https://docs.godotengine.org/en/4.7/tutorials/inputs/index.html>
- Input events: <https://docs.godotengine.org/en/4.7/tutorials/inputs/inputevent.html>
- Localization: <https://docs.godotengine.org/en/4.7/tutorials/i18n/internationalizing_games.html>
- Spreadsheet localization: <https://docs.godotengine.org/en/4.7/tutorials/i18n/localization_using_spreadsheets.html>
- Gettext localization: <https://docs.godotengine.org/en/4.7/tutorials/i18n/localization_using_gettext.html>
- Pseudolocalization: <https://docs.godotengine.org/en/4.7/tutorials/i18n/pseudolocalization.html>
