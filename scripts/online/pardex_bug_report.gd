extends RefCounted

# "Sorun bildir": the player's description plus the end of Godot's own log
# (user://logs/godot.log, file logging is on by default on desktop), the app
# version and the OS. Sent to the PARDEX server, or saved to the desktop when
# offline. Kept under the server's 16 KB message limit.

const LOG_PATH := "user://logs/godot.log"
const LOG_TAIL_CHARS := 6000


static func build(description: String) -> Dictionary:
	return {
		"text": description.strip_edges().left(500),
		"version": str(ProjectSettings.get_setting("application/config/version", "")),
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"log": log_tail(),
	}


static func log_tail() -> String:
	if not FileAccess.file_exists(LOG_PATH):
		return ""
	var text := FileAccess.get_file_as_string(LOG_PATH)
	return text.right(LOG_TAIL_CHARS) if text.length() > LOG_TAIL_CHARS else text


# Returns the saved file path, or "" when it could not be written.
static func save_to_desktop(report: Dictionary) -> String:
	var folder := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	if folder.is_empty():
		folder = ProjectSettings.globalize_path("user://")
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := folder.path_join("PARDEX-hata-raporu-%s.txt" % stamp)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string("PARDEX hata raporu\nSürüm: %s\nSistem: %s\n\nSorun:\n%s\n\n--- Kayıt (son kısım) ---\n%s\n" % [
		report["version"], report["os"], report["text"], report["log"],
	])
	file.close()
	return path
