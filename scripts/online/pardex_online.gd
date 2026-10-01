extends Node

signal connection_state_changed(state: String)
signal welcome_received(user_id: String, display_name: String)
signal room_state_changed(room: Dictionary)
signal room_left()
signal online_error(message: String)
signal game_start_requested(payload: Dictionary)
signal voice_frame_received(user_id: String, sequence: int, pcm_base64: String)
signal social_state_changed(state: Dictionary)
signal user_search_results(results: Array)
signal social_notice(message: String)
signal room_invite_received(invite: Dictionary)
signal room_invite_closed(invite_id: String, reason: String)
signal presence_changed(presence: String)
signal recovery_code_created(code: String)
signal account_recovered(account_id: String, display_name: String)
signal account_recovery_failed(message: String)

# Empty server_url = automatic: the host PC publishes its current tunnel
# address to online.json on the sunucu-adresi branch (host/pardex_host.js) and
# every client reads it from there, so friends never type an address.
const DEFAULT_SERVER_URL := ""
const ADDRESS_BOARD_URL := "https://api.github.com/repos/SerkanAydin06/Pardex/contents/online.json?ref=sunucu-adresi"
const ADDRESS_REFRESH_SECONDS := 65.0
const LEGACY_SERVER_URLS := [
	"ws://127.0.0.1:8765",
	"wss://pardex-online-production.up.railway.app",
]
const IDENTITY_PATH := "user://pardex_identity.cfg"
const RECONNECT_DELAY := 3.0
const HEARTBEAT_INTERVAL := 20.0
const SERVER_TIMEOUT := 60.0
const WEBSOCKET_OUTBOUND_BUFFER_SIZE := 262144
const VOICE_OUTBOUND_QUEUE_LIMIT := 32768
const VALID_PRESENCE := ["online", "away", "busy"]
const RECOVERY_HEX := "0123456789ABCDEF"

var server_url := DEFAULT_SERVER_URL
var _resolved_url := ""
var _address_age := INF
var _address_resolving := false
var _host_closed_reported := false
var _address_request: HTTPRequest
var display_name := "Pardus"
var user_id := ""
var account_id := ""
var identity_key := ""
var resume_token := ""
var current_room: Dictionary = {}
var social_state: Dictionary = {}
var pending_room_invite: Dictionary = {}
var connection_state := "offline"
var presence_status := "online"
var effective_presence := "offline"
var recovery_enabled := false

var _socket: WebSocketPeer
var _reconnect_elapsed := 0.0
var _heartbeat_elapsed := 0.0
var _server_silence_elapsed := 0.0
var _manual_disconnect := false
var _hello_sent := false
var _no_delay_configured := false
var _session_ready := false
var _pending_recovery_code := ""
var _pending_recovery_setup_code := ""


func _ready() -> void:
	_load_or_create_identity()


func _process(delta: float) -> void:
	_address_age += delta
	if _socket == null:
		if not _manual_disconnect and connection_state == "offline":
			_reconnect_elapsed += delta
			if _reconnect_elapsed >= RECONNECT_DELAY:
				_reconnect_elapsed = 0.0
				connect_server()
		return

	_socket.poll()
	var socket_state := _socket.get_ready_state()

	if socket_state == WebSocketPeer.STATE_OPEN:
		if not _no_delay_configured:
			_socket.set_no_delay(true)
			_no_delay_configured = true
		if not _hello_sent:
			_hello_sent = true
			_send_hello()

		_heartbeat_elapsed += delta
		_server_silence_elapsed += delta
		if _heartbeat_elapsed >= HEARTBEAT_INTERVAL:
			_heartbeat_elapsed = 0.0
			_send({"type": "ping"})
		if _server_silence_elapsed >= SERVER_TIMEOUT:
			_socket.close(4000, "PARDEX heartbeat timeout")
			return

		while _socket.get_available_packet_count() > 0:
			var packet := _socket.get_packet().get_string_from_utf8()
			_server_silence_elapsed = 0.0
			_handle_packet(packet)
	elif socket_state == WebSocketPeer.STATE_CLOSING:
		_session_ready = false
		_set_connection_state("connecting")
	elif socket_state == WebSocketPeer.STATE_CLOSED:
		var was_manual := _manual_disconnect
		_socket = null
		_hello_sent = false
		_no_delay_configured = false
		_session_ready = false
		_heartbeat_elapsed = 0.0
		_server_silence_elapsed = 0.0
		_set_effective_presence("offline")
		_set_connection_state("offline")
		if was_manual:
			_clear_session_state()
			_manual_disconnect = false


