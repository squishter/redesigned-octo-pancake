class_name BuildInfo
extends RefCounted
## Which build this is. tools/build_apk.sh writes STAMP_PATH just before it
## exports (and deletes it after), so an APK knows the commit it was built
## from and when; the editor and tests, with no stamp, are a development
## build. Settings shows line() at the bottom so a player can say which
## build she has. The project's version (export_presets.cfg) stays 0.1.0, so
## this is the only way to tell builds apart.

const STAMP_PATH := "res://game/build_stamp.json"


## The stamp: {commit, branch, dirty, built (UTC, ISO 8601), mode}, or empty
## when there is none.
static func stamp() -> Dictionary:
	if not FileAccess.file_exists(STAMP_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STAMP_PATH))
	return parsed if parsed is Dictionary else {}


## One line for people: "Build 657adc2 · 27 Nov 2026 14:05 UTC", with
## "+ changes" when it was built from uncommitted work, or
## "Development build" with no stamp.
static func line(from: Dictionary = stamp()) -> String:
	var commit := str(from.get("commit", ""))
	if commit == "":
		return "Development build"
	var text := "Build %s" % commit
	if bool(from.get("dirty", false)):
		text += " + changes"
	var built := str(from.get("built", ""))
	if built.length() >= 16:
		var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
		var month := clampi(built.substr(5, 2).to_int(), 1, 12)
		text += " · %d %s %s %s UTC" % [built.substr(8, 2).to_int(), months[month - 1], built.substr(0, 4),
				built.substr(11, 5)]
	return text
