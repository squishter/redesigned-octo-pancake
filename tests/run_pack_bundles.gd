extends SceneTree
## Bundle economy and real reveal-controller checks. Use isolated XDG_DATA_HOME.

const GameTheme := preload("res://scenes/game/game_theme.gd")
const CollectionScreen := preload("res://scenes/game/collection_screen.gd")
var _checks := 0
var _failures := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_size = Vector2i(1080, 2400)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.theme = GameTheme.build()
	_test_payments()
	await _test_debug_free_purchases()
	_test_stock()
	_test_mixed_bundle()
	_test_newly_eligible_cuts()
	_test_pack_rewards()
	_test_everything_stock()
	await _test_everything_purchase()
	await _test_theme_bonus_flow()
	await _test_card_sequence()
	await _test_long_summary()
	await _test_empty_reveal()
	print("Pack bundles: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: ", message)


func _profile() -> Dictionary:
	return SaveStore.upgrade({"wallet": {"coins": 120, "picks": 2}})


func _catalog(pack: String, count: int) -> Dictionary:
	var catalog: Dictionary = Packs.PACKS.duplicate(true)
	catalog[pack]["rewards"] = count
	return catalog


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8421
	return rng


func _base(rewards: Array) -> Array:
	return rewards.filter(func(item: Dictionary) -> bool: return not item.get("bonus", false))


func _check_receipt(profile: Dictionary, rewards: Array) -> void:
	var seen := {}
	for item: Dictionary in rewards:
		var key := "%s|%s" % [item["kind"], item["id"]]
		_check(not seen.has(key), "Distinct receipt entry: " + key)
		seen[key] = true
		if item["kind"] == "power":
			_check(Packs.charges(profile, item["id"]) >= int(item["charges"]), "Power charges are granted")
		else:
			_check(Unlockables.has(profile["unlocks"], item), "Receipt reward is actually unlocked: " + key)


func _test_payments() -> void:
	print("One payment for all rewards")
	var profile := _profile()
	var before: int = profile["unlocks"]["colors"].size()
	var rewards := Packs.open(profile, "colors", false, _rng(), _catalog("colors", 3))
	_check(_base(rewards).size() == 3, "Three base rewards are drawn")
	_check(profile["unlocks"]["colors"].size() == before + 3, "All three colors are granted")
	_check(Packs.coins(profile) == 90 and Packs.picks(profile) == 2, "Coin purchase charges once")
	_check_receipt(profile, rewards)
	var powers_before: Dictionary = profile["powers"].duplicate()
	var powers := Packs.open(profile, "powers", true, _rng(), _catalog("powers", 3))
	_check(_base(powers).size() == 3 and Packs.picks(profile) == 1, "One pick buys a three-power bundle")
	for power: Dictionary in powers:
		_check(Packs.charges(profile, power["id"]) - int(powers_before.get(power["id"], 0)) == int(power["charges"]),
			"Power quantity is preserved for " + power["id"])
	_check_receipt(profile, powers)
	var single := Packs.open(profile, "shapes", true, _rng())
	_check(_base(single).size() == 1 and Packs.picks(profile) == 0, "Default packs still give one base reward")
	_check(Packs.price("colors") == 30 and Packs.price("powers") == 10, "Existing pack prices are unchanged")
	profile["wallet"] = {"coins": 0, "picks": 0}
	var snapshot := JSON.stringify(profile)
	_check(Packs.open(profile, "colors", false, _rng(), _catalog("colors", 4)).is_empty(), "Unaffordable bundle is rejected")
	_check(Packs.open(profile, "colors", true, _rng()).is_empty(), "A missing pick cannot buy a bundle")
	_check(Packs.open(profile, "unknown", false, _rng()).is_empty(), "Unknown pack is rejected")
	_check(JSON.stringify(profile) == snapshot, "Failed purchases never change the wallet or unlocks")
	profile = _profile()
	snapshot = JSON.stringify(profile)
	_check(Packs.open(profile, "all", true, _rng()).is_empty(), "Free picks cannot buy Everything packs")
	_check(JSON.stringify(profile) == snapshot, "Rejected Everything free pick changes nothing")
	profile["wallet"]["coins"] = 49
	snapshot = JSON.stringify(profile)
	_check(Packs.open(profile, "all", false, _rng()).is_empty(), "49 coins cannot buy an Everything pack")
	_check(JSON.stringify(profile) == snapshot, "Unaffordable Everything pack changes nothing")


