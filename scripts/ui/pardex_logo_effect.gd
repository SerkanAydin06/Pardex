extends TextureRect

# Scene-owned shader; these switches are available on Logo in the Inspector.
@export var effects_enabled := true:
	set(value):
		effects_enabled = value
		_apply_options()
@export var animation_enabled := true:
	set(value):
		animation_enabled = value
		_apply_options()

var _effect_material: ShaderMaterial
var _elapsed := 0.0


func _ready() -> void:
	_effect_material = material as ShaderMaterial
	_apply_options()
	if _effect_material != null:
		_effect_material.set_shader_parameter("effect_time", 0.0 if animation_enabled else 2.0)


func _apply_options() -> void:
	if _effect_material != null:
		_effect_material.set_shader_parameter("effects_enabled", effects_enabled)
		_effect_material.set_shader_parameter("motion_enabled", animation_enabled)
	set_process(effects_enabled and animation_enabled)


func _process(delta: float) -> void:
	if _effect_material == null or not is_visible_in_tree():
		return
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		return
	_elapsed += delta
	_effect_material.set_shader_parameter("effect_time", _elapsed)
