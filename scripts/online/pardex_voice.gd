extends Node

signal voice_activity_changed(user_id: String, speaking: bool)
signal voice_settings_changed(microphone_muted: bool, output_muted: bool)
signal voice_channel_state_changed(active: bool)

const CAPTURE_BUS := "PARDEX_MIC"
const TARGET_SAMPLE_RATE := 16000
const PACKET_SECONDS := 0.08
const SPEAKING_THRESHOLD := 0.018
const SPEAKING_HOLD_MS := 280
const PLAYBACK_BUFFER_SECONDS := 0.35

var microphone_muted := false
var output_muted := false

var _capture: AudioEffectCapture
var _microphone_player: AudioStreamPlayer
var _capture_frames_per_packet := 0
var _sequence := 0
var _channel_active := false
var _remote_players: Dictionary = {}
var _last_sequence_by_user: Dictionary = {}
var _speaking_by_user: Dictionary = {}
var _speaking_deadline_ms: Dictionary = {}


func _ready() -> void:
    PardexOnline.room_state_changed.connect(_on_room_state_changed)
    PardexOnline.room_left.connect(_on_room_left)
    PardexOnline.voice_frame_received.connect(_on_voice_frame_received)


func _process(_delta: float) -> void:
    if _channel_active:
        _capture_microphone_packet()
    _expire_speaking_states()


func toggle_microphone() -> void:
    set_microphone_muted(not microphone_muted)


func set_microphone_muted(value: bool) -> void:
    if microphone_muted == value:
        return
    microphone_muted = value
    if microphone_muted and not PardexOnline.user_id.is_empty():
        _set_speaking(PardexOnline.user_id, false)
    if PardexOnline.is_in_room():
        PardexOnline.set_voice_muted(microphone_muted)
    voice_settings_changed.emit(microphone_muted, output_muted)


func toggle_output_muted() -> void:
    output_muted = not output_muted
    for entry in _remote_players.values():
        var player := entry.get("player") as AudioStreamPlayer
        if player != null:
            player.stream_paused = output_muted
    voice_settings_changed.emit(microphone_muted, output_muted)


func is_user_speaking(user_id: String) -> bool:
    return bool(_speaking_by_user.get(user_id, false))


func is_channel_active() -> bool:
    return _channel_active


func _on_room_state_changed(room: Dictionary) -> void:
    if room.is_empty():
        _stop_voice_channel()
        return

    _start_voice_channel()
    PardexOnline.set_voice_muted(microphone_muted)
    _prune_remote_players(room)


func _on_room_left() -> void:
    _stop_voice_channel()


func _start_voice_channel() -> void:
    if _channel_active:
        return
    if not _ensure_capture_pipeline():
        return
    _channel_active = true
    voice_channel_state_changed.emit(true)
    voice_settings_changed.emit(microphone_muted, output_muted)


func _stop_voice_channel() -> void:
    if not _channel_active and _remote_players.is_empty():
        return
    _channel_active = false
    if _capture != null:
        _capture.clear_buffer()
    for entry in _remote_players.values():
        var player := entry.get("player") as AudioStreamPlayer
        if player != null:
            player.queue_free()
    _remote_players.clear()
    _last_sequence_by_user.clear()
    _speaking_deadline_ms.clear()
    for user_id in _speaking_by_user.keys():
        _set_speaking(str(user_id), false)
    _speaking_by_user.clear()
    voice_channel_state_changed.emit(false)


func _ensure_capture_pipeline() -> bool:
    var bus_index := AudioServer.get_bus_index(CAPTURE_BUS)
    if bus_index < 0:
        AudioServer.add_bus()
        bus_index = AudioServer.bus_count - 1
        AudioServer.set_bus_name(bus_index, CAPTURE_BUS)
    AudioServer.set_bus_mute(bus_index, true)

    if _capture == null:
        _capture = AudioEffectCapture.new()
        _capture.buffer_length = 0.5
        AudioServer.add_bus_effect(bus_index, _capture, 0)

    if _microphone_player == null:
        _microphone_player = AudioStreamPlayer.new()
        _microphone_player.name = "PardexMicrophoneCapture"
        _microphone_player.stream = AudioStreamMicrophone.new()
        _microphone_player.bus = CAPTURE_BUS
        add_child(_microphone_player)
        _microphone_player.play()

    var source_rate := int(AudioServer.get_mix_rate())
    if source_rate <= 0:
        return false
    _capture_frames_per_packet = maxi(1, int(round(float(source_rate) * PACKET_SECONDS)))
    return true


func _capture_microphone_packet() -> void:
    if _capture == null or _capture_frames_per_packet <= 0:
        return
    if not PardexOnline.is_online() or not PardexOnline.is_in_room():
        return

    while _capture.can_get_buffer(_capture_frames_per_packet):
        var frames := _capture.get_buffer(_capture_frames_per_packet)
        if frames.is_empty():
            return
        if microphone_muted:
            _set_speaking(PardexOnline.user_id, false)
            continue

        var encoded := _encode_voice_packet(frames)
        var pcm: PackedByteArray = encoded.get("pcm", PackedByteArray())
        var rms := float(encoded.get("rms", 0.0))
        _set_speaking(PardexOnline.user_id, rms >= SPEAKING_THRESHOLD)
        if pcm.is_empty():
            continue

        _sequence = (_sequence + 1) & 0x7fffffff
        PardexOnline.send_voice_frame(_sequence, Marshalls.raw_to_base64(pcm))