func _test_debug_free_purchases() -> void:
	print("Debug free purchases preserve balances and respect pack availability")
	_check(not SaveStore.free_purchases_enabled(_profile()), "Free purchases are off by default")
	for pack: String in Packs.PACKS:
		var profile := SaveStore.upgrade({"wallet": {"coins": 0, "picks": 0}})
		SaveStore.set_free_purchases(profile, true)
		var rewards := Packs.open(profile, pack, false, _rng())
		_check(not rewards.is_empty(), "Debug mode can open %s with an empty wallet" % pack)
		_check(Packs.coins(profile) == 0 and Packs.picks(profile) == 0, "Debug purchases never debit the wallet: " + pack)
		_check_receipt(profile, rewards)
		SaveStore.set_free_purchases(profile, false)
		_check(Packs.open(profile, pack, false, _rng()).is_empty(), "Disabling debug mode restores affordability: " + pack)
	var profile := _profile()
	SaveStore.set_free_purchases(profile, true)
	_check(not Packs.open(profile, "colors", true, _rng()).is_empty(), "Debug mode also allows the pick payment path")
	_check(Packs.coins(profile) == 120 and Packs.picks(profile) == 2, "Debug mode preserves existing coin and pick balances")
	var snapshot := JSON.stringify(profile)
	_check(Packs.open(profile, "all", true, _rng()).is_empty(), "Everything still uses its coin purchase path")
	_check(Packs.open(profile, "unknown", false, _rng()).is_empty(), "Free purchases reject unknown packs")
	_check(JSON.stringify(profile) == snapshot, "Rejected debug purchases change nothing")
	profile["unlocks"] = Unlockables.all_unlocks()
	snapshot = JSON.stringify(profile)
	_check(Packs.open(profile, "colors", false, _rng()).is_empty(), "Free purchases cannot open sold-out packs")
	_check(Packs.open(profile, "all", false, _rng()).is_empty(), "Free Everything packs still require two unlockables")
	_check(JSON.stringify(profile) == snapshot, "Sold-out debug purchases change nothing")
	var screen := CollectionScreen.new()
	screen.profile = SaveStore.upgrade({"wallet": {"coins": 0, "picks": 0}})
	SaveStore.set_free_purchases(screen.profile, true)
	root.add_child(screen)
	screen._update_pack("all")
	await _frames()
	_check(not screen._buy.disabled and screen._buy.text == "Open free (debug)", "Debug UI offers a free Everything purchase")
	_check(not screen._free.visible, "Debug UI avoids spending a free pick")
	screen._open("all", false)
	var saved := SaveStore.load_profile()
	_check(SaveStore.free_purchases_enabled(saved), "Debug mode survives saving and loading")
	_check(Packs.coins(saved) == 0 and Packs.picks(saved) == 0, "The saved wallet stays unchanged")
	_check_receipt(saved, screen._opening.rewards)
	SaveStore.set_free_purchases(screen.profile, false)
	SaveStore.save_profile(screen.profile)
	screen._update_pack("all")
	_check(screen._buy.disabled and screen._buy.text == "50 coins", "Disabling debug mode restores normal UI prices")
	screen.queue_free()
	await process_frame


func _test_stock() -> void:
	print("Low stock and sold-out bundles")
	var profile := _profile()
	var available := Packs.pool("colors", profile)
	var missing := [available[0]["id"], available[1]["id"]]
	for item: Dictionary in available:
		if not item["id"] in missing:
			Unlockables.grant(profile, item)
	var rewards := Packs.open(profile, "colors", false, _rng(), _catalog("colors", 5))
	_check(_base(rewards).size() == 2, "Low stock gives the remaining rewards without duplicates")
	_check(Packs.coins(profile) == 90, "A low-stock bundle still charges only once")
	_check_receipt(profile, rewards)
	var snapshot := JSON.stringify(profile)
	_check(Packs.sold_out("colors", profile), "The completed category is sold out")
	_check(Packs.open(profile, "colors", false, _rng(), _catalog("colors", 5)).is_empty(), "Sold-out bundle is rejected")
	_check(JSON.stringify(profile) == snapshot, "Sold-out bundle cannot charge or grant anything")


func _test_mixed_bundle() -> void:
	print("Configurable mixed pack with a single price")
	var profile := _profile()
	var catalog: Dictionary = Packs.PACKS.duplicate(true)
	catalog["bundle"] = {"name": "Discovery bundle", "source": "all", "rewards": 12, "price": 75}
	var rewards := Packs.open(profile, "bundle", false, _rng(), catalog)
	_check(_base(rewards).size() == 12, "Mixed bundle gives every requested base draw")
	_check(Packs.coins(profile) == 45, "The custom bundle price is charged once")
	_check_receipt(profile, rewards)


