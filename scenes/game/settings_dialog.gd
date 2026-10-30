extends GameDialog
## Shared settings for the menu and board. Changes are saved and applied immediately.

signal settings_changed
signal reload_requested

var profile: Dictionary = {}
var show_debug_settings := false
var done_text := "Done"


func _init() -> void:
	super("Your finishing touches", "Make the sparkle feel like you.", "settings")
	preferred_height = 1420
	hide()


func _ready() -> void:
	super()
	_setting("Placing gems", "fill_animation", GemCatalog.ANIMATIONS, "animations")
	_setting("Grand finale", "finale", GemCatalog.FINALES, "finales")
	_frame_rate_setting()
	if show_debug_settings and OS.is_debug_build():
		_unlock_all_setting()
	var done := GameTheme.button(done_text, true)
	done.pressed.connect(close)
	actions.add_child(done)


func _setting(label: String, key: String, catalog: Dictionary, unlocked: String) -> void:
	var options := UI.field(body, label, "sparkle")
	options.name = key.to_pascal_case()
	var settings: Dictionary = profile["settings"]
	for id: String in catalog:
		if id in profile["unlocks"].get(unlocked, []):
			options.add_item(catalog[id]["name"])
			options.set_item_metadata(options.item_count - 1, id)
			if id == settings.get(key, ""):
				options.select(options.item_count - 1)
	var about := UI.label("", 29, GameTheme.TEXT_DIM)
	body.add_child(about)
	if options.selected >= 0:
		about.text = catalog[options.get_item_metadata(options.selected)].get("about", "")
	options.item_selected.connect(func(i: int) -> void:
		settings[key] = options.get_item_metadata(i)
		about.text = catalog[settings[key]].get("about", "")
		SaveStore.save_profile(profile)
		settings_changed.emit())


func _frame_rate_setting() -> void:
	var options := UI.field(body, "FPS cap", "settings")
	options.name = "FpsCap"
	var labels := ["30 FPS · Recommended", "60 FPS", "90 FPS", "120 FPS", "Unlimited"]
	for i in SaveStore.FPS_CAPS.size():
		options.add_item(labels[i])
		options.set_item_metadata(i, SaveStore.FPS_CAPS[i])
		if SaveStore.FPS_CAPS[i] == SaveStore.fps_cap(profile["settings"]):
			options.select(i)
	body.add_child(UI.label("Lower frame rates use less battery. Higher frame rates make movement smoother, "
			+ "up to what your screen supports. Changes apply right away.", 29, GameTheme.TEXT_DIM))
	options.item_selected.connect(func(i: int) -> void:
		profile["settings"]["fps_cap"] = options.get_item_metadata(i)
		SaveStore.apply_settings(profile)
		SaveStore.save_profile(profile)
		settings_changed.emit())


## Only the menu offers debug unlocks: changing a collection rebuilds that screen.
func _unlock_all_setting() -> void:
	body.add_child(UI.label("Testing (debug builds only)", 32, GameTheme.GOLD))
	var on := SaveStore.is_unlock_all(profile)
	var toggle := GameTheme.button("Unlock everything: %s" % ("On" if on else "Off"))
	toggle.theme_type_variation = "QuietButton"
	toggle.name = "UnlockAll"
	toggle.pressed.connect(func() -> void:
		SaveStore.set_unlock_all(profile, not SaveStore.is_unlock_all(profile))
		SaveStore.save_profile(profile)
		reload_requested.emit())
	body.add_child(toggle)
	body.add_child(UI.label("Every color, shape, cut, theme, picture type, flourish and animation, for "
			+ "testing. Your own collection is kept and comes back when this is off.", 29, GameTheme.TEXT_DIM))
