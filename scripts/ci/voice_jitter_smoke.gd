extends SceneTree

# Voice call jitter buffer: order, start delay, lost-packet cover, long gaps,
# late packets, delay cap, 16-bit sequence wrap and the loss figure.

const JitterBuffer := preload("res://scripts/online/pardex_jitter_buffer.gd")
const Codec := preload("res://scripts/online/pardex_voice_codec.gd")

var failures := PackedStringArray()


func expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func frame(value: float) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(Codec.FRAME_SAMPLES)
	samples.fill(value)
	return samples


func _initialize() -> void:
	var buffer := JitterBuffer.new()
	# A talk spurt waits for two packets, then plays in sequence order.
	buffer.push(11, frame(0.2), 0)
	expect(buffer.pull(10).is_empty(), "waits for a second packet")
	buffer.push(10, frame(0.1), 20)
	expect(is_equal_approx(buffer.pull(30)[0], 0.1), "reordered packets play in order")
	expect(is_equal_approx(buffer.pull(40)[0], 0.2), "second packet next")
	expect(buffer.pull(50).is_empty(), "spurt ends when empty")

	# A single short word still plays after the start wait.
	buffer.push(12, frame(0.3), 1000)
	expect(buffer.pull(1050).is_empty(), "short wait first")
	expect(is_equal_approx(buffer.pull(1000 + JitterBuffer.START_WAIT_MS)[0], 0.3), "single packet plays after the wait")

	# A lost packet is covered by a quieter copy of the previous one.
	buffer.push(13, frame(0.4), 2000)
	buffer.push(15, frame(0.6), 2010)
	expect(is_equal_approx(buffer.pull(2200)[0], 0.4), "13 plays")
	expect(is_equal_approx(buffer.pull(2210)[0], 0.2), "14 lost: half of 13")
	expect(is_equal_approx(buffer.pull(2220)[0], 0.6), "15 plays")
	# The late 14 is not played after its place passed.
	buffer.push(14, frame(0.5), 2230)
	expect(buffer.buffered() == 0, "late packet dropped")

	# A long gap is skipped instead of playing seconds of silence.
	buffer.push(16, frame(0.7), 3000)
	expect(is_equal_approx(buffer.pull(3200)[0], 0.7), "16 plays")
	buffer.push(40, frame(0.8), 3210)
	expect(is_equal_approx(buffer.pull(3220)[0], 0.8), "gap of 23 skipped")

	# Too much buffered audio drops the oldest (keeps the delay low).
	for i in 10:
		buffer.push(41 + i, frame(0.01 * i), 4000)
	expect(buffer.buffered() == JitterBuffer.MAX_FRAMES, "buffer capped at %d" % JitterBuffer.MAX_FRAMES)
	expect(is_equal_approx(buffer.pull(4010)[0], 0.04), "oldest audio dropped")

	# Loss figure: lost / (received + lost), then reset.
	var loss := buffer.take_loss_percent()
	expect(loss > 0.0 and loss < 100.0, "loss percent %.1f" % loss)
	expect(buffer.take_loss_percent() == -1.0, "loss resets")

	# 16-bit sequence numbers wrap around.
	buffer.clear()
	buffer.push(65535, frame(0.1), 0)
	buffer.push(0, frame(0.2), 0)
	expect(is_equal_approx(buffer.pull(10)[0], 0.1), "65535 before 0")
	expect(is_equal_approx(buffer.pull(20)[0], 0.2), "0 after 65535")

	if failures.is_empty():
		print("PARDEX voice jitter smoke passed: order, start wait, loss cover, gap skip, late drop, delay cap, wrap, loss figure")
		quit(0)
	else:
		push_error("PARDEX voice jitter: " + "; ".join(failures))
		quit(1)