func _near_themes() -> Dictionary:
	var profile := _profile()
	var candidates := Packs.pool("colors", profile)
	var missing := ""
	var best := -1
	for item: Dictionary in candidates:
		var memberships := 0
		for theme: Dictionary in GemCatalog.THEMES.values():
			if item["id"] in theme["gems"]:
				memberships += 1
		if memberships > best:
			missing = item["id"]
			best = memberships
	for item: Dictionary in candidates:
		if item["id"] != missing:
			Unlockables.grant(profile, item)
	return profile


func _test_newly_eligible_cuts() -> void:
	print("Later draws can unlock cuts for a shape found earlier in the bundle")
	var profile := _profile()
	var shape: String = Packs.pool("shapes", profile)[0]["id"]
	for kind: String in Unlockables.KINDS:
		if kind in ["theme", "power"]:
			continue
		for entry: Dictionary in Unlockables.items(kind):
			if (kind == "shape" and entry["id"] == shape) or (kind == "cut" and entry["shape"] == shape):
				continue
			Unlockables.grant(profile, entry)
	_check(not Packs.sold_out("all", profile), "A remaining shape can supply its newly eligible cut")
	var rewards := Packs.open(profile, "all", false, _rng(), _catalog("all", 100))
	var shape_index := -1
	var cut_count := 0
	for i in rewards.size():
		var entry := rewards[i]
		if entry["kind"] == "shape" and entry["id"] == shape:
			shape_index = i
		elif entry["kind"] == "cut" and entry["shape"] == shape:
			cut_count += 1
			_check(shape_index >= 0 and shape_index < i, "A cut follows its required shape")
	_check(shape_index >= 0 and cut_count > 0, "The same bundle finds a shape and its newly eligible cuts")
	_check(Packs.coins(profile) == 70 and Packs.picks(profile) == 2, "Dependent rewards cost 50 coins and no picks")
	_check_receipt(profile, rewards)


func _test_pack_rewards() -> void:
	print("Production reward counts, independent rare rolls and power-up quantities")
	_check(Packs.price("all") == 50 and not Packs.can_use_pick("all"), "Everything is 50 coins, coins only")
	var template := _profile()
	var outcomes := {}
	var rare_count := 0
	var bonus_count := 0
	for value in 450:
		var profile: Dictionary = template.duplicate(true)
		var rng := RandomNumberGenerator.new()
		rng.seed = value
		var rewards := Packs.open(profile, "all", false, rng)
		var unlocks := _base(rewards)
		var powers := rewards.filter(func(item: Dictionary) -> bool: return item["kind"] == "power")
		_check(unlocks.size() in [2, 3] and unlocks.all(func(item: Dictionary) -> bool: return item["kind"] != "power"),
			"Everything guarantees two or three distinct unlockables")
		_check(powers.size() in [0, 1] and powers.all(func(item: Dictionary) -> bool: return item.get("bonus", false)),
			"Everything's optional power-up is an extra reward")
		_check(Packs.coins(profile) == 70 and Packs.picks(profile) == 2, "Every Everything outcome costs exactly 50 coins")
		var key := "%d/%d" % [unlocks.size(), powers.size()]
		if not outcomes.has(key):
			_check_receipt(profile, rewards)
		outcomes[key] = true
		rare_count += int(unlocks.size() == 3)
		bonus_count += powers.size()
	_check(outcomes.size() == 4, "Independent rolls produce 2, 2+power, 3, and 3+power outcomes")
	_check(rare_count >= 15 and rare_count <= 50, "Third unlockable occurs about 1 in 15 times: %d/450" % rare_count)
	_check(bonus_count >= 60 and bonus_count <= 120, "Power bonus occurs about 1 in 5 times: %d/450" % bonus_count)
	for pack: String in Packs.PACKS:
		if pack == "all":
			continue
		var bonuses := 0
		for value in 50:
			var profile: Dictionary = template.duplicate(true)
			var before: Dictionary = profile["powers"].duplicate()
			var rng := RandomNumberGenerator.new()
			rng.seed = value
			var rewards := Packs.open(profile, pack, true, rng)
			var base := _base(rewards)
			var extra := rewards.filter(func(item: Dictionary) -> bool:
				return item["kind"] == "power" and item.get("bonus", false))
			_check(base.size() == (2 if pack == "powers" else 1), "Guaranteed base reward count: " + pack)
			_check(extra.size() in [0, 1], "At most one extra power-up per pack: " + pack)
			bonuses += extra.size()
			for item: Dictionary in rewards:
				if item["kind"] == "power":
					_check(Packs.charges(profile, item["id"]) - int(before.get(item["id"], 0)) == int(item["charges"]),
						"Every base or bonus power-up grants its usual charges once")
			_check(Packs.picks(profile) == 1 and Packs.coins(profile) == 120, "A free pick pays once, including bonuses")
		_check(bonuses > 0 and bonuses < 50, "Every pack can roll a bonus power-up: " + pack)


