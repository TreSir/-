extends Node
const Investigation = preload("res://scripts/black_page/investigation.gd")
const Loader = preload("res://scripts/black_page/data_loader.gd")
const Store = preload("res://scripts/core/save_store.gd")
const UI = preload("res://scripts/black_page/ui_style.gd")
var checks := 0
var failures := 0
var game = Investigation.new()

func _ready() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("BLACK_PAGE CHECK FAILED: " + message)

## 在指定坐标模拟一次真实的左键点击（按下 + 抬起）。
##
## 必须走 viewport.push_input 而不是直接 emit pressed：只有真实事件才会经过
## Godot 的 GUI 命中测试，才能发现「某个全屏 Control 挡在上面把点击吃掉」这类问题。
##
## in_local_coords 必须传 true：默认 false 时事件坐标按【窗口】坐标解释，
## 会被 stretch 变换（1152x720 → 1280x800）再换算一次，导致命中位置整体偏移。
func _click_at(ui: Node, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.global_position = position
	event.pressed = true
	ui.get_viewport().push_input(event, true)
	var release := event.duplicate() as InputEventMouseButton
	release.pressed = false
	ui.get_viewport().push_input(release, true)

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
	# 页级 speed：配了就用它，没配走全局 TYPE_SPEED
	ui.prologue.step = 3
	ui.prologue._render_page()
	check(ui.prologue._speed == 26.0, "page speed overrides the global typing speed")
	ui.prologue.step = 0
	ui.prologue._render_page()
	check(ui.prologue._speed == UI.TYPE_SPEED, "page without speed falls back to the global")
	# 自动模式要在按钮上看得出来，不然玩家不知道自己处在什么状态
	ui.prologue._auto = true
	ui.prologue._refresh_auto()
	check(ui.prologue._auto_link.text == "自动中", "auto mode marks itself on the button")
	ui.prologue._auto = false
	ui.prologue._refresh_auto()
	check(ui.prologue._auto_link.text == "自动", "auto mode reverts the button label")
	if "--capture-render" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("user://screenshots")
		get_viewport().get_texture().get_image().save_png("user://screenshots/black_page_prologue.png")
	for _step in 5: ui.prologue._advance()
	if "--capture-render" in OS.get_cmdline_user_args():
		await get_tree().create_timer(1.1).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://screenshots/black_page_chapter.png")
	await get_tree().create_timer(1.8).timeout
	check(not is_instance_valid(ui.prologue) and ui.shell.visible and ui.game.flag("prologue.completed"), "first writing sequence reveals title and hub")
	check(ui.header.text.contains("第 1 天"), "room UI starts")
	if "--capture-render" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("user://screenshots")
		get_viewport().get_texture().get_image().save_png("user://screenshots/black_page_room.png")
	ui._toggle_menu()
	if "--capture-render" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://screenshots/black_page_menu.png")
	ui._close_menu()
	# 左侧栏是常驻的四个系统功能，点开各自的面板。
	# 这类问题来自「全屏容器默认 MOUSE_FILTER_STOP 盖在上面吃点击」，
	# 直接调方法测不出来，必须模拟真实鼠标点击。
	# 开局：四个入口**全部锁着**，要把开场那段（手机震动 → 消息 → 自言自语）点完才出现
	await get_tree().create_timer(1.0).timeout
	check(not ui.nav_buttons["case"].visible, "no rail icons before the opening plays")
	var opening_guard := 0
	while not ui.nav_buttons["case"].visible and opening_guard < 30:
		_click_at(ui, Vector2(200, 200))
		await get_tree().create_timer(0.12).timeout
		opening_guard += 1
	check(ui.nav_buttons["case"].visible, "case icon unlocks after the opening")
	await get_tree().create_timer(1.2).timeout

	_click_at(ui, ui.nav_buttons["people"].get_global_rect().get_center())
	await get_tree().process_frame
	await get_tree().process_frame
	check(ui.modal.visible and ui._open_panel == "people", "side rail opens the people panel on a real click")
	# 图鉴正文（codex.json）必须真的进到 bundle 里，单人页才有的显示
	check(ui.game.bundle.has("codex") and not ui.game.bundle.codex.is_empty(), "codex data loaded")
	ui._open_person("zhou")
	await get_tree().process_frame
	await get_tree().process_frame
	check(ui.modal.visible and ui._open_panel == "people", "person codex page opens")
	if "--capture-render" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://screenshots/black_page_people.png")
	# 案件面板里挂着调查方向
	ui._open_case()
	await get_tree().process_frame
	await get_tree().process_frame
	check(ui.modal.visible and ui._open_panel == "case", "case panel opens")
	if "--capture-render" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://screenshots/black_page_case.png")
	ui._close_modal()
	# 三条杠
	_click_at(ui, ui._menu_button.get_global_rect().get_center())
	await get_tree().process_frame
	check(ui._menu_layer.visible, "hamburger opens the menu on a real click")
	_click_at(ui, ui._menu_button.get_global_rect().get_center())
	await get_tree().process_frame
	check(not ui._menu_layer.visible, "clicking outside closes the menu")
	# 顶栏的「黑页」点回房间
	_click_at(ui, ui._logo_button.get_global_rect().get_center())
	# 回房间会走转场，等它走完再看场景
	await get_tree().create_timer(1.0).timeout
	check(ui.scene_id == "room", "top bar breadcrumb responds to a real click")

	# 黑页面板会把场景切走
	ui._open_notebook()
	await get_tree().create_timer(0.1).timeout
	check(ui.scene_id == "notebook", "opening the notebook switches the scene")
	if "--capture-render" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://screenshots/black_page_notebook.png")
	ui._close_modal()
	ui._enter_room()
	await get_tree().process_frame

	# 小游戏
	# _investigate 里有转场（异步），要等它走完再取弹层内容
	ui._investigate("camera")
	await get_tree().create_timer(1.0).timeout
	var activity = ui.modal_rows.get_child(1)
	activity._select(0)
	check(activity.selected.is_empty(), "minigame incorrect choice resets")
	for index in [1, 2, 0]: activity._select(index)
	await get_tree().process_frame
	await get_tree().process_frame
	ui.modal_rows.get_child(2).pressed.emit()
	check(ui.game.owns("camera") and ui.game.flag("actions_left") == 2 and not ui.modal.visible, "UI minigame reward once and return")
	await get_tree().process_frame

	# 调查：场景整张切换 → 底部逐句读 → 读完自动结算回房间（主界面没有推进按钮）
	ui._investigate("badge")
	await get_tree().create_timer(1.0).timeout
	check(ui.scene_id != "room", "investigation switches the scene")
	if "--capture-render" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://screenshots/black_page_scene.png")
	# 每次点击之间留一点时间：转场期间遮罩会吃掉点击，不能只等一帧
	var guard := 0
	while ui.scene_id != "room" and guard < 24:
		_click_at(ui, Vector2(200, 200))
		await get_tree().create_timer(0.12).timeout
		guard += 1
	check(ui.scene_id == "room" and ui.game.flag("actions_left") == 1, "reading the report settles the action and returns to the room")
	ui.free()
