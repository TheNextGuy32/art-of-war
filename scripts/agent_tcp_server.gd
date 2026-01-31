extends Node

const ARG_FLAG := "--agent-tcp"
const ARG_PORT_PREFIX := "--agent-tcp="
const ARG_PORT_FLAG := "--agent-tcp-port"
const ARG_PORT_PREFIX_ALT := "--agent-tcp-port="
const DEFAULT_PORT_START := 60111
const DEFAULT_PORT_COUNT := 20
const BIND_ADDRESS := "127.0.0.1"
const TMP_DIR := "res://tmp"

var _server: TCPServer
var _clients := {}
var _state := {}
var _enabled := false
var _game_controller: Node = null

func set_game_controller(node: Node) -> void:
	_game_controller = node

func set_state_value(key: String, value) -> void:
	_state[key] = value

func _ready() -> void:
	_game_controller = _resolve_game_controller()
	if _game_controller == null:
		for _i in range(60):
			await get_tree().process_frame
			_game_controller = _resolve_game_controller()
			if _game_controller != null:
				break
	var port_request = _parse_port_request(OS.get_cmdline_user_args())
	if port_request == null:
		return
	_enabled = true
	var port = _start_server(port_request)
	if port < 0:
		return
	set_process(true)
	print("AGENT_TCP_PORT=%d" % port)

func _process(_delta: float) -> void:
	if not _enabled or _server == null or not _server.is_listening():
		return
	while _server.is_connection_available():
		var peer = _server.take_connection()
		if peer == null:
			break
		peer.set_no_delay(true)
		_clients[peer.get_instance_id()] = {"peer": peer, "buffer": ""}
		if _game_controller != null and _game_controller.has_method("refresh_agent_state"):
			_game_controller.refresh_agent_state()
	var dead_ids := []
	for id in _clients.keys():
		var entry = _clients[id]
		var peer: StreamPeerTCP = entry["peer"]
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			dead_ids.append(id)
			continue
		var available := peer.get_available_bytes()
		if available <= 0:
			continue
		var data: Array = peer.get_partial_data(available)
		if data.size() < 2 or data[0] != OK:
			dead_ids.append(id)
			continue
		var chunk: String = data[1].get_string_from_utf8()
		entry["buffer"] += chunk
		var parts: PackedStringArray = entry["buffer"].split("\n")
		for i in range(parts.size() - 1):
			var line: String = parts[i].strip_edges()
			if line == "":
				continue
			_handle_line(peer, line)
		entry["buffer"] = parts[parts.size() - 1]
		_clients[id] = entry
	for id in dead_ids:
		_clients.erase(id)

func _parse_port_request(args: PackedStringArray):
	var enabled := false
	var port := 0
	for i in range(args.size()):
		var arg := args[i]
		if arg == ARG_FLAG:
			enabled = true
		elif arg.begins_with(ARG_PORT_PREFIX):
			enabled = true
			port = int(arg.substr(ARG_PORT_PREFIX.length()))
		elif arg == ARG_PORT_FLAG and i + 1 < args.size():
			enabled = true
			port = int(args[i + 1])
		elif arg.begins_with(ARG_PORT_PREFIX_ALT):
			enabled = true
			port = int(arg.substr(ARG_PORT_PREFIX_ALT.length()))
	if not enabled:
		return null
	if port <= 0:
		return 0
	return port

func _start_server(port_request: int) -> int:
	_server = TCPServer.new()
	var port := -1
	if port_request > 0:
		var err = _server.listen(port_request, BIND_ADDRESS)
		if err == OK:
			port = port_request
		else:
			push_error("Agent TCP server failed to listen on %d (err %d)" % [port_request, err])
			return -1
	else:
		port = _listen_on_range(DEFAULT_PORT_START, DEFAULT_PORT_COUNT)
		if port < 0:
			push_error("Agent TCP server failed to find a free port in range %d-%d" % [DEFAULT_PORT_START, DEFAULT_PORT_START + DEFAULT_PORT_COUNT - 1])
			return -1
	return port