func _test_everything_stock() -> void:
	print("Everything guarantees two unlockables even near collection completion")
	var profile := _profile()
	var missing := Packs.pool("colors", profile).slice(0, 2)
	profile["unlocks"] = Unlockables.all_unlocks()
	for item: Dictionary in missing:
		profile["unlocks"]["colors"].erase(item["id"])
	_check(not Packs.sold_out("all", profile), "Two remaining unlockables allow an Everything purchase")
	var rewards := Packs.open(profile, "all", false, _rng())
	_check(_base(rewards).size() == 2, "Everything grants both remaining unlockables")
	_check(Packs.sold_out("all", profile), "A complete collection sells out Everything packs")
	profile["unlocks"]["colors"].erase(missing[0]["id"])
	var snapshot := JSON.stringify(profile)
	_check(Packs.sold_out("all", profile), "One remaining unlockable cannot fill an Everything pack")
	_check(Packs.open(profile, "all", false, _rng()).is_empty(), "Everything never sells a short bundle")
	_check(JSON.stringify(profile) == snapshot, "A short bundle charges nothing and grants no power bonus")
	_check(not Packs.sold_out("powers", profile), "Power-up packs remain available after collection completion")


func _test_everything_purchase() -> void:
	print("Everything payment UI, atomic save, and bonus reveal")
	var screen := CollectionScreen.new()
	screen.profile = _profile()
	root.add_child(screen)
	screen._update_pack("all")
	await _frames()
	_check(not screen._free.visible and screen._free.disabled, "Everything hides and disables free-pick payment")
	_check(screen._buy.text == "50 coins" and not screen._buy.disabled, "Everything shows its 50-coin price")
	_check("1 in 15" in screen._pack_about.text and "1 in 5" in screen._pack_about.text, "Pack details disclose both odds")
	screen._open("all", true)
	_check(not is_instance_valid(screen._opening), "Calling the UI's free-pick path cannot buy Everything")
	screen._update_pack("powers")
	_check(screen._free.visible and not screen._free.disabled, "Switching packs restores eligible free-pick payment")
	screen._update_pack("all")
	# Find a deterministic seed with both extras to exercise the complete saved receipt.
	for value in 450:
		var rng := RandomNumberGenerator.new()
		rng.seed = value
		if rng.randi_range(1, 5) == 1 and rng.randi_range(1, 15) == 1:
			screen._rng.seed = value
			break
	screen._open("all", false)
	screen._open("all", false)
	var saved := SaveStore.load_profile()
	_check(Packs.coins(saved) == 70 and Packs.picks(saved) == 2, "Purchase and all rewards save before reveal; repeat press is ignored")
	_check(_base(screen._opening.rewards).size() == 3, "The lucky paid bundle includes three unlockables")
	_check_receipt(saved, screen._opening.rewards)
	screen._opening.show_reward()
	await _frames()
	_check_summary(screen._opening)
	var bonus: Dictionary = screen._opening.rewards.filter(func(item: Dictionary) -> bool: return item["kind"] == "power")[0]
	var card := PackOpening.new()
	card.item = bonus
	root.add_child(card)
	_check(card.find_children("*", "Label", true, false).any(func(label: Label) -> bool: return label.text == "BONUS POWER-UP"),
		"A bonus power-up is labeled separately from a bonus color story")
	card.queue_free()
	screen.queue_free()
	await process_frame


func _frames() -> void:
	for _i in 5:
		await process_frame


func _check_summary(opening: PackOpening) -> void:
	_check(opening._showing_summary and opening._summary.visible, "Full summary is visible")
	var labels := opening._summary.body.find_children("*", "Label", true, false)
	for reward: Dictionary in opening.rewards:
		_check(labels.any(func(label: Label) -> bool: return reward["name"] in label.text),
			"Summary includes " + str(reward["name"]))
	var rect := opening._summary.card.get_global_rect()
	_check(rect.position.y >= 0 and rect.end.y <= opening.size.y, "Summary fits the phone viewport")
	_check(opening._summary.actions.get_global_rect().end.y <= opening.size.y, "Summary actions stay on screen")


