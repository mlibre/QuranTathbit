extends SceneTree
const HttpClientScript := preload("res://scripts/net/http_client.gd")

## The network client against a real socket. A local server answers on
## 127.0.0.1, and the client's single and batch requests must both complete
## against it -- which is only possible while every HTTPRequest node sits
## inside the tree before request() is called. The batch path once started
## its nodes outside the tree (ERR_UNCONFIGURED, "blob progress.json
## failed (0)"), and a first sync died in front of the user; this suite keeps
## that from coming back by construction, not by convention.

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

        # A batch of three, all in flight at once, answered in order.
        var batch: Array = await http.request_many([
                {"method": "GET", "url": _url("/first")},
                {"method": "GET", "url": _url("/second")},
                {"method": "GET", "url": _url("/third")},
        ])
        _ok(batch.size() == 3, "the batch returns one answer per request")
        _ok(batch.all(func(r: Dictionary) -> bool: return bool(r.status)), "every batched request completes")
        _is(batch[0].body.get_string_from_utf8(), "first", "answers keep the order of the asks (1)")
        _is(batch[1].body.get_string_from_utf8(), "second", "answers keep the order of the asks (2)")
        _is(batch[2].body.get_string_from_utf8(), "third", "answers keep the order of the asks (3)")

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
