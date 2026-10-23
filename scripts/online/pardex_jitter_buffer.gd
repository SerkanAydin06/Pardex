extends RefCounted

# Voice call jitter buffer. Packets arrive unevenly over the internet; playing
# each one the moment it lands makes speech choppy. Each talk spurt waits for
# a little audio (or a short time) before it starts, packets are played in
# sequence order, a missing packet is covered by a fading copy of the previous
# one, and a buffer that grows too long drops its oldest audio to keep the
# delay low. Sequence numbers are 16-bit and wrap around.

const Codec := preload("res://scripts/online/pardex_voice_codec.gd")

# Audio to collect before a talk spurt starts (2 packets = 120 ms)...
const TARGET_FRAMES := 2
# ...or this long after its first packet, so a short word still plays.
const START_WAIT_MS := 120
# More buffered than this is extra delay: the oldest audio is dropped.
const MAX_FRAMES := 6
# A lost packet is replaced by the previous one, quieter each time, at most
# this many times in a row; after that silence.
const MAX_CONCEALED := 2

var received := 0
var lost := 0

var _frames := {}
var _next := -1
var _last := PackedFloat32Array()
var _concealed := 0
var _waiting_since := -1


static func seq_diff(a: int, b: int) -> int:
	return ((a - b + 32768) & 0xFFFF) - 32768


func clear() -> void:
	_frames.clear()
	_next = -1
	_last = PackedFloat32Array()
	_concealed = 0
	_waiting_since = -1
	received = 0
	lost = 0


func buffered() -> int:
	return _frames.size()


func push(sequence: int, samples: PackedFloat32Array, now_ms: int) -> void:
	sequence &= 0xFFFF
	if samples.is_empty() or _frames.has(sequence):
		return
	# Too late: its place was already played or covered.
	if _next >= 0 and seq_diff(sequence, _next) < 0:
		return
	_frames[sequence] = samples
	received += 1
	if _next < 0 and _waiting_since < 0:
		_waiting_since = now_ms
	while _frames.size() > MAX_FRAMES:
		var oldest := _oldest()
		_frames.erase(oldest)
		if _next >= 0 and seq_diff(oldest, _next) >= 0:
			_next = (oldest + 1) & 0xFFFF


# The next 60 ms to play, or an empty array when there is nothing to play yet.
func pull(now_ms: int) -> PackedFloat32Array:
	if _next < 0:
		if _frames.is_empty():
			return PackedFloat32Array()
		if _frames.size() < TARGET_FRAMES and now_ms - _waiting_since < START_WAIT_MS:
			return PackedFloat32Array()
		_next = _oldest()
		_waiting_since = -1
	if _frames.has(_next):
		var frame: PackedFloat32Array = _frames[_next]
		_frames.erase(_next)
		_next = (_next + 1) & 0xFFFF
		_last = frame
		_concealed = 0
		return frame
	if _frames.is_empty():
		# The talk spurt ended; the next packet starts a new one.
		_next = -1
		return PackedFloat32Array()
	# A gap with later audio waiting. A long gap is skipped at once instead
	# of being played as seconds of silence.
	var gap := seq_diff(_oldest(), _next)
	if gap > MAX_FRAMES:
		lost += gap
		_next = _oldest()
		return pull(now_ms)
	lost += 1
	_next = (_next + 1) & 0xFFFF
	_concealed += 1
	if _concealed > MAX_CONCEALED or _last.is_empty():
		var silence := PackedFloat32Array()
		silence.resize(Codec.FRAME_SAMPLES)
		return silence
	var faded := _last.duplicate()
	var gain := pow(0.5, _concealed)
	for i in faded.size():
		faded[i] *= gain
	return faded


# Share of packets lost since the last call (0..100), or -1 if none arrived.
func take_loss_percent() -> float:
	var total := received + lost
	var result := -1.0 if total == 0 else 100.0 * lost / total
	received = 0
	lost = 0
	return result


func _oldest() -> int:
	var oldest := -1
	for key in _frames:
		if oldest < 0 or seq_diff(int(key), oldest) < 0:
			oldest = int(key)
	return oldest
