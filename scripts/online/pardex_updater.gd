extends Node

# Self-update for installed Windows builds. Compares APP_VERSION with the
# latest GitHub release of PARDEX; when the release is newer and carries
# PARDEX-Setup.exe (tools/pardex_installer.iss), the installer is downloaded
# and run silently. It closes PARDEX, installs over it and starts it again.

signal update_available(version: String)
signal update_failed(message: String)

const RELEASES_URL := "https://api.github.com/repos/SerkanAydin06/Pardex/releases/latest"
const SETUP_ASSET := "PARDEX-Setup.exe"

var latest_version := ""
var _setup_url := ""
var _request: HTTPRequest


# Editor runs and other platforms never update themselves.
static func can_self_update() -> bool:
	return OS.has_feature("template") and OS.get_name() == "Windows"


# "v1.2.10" is newer than "1.2.9"; missing parts count as 0.
static func is_newer(candidate: String, current: String) -> bool:
	var a := candidate.strip_edges().trim_prefix("v").split(".")
	var b := current.strip_edges().trim_prefix("v").split(".")
	for index in maxi(a.size(), b.size()):
		var left := int(a[index]) if index < a.size() else 0
		var right := int(b[index]) if index < b.size() else 0
		if left != right:
			return left > right
	return false


func check(current_version: String) -> void:
	if not can_self_update():
		return
	var request := _new_request()
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
		request.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			return
		var release: Variant = JSON.parse_string(body.get_string_from_utf8())
		if not release is Dictionary:
			return
		var version := str((release as Dictionary).get("tag_name", "")).trim_prefix("v")
		if not is_newer(version, current_version):
			return
		for asset in (release as Dictionary).get("assets", []):
			if asset is Dictionary and str(asset.get("name", "")) == SETUP_ASSET:
				latest_version = version
				_setup_url = str(asset.get("browser_download_url", ""))
				update_available.emit(version)
				return
	)
	if request.request(RELEASES_URL, PackedStringArray(["Accept: application/vnd.github+json"])) != OK:
		request.queue_free()


func install() -> void:
	if _setup_url.is_empty() or _request != null:
		return
	var target := OS.get_user_data_dir().path_join(SETUP_ASSET)
	_request = _new_request()
	_request.download_file = target
	_request.timeout = 300.0
	_request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray):
		_request.queue_free()
		_request = null
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			update_failed.emit("Güncelleme indirilemedi. Daha sonra tekrar dene.")
			return
		if OS.create_process(target, PackedStringArray(["/SILENT", "/SP-", "/NOCANCEL"])) <= 0:
			update_failed.emit("Güncelleme başlatılamadı.")
			return
		get_tree().quit()
	)
	if _request.request(_setup_url) != OK:
		_request.queue_free()
		_request = null
		update_failed.emit("Güncelleme indirilemedi. Daha sonra tekrar dene.")


func _new_request() -> HTTPRequest:
	var request := HTTPRequest.new()
	request.timeout = 15.0
	add_child(request)
	return request
