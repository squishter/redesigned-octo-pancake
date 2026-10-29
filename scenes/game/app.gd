extends Control
## The game's root: shows the menu, a puzzle being played, Collection &
## packs, or the generator lab (a debug mode for trying out new pattern
## generation), one at a time. Holds her profile (SaveStore), shared by all
## of them, and gives the day's free pick for opening the game (see Packs).

const LabTheme := preload("res://scenes/dev/lab_theme.gd")
const MainMenu := preload("res://scenes/game/main_menu.gd")
const PlayScreen := preload("res://scenes/game/play_screen.gd")
const CollectionScreen := preload("res://scenes/game/collection_screen.gd")
const LAB_SCENE := preload("res://scenes/dev/generator_lab.tscn")

var profile: Dictionary = {}
var _screen: Control


func _ready() -> void:
	get_tree().root.theme = LabTheme.build()
	RenderingServer.set_default_clear_color(LabTheme.BG)
	profile = SaveStore.load_profile()
	_show_menu()


func _show_menu() -> void:
	# A new day (the game may have stayed open overnight): a free pick.
	if Packs.daily_open(profile):
		SaveStore.save_profile(profile)
	var menu := MainMenu.new()
	menu.profile = profile
	menu.play_requested.connect(_play)
	menu.lab_requested.connect(_show_lab)
	menu.collection_requested.connect(_show_collection)
	_swap(menu)


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
	_swap(play)


func _show_lab() -> void:
	var lab: Control = LAB_SCENE.instantiate()
	lab.set("show_back", true)
	lab.connect("back_requested", _show_menu)
	_swap(lab)


func _swap(next: Control) -> void:
	if _screen != null:
		_screen.queue_free()
	_screen = next
	add_child(next)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _screen != null and _screen.has_method("go_back"):
		_screen.call("go_back")
