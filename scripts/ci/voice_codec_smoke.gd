extends SceneTree

# Voice call codec: size, quality (signal-to-noise), independent packets and
# mixer-rate conversion.

const Codec := preload("res://scripts/online/pardex_voice_codec.gd")


func _initialize() -> void:
	var failures := PackedStringArray()
	var tone := PackedFloat32Array()
	tone.resize(Codec.FRAME_SAMPLES)
	for i in tone.size():
		tone[i] = 0.5 * sin(TAU * 440.0 * i / Codec.RATE) + 0.2 * sin(TAU * 1300.0 * i / Codec.RATE)
	# A stream: the second packet uses the adapted encoder state.
	var stream := {}
	Codec.encode(tone, stream)
	var packet := Codec.encode(tone, stream)
	if packet.size() != Codec.HEADER_BYTES + Codec.FRAME_SAMPLES / 2:
		failures.append("packet size %d" % packet.size())
	var decoded := Codec.decode(packet)
	if decoded.size() != tone.size():
		failures.append("decoded length %d" % decoded.size())
	else:
		var signal_power := 0.0
		var noise_power := 0.0
		for i in tone.size():
			signal_power += tone[i] * tone[i]
			noise_power += pow(tone[i] - decoded[i], 2)
		var snr := 10.0 * log(signal_power / maxf(noise_power, 1e-9)) / log(10.0)
		if snr < 28.0:
			failures.append("quality too low: %.1f dB" % snr)
		print("voice codec SNR %.1f dB, %d bytes per 60 ms" % [snr, packet.size()])
	# Each packet decodes alone (a lost packet does not break the next one).
	var second := tone.slice(480)
	var alone := Codec.decode(Codec.encode(second))
	if absf(alone[10] - second[10]) > 0.1:
		failures.append("packet depends on previous packet")
	if not Codec.decode(PackedByteArray([1, 2])).is_empty():
		failures.append("short packet accepted")
	# 48 kHz stereo capture becomes 16 kHz mono.
	var capture := PackedVector2Array()
	capture.resize(2880)
	capture.fill(Vector2(0.25, 0.75))
	var mono := Codec.to_mono_16k(capture, 48000.0)
	if mono.size() != 960 or absf(mono[100] - 0.5) > 0.001:
		failures.append("resample %d / %.3f" % [mono.size(), mono[100] if not mono.is_empty() else -1.0])
	if Codec.rms(PackedFloat32Array([0.5, -0.5])) != 0.5:
		failures.append("rms")
	if failures.is_empty():
		print("PARDEX voice codec smoke passed: 4x smaller packets, clear audio, independent packets, 48k -> 16k mono")
		quit(0)
	else:
		push_error("PARDEX voice codec: " + "; ".join(failures))
		quit(1)
