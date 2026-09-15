extends Control
const Investigation = preload("res://scripts/black_page/investigation.gd")
const Room = preload("res://scripts/black_page/room.gd")
const IconButton = preload("res://scripts/black_page/icon_button.gd")
const Prologue = preload("res://scripts/black_page/prologue.gd")
const Launch = preload("res://scripts/black_page/launch.gd")
const RainAmbience = preload("res://scripts/black_page/rain_ambience.gd")
const Store = preload("res://scripts/core/save_store.gd")
const PERSON_STATUS := {"normal": "正常", "missing": "下落不明", "fugitive": "逃亡", "injured": "受伤", "dead": "死亡", "arrested": "被捕", "hidden": "隐藏", "left": "离开城市"}
const CASE_STATUS := {"undiscovered": "未发现", "investigating": "调查中", "blocked": "暂无调查方向", "clear": "真相基本明确", "frozen": "冻结"}
const RELIABILITY := {"reliable": "可靠", "dubious": "存疑", "contradictory": "矛盾", "forged": "伪造"}
var game = Investigation.new()
var page := "room"
var rows: VBoxContainer
var header: Label
var notice: Label
var feed: RichTextLabel
var side: VBoxContainer
var modal: PanelContainer
var modal_rows: VBoxContainer
var shell: VBoxContainer
var nav_buttons: Dictionary = {}
var prologue: Prologue
var launch: Launch
var rain: RainAmbience

func _ready() -> void:
	name = "BlackPage"
	_build()
	game.name = "Investigation"
	add_child(game)
	game.changed.connect(refresh)
	var error: String = game.open()
	if not error.is_empty(): _message(error)
	else:
		_show_launch()

