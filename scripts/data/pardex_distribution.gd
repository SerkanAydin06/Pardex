extends RefCounted

const CACHE := "user://distribution.json"
const INSTALLED := "user://installed_games.cfg"
const ROOT := "user://games"
const ART := "user://art"
const MAX_ART_BYTES := 8388608
static var manifest: Dictionary = {}


static func base_url() -> String:
	var value := OS.get_environment("PARDEX_DISTRIBUTION_URL").strip_edges()
	if value.is_empty():
		var path := OS.get_executable_path().get_base_dir().path_join("pardex-distribution.json")
		if FileAccess.file_exists(path):
			var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if config is Dictionary:
				value = str(config.get("url", "")).strip_edges()
	return value.trim_suffix("/") if valid_url(value) else ""


static func valid_url(value: String) -> bool:
	return value.begins_with("https://") and value.length() > 8 and not "@" in value and not " " in value and not "#" in value and not "?" in value


static func valid_id(value: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[a-z][a-z0-9_-]{0,47}$")
	return pattern.search(value) != null


static func valid_version(value: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[0-9]{1,6}(\\.[0-9]{1,6}){0,3}$")
	return pattern.search(value) != null


static func safe_path(value: String) -> bool:
	if value.is_empty() or value.begins_with("/") or "\\" in value or ":" in value:
		return false
	for part in value.split("/"):
		if part.is_empty() or part in [".", ".."] or part.ends_with(".") or part.ends_with(" "):
			return false
		for character in ['<', '>', '"', '|', '?', '*']:
			if character in part:
				return false
		for index in part.length():
			if part.unicode_at(index) < 32:
				return false
		var stem := part.get_slice(".", 0).to_upper()
		if stem in ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]:
			return false
	return true


static func valid_package(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var digest := str(value.get("sha256", ""))
	return valid_url(str(value.get("url", ""))) and digest.length() == 64 and digest.is_valid_hex_number(false) and int(value.get("size", 0)) > 0 and int(value.get("size", 0)) <= 2147483648


static func verified_file(path: String, package: Dictionary) -> bool:
	if not valid_package(package):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() != int(package["size"]):
		return false
	file.close()
	return FileAccess.get_sha256(path).to_lower() == str(package["sha256"]).to_lower()


# Store artwork: a package whose URL ends in an image extension, at most 8 MiB.
static func valid_art(value: Variant) -> bool:
	if not valid_package(value) or int(value["size"]) > MAX_ART_BYTES:
		return false
	return str(value["url"]).get_extension().to_lower() in ["png", "jpg", "webp"]


static func valid_genres(value: Variant) -> bool:
	if not value is Array or value.size() > 4:
		return false
	for genre in value:
		if not genre is String or genre.strip_edges().is_empty() or genre.length() > 24:
			return false
	return true


static func validate(value: Variant) -> bool:
	if not value is Dictionary or int(value.get("schema", 0)) != 1 or not value.get("games", []) is Array:
		return false
	var app: Variant = value.get("launcher", {})
	if not app is Dictionary:
		return false
	if not app.is_empty() and (not valid_version(str(app.get("version", ""))) or not valid_package(app.get("package"))):
		return false
	var ids := {}
	for entry in value.get("games", []):
		if not entry is Dictionary:
			return false
		var id := str(entry.get("id", ""))
		var executable_path := str(entry.get("executable", ""))
		if not valid_id(id) or ids.has(id) or not valid_version(str(entry.get("version", ""))) or not safe_path(executable_path) or not executable_path.to_lower().ends_with(".exe") or not valid_package(entry.get("package")) or str(entry.get("title", "")).is_empty():
			return false
		for key in ["cover", "banner"]:
			if entry.has(key) and not valid_art(entry[key]):
				return false
		if entry.has("genres") and not valid_genres(entry["genres"]):
			return false
		ids[id] = true
	return ids.size() <= 100


# Local copy of a verified artwork file, or "" until it has been downloaded.
static func art_path(asset: Variant) -> String:
	if not valid_art(asset):
		return ""
	var path := ART.path_join(str(asset["sha256"]).to_lower() + "." + str(asset["url"]).get_extension().to_lower())
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var matches := file.get_length() == int(asset["size"])
	file.close()
	return path if matches else ""


static func art_download_path(asset: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ART))
	return ART.path_join(str(asset["sha256"]).to_lower() + "." + str(asset["url"]).get_extension().to_lower())


static func load_cache() -> void:
	if FileAccess.file_exists(CACHE):
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(CACHE))
		if validate(value):
			manifest = value


