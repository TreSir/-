extends Node
@onready var root: Window = get_tree().root
const Runtime = preload("res://scripts/core/story_runtime.gd")
const Compiler = preload("res://scripts/core/story_compiler.gd")
const Source = preload("res://scripts/core/json_source.gd")
const Migrations = preload("res://scripts/services/save_migrations.gd")
var failures := 0
var assertions := 0
var temporary_files: Array[String] = []
func _ready() -> void: _run.call_deferred()
func quit(code: int) -> void: get_tree().quit(code)
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("CHECK FAILED: " + message)
func fixture(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "\t"))
	file.close()
	if not temporary_files.has(path): temporary_files.append(path)

func _run() -> void:
	var runner = Runtime.new()
	root.add_child(runner)
	runner.auto_reload = false
	var error: String = runner.open("res://data/game.json")
	check(error.is_empty(), "compile: " + error)
	if not error.is_empty():
		quit(1)
		return
	Collections.configure(runner.bundle, false)
	runner.start()
	runner.submit({})
	check(runner.cursor == "prologue.invitation", "automatic commands reach choice")
	check(GameState.inventory.get("old_key") == 1 and GameState.inventory.get("tea") == 2, "declarative inventory rewards")
	var checkpoint := runner.save_data()
	check(Collections.discovered.has("keeper"), "event listener unlocks codex")
	check(Collections.use_item("tea").is_empty(), "use consumable")
	check(GameState.inventory.tea == 1 and GameState.flags.courage == 1, "consume and flag effect")
	var before := GameState.snapshot()
	check(not GameState.apply({"set": {"trsut": 2}}).is_empty(), "reject misspelled flag")
	check(not GameState.apply({"set": {"trust": true}}).is_empty(), "reject wrong flag type")
	check(not GameState.apply({"set": {"courage": 99}, "inventory": {"tea": -1}}).is_empty(), "reject out of range")
	check(before == GameState.snapshot(), "failed transaction changes nothing")
	runner.submit({"choice": 2})
	check(GameState.inventory.get("old_key", 0) == 0 and GameState.inventory.letter == 1, "exchange quest item")
	check(Collections.use_item("letter").is_empty() and Collections.discovered.has("letter_story"), "read collectible")
	check(GameState.inventory.letter == 1, "nonconsumable retained")
	runner.submit({})
	check(runner.view.options.size() == 2, "item-gated option hidden")
	check(runner.restore(checkpoint).is_empty(), "restore checkpoint")
	check(GameState.inventory.old_key == 1 and GameState.inventory.tea == 2, "restore inventory without replay")
	check(Collections.discovered.has("letter_story"), "codex does not roll back with save")
	runner.submit({"choice": 0})
	runner.submit({})
	check(runner.cursor == "prologue.repair", "minigame slot")
	var stale: int = runner.generation
	runner.submit({"result": {"success": true, "score": 3}}, stale)
	check(runner.cursor == "prologue.film", "activity result returns to story")
	runner.submit({"result": {"success": false}}, stale)
	check(GameState.flags["puzzle.success"], "stale completion ignored")
	runner.submit({"result": {"played": false, "skipped": true}})
	check(runner.view.get("ending_id") == "light", "highest priority ending")
	check(Collections.discovered.has("ending_light"), "ending listener")
	runner.restore(checkpoint)
	runner.submit({"choice": 0})
	runner.submit({})
	runner.submit({"result": {"success": false, "score": 0}})
	runner.submit({"result": {"skipped": true}})
	check(runner.view.get("ending_id") == "wait", "second ending")
	runner.restore(checkpoint)
	runner.submit({"choice": 1})
	runner.submit({"result": {"skipped": true}})
	check(runner.view.get("ending_id") == "alone", "fallback ending")
	runner.start()
	check(Collections.discovered.has("ending_light"), "new run retains collection")
	check(GameState.inventory.is_empty(), "new run resets backpack")
	var migrated: Dictionary = Migrations.new().migrate({"format": 1, "data": {
		"story_id": "lighthouse_demo", "story_version": 1, "node": "invitation",
		"variables": {"trust": 1, "puzzle.success": false, "puzzle.score": 0}}}, runner.bundle)
	check(not migrated.has("error") and runner.restore(migrated.get("data", {})).is_empty(), "legacy save migration")
	check(GameState.flags.has("courage"), "new flag defaults populated")
	var invalid := checkpoint.duplicate(true)
	invalid.state.inventory.tea = -1
	before = GameState.snapshot()
	check(not runner.restore(invalid).is_empty() and GameState.snapshot() == before, "bad save rejected atomically")
	invalid = checkpoint.duplicate(true)
	invalid.cursor = "prologue.gifts"
	check(not runner.restore(invalid).is_empty(), "no replay of automatic reward checkpoint")
	DirAccess.make_dir_recursive_absolute("user://framework_tests")
	SaveService.directory = "user://framework_tests"
	check(SaveService.save_slot("roundtrip", checkpoint).is_empty(), "write slot")
	temporary_files.append("user://framework_tests/roundtrip.json")
	check(SaveService.save_slot("roundtrip", checkpoint).is_empty(), "replace existing slot")
	var loaded: Dictionary = SaveService.load_slot("roundtrip", runner.bundle)
	check(loaded.get("data", {}) == checkpoint, "save JSON roundtrip")
	check(SaveService.load_slot("../slot_1", runner.bundle).has("error"), "invalid slot path rejected")
	fixture("user://framework_tests/corrupt.json", {"format": 999})
	check(SaveService.load_slot("corrupt", runner.bundle).has("error"), "unsupported save schema rejected")
	SaveService.directory = "user://saves"
	runner.restore(checkpoint)
	await _reload_checks(runner)
	var source = Source.new()
	source.parse_text("{\n  \"options\": [\n    {\"flag\": \"typo\"}\n  ]\n}", "fixture.json")
	check(source.locations.get("/options/0/flag") == 3, "exact nested JSON source line")
	source.parse_text("{\"id\":1,\"id\":2}", "duplicate.json")
	check(source.error.contains("重复 JSON 键"), "duplicate JSON keys rejected")
	source.parse_text("{\n  \"id\": }", "invalid.json")
	check(source.error.begins_with("invalid.json:2:"), "syntax error uses one-based line")
	check(Migrations.new().migrate({"format": {}}, runner.bundle).has("error"), "corrupt schema value safely rejected")
	check(runner.registry.commands.has("emit"), "extension command auto-registered")
	var captured: Array = []
	var listener := func(name: String, _payload: Dictionary): captured.append(name)
	EventBus.custom_event.connect(listener)
	var emitted: Dictionary = runner.registry.commands.emit.execute(runner, {"event": "test_extension", "payload": {}, "next": "prologue.arrival"})
	check(emitted.status == "goto" and captured.has("test_extension"), "new command runs through bus without core changes")
	EventBus.custom_event.disconnect(listener)
	var loop_node: Dictionary = {"id": "test.loop", "op": "jump", "next": "test.loop"}
	runner.bundle.nodes["test.loop"] = loop_node
	var loop_errors: Array = []
	runner.failed.connect(func(message: String): loop_errors.append(message))
	runner.jump_to("test.loop")
	check(not loop_errors.is_empty() and not runner.waiting, "automatic loop bounded")
	var game = load("res://scenes/minigames/signal_game.tscn").instantiate()
	root.add_child(game)
	var results: Array = []
	game.completed.connect(func(result: Dictionary): results.append(result))
	game.begin({"target": 3}, {})
	for index in 3: game.get_node("Panel/Rows/Collect").pressed.emit()
	game.finish({"success": false})
	check(results.size() == 1 and results[0].success, "minigame output contract exactly once")
	game.free()
	runner.free()
	await _ui_checks()
	for path in temporary_files: DirAccess.remove_absolute(path)
	print("FRAMEWORK_V2: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", assertions])
	quit(0 if failures == 0 else 1)

