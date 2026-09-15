extends PanelContainer
## Receives read models only; gameplay changes are requested by signals.
signal use_requested(id: String)
signal closed
var rows: VBoxContainer
var heading: Label
var _was_paused := false
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 36)
	add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 14)
	margin.add_child(stack)
	heading = Label.new()
	stack.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 12)
	scroll.add_child(rows)
	var close := Button.new()
	close.text = "关闭 / Close"
	close.pressed.connect(dismiss)
	stack.add_child(close)
	hide()
func display(title: String, models: Array) -> void:
	heading.text = title
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	if models.is_empty():
		var empty := Label.new()
		empty.text = "暂无内容"
		rows.add_child(empty)
	for model in models:
		var panel := VBoxContainer.new()
		rows.add_child(panel)
		var name_label := Label.new()
		name_label.text = str(model.get("name", "???"))
		panel.add_child(name_label)
		var description := Label.new()
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.text = str(model.get("description", "尚未解锁"))
		panel.add_child(description)
		if model.get("usable", false):
			var use := Button.new()
			use.text = "使用 / Use"
			use.pressed.connect(func(): use_requested.emit(str(model.id)))
			panel.add_child(use)
	if not visible:
		_was_paused = get_tree().paused
		show()
		get_tree().paused = true
func dismiss() -> void:
	hide()
	get_tree().paused = _was_paused
	closed.emit()