func configure(url: String, player_name: String) -> void:
	var normalized_url := url.strip_edges()
	server_url = DEFAULT_SERVER_URL if is_automatic_url(normalized_url) else normalized_url
	_address_age = INF
	var normalized_name := player_name.strip_edges()
	display_name = normalized_name.left(24) if not normalized_name.is_empty() else "Pardus"


func update_display_name(player_name: String) -> void:
	var normalized_name := player_name.strip_edges()
	display_name = normalized_name.left(24) if not normalized_name.is_empty() else "Pardus"
	if is_online():
		_send_hello()


func connect_server() -> void:
	if _socket != null and _socket.get_ready_state() in [WebSocketPeer.STATE_CONNECTING, WebSocketPeer.STATE_OPEN]:
		return
	if identity_key.is_empty():
		_load_or_create_identity()

	_manual_disconnect = false
	# GitHub allows 60 anonymous requests per hour, so the address is asked at
	# most about once a minute; in between the last known address is reused.
	if server_url.is_empty() and _address_age >= ADDRESS_REFRESH_SECONDS:
		_resolve_address()
		return
	var target_url := get_active_server_url()
	if target_url.is_empty():
		_set_connection_state("offline")
		return
	_hello_sent = false
	_no_delay_configured = false
	_session_ready = false
	_reconnect_elapsed = 0.0
	_heartbeat_elapsed = 0.0
	_server_silence_elapsed = 0.0
	_socket = WebSocketPeer.new()
	_socket.outbound_buffer_size = WEBSOCKET_OUTBOUND_BUFFER_SIZE
	var connection_error := _socket.connect_to_url(target_url)
	if connection_error != OK:
		_socket = null
		_set_connection_state("offline")
		online_error.emit("PARDEX Online sunucusuna bağlantı başlatılamadı.")
		return
	_set_connection_state("connecting")


static func is_automatic_url(url: String) -> bool:
	var clean := url.strip_edges()
	return clean.is_empty() or LEGACY_SERVER_URLS.has(clean)


func get_active_server_url() -> String:
	return _resolved_url if server_url.is_empty() else server_url


func _resolve_address() -> void:
	if _address_resolving:
		return
	if _address_request == null:
		_address_request = HTTPRequest.new()
		_address_request.timeout = 8.0
		add_child(_address_request)
		_address_request.request_completed.connect(_on_address_resolved)
	_address_resolving = true
	_set_connection_state("connecting")
	var board_url := OS.get_environment("PARDEX_ADDRESS_BOARD_URL").strip_edges()
	if board_url.is_empty():
		board_url = ADDRESS_BOARD_URL
	var headers := PackedStringArray(["Accept: application/vnd.github.raw+json", "Cache-Control: no-cache"])
	if _address_request.request(board_url, headers) != OK:
		_on_address_resolved(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())


