extends Node

# PARDEX voice is temporarily disabled.
# Keep the public API in place so room/main code remains stable while
# microphone capture and network voice transport are turned off.

signal voice_activity_changed(user_id: String, speaking: bool)
signal voice_settings_changed(microphone_muted: bool, output_muted: bool)
signal voice_channel_state_changed(active: bool)

var microphone_muted := true
var output_muted := true


func _ready() -> void:
    voice_channel_state_changed.emit(false)
    voice_settings_changed.emit(microphone_muted, output_muted)


func toggle_microphone() -> void:
    microphone_muted = true
    voice_settings_changed.emit(microphone_muted, output_muted)


func set_microphone_muted(_value: bool) -> void:
    microphone_muted = true
    voice_settings_changed.emit(microphone_muted, output_muted)


func toggle_output_muted() -> void:
    output_muted = true
    voice_settings_changed.emit(microphone_muted, output_muted)


func is_user_speaking(_user_id: String) -> bool:
    return false


func is_channel_active() -> bool:
    return false
