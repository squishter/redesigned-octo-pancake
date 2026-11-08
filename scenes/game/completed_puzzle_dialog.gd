class_name CompletedPuzzleDialog
extends GameDialog
## Actions for a finished picture. Restarting requires a separate confirmation state.

signal admired(puzzle_id: String)
signal restarted(puzzle_id: String)
signal recolored(puzzle_id: String)

var _puzzle: Dictionary = {}
var _confirming := false
var _art: TextureRect
var _admire: Button
var _restart: Button
var _recolor: Button
var _cancel: Button


func _init() -> void:
	super("A beautiful finish", "", "trophy")
	preferred_height = 1580
	_art = TextureRect.new()
	_art.custom_minimum_size.y = 400
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	body.add_child(_art)
	_admire = _action("Admire", func() -> void:
		close()
		admired.emit(_puzzle["id"]))
	_admire.icon = GameTheme.icon("picture")
	_admire.theme_type_variation = "PrimaryButton"
	_restart = _action("Restart", _ask_restart)
	_recolor = _action("Recolor", func() -> void: recolored.emit(_puzzle["id"]))
	_cancel = _action("Back to gallery", _back)
	_cancel.icon = GameTheme.icon("back")


func open_puzzle(meta: Dictionary) -> void:
	_puzzle = meta
	_art.texture = SaveStore.load_thumbnail(meta["id"])
	if _art.texture == null:
		_art.texture = GameTheme.icon("picture")
	_set_confirmation(false)
	body_scroll.scroll_vertical = 0
	open()


func _ask_restart() -> void:
	if not _confirming:
		_set_confirmation(true)
		return
	close()
	restarted.emit(_puzzle["id"])


func _set_confirmation(confirming: bool) -> void:
	_confirming = confirming
	title_label.text = "Restart this puzzle?" if confirming else GemCatalog.puzzle_title(_puzzle)
	subtitle_label.text = ("This will clear the placed gems and return the picture to your studio."
		if confirming else CompletedPuzzles.color_name(_puzzle))
	_admire.visible = not confirming
	_recolor.visible = not confirming
	_restart.text = "Restart puzzle" if confirming else "Restart"
	_restart.theme_type_variation = "PrimaryButton" if confirming else "QuietButton"
	_cancel.text = "Cancel" if confirming else "Back to gallery"
	contain_focus.call_deferred()


func _back() -> void:
	if _confirming:
		_set_confirmation(false)
	else:
		close()


func go_back() -> void:
	_back()


func _action(text: String, action: Callable) -> Button:
	var button := GameTheme.button(text)
	button.add_theme_font_size_override("font_size", 32)
	button.theme_type_variation = "QuietButton"
	button.pressed.connect(action)
	actions.add_child(button)
	return button
