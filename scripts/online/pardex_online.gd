extends Node

signal connection_state_changed(state: String)
signal welcome_received(user_id: String, display_name: String)
signal room_state_changed(room: Dictionary)
signal room_left()
signal online_error(message: String)

const DEFAULT_SERVER_URL := "wss://pardex-online-production.up.railway.app"
const LEGACY_LOCAL_SERVER_URL := "ws://127.0.0.1:8765"
const RECONNECT_DELAY := 3.0
const HEARTBEAT_INTERVAL := 20.0
const SERVER_TIMEOUT := 60.0

var server_url := DEFAULT_SERVER_URL
var display_name := "Pardus"
var user_id := ""
var current_room: Dictionary = {}
var connection_state := "offline"

var _socket: WebSocketPeer
var _reconnect_elapsed := 0.0
var _heartbeat_elapsed := 0.0
var _server_silence_elapsed := 0.0
var _manual_disconnect := false
var _hello_sent := false

func _process(delta: float) -> void:
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
        if connection_state != "online":
            _set_connection_state("online")
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
        _set_connection_state("connecting")
    elif socket_state == WebSocketPeer.STATE_CLOSED:
        var was_manual := _manual_disconnect
        _socket = null
        _hello_sent = false
        _heartbeat_elapsed = 0.0
        _server_silence_elapsed = 0.0
        user_id = ""
        if not current_room.is_empty():
            current_room.clear()
            room_left.emit()
        _set_connection_state("offline")
        if was_manual:
            _manual_disconnect = false

func configure(url: String, player_name: String) -> void:
    var normalized_url := url.strip_edges()
    if normalized_url.is_empty() or normalized_url == LEGACY_LOCAL_SERVER_URL:
        server_url = DEFAULT_SERVER_URL
    else:
        server_url = normalized_url

    var normalized_name := player_name.strip_edges()
    display_name = normalized_name.left(24) if not normalized_name.is_empty() else "Pardus"

func update_display_name(player_name: String) -> void:
    var normalized_name := player_name.strip_edges()
    display_name = normalized_name.left(24) if not normalized_name.is_empty() else "Pardus"
    if is_online():
        _send_hello()

func connect_server() -> void:
    if _socket != null and _socket.get_ready_state() in [
        WebSocketPeer.STATE_CONNECTING,
        WebSocketPeer.STATE_OPEN,
    ]:
        return

    _manual_disconnect = false
    _hello_sent = false
    _reconnect_elapsed = 0.0
    _heartbeat_elapsed = 0.0
    _server_silence_elapsed = 0.0
    _socket = WebSocketPeer.new()
    var connection_error := _socket.connect_to_url(server_url)
    if connection_error != OK:
        _socket = null
        _set_connection_state("offline")
        online_error.emit("PARDEX Online sunucusuna bağlantı başlatılamadı.")
        return
    _set_connection_state("connecting")

func reconnect_server() -> void:
    _manual_disconnect = false
    _hello_sent = false
    _reconnect_elapsed = 0.0
    _heartbeat_elapsed = 0.0
    _server_silence_elapsed = 0.0
    if _socket != null:
        _socket.close(1000, "PARDEX reconnect")
    _socket = null
    user_id = ""
    if not current_room.is_empty():
        current_room.clear()
        room_left.emit()
    _set_connection_state("offline")
    connect_server()

func disconnect_server() -> void:
    _manual_disconnect = true
    _heartbeat_elapsed = 0.0
    _server_silence_elapsed = 0.0
    if _socket != null:
        _socket.close(1000, "PARDEX closed")
    else:
        _set_connection_state("offline")

func create_room(game_id := "korsanlar", max_players := 4) -> void:
    if not is_online():
        online_error.emit("PARDEX Online bağlantısı yok.")
        return
    _send({
        "type": "create_room",
        "game_id": game_id,
        "max_players": clampi(max_players, 2, 8),
    })

func join_room(code: String) -> void:
    var normalized_code := code.strip_edges().to_upper()
    if normalized_code.is_empty():
        online_error.emit("Oda kodu boş bırakılamaz.")
        return
    if not is_online():
        online_error.emit("PARDEX Online bağlantısı yok.")
        return
    _send({
        "type": "join_room",
        "code": normalized_code,
    })

func leave_room() -> void:
    if not is_online():
        return
    _send({"type": "leave_room"})

func set_ready(is_ready: bool) -> void:
    if not is_online() or current_room.is_empty():
        return
    _send({
        "type": "set_ready",
        "ready": is_ready,
    })

func is_online() -> bool:
    return (
        _socket != null
        and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN
        and connection_state == "online"
    )

func is_in_room() -> bool:
    return not current_room.is_empty()

func _send_hello() -> void:
    _send({
        "type": "hello",
        "display_name": display_name,
    })

func _send(payload: Dictionary) -> void:
    if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
        return
    _socket.send_text(JSON.stringify(payload))

func _handle_packet(packet: String) -> void:
    var parsed = JSON.parse_string(packet)
    if typeof(parsed) != TYPE_DICTIONARY:
        online_error.emit("Sunucudan geçersiz veri alındı.")
        return

    var message: Dictionary = parsed
    var message_type := str(message.get("type", ""))

    match message_type:
        "welcome":
            user_id = str(message.get("user_id", ""))
            display_name = str(message.get("display_name", display_name))
            welcome_received.emit(user_id, display_name)
        "room_state":
            var room_data = message.get("room", {})
            if typeof(room_data) == TYPE_DICTIONARY:
                current_room = (room_data as Dictionary).duplicate(true)
                room_state_changed.emit(current_room.duplicate(true))
        "left_room":
            current_room.clear()
            room_left.emit()
        "error":
            online_error.emit(str(message.get("message", "Bilinmeyen PARDEX Online hatası.")))
        "pong":
            pass

func _set_connection_state(new_state: String) -> void:
    if connection_state == new_state:
        return
    connection_state = new_state
    connection_state_changed.emit(connection_state)
