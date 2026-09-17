extends SceneTree

const DEFAULT_URL := "wss://korsan-game-production.up.railway.app"
const TIMEOUT_SECONDS := 15.0

var _peer: WebSocketMultiplayerPeer
var _elapsed := 0.0

func _initialize() -> void:
    var url := OS.get_environment("PARDEX_GAME_SERVER_URL").strip_edges()
    if url.is_empty():
        url = DEFAULT_URL

    _peer = WebSocketMultiplayerPeer.new()
    var err := _peer.create_client(url)
    if err != OK:
        push_error("PARDEX game server probe could not start: %s" % err)
        quit(1)
        return

    print("PARDEX_GAME_SERVER_PROBE connecting=%s" % url)

func _process(delta: float) -> bool:
    if _peer == null:
        return false

    _elapsed += delta
    _peer.poll()

    var status := _peer.get_connection_status()
    if status == MultiplayerPeer.CONNECTION_CONNECTED:
        print("PARDEX_GAME_SERVER_PROBE_CONNECTED peer_id=%s" % _peer.get_unique_id())
        _peer.close()
        quit(0)
        return false

    if status == MultiplayerPeer.CONNECTION_DISCONNECTED and _elapsed > 1.0:
        push_error("PARDEX game server probe disconnected before handshake completed.")
        quit(2)
        return false

    if _elapsed >= TIMEOUT_SECONDS:
        push_error("PARDEX game server probe timed out after %.1f seconds." % TIMEOUT_SECONDS)
        _peer.close()
        quit(3)

    return false