func _listen_on_range(start_port: int, count: int) -> int:
	for offset in range(count):
		var candidate := start_port + offset
		var err = _server.listen(candidate, BIND_ADDRESS)
		if err == OK:
			return candidate
		_server.stop()
	return -1

func _handle_line(peer: StreamPeerTCP, line: String) -> void:
	var parsed = JSON.parse_string(line)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		_send_error(peer, null, "invalid_json", "Expected a JSON object per line.")
		return
	var msg: Dictionary = parsed
	var msg_id = msg.get("id", null)
	var msg_type := str(msg.get("type", ""))
	if msg_type == "command":
		_handle_command(peer, msg, msg_id)
	elif msg_type == "assert":
		_handle_assert(peer, msg, msg_id)
	else:
		_send_error(peer, msg_id, "unknown_type", "Unknown message type: %s" % msg_type)

func _handle_command(peer: StreamPeerTCP, msg: Dictionary, msg_id) -> void:
	var name := str(msg.get("name", ""))
	if name == "ping":
		_send_response(peer, msg_id, {"ok": true, "type": "pong"})
		return
	elif name == "set":
		if not msg.has("key"):
			_send_error(peer, msg_id, "missing_key", "Command 'set' requires 'key'.")
			return
		_state[msg["key"]] = msg.get("value", null)
		_send_response(peer, msg_id, {"ok": true})
		return
	elif name == "get":
		if not msg.has("key"):
			_send_error(peer, msg_id, "missing_key", "Command 'get' requires 'key'.")
			return
		var key = msg["key"]
		var value = _state.get(key, null)
		_send_response(peer, msg_id, {"ok": true, "value": value})
		return
	elif name == "clear":
		_state.clear()
		_send_response(peer, msg_id, {"ok": true})
		return
	elif name == "echo":
		_send_response(peer, msg_id, {"ok": true, "echo": msg.get("payload", null)})
		return
	elif name == "walk_to":
		var position = _parse_position(msg)
		if position == null:
			_send_error(peer, msg_id, "missing_position", "Command 'walk_to' requires 'position' or x/y/z.")
			return
		_state["last_walk_to"] = position
		_send_response(peer, msg_id, {"ok": true, "position": position})
		return
	elif name == "look_at":
		var target = msg.get("target", null)
		if target == null and msg.has("position"):
			target = msg["position"]
		if target == null:
			_send_error(peer, msg_id, "missing_target", "Command 'look_at' requires 'target' or 'position'.")
			return
		_state["last_look_at"] = target
		_send_response(peer, msg_id, {"ok": true, "target": target})
		return
	elif name == "screenshot":
		_handle_screenshot(peer, msg, msg_id)
		return
	elif name == "quit":
		_send_response(peer, msg_id, {"ok": true})
		get_tree().quit()
		return
	if _game_controller == null:
		_game_controller = _resolve_game_controller()
	if _game_controller != null and _game_controller.has_method("handle_agent_command"):
		var result = _game_controller.handle_agent_command(name, msg)
		if typeof(result) == TYPE_DICTIONARY and result.has("ok"):
			_send_response(peer, msg_id, result)
			return
	_send_error(peer, msg_id, "unknown_command", "Unknown command: %s" % name)

func _handle_assert(peer: StreamPeerTCP, msg: Dictionary, msg_id) -> void:
	var op := str(msg.get("op", "equals"))
	var actual = null
	if msg.has("key"):
		actual = _state.get(msg["key"], null)
	elif msg.has("actual"):
		actual = msg.get("actual", null)
	var expected = msg.get("expected", null)
	var ok := false
	if op == "equals":
		ok = actual == expected
	elif op == "exists":
		if msg.has("key"):
			ok = _state.has(msg["key"])
		else:
			ok = actual != null
	elif op == "truthy":
		ok = bool(actual)
	elif op == "contains":
		if typeof(actual) == TYPE_ARRAY:
			ok = actual.has(expected)
		elif typeof(actual) == TYPE_STRING:
			ok = str(actual).find(str(expected)) != -1
		elif typeof(actual) == TYPE_DICTIONARY and expected != null:
			ok = actual.has(expected)
		else:
			ok = false
	else:
		_send_error(peer, msg_id, "unknown_assert", "Unknown assert op: %s" % op)
		return
	if ok:
		_send_response(peer, msg_id, {"ok": true, "type": "assert_result", "op": op})
	else:
		_send_response(peer, msg_id, {"ok": false, "type": "assert_result", "op": op, "actual": actual, "expected": expected, "error": "Assertion failed."})

