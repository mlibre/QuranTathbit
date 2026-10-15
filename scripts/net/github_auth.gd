class_name GitHubAuth
extends RefCounted
const HttpClientScript := preload("res://scripts/net/http_client.gd")

## GitHub sign-in with the OAuth device flow: the app shows a short code, the
## user types it at github.com/login/device on any device they trust, and the
## app polls until GitHub hands back a token. No browser redirect, no client
## secret, no embedded credentials -- the same flow on desktop, web and
## Android.
##
## The client id is public by design. Create one OAuth app per deployment
## (GitHub → Settings → Developer settings → OAuth Apps → New application,
## no callback URL needed for the device flow) and paste it below; with the
## id empty the app says so instead of failing mysteriously. Users who prefer
## can paste a classic token with `repo` scope instead, in Settings.

# Paste your OAuth app's client ID here (it is not a secret).
const CLIENT_ID := ""

const DEVICE_CODE_URL := "https://github.com/login/device/code"
const TOKEN_URL := "https://github.com/login/oauth/access_token"
const SCOPE := "repo"
const GRANT := "urn:ietf:params:oauth:grant-type:device_code"
const USER_AGENT := "QuranTathbit"

var client_id := CLIENT_ID

func is_configured() -> bool:
        return not client_id.strip_edges().is_empty()

## Start a flow. Returns {device_code, user_code, verification_uri, interval,
## expires_in}, or {error: "..."} when it could not start.
func begin(http: HttpClientScript) -> Dictionary:
        if not is_configured():
                return {"error": "no_client_id"}
        var response: Dictionary = await http.request_json(
                "POST",
                DEVICE_CODE_URL,
                {"User-Agent": USER_AGENT, "Accept": "application/json"},
                {"client_id": client_id, "scope": SCOPE}
        )
        if not bool(response.get("status", false)) or int(response.get("code", 0)) != 200:
                return {"error": "device_code_failed", "code": int(response.get("code", 0))}
        var data: Variant = JSON.parse_string(response.body.get_string_from_utf8())
        if typeof(data) != TYPE_DICTIONARY:
                return {"error": "device_code_unreadable"}
        return {
                "device_code": str(data.get("device_code", "")),
                "user_code": str(data.get("user_code", "")),
                "verification_uri": str(data.get("verification_uri", "https://github.com/login/device")),
                "interval": int(data.get("interval", 5)),
                "expires_in": int(data.get("expires_in", 900)),
        }

## Ask once. Returns {token: "..."} on success, {error: "..."} on failure,
## or {pending: true} while the user has not typed the code yet.
func poll(http: HttpClientScript, device_code: String) -> Dictionary:
        var response: Dictionary = await http.request_json(
                "POST",
                TOKEN_URL,
                {"User-Agent": USER_AGENT, "Accept": "application/json"},
                {"client_id": client_id, "device_code": device_code, "grant_type": GRANT}
        )
        var data: Variant = JSON.parse_string((response.body as PackedByteArray).get_string_from_utf8())
        if typeof(data) != TYPE_DICTIONARY:
                return {"error": "poll_failed", "code": int(response.get("code", 0))}
        if (data as Dictionary).has("access_token"):
                return {"token": str((data as Dictionary).access_token)}
        return {"error": str((data as Dictionary).get("error", "unknown"))}

## Who this token belongs to. Returns {login: "name"} or {error: ...}.
func whoami(http: HttpClientScript, token: String) -> Dictionary:
        var response: Dictionary = await http.request_json(
                "GET", "https://api.github.com/user", {"User-Agent": USER_AGENT, "Authorization": "Bearer " + token}
        )
        if int(response.get("code", 0)) != 200:
                return {"error": "whoami_failed", "code": int(response.get("code", 0))}
        var data: Variant = JSON.parse_string(response.body.get_string_from_utf8())
        if typeof(data) != TYPE_DICTIONARY or not data.has("login"):
                return {"error": "whoami_unreadable"}
        return {"login": str(data.login)}