func _ui_checks() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	main.get_node("GameController").persist_progress = false
	root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var runner = main.get_node("StoryRunner")
	runner.auto_reload = false
	check(main.get_node("%Dialogue").text.contains("灯塔"), "UI renders localized opening")
	main.get_node("%Next").pressed.emit()
	check(main.get_node("%Choices").get_child_count() == 3, "UI renders choices")
	main.library_requested.emit("bag")
	check(main.library.visible and get_tree().paused, "inventory modal pauses gameplay")
	main.use_requested.emit("tea")
	check(GameState.flags.courage == 1, "UI uses inventory item")
	main.library.dismiss()
	check(not get_tree().paused, "closing modal resumes gameplay")
	main.get_node("%Choices").get_child(0).pressed.emit()
	main.get_node("%Next").pressed.emit()
	check(is_instance_valid(main.active_game), "UI mounts independent minigame")
	var instance = main.active_game
	for index in 3: instance.get_node("Panel/Rows/Collect").pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	check(main.model.get("ending_id") == "light", "UI minigame to video skip to ending")
	main.library_requested.emit("codex")
	check(main.library.visible and main.library.rows.get_child_count() == Collections.catalog.entries.size(), "codex view lists entries")
	main.library.dismiss()
	main.free()

func _reload_checks(runner) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/game.json"))
	var chapter: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/chapters/prologue.json"))
	var manifest_path := "user://framework_tests/game.json"
	var chapter_path := "user://framework_tests/chapter.json"
	manifest.chapters = [chapter_path]
	fixture(manifest_path, manifest)
	fixture(chapter_path, chapter)
	runner.manifest_path = manifest_path
	var before := GameState.snapshot()
	check(runner.reload_story().is_empty() and GameState.snapshot() == before, "reload keeps state")
	chapter.nodes[2].text = "热重载后的选项"
	fixture(chapter_path, chapter)
	check(runner.reload_story().is_empty() and runner.view.text == "热重载后的选项", "reload updates current view")
	check(GameState.snapshot() == before, "reload never repeats rewards")
	chapter.nodes[2].options[0].effects.add = {"trsut": 1}
	fixture(chapter_path, chapter)
	var error: String = runner.reload_story()
	check(error.contains(chapter_path + ":") and error.contains("trsut"), "unknown variable reports file and line")
	check(runner.view.text == "热重载后的选项" and GameState.snapshot() == before, "invalid reload retains last good story")
	runner.manifest_path = "res://data/game.json"
	check(runner.reload_story().is_empty(), "recover after bad reload")
