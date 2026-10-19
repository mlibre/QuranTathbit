extends SceneTree

## Verify export_presets.cfg's html/head_include value is intact after the
## guards were appended: the value parses, carries every part, and did not
## swallow the keys that follow it (a stray double quote would terminate the
## value early and turn the rest of the section into garbage). Two shapes
## are demanded as well, both learned from a phone that sat at a silent
## loading bar: the value may carry no real line break (Godot's config
## parser turns a \n escape into one, and no JS string literal may span a
## line -- write \\n when the script means a newline), and every <script>
## the value opens must be closed before the next opens (a missing closer
## hands the next script's text to the JS parser, which dies on the literal
## '<' and takes both scripts with it). The notice builder must stand first
## among the scripts, so every later guard speaks through a builder that
## already exists.

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
                "qt-notice",
                "__qtNotice",
                "releases/latest/download/QuranTathbit-Android.apk",
                "qt-webgl2-guard",
                "__qtWebGL2Missing",
                "WebGL2RenderingContext",
                "status-notice",
                "qt-simd-guard",
                "__qtWasmSimdMissing",
                "qt-zip-bridge",
                "qt-paste-bridge",
                "qt-browser-keys",
                "qt-update-watch",
                "qt-boot-watch",
                "unhandledrejection",
                "controllerchange",
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
        # The notice builder must stand BEFORE every script that may speak
        # through it (the guards and the boot watch call __qtNotice), and the
        # WebGL2 guard must sit AFTER the wasm-gz shim, so the guard's fetch
        # wrapper wraps the shim's (and rejects wasm first).
        var notice_at := include.find("qt-notice")
        var shim_at := include.find("DecompressionStream")
        var guard_at := include.find("qt-webgl2-guard")
        if not (0 <= notice_at and notice_at < shim_at):
                push_error("the notice builder must be installed before the gz shim")
                failures += 1
        if not (0 <= shim_at and shim_at < guard_at):
                push_error("the guard must be installed after the gz shim")
                failures += 1
        # A newline inside the value is a JS string literal asked to span a
        # line: the config parser made it from a \n escape, and the browser
        # answers with a SyntaxError. The value is written on one line of the
        # cfg and must stay on one line in the page.
        if include.contains("\n"):
                push_error("head_include carries a real line break; a \\n escape in the cfg became one -- write \\\\n where a script means a newline")
                failures += 1
        # Every <script> the value opens must close before the next opens:
        # walking the tags, the depth may never pass one and must end at zero.
        # A missing closer merges two scripts into one (the JS then meets a
        # literal '<'); a stray closer ends the head early.
        var depth := 0
        var at := 0
        while true:
                var opens := include.find("<script>", at)
                var closes := include.find("</script>", at)
                if opens == -1 and closes == -1:
                        break
                if closes == -1 or (opens != -1 and opens < closes):
                        depth += 1
                        at = opens + 8
                        if depth > 1:
                                push_error("head_include opens a <script> before the last one closed; a </script> went missing")
                                failures += 1
                else:
                        depth -= 1
                        at = closes + 9
                        if depth < 0:
                                push_error("head_include closes a </script> that was never opened")
                                failures += 1
        if depth != 0:
                push_error("head_include ends with a <script> left open")
                failures += 1
        # The SIMD guard must sit AFTER the WebGL2 one, so a device missing
        # both hears the WebGL2 reason (the first guard to speak wins, and
        # the SIMD guard's say() stays quiet beside it).
        var simd_at := include.find("qt-simd-guard")
        if not (0 <= guard_at and guard_at < simd_at):
                push_error("the SIMD guard must be installed after the WebGL2 guard")
                failures += 1
        # The debug log is gone (v1.0.36): its five-tap overlay earned its
        # keep diagnosing the phone that sat in silence, and was retired the
        # release after -- nothing may quietly bring it back.
        if include.contains("qt-debug-log") or include.contains("__qtDebugShow"):
                push_error("the debug log was retired in v1.0.36; it must not return")
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