func _encode_voice_packet(frames: PackedVector2Array) -> Dictionary:
    var source_rate := float(AudioServer.get_mix_rate())
    if source_rate <= 0.0 or frames.is_empty():
        return {"pcm": PackedByteArray(), "rms": 0.0}

    var target_count := maxi(1, int(round(float(frames.size()) * float(TARGET_SAMPLE_RATE) / source_rate)))
    var bytes := PackedByteArray()
    bytes.resize(target_count * 2)

    var square_sum := 0.0
    for i in range(target_count):
        var source_position := float(i) * source_rate / float(TARGET_SAMPLE_RATE)
        var source_index := clampi(int(floor(source_position)), 0, frames.size() - 1)
        var sample_frame := frames[source_index]
        var mono := clampf((sample_frame.x + sample_frame.y) * 0.5, -1.0, 1.0)
        square_sum += mono * mono

        var value := int(round(mono * 32767.0))
        if value < 0:
            value += 65536
        bytes[i * 2] = value & 0xff
        bytes[i * 2 + 1] = (value >> 8) & 0xff

    var rms := sqrt(square_sum / float(target_count))
    return {"pcm": bytes, "rms": rms}


func _on_voice_frame_received(user_id: String, sequence: int, pcm_base64: String) -> void:
    if not _channel_active or output_muted:
        return
    if user_id.is_empty() or user_id == PardexOnline.user_id:
        return

    var previous_sequence := int(_last_sequence_by_user.get(user_id, -1))
    if previous_sequence >= 0 and sequence <= previous_sequence:
        return
    _last_sequence_by_user[user_id] = sequence

    var pcm := Marshalls.base64_to_raw(pcm_base64)
    if pcm.is_empty() or pcm.size() % 2 != 0:
        return

    var frames := PackedVector2Array()
    frames.resize(pcm.size() / 2)
    var square_sum := 0.0
    for i in range(frames.size()):
        var value := int(pcm[i * 2]) | (int(pcm[i * 2 + 1]) << 8)
        if value >= 32768:
            value -= 65536
        var sample := clampf(float(value) / 32767.0, -1.0, 1.0)
        frames[i] = Vector2(sample, sample)
        square_sum += sample * sample

    var playback := _ensure_remote_playback(user_id)
    if playback == null:
        return
    if not playback.can_push_buffer(frames.size()):
        playback.clear_buffer()
    playback.push_buffer(frames)

    var rms := sqrt(square_sum / float(maxi(1, frames.size())))
    if rms >= SPEAKING_THRESHOLD:
        _mark_speaking(user_id)


func _ensure_remote_playback(user_id: String) -> AudioStreamGeneratorPlayback:
    if _remote_players.has(user_id):
        return _remote_players[user_id].get("playback") as AudioStreamGeneratorPlayback

    var generator := AudioStreamGenerator.new()
    generator.mix_rate = TARGET_SAMPLE_RATE
    generator.buffer_length = PLAYBACK_BUFFER_SECONDS

    var player := AudioStreamPlayer.new()
    player.name = "Voice_%s" % user_id.left(8)
    player.stream = generator
    player.stream_paused = output_muted
    add_child(player)
    player.play()

    var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
    if playback == null:
        player.queue_free()
        return null

    _remote_players[user_id] = {
        "player": player,
        "playback": playback,
    }
    return playback


func _prune_remote_players(room: Dictionary) -> void:
    var active_ids: Dictionary = {}
    var members: Array = room.get("members", [])
    for member_data in members:
        if typeof(member_data) != TYPE_DICTIONARY:
            continue
        var member: Dictionary = member_data
        var member_id := str(member.get("user_id", ""))
        if not member_id.is_empty():
            active_ids[member_id] = true

    for user_id_value in _remote_players.keys():
        var user_id := str(user_id_value)
        if active_ids.has(user_id):
            continue
        var entry: Dictionary = _remote_players[user_id]
        var player := entry.get("player") as AudioStreamPlayer
        if player != null:
            player.queue_free()
        _remote_players.erase(user_id)
        _last_sequence_by_user.erase(user_id)
        _speaking_deadline_ms.erase(user_id)
        _set_speaking(user_id, false)


func _mark_speaking(user_id: String) -> void:
    _speaking_deadline_ms[user_id] = Time.get_ticks_msec() + SPEAKING_HOLD_MS
    _set_speaking(user_id, true)


func _expire_speaking_states() -> void:
    var now := Time.get_ticks_msec()
    for user_id_value in _speaking_deadline_ms.keys():
        var user_id := str(user_id_value)
        if now < int(_speaking_deadline_ms[user_id]):
            continue
        _speaking_deadline_ms.erase(user_id)
        _set_speaking(user_id, false)


func _set_speaking(user_id: String, speaking: bool) -> void:
    if user_id.is_empty():
        return
    if bool(_speaking_by_user.get(user_id, false)) == speaking:
        return
    _speaking_by_user[user_id] = speaking
    voice_activity_changed.emit(user_id, speaking)
