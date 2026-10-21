extends SceneTree
const HttpClientScript := preload("res://scripts/net/http_client.gd")

## The network client against a real socket. A local server answers on
## 127.0.0.1, and the client's requests must complete against it -- which
## is only possible while the HTTPRequest node sits inside the tree before
## request() is called. A node started outside the tree once died with
## ERR_UNCONFIGURED ("blob progress.json failed (0)") and a first sync died
## in front of the user; this suite keeps that from coming back by
## construction, not by convention.

var _failures := 0
var _server := TCPServer.new()
var _port := 0
var _served := 0


func _init() -> void:
        _run()


func _run() -> void:
        if _server.listen(0, "127.0.0.1") != OK:
                print("http: could not open a local server")
                print("http: 1 FAILURE(S)")
                quit(1)
                return
        _port = _server.get_local_port()

        # A SceneTree script's _init runs before the tree itself has started;
        # nodes added now have not entered it. Let one frame pass so the app's
        # own _ready-style timing is what the client runs under.
        await create_timer(0.1).timeout

        var http := HttpClientScript.new()
        root.add_child(http)

        # One request, answered by the socket.
        var one: Dictionary = await http.request("GET", _url("/one"))
        _ok(bool(one.status), "a single request completes against a real socket")
        _is(int(one.code), 200, "the single request sees HTTP 200")
        _is(one.body.get_string_from_utf8(), "one", "the single request reads its body")

        # And the next one after it, on its own node: the app asks for one
        # thing at a time, so two in a row must both land, each on a fresh
        # node that was in the tree before it asked.
        var second: Dictionary = await http.request("GET", _url("/two"))
        _ok(bool(second.status), "a second request lands on its own node")
        _is(second.body.get_string_from_utf8(), "two", "the second request reads its own body")

        # A request that cannot start answers false, not hangs.
        var bad: Dictionary = await http.request("GET", "not-a-url")
        _ok(not bool(bad.status), "a request that cannot start answers false")

        http.queue_free()
        _server.stop()

        if _failures > 0:
                print("http: %d FAILURE(S)" % _failures)
                quit(1)
        else:
                print("http: all checks passed")
                quit(0)


func _url(path: String) -> String:
        return "http://127.0.0.1:%d%s" % [_port, path]


func _ok(condition: bool, what: String) -> void:
        if not condition:
                _failures += 1
                print("  FAIL: %s" % what)


func _is(got: Variant, expected: Variant, what: String) -> void:
        if got != expected:
                _failures += 1
                print("  FAIL: %s — got %s, expected %s" % [what, str(got), str(expected)])


## Serve until every request the tests asked for has been answered. Each
## connection is one request; the path names the body it gets back.
func _process(_delta: float) -> bool:
        while _server.is_connection_available():
                _answer.call_deferred(_server.take_connection())
        return false


func _answer(peer: StreamPeerTCP) -> void:
        var request: String = await _read_request(peer)
        var path := "/"
        for line in request.split("\r\n"):
                if line.begins_with("GET "):
                        path = line.substr(4).split(" ")[0]
        var body := path.trim_prefix("/")
        var head: String = (
                "HTTP/1.1 200 OK\r\n"
                + "Content-Type: text/plain\r\n"
                + "Content-Length: %d\r\n"
                + "Connection: close\r\n\r\n"
        ) % body.length()
        peer.put_data((head + body).to_utf8_buffer())
        _served += 1


## Read one whole request head: poll until the blank line arrives.
func _read_request(peer: StreamPeerTCP) -> String:
        var got := ""
        var deadline := Time.get_ticks_msec() + 500
        while Time.get_ticks_msec() < deadline:
                peer.poll()
                if peer.get_available_bytes() > 0:
                        got += peer.get_utf8_string(peer.get_available_bytes())
                if got.contains("\r\n\r\n"):
                        return got
                await create_timer(0.01).timeout
        return got