func _test_theme_bonus_flow() -> void:
	print("Real purchase: completed themes become cards and skipping shows all")
	var screen := CollectionScreen.new()
	screen.profile = _near_themes()
	root.add_child(screen)
	await _frames()
	var before: Dictionary = screen.profile["unlocks"].duplicate(true)
	screen._open("colors", true)
	screen._open("colors", true)
	var opening: PackOpening = screen._opening
	var earned := Unlockables.themes_gained(before, screen.profile["unlocks"])
	var powers := opening.rewards.filter(func(item: Dictionary) -> bool: return item["kind"] == "power")
	_check(opening.rewards.size() == 1 + earned.size() + powers.size() and earned.size() > 0, "Every completed theme is a bonus card")
	_check(Packs.picks(screen.profile) == 1, "Repeated purchase press spends one pick")
	var saved := SaveStore.load_profile()
	_check(Packs.picks(saved) == 1, "The entire purchase is saved before the foil opens")
	_check_receipt(saved, opening.rewards)
	var snapshot := JSON.stringify(screen.profile)
	opening.show_reward()
	await _frames()
	_check_summary(opening)
	_check(JSON.stringify(screen.profile) == snapshot, "Skipping changes no grants or payment")
	var dismissed := [0]
	opening.dismissed.connect(func() -> void: dismissed[0] += 1)
	screen.go_back()
	opening.close()
	await create_timer(0.25).timeout
	_check(dismissed[0] == 1, "Back and repeated close dismiss only once")
	_check(Packs.picks(screen.profile) == 1, "Dismissal cannot charge a second pick")
	screen.queue_free()
	await process_frame


func _test_card_sequence() -> void:
	print("Sequential cards, rapid next presses, and skipping mid-flip")
	var screen := CollectionScreen.new()
	screen.profile = _profile()
	var rewards := Packs.open(screen.profile, "colors", true, _rng(), _catalog("colors", 3))
	SaveStore.save_profile(screen.profile)
	root.add_child(screen)
	screen._reveal("colors", rewards)
	var opening: PackOpening = screen._opening
	opening._timeline.custom_step(10)
	_check(opening._revealed and opening.item["id"] == rewards[0]["id"], "First card is revealed after the foil opens")
	opening._keep.pressed.emit()
	opening._keep.pressed.emit()
	opening._timeline.custom_step(0.3)
	opening._timeline.custom_step(1)
	_check(opening._index == 1 and opening.item["id"] == rewards[1]["id"], "Rapid next presses advance exactly one card")
	opening._keep.pressed.emit()
	opening._timeline.custom_step(0.3)
	opening._timeline.custom_step(1)
	_check(opening._index == 2 and opening._revealed, "The last reward has its own reveal")
	opening._keep.pressed.emit()
	await _frames()
	_check_summary(opening)
	opening._summary.close()
	await create_timer(0.25).timeout
	var snapshot := JSON.stringify(screen.profile)
	screen._reveal("colors", rewards)
	opening = screen._opening
	opening._timeline.custom_step(10)
	opening._keep.pressed.emit()
	opening.show_reward()
	await create_timer(0.3).timeout
	_check_summary(opening)
	_check(opening._index == 0, "Skipping cancels the pending card-flip callback")
	_check(JSON.stringify(screen.profile) == snapshot, "Replaying or skipping presentation never changes the receipt")
	opening.advance_or_close()
	await create_timer(0.25).timeout
	screen.queue_free()
	await process_frame


func _test_long_summary() -> void:
	print("Large bundle summary scrolls and preserves quantities")
	var screen := CollectionScreen.new()
	screen.profile = _profile()
	var rewards := Packs.open(screen.profile, "all", false, _rng(), _catalog("all", 30))
	root.add_child(screen)
	screen._reveal("all", rewards)
	screen._opening.show_reward()
	await _frames()
	_check_summary(screen._opening)
	_check(screen._opening._summary.body.get_child_count() == rewards.size(), "Every reward gets a summary row")
	screen.queue_free()
	await process_frame


func _test_empty_reveal() -> void:
	var opening := PackOpening.new()
	var dismissed := [0]
	opening.dismissed.connect(func() -> void: dismissed[0] += 1)
	root.add_child(opening)
	opening.show_reward()
	await _frames()
	_check(not is_instance_valid(opening) and dismissed[0] == 1, "An empty reveal closes safely without a fake reward")
