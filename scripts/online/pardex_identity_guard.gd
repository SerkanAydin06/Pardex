extends Node

const IDENTITY_PATH := "user://pardex_identity.cfg"


func _enter_tree() -> void:
	_ensure_valid_identity()


func _ensure_valid_identity() -> void:
	var config := ConfigFile.new()
	if config.load(IDENTITY_PATH) == OK:
		var saved_key := str(config.get_value("identity", "key", "")).strip_edges().to_lower()
		if _is_valid_identity_key(saved_key):
			return
		push_warning("PARDEX identity file was invalid and has been regenerated.")

	var crypto := Crypto.new()
	var identity_key := crypto.generate_random_bytes(32).hex_encode()
	config = ConfigFile.new()
	config.set_value("identity", "key", identity_key)
	var result := config.save(IDENTITY_PATH)
	if result != OK:
		push_warning("PARDEX identity could not be saved: %s" % error_string(result))


func _is_valid_identity_key(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		var is_digit := code >= 48 and code <= 57
		var is_hex_letter := code >= 97 and code <= 102
		if not is_digit and not is_hex_letter:
			return false
	return true
