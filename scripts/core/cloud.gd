class_name Cloud
extends Node
## Online leaderboards (and later cloud saves) on Firebase, over its REST API: an anonymous account per
## browser, one score document per player per board. Off until project.godot has
## packcraft/firebase_api_key and packcraft/firebase_project (see docs/firebase_setup.md); while off,
## every call does nothing. Not shown in the game yet.
##
## Boards: "endless_<diff>" (deepest floor), "rush" (bosses beaten), "mastery" (levels over all
## classes), "weekly_<year>_<week>" (the weekly run's score).

signal top_loaded(board: String, rows: Array)   # rows: [{uid, name, score, cls, ver}], best first

const AUTH := "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=%s"
const REFRESH := "https://securetoken.googleapis.com/v1/token?key=%s"
const DOCS := "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents"

var _token := ""
var _token_at := 0.0


static func api_key() -> String:
	return str(ProjectSettings.get_setting("packcraft/firebase_api_key", ""))


static func project() -> String:
	return str(ProjectSettings.get_setting("packcraft/firebase_project", ""))


static func enabled() -> bool:
	return api_key() != "" and project() != ""


## Sends a score if it beats this player's best on that board (kept locally, so only bests travel).
func submit(board: String, score: int, cls := "") -> void:
	var key := "lb_best_" + board
	if not enabled() or score <= int(SaveGame.get_setting(key, 0)):
		return
	SaveGame.set_setting(key, score)
	if not await _auth():
		return
	var uid := str(SaveGame.get_setting("fb_uid", ""))
	var body := {"fields": {
		"score": {"integerValue": str(score)},
		"name": {"stringValue": str(SaveGame.get_setting("player_name", "Adventurer"))},
		"cls": {"stringValue": cls},
		"ver": {"stringValue": str(ProjectSettings.get_setting("application/config/version", ""))},
	}}
	await _request(DOCS % project() + "/boards/%s/scores/%s" % [board.uri_encode(), uid], HTTPClient.METHOD_PATCH, JSON.stringify(body))


## Loads the best 50 of a board; answers with top_loaded.
func load_top(board: String) -> void:
	if not enabled() or not await _auth():
		top_loaded.emit(board, [])
		return
	var q := {"structuredQuery": {"from": [{"collectionId": "scores"}],
		"orderBy": [{"field": {"fieldPath": "score"}, "direction": "DESCENDING"}], "limit": 50}}
	var res = await _request(DOCS % project() + "/boards/%s:runQuery" % board.uri_encode(), HTTPClient.METHOD_POST, JSON.stringify(q))
	var rows := []
	if res is Array:
		for e in res:
			var doc: Dictionary = e.get("document", {})
			if doc.is_empty():
				continue
			var f: Dictionary = doc.get("fields", {})
			rows.append({"uid": str(doc.name).get_file(), "name": f.get("name", {}).get("stringValue", "?"),
				"score": int(f.get("score", {}).get("integerValue", "0")), "cls": f.get("cls", {}).get("stringValue", ""),
				"ver": f.get("ver", {}).get("stringValue", "")})
	top_loaded.emit(board, rows)


## An anonymous account for this browser (made once), and a fresh ID token (they last an hour).
func _auth() -> bool:
	if _token != "" and Time.get_unix_time_from_system() - _token_at < 3000:
		return true
	var refresh := str(SaveGame.get_setting("fb_refresh", ""))
	var res
	if refresh == "":
		res = await _request(AUTH % api_key(), HTTPClient.METHOD_POST, JSON.stringify({"returnSecureToken": true}), false)
		if res is Dictionary and res.has("idToken"):
			SaveGame.set_setting("fb_uid", res.localId)
			SaveGame.set_setting("fb_refresh", res.refreshToken)
			_token = res.idToken
	else:
		res = await _request(REFRESH % api_key(), HTTPClient.METHOD_POST, "grant_type=refresh_token&refresh_token=" + refresh.uri_encode(), false, "application/x-www-form-urlencoded")
		if res is Dictionary and res.has("id_token"):
			SaveGame.set_setting("fb_refresh", res.refresh_token)
			_token = res.id_token
	if _token == "":
		return false
	_token_at = Time.get_unix_time_from_system()
	return true


## One HTTP call; the parsed JSON answer, or null on any failure (leaderboards never block the game).
func _request(url: String, method: int, body: String, auth := true, ctype := "application/json"):
	var h := HTTPRequest.new()
	add_child(h)
	var headers := ["Content-Type: " + ctype]
	if auth:
		headers.append("Authorization: Bearer " + _token)
	if h.request(url, headers, method, body) != OK:
		h.queue_free()
		return null
	var out: Array = await h.request_completed
	h.queue_free()
	if int(out[0]) != HTTPRequest.RESULT_SUCCESS or int(out[1]) >= 300:
		return null
	return JSON.parse_string((out[3] as PackedByteArray).get_string_from_utf8())
