extends SceneTree

## Verify export_presets.cfg's html/head_include value is intact after the
## guard was appended: the value parses, carries the guard's working parts,
## and did not swallow the keys that follow it (a stray double quote would
## terminate the value early and turn the rest of the section into garbage).

func _init() -> void:
        var cfg := ConfigFile.new()
        var err := cfg.load("res://export_presets.cfg")
        if err != OK:
                push_error("export_presets.cfg failed to parse: %d" % err)
                quit(1)
                return
        var include := str(cfg.get_value("preset.0.options", "html/head_include", ""))
        var failures := 0
        for part in [
                "qt-webgl2-guard",
                "__qtWebGL2Missing",
                "WebGL2RenderingContext",
                "status-notice",
                "qt-zip-bridge",
                "qt-paste-bridge",
                "qt-browser-keys",
                "qt-update-watch",
                "index.wasm.gz",
        ]:
                if not include.contains(part):
                        push_error("head_include lost its part: %s" % part)
                        failures += 1
        # A value that ended early at a stray quote would drag the following
        # keys into itself; the keys must still stand on their own.
        for key in ["html/canvas_resize_policy", "html/focus_canvas_on_start", "progressive_web_app/enabled"]:
                if not cfg.has_section_key("preset.0.options", key):
                        push_error("head_include swallowed its sibling key: %s" % key)
                        failures += 1
        var resize: int = cfg.get_value("preset.0.options", "html/canvas_resize_policy", -1)
        if int(resize) != 2:
                push_error("canvas_resize_policy lost its value: %s" % str(resize))
                failures += 1
        # The guard must sit AFTER the wasm-gz shim in the string, so the
        # guard's fetch wrapper wraps the shim's (and rejects wasm first).
        var shim_at := include.find("DecompressionStream")
        var guard_at := include.find("qt-webgl2-guard")
        if not (0 <= shim_at and shim_at < guard_at):
                push_error("the guard must be installed after the gz shim")
                failures += 1
        # The Android preset: both ABIs, and the version code moved.
        var v7a: bool = cfg.get_value("preset.3.options", "architectures/armeabi-v7a", false)
        var v8a: bool = cfg.get_value("preset.3.options", "architectures/arm64-v8a", false)
        if not (v7a and v8a):
                push_error("the Android preset must ship both 32- and 64-bit")
                failures += 1
        var code := int(cfg.get_value("preset.3.options", "version/code", 0))
        if code < 13:
                push_error("the Android version code must move past 12")
                failures += 1
        print("export_presets.cfg: %s (guard at %d of %d chars; android code %d)" % [
                "OK" if failures == 0 else "BROKEN", guard_at, include.length(), code,
        ])
        quit(1 if failures > 0 else 0)
