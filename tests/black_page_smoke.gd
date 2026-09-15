extends Node
const Investigation = preload("res://scripts/black_page/investigation.gd")
const Loader = preload("res://scripts/black_page/data_loader.gd")
const Store = preload("res://scripts/core/save_store.gd")
var checks := 0
var failures := 0
var game = Investigation.new()

func _ready() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("BLACK_PAGE CHECK FAILED: " + message)

func act(id: String) -> void:
	check(game.begin_action(id).is_empty(), "begin " + id)
	check(game.complete_action(game.ticket, {"success": true}).is_empty(), "complete " + id)

func identity_route() -> void:
	act("camera")
	act("badge")
	check(game.person_flag("zhou", "identity") == 70, "initial identity")
	act("archive")
	check(game.person_flag("zhou", "identity") == 52 and game.flag("clue.badge.reliability") == "forged", "contradictory evidence lowers identity")
	check(game.flag("day") == 2 and game.flag("actions_left") == 3, "third action automatically settles day")
	act("photo")
	check(game.person_name("zhou") == "周文远" and game.person_flag("zhou", "truth") == 15, "identity independent of truth")

func _run() -> void:
	add_child(game)
	var error: String = game.open()
	check(error.is_empty(), "content compiles: " + error)
	if not error.is_empty():
		get_tree().quit(1)
		return
	check(game.bundle.clues.size() == 5 and game.bundle.people.size() == 3, "MVP content")
	check(not game.available("photo"), "evidence gates")
	check(not game.begin_action("photo").is_empty(), "locked action rejected")
	identity_route()
	var identity_checkpoint: Dictionary = game.snapshot()
	check(game.reload_data().is_empty() and game.snapshot() == identity_checkpoint, "hot reload preserves rewards and state")
	check(game.write_name("zhou").is_empty(), "confirmed write")
	check(game.person_flag("zhou", "status") != "dead", "death is delayed")
	check(not game.write_name("zhou").is_empty(), "duplicate pending write rejected")
	var written: Dictionary = game.snapshot()
	var store = Store.new()
	check(store.write("black_page_smoke_roundtrip", written).is_empty(), "save write")
	check(store.write("black_page_smoke_roundtrip", written).is_empty(), "save overwrite")
	game.new_game()
	check(game.restore(store.read("black_page_smoke_roundtrip").get("data", {})).is_empty(), "JSON save restores pending write")
	check(game.end_day().is_empty() and game.person_flag("zhou", "status") == "dead", "next-day death")
	check(game.flag("writes") == 1 and game.flag("linmo_suspicion") > 0 and game.flag("testimony_lost"), "death cascades")
	check(game.available("fallback") and not game.available("testimony"), "soft failure opens fallback")
	act("fallback")
	check(game.person_flag("zhou", "truth") == 40, "fallback does not reveal full truth")
	var dead_checkpoint: Dictionary = game.snapshot()
	check(game.finish_case("seal").is_empty() and game.flag("ending") == "wrong", "wrong justice ending")
	game.restore(dead_checkpoint)
	check(game.finish_case("keep").is_empty() and game.flag("ending") == "judge", "judge ending")
	game.restore(identity_checkpoint)
	act("testimony")
	var full_checkpoint: Dictionary = game.snapshot()
	check(game.finish_case("seal").is_empty() and game.flag("ending") == "closed", "abstain and next-day ending")
	game.restore(full_checkpoint)
	act("notebook")
	check(game.finish_case("seal").is_empty() and game.flag("ending") == "secret", "priority hidden ending")
	game.new_game()
	check(game.write_name("zhou").is_empty(), "unconfirmed writing allowed")
	game.end_day()
	check(game.flag("wrong_writes") == 1 and game.person_flag("zhou", "status") != "dead", "wrong identity fails softly")
	game.new_game()
	game.write_name("linmo")
	game.end_day()
	act("camera")
	act("badge")
	check(not game.available("archive") and game.available("archive_public"), "dead contact replaced by public records route")
	act("archive_public")
	check(game.owns("archive") and game.available("photo"), "public records keep identity route open")
	game.restore(identity_checkpoint)
	game.end_day()
	game.end_day()
	check(not game.available("testimony") and game.available("fallback"), "missed deadline preserves route")
	var before: Dictionary = game.snapshot()
	var invalid: Dictionary = before.duplicate(true)
	invalid.state.flags.day = -1
	check(not game.restore(invalid).is_empty() and game.snapshot() == before, "corrupt state restore atomic")
	invalid = before.duplicate(true)
	invalid.pending = [{"person": "typo"}]
	check(not game.restore(invalid).is_empty() and game.snapshot() == before, "corrupt pending record rejected")
	invalid = before.duplicate(true)
	invalid.schema = 999
	check(not game.restore(invalid).is_empty(), "future schema rejected")
	game.new_game()
	game.begin_action("camera")
	var token: int = game.ticket
	game.cancel_action()
	check(not game.complete_action(token, {"success": true}).is_empty() and not game.owns("camera"), "stale callback cannot grant rewards")
	var loader = Loader.new()
	var compiled: Dictionary = loader.compile()
	var bad: Dictionary = compiled.actions.badge.duplicate(true)
	bad.effects = {"set": {"linmo_trsut": 30}}
	check(not loader._validate_row("actions", "badge", bad, compiled) and loader.error.contains("actions.json:") and loader.error.contains("linmo_trsut"), "reference error has source location")
	await _ui()
	print("BLACK_PAGE: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)

func _ui() -> void:
	var ui = load("res://scenes/black_page/main.tscn").instantiate()
	add_child(ui)
	await get_tree().process_frame
	check(is_instance_valid(ui.launch) and not ui.shell.visible, "launch page gates game")
	if "--capture-render" in OS.get_cmdline_user_args():
		await get_tree().create_timer(2.9).timeout
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("user://screenshots")
		get_viewport().get_texture().get_image().save_png("user://screenshots/black_page_launch.png")
	ui._start_new_game()
	await get_tree().create_timer(0.6).timeout
	check(is_instance_valid(ui.prologue) and not ui.shell.visible, "opening prologue gates investigation hub")
	if "--capture-render" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("user://screenshots")
		get_viewport().get_texture().get_image().save_png("user://screenshots/black_page_prologue.png")
	for _step in 5: ui.prologue._advance()
	await get_tree().create_timer(1.8).timeout
	check(not is_instance_valid(ui.prologue) and ui.shell.visible and ui.game.flag("prologue.completed"), "first writing sequence reveals title and hub")
	check(ui.header.text.contains("第 1 天"), "room UI starts")
	if "--capture-render" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("user://screenshots")
		get_viewport().get_texture().get_image().save_png("user://screenshots/black_page_room.png")
	for page in ["cases", "people", "clues", "notebook"]:
		ui._navigate(page)
		check(ui.rows.get_child_count() > 0, "panel " + page)
		if "--capture-render" in OS.get_cmdline_user_args():
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://screenshots/black_page_" + page + ".png")
	ui._start_action("camera")
	var activity = ui.modal_rows.get_child(1)
	activity._select(0)
	check(activity.selected.is_empty(), "minigame incorrect choice resets")
	for index in [1, 2, 0]: activity._select(index)
	await get_tree().process_frame
	await get_tree().process_frame
	ui.modal_rows.get_child(2).pressed.emit()
	check(ui.game.owns("camera") and ui.game.flag("actions_left") == 2 and not ui.modal.visible, "UI minigame reward once and return")
	ui.free()
