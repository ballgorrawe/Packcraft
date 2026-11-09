class_name I18n
extends RefCounted
## Runtime translations without the editor's CSV import step.
## data/i18n.json = {"th": {"English source text": "คำแปล", ...}}.
## Code always uses the English text as the key (tr("Depart")), so a missing
## translation simply falls back to English.

const PATH := "res://data/i18n.json"
const LANGS := ["en", "th"]

static var _done := false


static func setup(lang: String) -> void:
	if not _done:
		_done = true
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				for loc in d:
					var t := Translation.new()
					t.locale = loc
					var m: Dictionary = d[loc]
					for k in m:
						t.add_message(k, m[k])
					TranslationServer.add_translation(t)
	set_lang(lang)


static func set_lang(lang: String) -> void:
	TranslationServer.set_locale(lang if LANGS.has(lang) else "en")


static func lang() -> String:
	return "th" if TranslationServer.get_locale().begins_with("th") else "en"


## Translate from static code (Node.tr is not available there).
static func t(s: String) -> String:
	return TranslationServer.translate(s)
