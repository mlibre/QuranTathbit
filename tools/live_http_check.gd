extends SceneTree

## One live request through the app's own HttpClient, so the network path is
## proven outside the tests' fakes. A bogus client id is fine: any HTTP status
## back from GitHub means the request pipeline works. Run:
##   timeout 60 godot --headless --path . --script tools/live_http_check.gd

const HttpClientScript := preload("res://scripts/net/http_client.gd")

func _init() -> void:
        var http = HttpClientScript.new()
        root.add_child(http)
        # The main loop must be running before HTTPRequest will fire: it needs
        # to be inside a started tree, so wait one process frame.
        await process_frame
        var response: Dictionary = await http.request_json(
                "POST",
                "https://github.com/login/device/code",
                {"User-Agent": "QuranTathbit", "Accept": "application/json"},
                {"client_id": "00000000000000000000", "scope": "repo"}
        )
        print("status=", response.get("status"), " code=", response.get("code"))
        print("body head: ", (response.get("body", PackedByteArray()) as PackedByteArray).slice(0, 120).get_string_from_utf8())
        if int(response.get("code", 0)) != 0:
                print("LIVE_HTTP_OK")
                quit(0)
        else:
                print("LIVE_HTTP_FAILED")
                quit(1)