func _parse_position(msg: Dictionary):
	if msg.has("position"):
		return msg["position"]
	if msg.has("x") and msg.has("y"):
		var z_val = msg.get("z", 0)
		return [msg["x"], msg["y"], z_val]
	return null

func _handle_screenshot(peer: StreamPeerTCP, msg: Dictionary, msg_id) -> void:
	var filename_raw := str(msg.get("filename", msg.get("path", "")))
	if filename_raw == "":
		_send_error(peer, msg_id, "missing_filename", "Command 'screenshot' requires 'filename'.")
		return
	var description := str(msg.get("description", ""))
	if description == "":
		_send_error(peer, msg_id, "missing_description", "Command 'screenshot' requires 'description'.")
		return
	var filename := _sanitize_filename(filename_raw)
	if not filename.to_lower().ends_with(".png"):
		filename += ".png"
	var base_name := filename
	if base_name.find(".") != -1:
		base_name = base_name.get_basename()
	var description_name := "%s_description.txt" % base_name
	var dir_path := ProjectSettings.globalize_path(TMP_DIR)
	var screenshot_path := ProjectSettings.globalize_path("%s/%s" % [TMP_DIR, filename])
	var description_path := ProjectSettings.globalize_path("%s/%s" % [TMP_DIR, description_name])
	if not _ensure_dir(dir_path):
		_send_error(peer, msg_id, "dir_error", "Failed to create tmp directory.")
		return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var save_err := image.save_png(screenshot_path)
	if save_err != OK:
		_send_error(peer, msg_id, "save_error", "Failed to save screenshot.")
		return
	var file = FileAccess.open(description_path, FileAccess.WRITE)
	if file == null:
		_send_error(peer, msg_id, "save_error", "Failed to save description file.")
		return
	file.store_string(description)
	file.close()
	_send_response(peer, msg_id, {
		"ok": true,
		"type": "screenshot_saved",
		"path": screenshot_path,
		"description_path": description_path
	})

func _send_response(peer: StreamPeerTCP, msg_id, payload: Dictionary) -> void:
	if msg_id != null:
		payload["id"] = msg_id
	var text := JSON.stringify(payload)
	var data := text.to_utf8_buffer()
	peer.put_data(data)
	peer.put_data("\n".to_utf8_buffer())

func _send_error(peer: StreamPeerTCP, msg_id, code: String, message: String) -> void:
	_send_response(peer, msg_id, {"ok": false, "error": message, "code": code})

func _ensure_dir(path: String) -> bool:
	var err = DirAccess.make_dir_recursive_absolute(path)
	return err == OK or err == ERR_ALREADY_EXISTS

func _resolve_game_controller() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var grouped := tree.get_nodes_in_group("game_controller")
	if grouped.size() > 0:
		return grouped[0]
	var root := tree.get_root()
	if root == null:
		return null
	var main = root.get_node_or_null("Main")
	if main != null and main.has_method("handle_agent_command"):
		return main
	return _find_controller(root)

func _find_controller(node: Node) -> Node:
	if node.has_method("handle_agent_command"):
		return node
	for child in node.get_children():
		var found = _find_controller(child)
		if found != null:
			return found
	return null

func _sanitize_filename(name: String) -> String:
	var safe := ""
	for i in range(name.length()):
		var ch := name[i]
		var code := name.unicode_at(i)
		var is_alpha := (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
		var is_digit := code >= 48 and code <= 57
		if is_alpha or is_digit or ch == "_" or ch == "-" or ch == ".":
			safe += ch
		else:
			safe += "_"
	if safe == "":
		safe = "screenshot.png"
	return safe
