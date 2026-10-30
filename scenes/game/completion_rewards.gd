class_name CompletionRewards
extends GameDialog
## Displays an already saved completion reward. Never grants or spends currency.

signal packs_requested
signal menu_requested

var reward: Dictionary = {}
var profile: Dictionary = {}
var picture: Texture2D
var puzzle_name := "Your picture"


func _init() -> void:
	super("A little masterpiece!", "Here's what you earned", "trophy")
	preferred_height = 1660


func _ready() -> void:
	super._ready()
	body.add_child(UI.label("PICTURE COMPLETE", 27, GameTheme.MINT, true))
	var artwork := UI.panel(false, 18)
	body.add_child(artwork)
	var art := TextureRect.new()
	art.texture = picture
	art.custom_minimum_size.y = 350
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	artwork.add_child(art)
	body.add_child(UI.label(puzzle_name, 42, GameTheme.GOLD, true))
	var coins := int(reward.get("coins", 0))
	if coins > 0:
		UI.item(body, "+%d coins" % coins,
			"Double coins bonus included" if coins > Packs.COINS_PER_PUZZLE else "A little more toward your next discovery", "coin")
	if reward.get("pick", false):
		UI.item(body, "+1 free pick", "Your first finished picture of the day", "pack")
	if coins == 0 and not reward.get("pick", false):
		UI.item(body, "Already celebrated", "This picture's rewards are already in your collection.", "trophy")
	body.add_child(UI.label("WALLET  ·  %d coins  ·  %d free picks" % [Packs.coins(profile), Packs.picks(profile)],
		28, GameTheme.TEXT_DIM, true))
	var admire := GameTheme.button("Admire my picture", true)
	admire.icon = GameTheme.icon("picture")
	admire.pressed.connect(close)
	actions.add_child(admire)
	var links := HBoxContainer.new()
	actions.add_child(links)
	for option: Array in [["Collection & packs", packs_requested], ["Menu", menu_requested]]:
		var button := GameTheme.button(option[0])
		button.add_theme_font_size_override("font_size", 30)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var action: Signal = option[1]
		button.pressed.connect(func() -> void: action.emit())
		links.add_child(button)