func _on_address_resolved(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_address_resolving = false
	_address_age = 0.0
	var url := ""
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var data: Variant = JSON.parse_string(body.get_string_from_utf8())
		if data is Dictionary:
			url = str((data as Dictionary).get("online", "")).strip_edges()
	if url.begins_with("wss://") or url.begins_with("ws://"):
		_resolved_url = url
	elif result == HTTPRequest.RESULT_SUCCESS and code == 200:
		_resolved_url = ""
	if _resolved_url.is_empty():
		# The host PC is closed (or the board is unreachable): stay offline and
		# let the normal reconnect loop ask again.
		_set_connection_state("offline")
		if not _host_closed_reported:
			_host_closed_reported = true
			online_error.emit("PARDEX sunucusu şu anda kapalı.")
		return
	_host_closed_reported = false
	if not _manual_disconnect:
		connect_server()


func reconnect_server() -> void:
	_manual_disconnect = false
	_hello_sent = false
	_no_delay_configured = false
	_session_ready = false
	_reconnect_elapsed = 0.0
	_heartbeat_elapsed = 0.0
	_server_silence_elapsed = 0.0
	if _socket != null:
		_socket.close(1000, "PARDEX reconnect")
	_socket = null
	_set_effective_presence("offline")
	_set_connection_state("offline")
	connect_server()


func disconnect_server() -> void:
	_manual_disconnect = true
	_session_ready = false
	_heartbeat_elapsed = 0.0
	_server_silence_elapsed = 0.0
	if _socket != null:
		_socket.close(1000, "PARDEX closed")
	else:
		_clear_session_state()
		_set_effective_presence("offline")
		_set_connection_state("offline")
		_manual_disconnect = false


func create_room(game_id := "korsanlar", max_players := 4) -> void:
	if not is_online():
		online_error.emit("PARDEX Online bağlantısı henüz hazır değil.")
		return
	_send({"type": "create_room", "game_id": game_id, "max_players": clampi(max_players, 2, 8)})


func join_room(code: String) -> void:
	var normalized_code := code.strip_edges().to_upper()
	if normalized_code.is_empty():
		online_error.emit("Oda kodu boş bırakılamaz.")
		return
	if not is_online():
		online_error.emit("PARDEX Online bağlantısı henüz hazır değil.")
		return
	_send({"type": "join_room", "code": normalized_code})


func join_friend_room(target_account_id: String) -> void:
	var normalized_id := target_account_id.strip_edges()
	if normalized_id.is_empty():
		return
	if not is_online():
		social_notice.emit("Arkadaşının odasına katılmak için PARDEX Online hazır olmalı.")
		return
	_send({"type": "join_friend_room", "account_id": normalized_id})


func leave_room() -> void:
	if is_online():
		_send({"type": "leave_room"})


func set_ready(is_ready: bool) -> void:
	if is_online() and not current_room.is_empty():
		_send({"type": "set_ready", "ready": is_ready})


func request_start_game() -> void:
	if not is_online() or current_room.is_empty():
		online_error.emit("Oyunu başlatmak için aktif bir PARDEX odası gerekli.")
		return
	_send({"type": "start_game"})


func report_game_launch_failed() -> void:
	if not is_online() or current_room.is_empty() or not bool(current_room.get("launching", false)):
		return
	_send({"type": "launch_failed"})


func request_social_state() -> void:
	if is_online():
		_send({"type": "get_social_state"})


func search_users(query: String) -> void:
	var normalized := query.strip_edges()
	if normalized.length() < 2:
		user_search_results.emit([])
		return
	if not is_online():
		social_notice.emit("Kullanıcı aramak için PARDEX Online bağlantısının hazırlanmasını bekle.")
		return
	_send({"type": "search_users", "query": normalized.left(48)})


func set_presence_status(value: String) -> void:
	var normalized := value.strip_edges().to_lower()
	if normalized not in VALID_PRESENCE:
		return
	presence_status = normalized
	if is_online():
		_send({"type": "set_presence", "presence": presence_status})
	else:
		_set_effective_presence("offline")


func send_friend_request(target_account_id: String) -> void:
	_send_social_action("send_friend_request", target_account_id)


func accept_friend_request(target_account_id: String) -> void:
	_send_social_action("accept_friend_request", target_account_id)


func decline_friend_request(target_account_id: String) -> void:
	_send_social_action("decline_friend_request", target_account_id)


func cancel_friend_request(target_account_id: String) -> void:
	_send_social_action("cancel_friend_request", target_account_id)


func remove_friend(target_account_id: String) -> void:
	_send_social_action("remove_friend", target_account_id)


func send_room_invite(target_account_id: String) -> void:
	var normalized_id := target_account_id.strip_edges()
	if normalized_id.is_empty():
		return
	if not is_online():
		social_notice.emit("Oda daveti göndermek için PARDEX Online bağlantısı gerekli.")
		return
	if current_room.is_empty():
		social_notice.emit("Arkadaşını davet etmek için önce bir oda oluştur veya odaya katıl.")
		return
	_send({"type": "send_room_invite", "account_id": normalized_id})


func accept_room_invite(invite_id: String) -> void:
	var normalized_id := invite_id.strip_edges()
	if normalized_id.is_empty() or not is_online():
		return
	_send({"type": "accept_room_invite", "invite_id": normalized_id})


func decline_room_invite(invite_id: String) -> void:
	var normalized_id := invite_id.strip_edges()
	if normalized_id.is_empty() or not is_online():
		return
	_send({"type": "decline_room_invite", "invite_id": normalized_id})


func _send_social_action(action_type: String, target_account_id: String) -> void:
	var normalized_id := target_account_id.strip_edges()
	if normalized_id.is_empty() or not is_online():
		return
	_send({"type": action_type, "account_id": normalized_id})


func request_recovery_code() -> void:
	if not is_online():
		account_recovery_failed.emit("Kurtarma kodu oluşturmak için PARDEX Online bağlantısı gerekli.")
		return
	var recovery_code := _generate_recovery_code()
	_pending_recovery_setup_code = recovery_code
	var result := _send({"type": "set_recovery_code", "recovery_code": recovery_code})
	if result != OK:
		_pending_recovery_setup_code = ""
		account_recovery_failed.emit("Kurtarma kodu sunucuya gönderilemedi.")


func recover_account(recovery_code: String) -> void:
	if not current_room.is_empty():
		account_recovery_failed.emit("Hesap kurtarmadan önce aktif oyun odasından çıkmalısın.")
		return
	var normalized := _normalize_recovery_code(recovery_code)
	if normalized.is_empty():
		account_recovery_failed.emit("Kurtarma kodu biçimi geçersiz.")
		return
	_pending_recovery_setup_code = ""
	_pending_recovery_code = normalized
	resume_token = ""
	reconnect_server()


func set_voice_muted(is_muted: bool) -> void:
	if is_online() and not current_room.is_empty():
		_send({"type": "voice_state", "muted": is_muted})


func send_voice_frame(sequence: int, pcm_base64: String) -> void:
	if not is_online() or current_room.is_empty() or pcm_base64.is_empty():
		return
	if _socket != null and _socket.get_current_outbound_buffered_amount() >= VOICE_OUTBOUND_QUEUE_LIMIT:
		return
	_send({"type": "voice_frame", "seq": sequence, "pcm": pcm_base64})


func is_online() -> bool:
	return (
		_session_ready
		and not account_id.is_empty()
		and _socket != null
		and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN
		and connection_state == "online"
	)


func is_identity_ready() -> bool:
	return _session_ready and not account_id.is_empty()


func is_in_room() -> bool:
	return not current_room.is_empty()


func has_game_server_assignment() -> bool:
	var game_server_url := str(current_room.get("game_server_url", "")).strip_edges()
	return game_server_url.begins_with("ws://") or game_server_url.begins_with("wss://")


func get_game_server_url() -> String:
	return str(current_room.get("game_server_url", "")).strip_edges()


func is_room_host() -> bool:
	return not user_id.is_empty() and str(current_room.get("host_id", "")) == user_id


func build_game_launch_args(expected_game_id: String) -> PackedStringArray:
	var args := PackedStringArray()
	if current_room.is_empty() or user_id.is_empty():
		return args
	if str(current_room.get("game_id", "")) != expected_game_id:
		return args
	args.append("--pardex")
	args.append("--pardex-session=%s" % str(current_room.get("code", "")))
	args.append("--pardex-player=%s" % user_id)
	args.append("--pardex-account=%s" % account_id)
	args.append("--pardex-name=%s" % display_name)
	args.append("--pardex-role=%s" % ("host" if is_room_host() else "client"))
	args.append("--pardex-online-server=%s" % get_active_server_url())
	args.append("--pardex-game-server=%s" % get_game_server_url())
	return args


func _load_or_create_identity() -> void:
	var config := ConfigFile.new()
	if config.load(IDENTITY_PATH) == OK:
		var saved_key := str(config.get_value("identity", "key", "")).strip_edges().to_lower()
		if saved_key.length() == 64:
			identity_key = saved_key
			return
	var crypto := Crypto.new()
	identity_key = crypto.generate_random_bytes(32).hex_encode()
	config.set_value("identity", "key", identity_key)
	var result := config.save(IDENTITY_PATH)
	if result != OK:
		push_warning("PARDEX identity could not be saved: %s" % error_string(result))


func _generate_recovery_code() -> String:
	var hex_value := Crypto.new().generate_random_bytes(16).hex_encode().to_upper()
	var groups: PackedStringArray = []
	for offset in range(0, hex_value.length(), 4):
		groups.append(hex_value.substr(offset, 4))
	return "PX1-" + "-".join(groups)


func _normalize_recovery_code(value: String) -> String:
	var compact := value.strip_edges().to_upper()
	for separator in ["-", " ", "\t", "\n", "\r"]:
		compact = compact.replace(separator, "")
	if compact.length() != 35 or not compact.begins_with("PX1"):
		return ""
	for character in compact.substr(3):
		if RECOVERY_HEX.find(character) == -1:
			return ""
	return compact


func _send_hello() -> void:
	var payload := {
		"type": "hello",
		"display_name": display_name,
		"identity_key": identity_key,
		"presence_status": presence_status,
	}
	if not _pending_recovery_code.is_empty():
		payload["recovery_code"] = _pending_recovery_code
	elif not resume_token.is_empty():
		payload["resume_token"] = resume_token
	_send(payload)


func _send(payload: Dictionary) -> Error:
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNAVAILABLE
	var result := _socket.send_text(JSON.stringify(payload))
	if result != OK and str(payload.get("type", "")) != "voice_frame":
		push_warning("PARDEX WebSocket send failed: %s" % error_string(result))
	return result


func _handle_packet(packet: String) -> void:
	var parsed = JSON.parse_string(packet)
	if typeof(parsed) != TYPE_DICTIONARY:
		online_error.emit("Sunucudan geçersiz veri alındı.")
		return

	var message: Dictionary = parsed
	var message_type := str(message.get("type", ""))
	match message_type:
		"welcome":
			var previous_user_id := user_id
			var had_room := not current_room.is_empty()
			var recovered := bool(message.get("recovered", false))
			user_id = str(message.get("user_id", ""))
			account_id = str(message.get("account_id", account_id))
			resume_token = str(message.get("resume_token", ""))
			display_name = str(message.get("display_name", display_name))
			recovery_enabled = bool(message.get("recovery_enabled", recovery_enabled))
			_session_ready = not account_id.is_empty() and not user_id.is_empty()
			if not _session_ready:
				online_error.emit("PARDEX kimliği sunucudan alınamadı.")
				return
			if had_room and not previous_user_id.is_empty() and user_id != previous_user_id:
				current_room.clear()
				room_left.emit()
				online_error.emit("Önceki PARDEX odası geri yüklenemedi. Yeniden katılman gerekiyor.")
			_set_connection_state("online")
			welcome_received.emit(user_id, display_name)
			if recovered:
				_pending_recovery_code = ""
				account_recovered.emit(account_id, display_name)
			if bool(message.get("social_enabled", false)):
				request_social_state()
		"recovery_code_saved":
			recovery_enabled = bool(message.get("recovery_enabled", true))
			var saved_code := _pending_recovery_setup_code
			_pending_recovery_setup_code = ""
			if not saved_code.is_empty():
				recovery_code_created.emit(saved_code)
		"presence_state":
			_set_effective_presence(str(message.get("presence", presence_status)))
		"social_state":
			var state_data = message.get("state", {})
			if typeof(state_data) == TYPE_DICTIONARY:
				social_state = (state_data as Dictionary).duplicate(true)
				var self_data = social_state.get("self", {})
				if typeof(self_data) == TYPE_DICTIONARY:
					_set_effective_presence(str((self_data as Dictionary).get("presence", presence_status)))
				social_state_changed.emit(social_state.duplicate(true))
		"user_search_results":
			var results_data = message.get("results", [])
			if typeof(results_data) == TYPE_ARRAY:
				user_search_results.emit((results_data as Array).duplicate(true))
		"social_notice":
			social_notice.emit(str(message.get("message", "PARDEX sosyal işlemi tamamlandı.")))
		"room_invite":
			var invite_data = message.get("invite", {})
			if typeof(invite_data) == TYPE_DICTIONARY:
				pending_room_invite = (invite_data as Dictionary).duplicate(true)
				room_invite_received.emit(pending_room_invite.duplicate(true))
		"room_invite_closed":
			var closed_id := str(message.get("invite_id", ""))
			var reason := str(message.get("reason", "closed"))
			if str(pending_room_invite.get("id", "")) == closed_id:
				pending_room_invite.clear()
			room_invite_closed.emit(closed_id, reason)
		"room_state":
			var room_data = message.get("room", {})
			if typeof(room_data) == TYPE_DICTIONARY:
				current_room = (room_data as Dictionary).duplicate(true)
				room_state_changed.emit(current_room.duplicate(true))
		"game_start":
			var game_room_data = message.get("room", {})
			if typeof(game_room_data) == TYPE_DICTIONARY:
				current_room = (game_room_data as Dictionary).duplicate(true)
				room_state_changed.emit(current_room.duplicate(true))
			game_start_requested.emit(message.duplicate(true))
		"voice_frame":
			var sender_id := str(message.get("user_id", ""))
			var sequence := int(message.get("seq", 0))
			var pcm_base64 := str(message.get("pcm", ""))
			if not sender_id.is_empty() and not pcm_base64.is_empty():
				voice_frame_received.emit(sender_id, sequence, pcm_base64)
		"left_room":
			current_room.clear()
			room_left.emit()
		"error":
			var error_message := str(message.get("message", "Bilinmeyen PARDEX Online hatası."))
			var error_code := str(message.get("code", ""))
			if not _pending_recovery_code.is_empty() and error_code in ["INVALID_RECOVERY_CODE", "RECOVERY_SAVE_FAILED", "INVALID_IDENTITY"]:
				_pending_recovery_code = ""
				account_recovery_failed.emit(error_message)
			if not _pending_recovery_setup_code.is_empty() and error_code.begins_with("RECOVERY_"):
				_pending_recovery_setup_code = ""
				account_recovery_failed.emit(error_message)
			online_error.emit(error_message)
			social_notice.emit(error_message)
		"pong":
			pass


func _clear_session_state() -> void:
	user_id = ""
	resume_token = ""
	_session_ready = false
	social_state.clear()
	social_state_changed.emit({})
	_set_effective_presence("offline")
	if not pending_room_invite.is_empty():
		var invite_id := str(pending_room_invite.get("id", ""))
		pending_room_invite.clear()
		room_invite_closed.emit(invite_id, "disconnected")
	if not current_room.is_empty():
		current_room.clear()
		room_left.emit()


func _set_effective_presence(value: String) -> void:
	var normalized := value.strip_edges().to_lower()
	if normalized.is_empty():
		normalized = "offline"
	if effective_presence == normalized:
		return
	effective_presence = normalized
	presence_changed.emit(effective_presence)


func _set_connection_state(new_state: String) -> void:
	if connection_state == new_state:
		return
	connection_state = new_state
	connection_state_changed.emit(connection_state)
