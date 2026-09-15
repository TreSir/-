extends Window
## Debug-only tools. Jump retains current flags; it is NOT time travel.
var runtime
var watch: RichTextLabel
var output: Label
var input: LineEdit
var _elapsed := 0.0
func _ready() -> void:
	title = "剧情调试 · F1"
	size = Vector2i(760, 520)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var rows := VBoxContainer.new()
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(rows)
	var help := Label.new()
	help.text = "get | set <flag> <JSON值> | jump <完整节点ID> | nodes | history | reload"
	rows.add_child(help)
	watch = RichTextLabel.new()
	watch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(watch)
	output = Label.new()
	output.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(output)
	input = LineEdit.new()
	input.placeholder_text = '例如：set trust 2'
	input.text_submitted.connect(execute)
	rows.add_child(input)
	close_requested.connect(hide)
	hide()
func toggle() -> void:
	if not OS.is_debug_build(): return
	if visible: hide()
	else:
		popup_centered()
		_update_watch()
		input.grab_focus()
func _process(delta: float) -> void:
	_elapsed += delta
	if visible and _elapsed >= 0.25:
		_elapsed = 0
		_update_watch()
func _update_watch() -> void:
	if runtime == null: return
	watch.text = "节点：%s\nFlag：\n%s\n背包：\n%s" % [runtime.cursor, JSON.stringify(GameState.flags, "\t"), JSON.stringify(GameState.inventory, "\t")]
func execute(command: String) -> void:
	if runtime == null or not OS.is_debug_build(): return
	var parts := command.strip_edges().split(" ", false, 2)
	if parts.is_empty(): return
	var error := ""
	match parts[0]:
		"get": _update_watch()
		"set":
			if parts.size() != 3:
				error = "格式：set flag JSON值"
			else:
				var parser := JSON.new()
				if parser.parse(parts[2]) != OK: error = "值不是有效 JSON"
				else:
					error = GameState.apply({"set": {parts[1]: parser.data}})
					if error.is_empty():
						runtime.debug_preview = true
						runtime.refresh()
		"jump":
			error = runtime.jump_to(parts[1]) if parts.size() > 1 else "缺少节点 ID"
		"nodes": output.text = "\n".join(runtime.bundle.nodes.keys())
		"history": output.text = " → ".join(runtime.history)
		"reload": error = runtime.reload_story()
		_: error = "未知命令"
	if not error.is_empty(): output.text = error
	elif parts[0] not in ["nodes", "history"]: output.text = "完成。跳转/改变量属于调试预览，不会解锁结局。"
	input.clear()
	_update_watch()
