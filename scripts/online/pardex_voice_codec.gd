extends RefCounted

# Voice call audio: 16 kHz mono, IMA ADPCM (4 bits per sample, ~64 kbit/s).
# Every packet starts with its own predictor and step index, so a lost or
# late packet never corrupts the ones after it.

const RATE := 16000
# 60 ms per packet: few enough messages for the server's rate limit.
const FRAME_SAMPLES := 960
const HEADER_BYTES := 3

const INDEX_TABLE := [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8]
const STEP_TABLE := [
	7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
	50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230,
	253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963,
	1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327,
	3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442,
	11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794,
	32767,
]


# Stereo capture at the mixer rate -> mono 16 kHz (box filter + linear step).
# Each frame keeps its louder channel: many Windows microphones arrive on the
# left channel only, and averaging would halve them below the speech threshold.
static func to_mono_16k(frames: PackedVector2Array, from_rate: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if frames.is_empty() or from_rate <= 0.0:
		return out
	var ratio := from_rate / RATE
	var count := int(frames.size() / ratio)
	out.resize(count)
	for i in count:
		var start := int(i * ratio)
		var stop := mini(int((i + 1) * ratio), frames.size())
		var total := 0.0
		for j in range(start, maxi(stop, start + 1)):
			var frame := frames[mini(j, frames.size() - 1)]
			total += frame.x if absf(frame.x) >= absf(frame.y) else frame.y
		out[i] = total / maxf(1.0, stop - start)
	return out


static func rms(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var total := 0.0
	for value in samples:
		total += value * value
	return sqrt(total / samples.size())


# `state` carries the encoder between packets of one stream (better quality:
# the step size is already adapted); the header still lets every packet be
# decoded on its own.
static func encode(samples: PackedFloat32Array, state := {}) -> PackedByteArray:
	var bytes := PackedByteArray()
	if samples.is_empty():
		return bytes
	var predictor: int = state.get("predictor", clampi(int(samples[0] * 32767.0), -32768, 32767))
	var index: int = state.get("index", 0)
	bytes.resize(HEADER_BYTES + ((samples.size() + 1) >> 1))
	bytes.encode_s16(0, predictor)
	bytes[2] = index
	for i in samples.size():
		var target := clampi(int(samples[i] * 32767.0), -32768, 32767)
		var step: int = STEP_TABLE[index]
		var diff := target - predictor
		var code := 0
		if diff < 0:
			code = 8
			diff = -diff
		var delta := step >> 3
		if diff >= step:
			code |= 4
			diff -= step
			delta += step
		if diff >= step >> 1:
			code |= 2
			diff -= step >> 1
			delta += step >> 1
		if diff >= step >> 2:
			code |= 1
			delta += step >> 2
		predictor = clampi(predictor - delta if code & 8 else predictor + delta, -32768, 32767)
		index = clampi(index + INDEX_TABLE[code], 0, 88)
		var position := HEADER_BYTES + (i >> 1)
		bytes[position] = bytes[position] | (code << 4 if i % 2 else code)
	state["predictor"] = predictor
	state["index"] = index
	return bytes


static func decode(bytes: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if bytes.size() <= HEADER_BYTES:
		return out
	var predictor := bytes.decode_s16(0)
	var index := clampi(bytes[2], 0, 88)
	var count := (bytes.size() - HEADER_BYTES) * 2
	out.resize(count)
	for i in count:
		var packed := bytes[HEADER_BYTES + (i >> 1)]
		var code := (packed >> 4) & 15 if i % 2 else packed & 15
		var step: int = STEP_TABLE[index]
		var delta := step >> 3
		if code & 4:
			delta += step
		if code & 2:
			delta += step >> 1
		if code & 1:
			delta += step >> 2
		predictor = clampi(predictor - delta if code & 8 else predictor + delta, -32768, 32767)
		index = clampi(index + INDEX_TABLE[code], 0, 88)
		out[i] = predictor / 32768.0
	return out
