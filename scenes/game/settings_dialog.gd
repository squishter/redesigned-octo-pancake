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
		preferred_height = 1900
		_unlock_all_setting()
		_free_purchases_setting()
		_performance_settings()
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
	var labels := ["30 FPS · Recommended", "45 FPS", "60 FPS", "90 FPS", "120 FPS", "Unlimited"]
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
	body.add_child(UI.label("Every color, shape, cut, theme, picture type, flourish and animation, and "
			+ "unlimited power-ups, for testing. Your own collection and charges are kept and come back when "
			+ "this is off.", 29, GameTheme.TEXT_DIM))


func _free_purchases_setting() -> void:
	var toggle := GameTheme.button("")
	toggle.name = "FreePurchases"
	toggle.icon = GameTheme.icon("coin")
	toggle.theme_type_variation = "QuietButton"
	var refresh := func() -> void:
		toggle.text = "Free purchases: %s" % ("On" if SaveStore.free_purchases_enabled(profile) else "Off")
	refresh.call()
	toggle.pressed.connect(func() -> void:
		SaveStore.set_free_purchases(profile, not SaveStore.free_purchases_enabled(profile))
		SaveStore.save_profile(profile)
		refresh.call())
	body.add_child(toggle)
	body.add_child(UI.label("Open packs without spending coins or free picks, for testing. "
			+ "Your balances stay the same. Available only in debug builds.", 29, GameTheme.TEXT_DIM))


## Keep the phone performance tools beside the other debug settings.
func _performance_settings() -> void:
	var settings: Dictionary = profile["settings"]
	var readout := GameTheme.button("")
	readout.theme_type_variation = "QuietButton"
	readout.name = "PerfReadout"
	body.add_child(readout)
	var test := GameTheme.button("")
	test.theme_type_variation = "QuietButton"
	test.name = "BoardTest"
	body.add_child(test)
	var relabel := func() -> void:
		readout.text = "Performance readout: %s" % ("On" if PerfReadout.shown else "Off")
		test.text = "Board test: %s" % GemBoard3D.debug_test
	relabel.call()
	readout.pressed.connect(func() -> void:
		PerfReadout.shown = not PerfReadout.shown
		settings[PerfReadout.SHOWN_KEY] = PerfReadout.shown
		SaveStore.save_profile(profile)
		relabel.call())
	test.pressed.connect(func() -> void:
		var i := GemBoard3D.DEBUG_TESTS.find(GemBoard3D.debug_test)
		GemBoard3D.debug_test = GemBoard3D.DEBUG_TESTS[(i + 1) % GemBoard3D.DEBUG_TESTS.size()]
		settings[PerfReadout.TEST_KEY] = GemBoard3D.debug_test
		SaveStore.save_profile(profile)
		relabel.call())
	body.add_child(UI.label("The readout sits over the board while playing (holding the progress line "
			+ "also turns it on or off). Board test draws puzzles opened from now on with one part left out "
			+ "or cheapened, to see what costs what. Use FPS cap above to change the frame rate.", 29, GameTheme.TEXT_DIM))
