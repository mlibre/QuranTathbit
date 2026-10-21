class_name HttpClient
extends Node

## One HTTP client for the whole app, made of throwaway HTTPRequest nodes.
## Everything that talks to the network goes through here, and everything
## that takes a client takes an HttpClient -- tests hand it a fake with the
## same request() shape and no network at all. One client, one request at
## a time: the app never asks the network for two things at once, because
## a parallel answer can race the very files it carries.
##
## Returns {status: bool, code: int, headers: Dictionary, body: PackedByteArray}.
## status is false when the request never completed (no network, refused,
## timed out).

const TIMEOUT := 30.0

# HTTPRequest takes HTTPClient.Method enum values, not verb strings.
const METHODS := {
        "GET": HTTPClient.METHOD_GET,
        "HEAD": HTTPClient.METHOD_HEAD,
        "POST": HTTPClient.METHOD_POST,
        "PUT": HTTPClient.METHOD_PUT,
        "DELETE": HTTPClient.METHOD_DELETE,
        "PATCH": HTTPClient.METHOD_PATCH,
}

func request(
        method: String,
        url: String,
        headers: Dictionary = {},
        body: PackedByteArray = PackedByteArray()
) -> Dictionary:
        var node := HTTPRequest.new()
        node.timeout = TIMEOUT
        add_child(node)
        var flat := PackedStringArray()
        for key in headers.keys():
                flat.append("%s: %s" % [str(key), str(headers[key])])
        var verb: int = METHODS.get(method.strip_edges().to_upper(), HTTPClient.METHOD_GET)
        var err := node.request(url, flat, verb, body.get_string_from_utf8())
        if err != OK:
                push_error("HttpClient: %s %s could not start (%s)" % [method, url, error_string(err)])
                node.queue_free()
                return _failed_result()
        var outcome: Array = await node.request_completed
        node.queue_free()
        return _outcome(outcome)


static func _failed_result() -> Dictionary:
        return {
                "status": false,
                "code": 0,
                "headers": {},
                "body": PackedByteArray(),
        }


## outcome is [result, code, headers, body] as request_completed emits it.
static func _outcome(outcome: Array) -> Dictionary:
        # outcome[0] is a result enum, not a bool: RESULT_SUCCESS is 0, and a
        # bare cast would read it as false -- inverting every answer.
        var ok: bool = int(outcome[0]) == HTTPRequest.RESULT_SUCCESS
        var code: int = outcome[1]
        # HTTPRequest reports headers as "Name: value" lines; flatten them into
        # the dictionary the rest of the app expects.
        var response_headers := {}
        for line in outcome[2] as PackedStringArray:
                var sep := line.find(":")
                if sep > 0:
                        response_headers[line.substr(0, sep).to_lower()] = line.substr(sep + 1).strip_edges()
        var response_body: PackedByteArray = outcome[3]
        return {
                "status": ok,
                "code": code,
                "headers": response_headers,
                "body": response_body,
        }


## A request whose body is JSON text.
func request_json(
        method: String,
        url: String,
        headers: Dictionary = {},
        payload: Variant = null
) -> Dictionary:
        var full := headers.duplicate()
        if not full.has("Accept"):
                full["Accept"] = "application/vnd.github+json"  # callers may bring their own
        full["Content-Type"] = "application/json"
        var body := PackedByteArray()
        if payload != null:
                body = JSON.stringify(payload).to_utf8_buffer()
        var response: Dictionary = await request(method, url, full, body)
        return response


## A request for raw file bytes (deck content), not JSON.
func request_raw(
        method: String,
        url: String,
        headers: Dictionary = {},
        body: PackedByteArray = PackedByteArray()
) -> Dictionary:
        return await request(method, url, headers, body)
