extends "res://scripts/core/minigame.gd"
## 时间轴小游戏。契约：begin(config, flags) 起，完成后 emit completed(结果)，
## 结果形状走 MiniGameResult 的 {type, score, data}。
var order: Array = []
var selected: Array = []
var buttons: Array[Button] = []
var status: Label

func begin(config: Dictionary, _story_variables: Dictionary) -> void:
	order = config.get("order", [1, 2, 0]).duplicate()
	var rows := VBoxContainer.new()
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rows.add_theme_constant_override("separation", 18)
	add_child(rows)
	status = Label.new()
	status.text = config.get("prompt", "按时间先后选择片段。")
	rows.add_child(status)
	var segments: Array = config.get("segments", [])
	for i in segments.size():
		var button := Button.new()
		button.text = str(segments[i])
		button.custom_minimum_size.y = 52
		button.pressed.connect(_select.bind(i))
		rows.add_child(button)
		buttons.append(button)

func _select(index: int) -> void:
	if _finished or index in selected: return
	if selected.size() >= order.size(): return
	if index != order[selected.size()]:
		selected.clear()
		for button in buttons: button.disabled = false
		status.text = "时间顺序不一致。可以重新排列。"
		return
	selected.append(index)
	buttons[index].disabled = true
	status.text = "已接回 %d 段画面。" % selected.size()
	if selected.size() == order.size(): finish({"type": "success", "score": 100})
