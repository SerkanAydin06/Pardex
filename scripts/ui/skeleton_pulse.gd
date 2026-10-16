extends Control

# Placeholder shown while data loads: pulses softly until it is replaced.

func _ready() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(self, "modulate:a", 0.45, 0.7).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)