func _build() -> void:
	var skin := Theme.new()
	skin.default_font_size = 18
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	skin.default_font = font
	skin.set_color("font_color", "Label", Color("c4d3db"))
	skin.set_color("default_color", "RichTextLabel", Color("b2c5d0"))
	for kind in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("223745") if kind == "hover" else Color("16232e")
		style.border_color = Color("547687") if kind == "focus" else Color("304350")
		style.set_border_width_all(1)
		style.set_content_margin_all(12)
		skin.set_stylebox(kind, "Button", style)
	theme = skin
	# The room is an environment layer for the entire investigation hub.
	var background: Control = get_node_or_null("RoomBackground")
	if background == null:
		background = Room.new()
		background.name = "RoomBackground"
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(background)
	var veil := ColorRect.new()
	veil.color = Color(0.015, 0.04, 0.07, 0.48)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 24)
	add_child(margin)
	shell = VBoxContainer.new()
	shell.add_theme_constant_override("separation", 18)
	margin.add_child(shell)
	var top := HBoxContainer.new()
	shell.add_child(top)
	var logo := _button(top, "黑 页  /  房间", func(): _navigate("room"))
	logo.custom_minimum_size = Vector2(150, 45)
	header = _label(top, "", 17)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 24)
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(layout)
	var nav := VBoxContainer.new()
	nav.custom_minimum_size.x = 130
	nav.add_theme_constant_override("separation", 14)
	layout.add_child(nav)
	for entry in [["案件", "cases", "case"], ["人物", "people", "people"], ["线索", "clues", "clue"], ["黑页", "notebook", "notebook"]]:
		var nav_button := _icon_button(nav, entry[0], entry[2], _navigate.bind(entry[1]))
		nav_buttons[entry[1]] = nav_button
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav.add_child(spacer)
	_icon_button(nav, "保存", "save", func(): _message(game.save_game(), "已保存当前进度。"))
	_icon_button(nav, "读取", "load", func(): _confirm("读取存档", "当前未保存进度将被替换。", func(): _message(game.load_game(), "已读取存档。")))
	_icon_button(nav, "重新开始", "restart", func(): _confirm("重新开始", "当前未保存进度将被替换。已有手动存档会保留。", _restart_game))
	if OS.is_debug_build():
		_icon_button(nav, "重载数据 F6", "reload", func(): _message(game.reload_data(), "已重载数据，调查进度保留。"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 18)
	scroll.add_child(rows)
	side = VBoxContainer.new()
	side.custom_minimum_size.x = 245
	side.add_theme_constant_override("separation", 14)
	layout.add_child(side)
	_label(side, "手机 / 调查日志", 20)
	feed = RichTextLabel.new()
	feed.size_flags_vertical = Control.SIZE_EXPAND_FILL
	feed.custom_minimum_size.y = 200
	side.add_child(feed)
	_button(side, "结束今天", func(): _confirm("结束今天", "剩余行动不会结转。进入次日并接收消息？", func(): _message(game.end_day())))
	notice = _label(shell, "每次调查消耗一次行动。第三次调查结束后自动进入次日。", 15)
	modal = PanelContainer.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("0c141e")
	panel_style.set_content_margin_all(60)
	modal.add_theme_stylebox_override("panel", panel_style)
	add_child(modal)
	var modal_scroll := ScrollContainer.new()
	modal.add_child(modal_scroll)
	modal_rows = VBoxContainer.new()
	modal_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_rows.add_theme_constant_override("separation", 22)
	modal_scroll.add_child(modal_rows)
	modal.hide()

func _label(parent: Node, text: String, size: int = 18) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable, disabled: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 45
	button.disabled = disabled
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _icon_button(parent: Node, label: String, glyph: String, action: Callable) -> IconButton:
	var button := IconButton.new()
	button.text = label
	button.glyph = glyph
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _message(error: String, success: String = "") -> void:
	notice.text = error if not error.is_empty() else success
	if not error.is_empty(): push_warning(error)

func _restart_game() -> void:
	game.new_game()
	page = "room"
	_show_launch()

func _show_launch() -> void:
	if is_instance_valid(launch): return
	shell.hide()
	if not is_instance_valid(rain):
		rain = RainAmbience.new()
		rain.name = "RainAmbience"
		add_child(rain)
	launch = Launch.new()
	launch.name = "Launch"
	launch.can_continue = not Store.new().read("black_page_slot_1").has("error")
	launch.start_requested.connect(_start_new_game)
	launch.continue_requested.connect(_continue_game)
	launch.rain_muted_changed.connect(func(value: bool): rain.set_muted_by_player(value))
	add_child(launch)

func _dismiss_launch() -> void:
	if is_instance_valid(launch):
		launch.close_to_game()
		launch = null

func _start_new_game() -> void:
	game.new_game()
	page = "room"
	_dismiss_launch()
	await get_tree().create_timer(0.5).timeout
	_show_prologue()

func _continue_game() -> void:
	var error := game.load_game()
	if not error.is_empty():
		_message(error)
		return
	page = "room"
	_dismiss_launch()
	if not game.flag("prologue.completed"):
		await get_tree().create_timer(0.5).timeout
		_show_prologue()
	else:
		shell.show()
		refresh()

func _show_prologue() -> void:
	if is_instance_valid(prologue): return
	shell.hide()
	prologue = Prologue.new()
	prologue.name = "Prologue"
	prologue.finished.connect(func():
		shell.show()
		prologue = null
		refresh())
	add_child(prologue)

func _navigate(target: String) -> void:
	page = target
	refresh()
	rows.modulate.a = 0.0
	rows.position.x = 18.0
	var tween := create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(rows, "modulate:a", 1.0, 0.22)
	tween.tween_property(rows, "position:x", 0.0, 0.24)

func refresh() -> void:
	if game.bundle.is_empty(): return
	_clear(rows)
	var times := ["23:40", "18:40", "14:20", "09:10"]
	header.text = "第 %d 天   %s     剩余行动 %d / 3" % [int(game.flag("day")), times[int(game.flag("actions_left"))], int(game.flag("actions_left"))]
	feed.text = "\n\n————\n\n".join(game.journal.duplicate().slice(-4))
	for key in nav_buttons:
		nav_buttons[key].accent = Color("75d7ee") if key == page else Color("5c8797")
		nav_buttons[key].queue_redraw()
	side.visible = page != "notebook"
	if game.flag("ending") != "":
		_label(rows, "首章结束", 32)
		_label(rows, str(game.journal.back()), 22)
		_label(rows, "可读取落笔前的存档体验另一条路线，或重新开始。", 16)
		return
	match page:
		"room": _room()
		"cases": _cases()
		"people": _people()
		"clues": _clues()
		"notebook": _notebook()

func _room() -> void:
	_label(rows, "雨没有停", 34)
	_label(rows, "第一章   /   消失在站台的人", 16)
	var space := Control.new()
	space.custom_minimum_size.y = 300
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(space)
	_label(rows, "电脑里是许妍的最后一段监控。手机还亮着。\n桌上的黑色笔记，比任何一件东西都安静。", 20)
	_button(rows, "打开调查笔记", _navigate.bind("cases"))
	if game.flag("erosion") > 0: _label(rows, "有一瞬间，你觉得下一个名字会更容易写。", 17)
	elif game.owns("photo"): _label(rows, "黑页不知何时翻开了。\n“你已经知道他的名字。”", 17)
	if game.flag("linmo_suspicion") >= 20: _label(rows, "林墨：把这几天的行动时间发给我。全部。", 17)
	elif game.flag("linmo_trust") >= 45: _label(rows, "林墨：有新的材料，我会先告诉你。", 17)

func _cases() -> void:
	for id in game.bundle.cases:
		var entry: Dictionary = game.bundle.cases[id]
		var status: String = game.flag("case." + id + ".status")
		if status == "undiscovered": continue
		_label(rows, entry.name, 30)
		_label(rows, CASE_STATUS[status] + "  /  " + entry.intro)
		_label(rows, "已知事实", 22)
		for clue in game.bundle.clues:
			if game.owns(clue) and game.bundle.clues[clue].case == id:
				_label(rows, "· " + game.bundle.clues[clue].name)
		_label(rows, "仍未回答", 22)
		for question in entry.questions:
			if game.matches(question.get("requires", [])): _label(rows, "· " + question.text)
		_label(rows, "调查方向", 22)
		var count := 0
		for action_id in game.bundle.actions:
			var action: Dictionary = game.bundle.actions[action_id]
			if action.case == id and game.available(action_id):
				count += 1
				_button(rows, action.name + "  ·  1 次行动", _ask_action.bind(action_id))
		if count == 0: _label(rows, "暂时没有新的方向。可以等待消息，或打开黑页作出决定。")

func _people() -> void:
	_label(rows, "人物档案", 30)
	for id in game.bundle.people:
		if not game.person_flag(id, "discovered"): continue
		var person: Dictionary = game.bundle.people[id]
		_label(rows, game.person_name(id) + "  /  " + PERSON_STATUS[game.person_flag(id, "status")], 23)
		_label(rows, person.role + "\n" + person.description)
		_label(rows, "真实姓名：" + (person.real_name if game.person_flag(id, "identity") == 100 else "尚未确认"))
		_label(rows, "身份确认 %d%%    真相掌握 %d%%" % [int(game.person_flag(id, "identity")), int(game.person_flag(id, "truth"))])
		_label(rows, "关联案件：" + game.bundle.cases[person.case].name, 16)

func _clues() -> void:
	_label(rows, "线索档案", 30)
	if GameState.inventory.is_empty(): _label(rows, "还没有收集到线索。可以从公交站监控开始。")
	for id in game.bundle.clues:
		if not game.owns(id): continue
		var clue: Dictionary = game.bundle.clues[id]
		_label(rows, clue.name + "  /  " + clue.type, 23)
		_label(rows, "可信度：" + RELIABILITY[game.flag("clue." + id + ".reliability")], 16)
		var description: String = clue.description
		if id == "testimony" and game.flag("action.fallback.done"): description = clue.fallback_description
		_label(rows, description)
		var names: Array = []
		for person in clue.people:
			if game.person_flag(person, "discovered"): names.append(game.person_name(person))
		_label(rows, "关联：" + " ↔ ".join(names) + "  /  " + game.bundle.cases[clue.case].name, 16)

func _notebook() -> void:
	_label(rows, "黑 页", 38)
	_label(rows, "纸页上没有规则，也没有劝告。", 18)
	for id in game.bundle.people:
		if not game.person_flag(id, "discovered"): continue
		_label(rows, game.person_name(id), 25)
		_label(rows, "身份确认 %d%%   /   真相掌握 %d%%   /   %s" % [int(game.person_flag(id, "identity")), int(game.person_flag(id, "truth")), PERSON_STATUS[game.person_flag(id, "status")]])
		_button(rows, "选择这个名字", _ask_write.bind(id), not game.can_write(id))
	if not game.pending.is_empty(): _label(rows, "纸上已有墨迹。后果还没有传来。", 18)
	_button(rows, "合上笔记，继续调查", _navigate.bind("room"))
	if game.flag("day") >= 2:
		_label(rows, "结束这一章", 23)
		_button(rows, "封存黑页", func(): _confirm("封存黑页", "进入次日，接收最后的消息，然后结束首章。", func(): _message(game.finish_case("seal"))))
		_button(rows, "保留黑页", func(): _confirm("保留黑页", "进入次日，接收最后的消息，然后结束首章。", func(): _message(game.finish_case("keep"))))

func _confirm(title: String, body: String, action: Callable) -> void:
	_clear(modal_rows)
	modal.show()
	shell.hide()
	_label(modal_rows, title, 30)
	_label(modal_rows, body, 22)
	_button(modal_rows, "确认", func(): _close_modal(); action.call())
	_button(modal_rows, "返回", _close_modal)

func _close_modal() -> void:
	modal.hide()
	shell.show()
	_clear(modal_rows)

func _ask_write(id: String) -> void:
	_confirm("写下「%s」" % game.person_name(id), "一旦写下，无法撤销。\n后果不会立刻出现。", func(): _message(game.write_name(id)); _navigate("room"))
	modal_rows.get_child(2).text = "落笔"
	modal_rows.get_child(3).text = "合上笔记"

func _ask_action(id: String) -> void:
	_confirm(game.bundle.actions[id].name, "预计消耗 1 次行动。前往调查？", _start_action.bind(id))

func _start_action(id: String) -> void:
	var error: String = game.begin_action(id)
	if not error.is_empty():
		_message(error)
		return
	_clear(modal_rows)
	modal.show()
	shell.hide()
	var action: Dictionary = game.bundle.actions[id]
	var token: int = game.ticket
	_label(modal_rows, action.name, 30)
	if action.kind == "minigame":
		var activity = load(action.scene).instantiate()
		modal_rows.add_child(activity)
		activity.completed.connect(func(result: Dictionary):
			if token == game.ticket: _show_report.call_deferred(id, token, result))
		activity.begin(action.config, GameState.flags.duplicate(true))
		_button(modal_rows, "返回（不消耗行动）", func(): game.cancel_action(); _close_modal())
	else:
		_show_report(id, token, {})

func _show_report(id: String, token: int, result: Dictionary) -> void:
	if token != game.ticket: return
	_clear(modal_rows)
	_label(modal_rows, game.bundle.actions[id].name, 30)
	_label(modal_rows, game.bundle.actions[id].text, 23)
	_button(modal_rows, "记录结果，返回房间", func():
		var error: String = game.complete_action(token, result)
		if not error.is_empty():
			_label(modal_rows, error)
			return
		_close_modal()
		_message(error)
		_navigate("room"))

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6 and OS.is_debug_build():
		_message(game.reload_data(), "已重载数据。")
