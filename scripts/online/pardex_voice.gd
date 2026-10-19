extends Node

# Microphone and speaker for voice calls. The microphone is opened only while
# a call is active (or during the microphone test in Ayarlar), captured
# through a muted bus, reduced to 16 kHz mono and sent in 60 ms ADPCM
# packets. "Ses algılama" sends only while you speak; "Bas-konuş" while the
# push-to-talk key is held (only while the PARDEX window has focus).

signal local_speaking_changed(speaking: bool)
signal remote_speaking_changed(speaking: bool)
signal mic_level_changed(level: float)

const Codec := preload("res://scripts/online/pardex_voice_codec.gd")
const MIC_BUS := "PardexMikrofon"
const PUSH_TO_TALK_ACTION := "pardex_push_to_talk"
# Speech keeps sending this long after the level drops (no cut-off words).
const HANGOVER_SECONDS := 0.4
const REMOTE_SPEAKING_SECONDS := 0.3
const SETTINGS_PATH := "user://pardex.cfg"

var mode := "voice" # "voice" (ses algılama) or "push" (bas-konuş)
var sensitivity := 0.02 # RMS level that counts as speech
var muted := false
var deafened := false
var testing := false

var _mic_player: AudioStreamPlayer
var _capture: AudioEffectCapture
var _speaker: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _pending := PackedFloat32Array()
var _encoder_state := {}
var _sequence := 0
var _hangover := 0.0
var _speaking := false
var _remote_timer := 0.0
var _remote_speaking := false
var _in_call := false


func _ready() -> void:
	_ensure_mic_bus()
	load_settings()
	if not InputMap.has_action(PUSH_TO_TALK_ACTION):
		InputMap.add_action(PUSH_TO_TALK_ACTION)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_V
		InputMap.action_add_event(PUSH_TO_TALK_ACTION, key)
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = MIC_BUS
	add_child(_mic_player)
	_speaker = AudioStreamPlayer.new()
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = Codec.RATE
	generator.buffer_length = 0.5
	_speaker.stream = generator
	add_child(_speaker)
	PardexOnline.call_state_changed.connect(_on_call_state)
	PardexOnline.call_ended.connect(func(_reason): _set_in_call(false))
	PardexOnline.call_frame_received.connect(_on_frame)


# Audio plumbing, not layout: a muted bus that only feeds the capture effect.
func _ensure_mic_bus() -> void:
	if AudioServer.get_bus_index(MIC_BUS) == -1:
		AudioServer.add_bus()
		var bus := AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, MIC_BUS)
		AudioServer.set_bus_mute(bus, true)
		AudioServer.add_bus_effect(bus, AudioEffectCapture.new())
	var index := AudioServer.get_bus_index(MIC_BUS)
	_capture = AudioServer.get_bus_effect(index, 0) as AudioEffectCapture


# Ayarlar › Sesli sohbet: mode, sensitivity and devices, in pardex.cfg [voice].
func load_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	mode = "push" if str(config.get_value("voice", "mode", "voice")) == "push" else "voice"
	sensitivity = clampf(float(config.get_value("voice", "sensitivity", 0.02)), 0.002, 0.2)
	_apply_device(str(config.get_value("voice", "input_device", "Default")), true)
	_apply_device(str(config.get_value("voice", "output_device", "Default")), false)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("voice", "mode", mode)
	config.set_value("voice", "sensitivity", sensitivity)
	config.set_value("voice", "input_device", AudioServer.input_device)
	config.set_value("voice", "output_device", AudioServer.output_device)
	config.save(SETTINGS_PATH)


func set_device(device: String, input: bool) -> void:
	_apply_device(device, input)
	save_settings()


func _apply_device(device: String, input: bool) -> void:
	var known := AudioServer.get_input_device_list() if input else AudioServer.get_output_device_list()
	if not device in known:
		device = "Default"
	if input:
		AudioServer.input_device = device
	else:
		AudioServer.output_device = device


func set_test(enabled: bool) -> void:
	testing = enabled
	_update_microphone()


func set_deafened(value: bool) -> void:
	deafened = value
	_speaker.volume_db = -80.0 if deafened else 0.0


func set_muted(value: bool) -> void:
	muted = value
	PardexOnline.send_call_mute(muted)
	if muted:
		_set_speaking(false)


func _on_call_state(call: Dictionary) -> void:
	_set_in_call(str(call.get("state", "")) == "active")


func _set_in_call(active: bool) -> void:
	if _in_call == active:
		return
	_in_call = active
	_pending.clear()
	_encoder_state.clear()
	_sequence = 0
	_set_speaking(false)
	if active:
		_speaker.play()
		_playback = _speaker.get_stream_playback() as AudioStreamGeneratorPlayback
	else:
		_speaker.stop()
		_playback = null
		_set_remote_speaking(false)
	_update_microphone()


func _update_microphone() -> void:
	var wanted := _in_call or testing
	if wanted and not _mic_player.playing:
		_capture.clear_buffer()
		_mic_player.play()
	elif not wanted and _mic_player.playing:
		_mic_player.stop()


func _process(delta: float) -> void:
	if _remote_timer > 0.0:
		_remote_timer -= delta
		if _remote_timer <= 0.0:
			_set_remote_speaking(false)
	if not _mic_player.playing:
		return
	var available := _capture.get_frames_available()
	if available > 0:
		_pending.append_array(Codec.to_mono_16k(_capture.get_buffer(available), AudioServer.get_mix_rate()))
	while _pending.size() >= Codec.FRAME_SAMPLES:
		var frame := _pending.slice(0, Codec.FRAME_SAMPLES)
		_pending = _pending.slice(Codec.FRAME_SAMPLES)
		_handle_frame(frame, float(Codec.FRAME_SAMPLES) / Codec.RATE)


func _handle_frame(frame: PackedFloat32Array, duration: float) -> void:
	var level := Codec.rms(frame)
	mic_level_changed.emit(level)
	if not _in_call or muted:
		return
	var talking := false
	if mode == "push":
		talking = Input.is_action_pressed(PUSH_TO_TALK_ACTION)
	else:
		if level >= sensitivity:
			_hangover = HANGOVER_SECONDS
		else:
			_hangover -= duration
		talking = _hangover > 0.0
	_set_speaking(talking)
	if talking:
		_sequence += 1
		PardexOnline.send_call_frame(_sequence, Marshalls.raw_to_base64(Codec.encode(frame, _encoder_state)))


func _on_frame(_sequence_number: int, data: String) -> void:
	if _playback == null:
		return
	var samples := Codec.decode(Marshalls.base64_to_raw(data))
	if samples.is_empty():
		return
	_set_remote_speaking(true)
	_remote_timer = REMOTE_SPEAKING_SECONDS
	# Keep latency low: if the buffer is backed up, drop this packet.
	if _playback.get_frames_available() < samples.size():
		return
	var frames := PackedVector2Array()
	frames.resize(samples.size())
	for i in samples.size():
		frames[i] = Vector2(samples[i], samples[i])
	_playback.push_buffer(frames)


func _set_speaking(value: bool) -> void:
	if _speaking != value:
		_speaking = value
		local_speaking_changed.emit(value)


func _set_remote_speaking(value: bool) -> void:
	if _remote_speaking != value:
		_remote_speaking = value
		remote_speaking_changed.emit(value)
