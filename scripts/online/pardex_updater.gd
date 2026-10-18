extends Node

signal update_available(version: String)
signal update_failed(message: String)
signal catalog_changed
signal game_installed(game_id: String)
signal progress(message: String)
signal game_uninstalled(game_id: String)

const Distribution := preload("res://scripts/data/pardex_distribution.gd")
const SETUP_ASSET := "PARDEX-Setup.exe"
var latest_version := ""
var _request: HTTPRequest
var _checking := false
var _worker: Thread
var _installing_game := ""
var _archive := ""
var _download_size := 0
var _download_title := ""
var _last_percent := -1
var _art_queue: Array = []
var _art_request: HTTPRequest


static func can_self_update() -> bool:
	return OS.has_feature("template") and OS.get_name() == "Windows"


static func is_newer(candidate: String, current: String) -> bool:
	var a := candidate.strip_edges().trim_prefix("v").split(".")
	var b := current.strip_edges().trim_prefix("v").split(".")
	for index in maxi(a.size(), b.size()):
		var left := int(a[index]) if index < a.size() else 0
		var right := int(b[index]) if index < b.size() else 0
		if left != right:
			return left > right
	return false


func busy() -> bool:
	return _request != null or _worker != null


func check(current_version: String) -> void:
	# The installer from the last self-update is no longer needed (in use only
	# while it is still finishing; then the next start removes it).
	if not busy():
		DirAccess.remove_absolute(OS.get_user_data_dir().path_join(SETUP_ASSET))
	Distribution.load_cache()
	catalog_changed.emit()
	var base := Distribution.base_url()
	if base.is_empty() or _checking:
		return
	_checking = true
	var request := _new_request()
	request.body_size_limit = 1024 * 1024
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
		_checking = false
		request.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			return
		var release: Variant = JSON.parse_string(body.get_string_from_utf8())
		if not Distribution.validate(release):
			update_failed.emit("Güncelleme listesi doğrulanamadı; mevcut sürümler korundu.")
			return
		Distribution.accept(release)
		catalog_changed.emit()
		_queue_art()
		var app: Dictionary = release.get("launcher", {})
		var version := str(app.get("version", ""))
		if can_self_update() and version != latest_version and is_newer(version, current_version):
			latest_version = version
			update_available.emit(version)
	)
	if request.request(base + "/channel.json", PackedStringArray(["Cache-Control: no-cache"])) != OK:
		_checking = false
		request.queue_free()


func install() -> void:
	if not can_self_update() or latest_version.is_empty():
		return
	_download(Distribution.manifest.get("launcher", {}).get("package", {}), {})


func install_game(id: String) -> void:
	var entry := Distribution.game(id)
	if OS.get_name() != "Windows":
		update_failed.emit("Oyun kurulumu şu anda Windows için kullanılabilir.")
		return
	if not entry.is_empty():
		_download(entry["package"], entry.duplicate(true))


