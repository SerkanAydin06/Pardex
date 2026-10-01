extends "res://scripts/online/pardex_online.gd"

# Keeps the short-lived game launch credential in memory only. The long-lived
# PARDEX identity never crosses the launcher -> game process boundary.
var _secure_game_start_payload: Dictionary = {}


func build_game_launch_args(expected_game_id: String) -> PackedStringArray:
	var args := PackedStringArray()
	if current_room.is_empty() or user_id.is_empty():
		return args

	var payload_game_id := str(
		_secure_game_start_payload.get("game_id", current_room.get("game_id", ""))
	).strip_edges()
	var match_id := str(
		_secure_game_start_payload.get("match_id", current_room.get("match_id", ""))
	).strip_edges()
	var launch_ticket := str(
		_secure_game_start_payload.get("launch_ticket", "")
	).strip_edges()
	if (
		payload_game_id != expected_game_id
		or match_id.is_empty()
		or launch_ticket.is_empty()
	):
		return args

	args.append("--pardex")
	args.append("--pardex-session=%s" % str(current_room.get("code", "")))
	args.append("--pardex-player=%s" % user_id)
	args.append("--pardex-name=%s" % display_name)
	args.append("--pardex-role=%s" % ("host" if is_room_host() else "client"))
	args.append("--pardex-url=%s" % get_active_server_url())
	args.append("--pardex-game-server=%s" % get_game_server_url())
	args.append("--pardex-match=%s" % match_id)
	args.append("--pardex-ticket=%s" % launch_ticket)

	# The child process now owns the one-time credential. Do not retain it in
	# launcher memory longer than necessary.
	_secure_game_start_payload.clear()
	return args


func report_game_launch_failed() -> void:
	if not is_online() or current_room.is_empty() or not bool(current_room.get("launching", false)):
		_secure_game_start_payload.clear()
		return
	var match_id := str(current_room.get("match_id", "")).strip_edges()
	var payload := {"type": "launch_failed"}
	if not match_id.is_empty():
		payload["match_id"] = match_id
	_send(payload)
	_secure_game_start_payload.clear()


func _handle_packet(packet: String) -> void:
	var parsed = JSON.parse_string(packet)
	if typeof(parsed) == TYPE_DICTIONARY:
		var message: Dictionary = parsed
		var message_type := str(message.get("type", ""))
		if message_type == "game_start":
			var incoming_match_id := str(message.get("match_id", "")).strip_edges()
			var incoming_ticket := str(message.get("launch_ticket", "")).strip_edges()
			if incoming_match_id.is_empty() or incoming_ticket.is_empty():
				_secure_game_start_payload.clear()
				var room_data = message.get("room", {})
				if typeof(room_data) == TYPE_DICTIONARY:
					current_room = (room_data as Dictionary).duplicate(true)
					report_game_launch_failed()
				online_error.emit("PARDEX güvenli oyun bileti alınamadı; oyun başlatılmadı.")
				return
			_secure_game_start_payload = message.duplicate(true)
		elif message_type == "room_state":
			var room_data = message.get("room", {})
			if typeof(room_data) == TYPE_DICTIONARY:
				var room_state := str((room_data as Dictionary).get("state", ""))
				if room_state in ["lobby", "ended", "closed"]:
					_secure_game_start_payload.clear()
		elif message_type == "left_room":
			_secure_game_start_payload.clear()

	super._handle_packet(packet)


func _clear_session_state() -> void:
	_secure_game_start_payload.clear()
	super._clear_session_state()
