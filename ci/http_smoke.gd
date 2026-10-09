extends SceneTree
## Run by ci/http_smoke.sh: drives LFHttp against the local server whose port is in
## the LF_SMOKE_PORT environment variable. Exits non-zero when any check fails.

const MIB := 1048576
var _frames := 0
var _failed := false


func _init() -> void:
	process_frame.connect(func() -> void: _frames += 1)
	_run.call_deferred()


func _check(name: String, ok: bool, detail := "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, "" if ok else " (%s)" % detail])
	if not ok:
		_failed = true


func _run() -> void:
	var base := "http://127.0.0.1:%s" % OS.get_environment("LF_SMOKE_PORT")
	var auth := {"Authorization": "Bearer secret"}

	var small: Dictionary = await LFHttp.request(HTTPClient.METHOD_GET, base + "/small", {}, "", 10000, 4 * MIB)
	_check("small body under max_body_bytes succeeds", small.ok and small.body_bytes.size() == 5, str(small.get("error")))

	var big: Dictionary = await LFHttp.request(HTTPClient.METHOD_GET, base + "/big", {}, "", 20000, 4 * MIB)
	_check("5 MiB body over a 4 MiB max_body_bytes fails with Body too large",
			not big.ok and big.get("error") == "Body too large", str(big.get("error")))

	var direct: Dictionary = await LFHttp.request(HTTPClient.METHOD_GET, base + "/echo", auth, "", 10000)
	var seen: Dictionary = direct.json if direct.json is Dictionary else {}
	_check("Authorization arrives on a direct request", seen.get("authorization") == "Bearer secret", str(direct.get("error")))

	var hopped: Dictionary = await LFHttp.request(HTTPClient.METHOD_GET, base + "/redir", auth, "", 10000)
	var after: Dictionary = hopped.json if hopped.json is Dictionary else {}
	_check("cross-origin redirect reaches /echo", hopped.ok and not after.is_empty(), str(hopped.get("error")))
	_check("Authorization is absent after the cross-origin redirect",
			not after.is_empty() and not after.has("authorization"), str(after))

	var before := _frames
	var whole: Dictionary = await LFHttp.request(HTTPClient.METHOD_GET, base + "/big", {}, "", 20000)
	var advanced := _frames - before
	_check("5 MiB body read completes", whole.ok and whole.body_bytes.size() == 5 * MIB, str(whole.get("error")))
	_check("frames keep advancing while the body is read (>= 4 frames, got %d)" % advanced, advanced >= 4, str(advanced))

	quit(1 if _failed else 0)
