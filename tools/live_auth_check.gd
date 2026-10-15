extends SceneTree

## Live proof of the sign-in path, run against GitHub's real servers with the
## real OAuth app id baked into GitHubAuth. Three checks:
##   1. begin() mints a real device/user code pair (HTTP 200).
##   2. poll() once with nobody entered: GitHub must answer the specific
##      error "authorization_pending" -- proof the token request is well
##      formed and the app id is accepted (a bad id returns invalid_client).
##   3. Optional: with QURAN_TATHBIT_LIVE_TOKEN holding a classic token,
##      whoami() must return the login it belongs to -- the same call every
##      sign-in path ends with. The token is read from the environment and
##      never written anywhere.
## Run:
##   timeout 90 godot --headless --path . --script tools/live_auth_check.gd
## Prints LIVE_AUTH_OK and exits 0 when all requested checks pass.

const GitHubAuthScript := preload("res://scripts/net/github_auth.gd")
const HttpClientScript := preload("res://scripts/net/http_client.gd")


func _init() -> void:
        var http = HttpClientScript.new()
        root.add_child(http)
        var auth = GitHubAuthScript.new()
        # The main loop must be running before HTTPRequest will fire.
        await process_frame

        if not auth.is_configured():
                print("FAIL: GitHubAuth has no client id")
                quit(1)
                return

        # 1. Mint a real flow.
        var began: Dictionary = await auth.begin(http)
        if not began.has("user_code") or not began.has("device_code"):
                print("FAIL: begin() did not mint codes: ", began)
                quit(1)
                return
        print("begin() OK: user_code=", began.user_code,
                " verification_uri=", began.verification_uri,
                " interval=", began.interval)

        # 2. Poll once, nobody has typed the code yet.
        var polled: Dictionary = await auth.poll(http, str(began.device_code))
        if str(polled.get("error", "")) != "authorization_pending":
                print("FAIL: expected authorization_pending, got: ", polled)
                quit(1)
                return
        print("poll() OK: GitHub accepted the token request shape")

        # 3. Optional whoami with a real token from the environment.
        var token := OS.get_environment("QURAN_TATHBIT_LIVE_TOKEN")
        if not token.strip_edges().is_empty():
                var who: Dictionary = await auth.whoami(http, token)
                if not who.has("login"):
                        print("FAIL: whoami with the provided token: ", who)
                        quit(1)
                        return
                print("whoami() OK: token belongs to @", who.login)

        print("LIVE_AUTH_OK")
        quit(0)
