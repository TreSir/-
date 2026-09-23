extends RefCounted
## 案件面板的表现层：只读调查门面的状态，调查请求交回主界面处理。
const UI = preload("res://scripts/black_page/ui_style.gd")

const CASE_STATES := {"active": "调查中", "completed": "已结案"}
const CASE_RESULTS := {"explained": "真相查清", "partial": "部分查清", "unresolved": "未能查清"}

static func populate(rows: VBoxContainer, game: Variant, on_investigate: Callable) -> void:
	var found := 0
	for id in game.bundle.cases:
		var state: String = game.flag("case." + id + ".state")
		if state == "locked": continue
		found += 1
		var entry: Dictionary = game.bundle.cases[id]
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 14)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 12)
		head.add_child(UI.heading(str(entry.name), UI.SIZE_TITLE))
		var chip := UI.accent_chip(CASE_STATES[state])
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(chip)
		column.add_child(head)
		column.add_child(UI.flow(str(entry.intro), UI.SIZE_SMALL + 1, Color("c6d5dd")))
		var note := _case_note(game, str(id), state)
		if not note.is_empty():
			column.add_child(UI.flow(note, UI.SIZE_SMALL, UI.TEXT_DIM))
		column.add_child(UI.rule())
		column.add_child(UI.label("已知事实", UI.SIZE_MICRO, UI.ACCENT))
		column.add_child(_clue_chips(game, str(id)))
		column.add_child(UI.label("仍未回答", UI.SIZE_MICRO, UI.ACCENT))
		var asked := 0
		for question in entry.questions:
			if game.matches(question.get("requires", [])):
				asked += 1
				column.add_child(_bullet(str(question.text)))
		if asked == 0: column.add_child(UI.flow("暂时没有新的疑点。", UI.SIZE_SMALL, UI.TEXT_DIM))
		column.add_child(UI.label("调查方向", UI.SIZE_MICRO, UI.ACCENT))
		var listed := 0
		for action_id in game.bundle.actions:
			var action: Dictionary = game.bundle.actions[action_id]
			if action.case != id or not game.available(action_id): continue
			listed += 1
			var row := UI.action_row(str(action.name), "")
			row.pressed.connect(on_investigate.bind(action_id))
			column.add_child(row)
		if listed == 0:
			column.add_child(UI.flow("暂时没有新的方向。可以先打开黑页作出决定，或进入次日看看。", UI.SIZE_SMALL, UI.TEXT_DIM))
		rows.add_child(column)
	if found == 0:
		rows.add_child(UI.flow("还没有接触到任何案件。", UI.SIZE_BODY, UI.TEXT_DIM))

static func _case_note(game: Variant, id: String, state: String) -> String:
	if state == "completed":
		return "已结案：%s。" % CASE_RESULTS.get(str(game.flag("case." + id + ".result")), "结果不详")
	var gone: Array = []
	for person in game.bundle.people:
		if game.bundle.people[person].case != id: continue
		if game.person_flag(person, "status") == "dead": gone.append(str(game.bundle.people[person].name))
	if not gone.is_empty(): return "关键人物已不在：" + "、".join(gone) + "。"
	if not game.case_outlook(id).is_empty(): return "线索已经连起来了。"
	return ""

static func _clue_chips(game: Variant, case_id: String) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	for clue in game.bundle.clues:
		if game.owns(clue) and str(game.bundle.clues[clue].case) == case_id:
			flow.add_child(UI.chip(str(game.bundle.clues[clue].name)))
	if flow.get_child_count() == 0:
		return UI.flow("还没有掌握任何事实。", UI.SIZE_SMALL, UI.TEXT_DIM)
	return flow

static func _bullet(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 11)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tick := ColorRect.new()
	tick.color = UI.AMBER_EDGE
	tick.custom_minimum_size = Vector2(2, 0)
	tick.size_flags_vertical = Control.SIZE_FILL
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tick)
	row.add_child(UI.flow(text, UI.SIZE_SMALL + 1, Color("c6d5dd")))
	return row
