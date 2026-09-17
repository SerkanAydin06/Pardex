extends Node

signal connection_state_changed(state: String)
signal welcome_received(user_id: String, display_name: String)
signal room_state_changed(room: Dictionary)
signal room_left()
signal online_error(message: String)

const DEFAULT_SERVER_URL := "ws://127.0.0.1:8765"
const RECONNECT_DELAY := 3.0

var server_url := DEFAULT_SERVER_URL
var display_name := "Pardus"
var user_id := ""
var current_room: Dictionary = {}
var connection_state := "offline"

var _socket: WebSocketPeer
var _reconnect_elapsed := 0.0
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
    var ready_state := _socket.get_ready_state()

    if ready_state == WebSocketPeer.STATE_OPEN:
        if connection_state != "online":
            _set_connection_state("online")
        if not _hello_sent:
            _hello_sent = true
            _send({
                "type": "hello",
                "display_name": display_name,
            })
        while _socket.get_available_packet_count() > 0:
            var packet := _socket.get_packet().get_string_from_utf8()
            _handle_packet(packet)
    elif ready_state == WebSocketPeer.STATE_CLOSING:
        _set_connection_state("connecting")
    elif ready_state == WebSocketPeer.STATE_CLOSED:
        var was_manual := _manual_disconnect
        _socket = null
        _hello_sent = false
        user_id = ""
        current_room.clear()
        _set_connection_state("offline")
        if was_manual:
            _manual_disconnect = false

func configure(url: String, player_name: String) -> void:
    var normalized_url := url.strip_edges()
    server_url = normalized_url if not normalized_url.is_empty() else DEFAULT_SERVER_URL

    var normalized_name := player_name.strip_edges()
    display_name = normalized_name.left(24) if not normalized_name.is_empty() else "Pardus"

func connect_server() -> void:
    if _socket != null and _socket.get_ready_state() in [
        WebSocketPeer.STATE_CONNECTING,
        WebSocketPeer.STATE_OPEN,
    ]:
        return

    _manual_disconnect = false
    _hello_sent = false
    _reconnect_elapsed = 0.0
    _socket = WebSocketPeer.new()
    var error := _socket.connect_to_url(server_url)
    if error != OK:
        _socket = null
        _set_connection_state("offline")
        online_error.emit("PARDEX Online sunucusuna bağlantı başlatılamadı.")
        return
    _set_connection_state("connecting")

func disconnect_server() -> void:
    _manual_disconnect = true
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

func set_ready(ready: bool) -> void:
    if not is_online() or current_room.is_empty():
        return
    _send({
        "type": "set_ready",
        "ready": ready,
    })

func is_online() -> bool:
    return (
        _socket != null
        and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN
        and connection_state == "online"
    )

func is_in_room() -> bool:
    return not current_room.is_empty()

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
            var room = message.get("room", {})
            if typeof(room) == TYPE_DICTIONARY:
                current_room = (room as Dictionary).duplicate(true)
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
