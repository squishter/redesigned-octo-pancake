extends Control
## The game's root: shows the menu, a puzzle being played, Collection &
## packs, or the generator lab (a debug mode for trying out new pattern
## generation), one at a time. Holds her profile (SaveStore), shared by all
## of them, and gives the day's free pick for opening the game (see Packs).

const LabTheme := preload("res://scenes/dev/lab_theme.gd")
const GameTheme := preload("res://scenes/game/game_theme.gd")
const MenuBackdrop := preload("res://scenes/game/menu_backdrop.gd")
const MainMenu := preload("res://scenes/game/main_menu.gd")
const PlayScreen := preload("res://scenes/game/play_screen.gd")
const CollectionScreen := preload("res://scenes/game/collection_screen.gd")
const SplashScreen := preload("res://scenes/game/splash_screen.gd")
const GemMenuReveal := preload("res://scenes/game/gem_menu_reveal.gd")
const LAB_SCENE := preload("res://scenes/dev/generator_lab.tscn")

var profile: Dictionary = {}
## Tests of other screens can bypass the launch presentation.
var show_splash := true
var _screen: Control
var _transitioning := false
var _backdrop: Control
var _veil: ColorRect
var _splash: SplashScreen
var _reveal: GemMenuReveal


func _ready() -> void:
	get_tree().root.theme = GameTheme.build()
	RenderingServer.set_default_clear_color(GameTheme.BG)
	_backdrop = MenuBackdrop.new()
	add_child(_backdrop)
	_veil = ColorRect.new()
	_veil.z_index = 1000
	_veil.color = Color(GameTheme.BG, 0.0)
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.hide()
	add_child(_veil)
	profile = SaveStore.load_profile()
	SaveStore.apply_settings(profile)
	PerfReadout.apply_settings(profile["settings"])
	if show_splash:
		_splash = SplashScreen.new()
		_splash.finished.connect(_reveal_menu)
		add_child(_splash)
		_screen = _splash
		_backdrop.hide()
	else:
		_show_menu()


func _show_menu() -> void:
	if _transitioning:
		return
	_swap(_make_menu())


func _make_menu() -> MainMenu:
	# A new day (the game may have stayed open overnight): a free pick.
	var daily_pick_awarded := Packs.daily_open(profile)
	if daily_pick_awarded:
		SaveStore.save_profile(profile)
	var menu := MainMenu.new()
	menu.profile = profile
	menu.daily_pick_awarded = daily_pick_awarded
	menu.play_requested.connect(_play)
	menu.lab_requested.connect(_show_lab)
	menu.collection_requested.connect(_show_collection)
	menu.reload_requested.connect(_show_menu)
	return menu


func _reveal_menu() -> void:
	if _transitioning:
		return
	_transitioning = true
	_reveal = GemMenuReveal.new()
	_reveal.menu = _make_menu()
	_reveal.finished.connect(_finish_reveal)
	add_child(_reveal)


func _finish_reveal() -> void:
	var menu := _reveal.menu as MainMenu
	menu.reparent(self, false)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.process_mode = Node.PROCESS_MODE_INHERIT
	_screen = menu
	_splash.queue_free()
	_splash = null
	_reveal.queue_free()
	_reveal = null
	_backdrop.show()
	move_child(_veil, get_child_count() - 1)
	_transitioning = false
	menu.present_daily_gift()


func _show_collection() -> void:
	var screen := CollectionScreen.new()
	screen.profile = profile
	screen.back_requested.connect(_show_menu)
	_swap(screen)


func _play(id: String) -> void:
	var play := PlayScreen.new()
	play.profile = profile
	play.puzzle_id = id
	play.back_requested.connect(_show_menu)
	play.collection_requested.connect(_show_collection)
	_swap(play)


func _show_lab() -> void:
	var lab: Control = LAB_SCENE.instantiate()
	lab.set("show_back", true)
	lab.theme = LabTheme.build()
	lab.connect("back_requested", _show_menu)
	_swap(lab, true)


func _swap(next: Control, debug := false) -> void:
	if _transitioning:
		next.free()
		return
	_transitioning = true
	_backdrop.visible = not debug
	RenderingServer.set_default_clear_color(LabTheme.BG if debug else GameTheme.BG)
	var previous := _screen
	_screen = next
	add_child(next)
	move_child(_veil, get_child_count() - 1)
	_veil.show()
	if previous != null:
		previous.process_mode = Node.PROCESS_MODE_DISABLED
	next.process_mode = Node.PROCESS_MODE_DISABLED
	next.modulate.a = 0.0
	next.position.y = 44.0
	var tween := create_tween()
	if previous != null:
		tween.tween_property(previous, "modulate:a", 0.0, 0.16)
		tween.parallel().tween_property(previous, "position:y", -24.0, 0.2).set_trans(Tween.TRANS_SINE)
		tween.parallel().tween_property(_veil, "color:a", 0.28, 0.16)
		tween.tween_callback(previous.queue_free)
	tween.tween_property(next, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(next, "position:y", 0.0, 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_veil, "color:a", 0.0, 0.3)
	tween.tween_callback(func() -> void:
		next.process_mode = Node.PROCESS_MODE_INHERIT
		_veil.hide()
		_transitioning = false
		if next is MainMenu:
			next.present_daily_gift())


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _transitioning and _screen != null and _screen.has_method("go_back"):
		_screen.call("go_back")
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if (what == NOTIFICATION_WM_GO_BACK_REQUEST and not _transitioning
			and _screen != null and _screen.has_method("go_back")):
		_screen.call("go_back")
