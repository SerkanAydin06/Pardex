extends SceneTree

const D := preload("res://scripts/data/pardex_distribution.gd")
const Catalog := preload("res://scripts/data/pardex_catalog.gd")
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("Distribution: " + message)


func _run() -> void:
	var entry := {"id":"ci_update_fixture", "title":"Test", "version":"1.0.0", "executable":"Game.exe",
		"package":{"url":"https://distribution.invalid/game.zip", "sha256":"a".repeat(64), "size":123}}
	var manifest := {"schema":1, "launcher":{}, "games":[entry]}
	expect(D.validate(manifest), "valid independent manifest")
	for url in ["http://example.com/file", "file:///tmp/file", "https://user@example.com/file"]:
		var bad := manifest.duplicate(true)
		bad["games"][0]["package"]["url"] = url
		expect(not D.validate(bad), "reject insecure package URL")
	for path in ["../outside.exe", "/root.exe", "C:/bad.exe", "folder/../bad.exe", "CON.exe", "Game.exe.", "a\\b.exe"]:
		expect(not D.safe_path(path), "reject unsafe Windows path")
	var duplicate := manifest.duplicate(true)
	duplicate["games"].append(entry)
	expect(not D.validate(duplicate), "reject duplicate game")
	var saved := D.manifest
	D.manifest = manifest
	expect(Catalog.game("ci_update_fixture").get("title", "") == "Test", "new remote game appears in catalog")
	expect(Catalog.action_label("ci_update_fixture") == "İndir", "new game download action")
	var archive := ProjectSettings.globalize_path("user://distribution-test.zip")
	var zip := ZIPPacker.new()
	expect(zip.open(archive) == OK, "create fixture zip")
	zip.start_file("Game.exe")
	zip.write_file("fixture-only-not-executable".to_utf8_buffer())
	zip.close_file()
	zip.close()
	var file := FileAccess.open(archive, FileAccess.READ)
	var metadata := {"url":"https://distribution.invalid/test.zip", "size":file.get_length(), "sha256":FileAccess.get_sha256(archive)}
	file.close()
	expect(D.verified_file(archive, metadata), "accept complete verified package")
	metadata["sha256"] = "0".repeat(64)
	expect(not D.verified_file(archive, metadata), "reject tampered package")
	metadata["size"] = 1
	expect(not D.verified_file(archive, metadata), "reject truncated package")
	expect(D.install_zip(archive, entry), "install verified fixture into version folder")
	var old := D.executable("ci_update_fixture")
	expect(not old.is_empty() and not D.needs_install("ci_update_fixture"), "activate installed version")
	var newer := entry.duplicate(true)
	newer["version"] = "1.1.0"
	newer["package"]["sha256"] = "b".repeat(64)
	D.manifest = {"schema":1, "games":[newer]}
	expect(Catalog.action_label("ci_update_fixture") == "Güncelle", "detect game update")
	zip.open(archive)
	zip.start_file("../Game.exe")
	zip.write_file("invalid".to_utf8_buffer())
	zip.close_file()
	zip.close()
	expect(not D.install_zip(archive, newer), "reject zip traversal")
	expect(D.executable("ci_update_fixture") == old and FileAccess.get_file_as_string(old) == "fixture-only-not-executable", "failed update preserves working version")
	zip.open(archive)
	zip.start_file("Game.exe")
	zip.write_file("new-fixture".to_utf8_buffer())
	zip.close_file()
	zip.close()
	expect(D.install_zip(archive, newer), "install second version")
	expect(D.executable("ci_update_fixture") != old and FileAccess.file_exists(old), "retain previous version")
	D.manifest = saved
	DirAccess.remove_absolute(archive)
	if failures == 0:
		print("DISTRIBUTION SMOKE PASSED: catalog, update, paths, atomic activation and previous-version preservation")
	quit(0 if failures == 0 else 1)
