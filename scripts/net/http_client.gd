class_name HttpClient
extends Node

## One HTTP client for the whole app, made of a pool of throwaway
## HTTPRequest nodes so calls can overlap. Everything that talks to the
## network goes through here, and everything that takes a client takes an
## HttpClient -- tests hand it a fake with the same request() shape and no
## network at all.
##
## Returns {status: bool, code: int, headers: Dictionary, body: PackedByteArray}.
## status is false when the request never completed (no network, refused).

func request(
	method: String,
	url: String,
	headers: Dictionary = {},
	body: PackedByteArray = PackedByteArray()
) -> Dictionary:
	var node := HTTPRequest.new()
	node.name = "HttpRequest"
	add_child(node)
	var outcome: Array = await node.request_completed
	node.queue_free()
	var ok: bool = outcome[0]
	var code: int = outcome[1]
	var response_headers: Dictionary = outcome[2]
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
	full["Accept"] = "application/vnd.github+json"
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