static func accept(value: Dictionary) -> void:
	manifest = value
	var file := FileAccess.open(CACHE + ".tmp", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value))
		file.close()
		DirAccess.rename_absolute(ProjectSettings.globalize_path(CACHE + ".tmp"), ProjectSettings.globalize_path(CACHE))


static func game(id: String) -> Dictionary:
	for entry in manifest.get("games", []):
		if str(entry.get("id", "")) == id:
			return entry
	return {}


static func installed(id: String) -> Dictionary:
	var config := ConfigFile.new()
	config.load(INSTALLED)
	var value: Variant = config.get_value(id, "package", {})
	return value if value is Dictionary else {}


static func executable(id: String) -> String:
	if not valid_id(id):
		return ""
	var record := installed(id)
	var relative := str(record.get("path", ""))
	if not safe_path(relative):
		return ""
	var path := ProjectSettings.globalize_path(ROOT.path_join(id).path_join(relative))
	return path if FileAccess.file_exists(path) else ""


static func needs_install(id: String) -> bool:
	var entry := game(id)
	if entry.is_empty():
		return false
	var record := installed(id)
	return executable(id).is_empty() or str(record.get("sha256", "")) != str(entry["package"]["sha256"])


# Runs on the install worker. A failed extraction never replaces the active version.
static func install_zip(archive: String, entry: Dictionary) -> bool:
	var zip := ZIPReader.new()
	if zip.open(archive) != OK:
		return false
	var files := zip.get_files()
	var names := {}
	if files.size() > 4096 or not files.has(str(entry["executable"])):
		zip.close()
		return false
	for filename in files:
		var clean := filename.trim_suffix("/")
		if not safe_path(clean) or names.has(clean.to_lower()):
			zip.close()
			return false
		names[clean.to_lower()] = true
	var folder := str(entry["version"]) + "-" + str(entry["package"]["sha256"]).left(16)
	var destination := ProjectSettings.globalize_path(ROOT.path_join(str(entry["id"])).path_join(folder))
	var total := 0
	for filename in files:
		if filename.ends_with("/"):
			continue
		var target := destination.path_join(filename)
		if DirAccess.make_dir_recursive_absolute(target.get_base_dir()) != OK:
			zip.close()
			return false
		var bytes := zip.read_file(filename)
		total += bytes.size()
		if total > 8589934592:
			zip.close()
			return false
		var output := FileAccess.open(target, FileAccess.WRITE)
		if output == null:
			zip.close()
			return false
		output.store_buffer(bytes)
		if output.get_error() != OK:
			zip.close()
			return false
	zip.close()
	var config := ConfigFile.new()
	config.load(INSTALLED)
	config.set_value(str(entry["id"]), "package", {"version": entry["version"], "sha256": entry["package"]["sha256"], "path": folder.path_join(str(entry["executable"]))})
	if config.save(INSTALLED + ".tmp") != OK:
		return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(INSTALLED + ".tmp"), ProjectSettings.globalize_path(INSTALLED)) != OK:
		return false
	# The new version is active: earlier version folders only take disk space.
	var game_root := ProjectSettings.globalize_path(ROOT.path_join(str(entry["id"])))
	for old in DirAccess.get_directories_at(game_root):
		if old != folder:
			_remove_tree(game_root.path_join(old))
	return true


# Deletes the game's files, then its install record. If a file cannot be
# removed (for example locked by a running game) the record stays, so PARDEX
# still knows the game is on disk. Saves made by the game in its own user
# folder are not touched.
static func uninstall(id: String) -> bool:
	if not valid_id(id):
		return false
	var folder := ProjectSettings.globalize_path(ROOT.path_join(id))
	if DirAccess.dir_exists_absolute(folder) and not _remove_tree(folder):
		return false
	var config := ConfigFile.new()
	config.load(INSTALLED)
	if config.has_section(id):
		config.erase_section(id)
		return config.save(INSTALLED) == OK
	return true


static func _remove_tree(path: String) -> bool:
	for file in DirAccess.get_files_at(path):
		if DirAccess.remove_absolute(path.path_join(file)) != OK:
			return false
	for child in DirAccess.get_directories_at(path):
		if not _remove_tree(path.path_join(child)):
			return false
	return DirAccess.remove_absolute(path) == OK