func _download(package: Dictionary, entry: Dictionary) -> void:
	if busy():
		update_failed.emit("Devam eden indirme veya kurulumun bitmesini bekle.")
		return
	if not Distribution.valid_package(package):
		update_failed.emit("Paket bilgileri doğrulanamadı.")
		return
	_archive = OS.get_user_data_dir().path_join(SETUP_ASSET if entry.is_empty() else "game-download.zip")
	_download_size = int(package["size"])
	_download_title = "PARDEX güncellemesi" if entry.is_empty() else str(entry.get("title", "Oyun"))
	_last_percent = -1
	_request = _new_request()
	_request.download_file = _archive + ".part"
	_request.body_size_limit = int(package["size"])
	_request.timeout = 1800.0
	_request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray):
		_request.queue_free()
		_request = null
		if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not Distribution.verified_file(_archive + ".part", package):
			DirAccess.remove_absolute(_archive + ".part")
			update_failed.emit("İndirme tamamlanamadı veya paket doğrulanamadı. Mevcut sürüm korundu.")
			return
		if DirAccess.rename_absolute(_archive + ".part", _archive) != OK:
			update_failed.emit("İndirilen paket kaydedilemedi.")
			return
		if entry.is_empty():
			var args := PackedStringArray(["/SILENT", "/SP-", "/NORESTART", "/DIR=" + OS.get_executable_path().get_base_dir()])
			if OS.create_process(_archive, args) <= 0:
				update_failed.emit("Güncelleme başlatılamadı.")
				return
			get_tree().quit()
		else:
			_installing_game = str(entry["id"])
			_worker = Thread.new()
			if _worker.start(Distribution.install_zip.bind(_archive, entry)) != OK:
				_worker = null
				update_failed.emit("Kurulum başlatılamadı.")
			else:
				progress.emit("Oyun kuruluyor…")
	)
	if _request.request(str(package["url"])) != OK:
		_request.queue_free()
		_request = null
		update_failed.emit("İndirme başlatılamadı.")
	else:
		progress.emit("Paket indiriliyor…")


func _process(_delta: float) -> void:
	if _request != null and _download_size > 0:
		var percent := clampi(int(100.0 * _request.get_downloaded_bytes() / _download_size), 0, 100)
		# A few steps are enough; every percent would keep the toast flickering.
		if percent >= _last_percent + 5 or (percent == 100 and _last_percent != 100):
			_last_percent = percent
			progress.emit("%s indiriliyor… %%%d" % [_download_title, percent])
	if _worker != null and not _worker.is_alive():
		var succeeded: bool = _worker.wait_to_finish()
		_worker = null
		DirAccess.remove_absolute(_archive)
		if succeeded:
			catalog_changed.emit()
			game_installed.emit(_installing_game)
		else:
			update_failed.emit("Kurulum tamamlanamadı. Önceki sürüm ve kayıtlar korundu.")


# Removes an installed game. Refused while a download or install is running.
func uninstall_game(id: String) -> bool:
	if busy():
		update_failed.emit("Devam eden indirme veya kurulumun bitmesini bekle.")
		return false
	if not Distribution.uninstall(id):
		update_failed.emit("Oyun kaldırılamadı. Oyun açıksa kapatıp tekrar dene.")
		return false
	catalog_changed.emit()
	game_uninstalled.emit(id)
	return true


# Store artwork from the catalog, one small file at a time in the background.
func _queue_art() -> void:
	for entry in Distribution.manifest.get("games", []):
		for key in ["cover", "banner"]:
			var asset: Variant = entry.get(key)
			if Distribution.valid_art(asset) and Distribution.art_path(asset).is_empty() and not _art_queue.has(asset):
				_art_queue.append(asset)
	_next_art()


func _next_art() -> void:
	if _art_request != null or _art_queue.is_empty():
		return
	var asset: Dictionary = _art_queue.pop_front()
	var target := Distribution.art_download_path(asset)
	_art_request = _new_request()
	_art_request.download_file = target + ".part"
	_art_request.body_size_limit = int(asset["size"])
	_art_request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray):
		_art_request.queue_free()
		_art_request = null
		if result == HTTPRequest.RESULT_SUCCESS and code == 200 and Distribution.verified_file(target + ".part", asset) \
				and DirAccess.rename_absolute(ProjectSettings.globalize_path(target + ".part"), ProjectSettings.globalize_path(target)) == OK:
			catalog_changed.emit()
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(target + ".part"))
		_next_art()
	)
	if _art_request.request(str(asset["url"])) != OK:
		_art_request.queue_free()
		_art_request = null
		_next_art()


func _exit_tree() -> void:
	if _worker != null:
		_worker.wait_to_finish()


func _new_request() -> HTTPRequest:
	var request := HTTPRequest.new()
	request.timeout = 15.0
	request.max_redirects = 0
	request.use_threads = true
	add_child(request)
	return request
