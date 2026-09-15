extends SceneTree
## Run: godot --headless --path <project> --script res://tests/smoke.gd
const Runner = preload("res://scripts/core/story_runner.gd")
const SaveStore = preload("res://scripts/core/save_store.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
		push_error(description)

func _run() -> void:
	var runner = Runner.new()
	root.add_child(runner)
	check(runner.load_story("res://story/demo.json").is_empty(), "Load demo")
	runner.start()
	runner.advance()
	var checkpoint: Dictionary = runner.snapshot()
	runner.choose(0)
	runner.advance()
	check(runner.current_id == "repair", "Enter minigame")
	runner.complete_activity({"success": true, "score": 3})
	check(runner.current_id == "film", "Enter video")
	runner.complete_activity({"skipped": true})
	check(runner.current_step().get("ending_id") == "light", "Success ending")
	check(runner.restore(checkpoint).is_empty(), "Restore choice checkpoint")
	check(runner.variables.trust == 0, "Restore variables by value")
	runner.choose(0)
	runner.advance()
	runner.complete_activity({"success": false})
	runner.complete_activity({"skipped": true})
	check(runner.current_step().get("ending_id") == "wait", "Failed minigame ending")
	runner.restore(checkpoint)
	runner.choose(1)
	runner.complete_activity({"skipped": true})
	check(runner.current_step().get("ending_id") == "alone", "Leave ending")
	check(not runner.matches([{"var": "trust", "op": ">=", "value": 1}]), "Condition filtering")
	var invalid := checkpoint.duplicate(true)
	invalid["node"] = "missing"
	check(not runner.restore(invalid).is_empty(), "Reject missing save node")
	var store = SaveStore.new()
	check(store.write("framework_smoke", checkpoint).is_empty(), "Write save")
	check(store.write("framework_smoke", checkpoint).is_empty(), "Replace existing save")
	check(store.read("framework_smoke").get("data", {}) == checkpoint, "Read save roundtrip")
	DirAccess.remove_absolute("user://saves/framework_smoke.json")
	var game = load("res://scenes/minigames/signal_game.tscn").instantiate()
	root.add_child(game)
	var results: Array = []
	game.completed.connect(func(result: Dictionary): results.append(result))
	game.begin({"target": 3}, {})
	for index in range(3): game.get_node("Panel/Rows/Collect").pressed.emit()
	check(results.size() == 1 and results[0].get("success") == true, "Minigame completion contract")
	game.finish({"success": false})
	check(results.size() == 1, "Minigame completes only once")
	game.free()
	runner.free()
	print("FRAMEWORK_SMOKE: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
