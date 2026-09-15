extends Control
## A short playable proof that the notebook is real before the investigation hub opens.
signal finished
var step := 0
var title: Label
var body: Label
var action: Button
var card: PanelContainer

const PAGES := [
	{
		"title": "雨夜 / 00:17",
		"body": "楼道的声控灯灭了又亮。\n门缝下方，有人塞进来一个没有署名的纸盒。\n\n纸盒里是一册黑色笔记，封面干净得像从来没有被人碰过。",
		"action": "查看手机"
	},
	{
		"title": "未读消息 / 1",
		"body": "本地新闻：催收员高启明因非法拘禁、暴力威胁多名租户被立案调查。\n\n今天下午，他仍带人堵在受害者陈岚的住处。陈岚在语音里只说了一句：\n“他们说，明天会再来。”\n\n他的名字、照片和住址，被人整理得过于完整。",
		"action": "打开黑色笔记"
	},
	{
		"title": "黑页",
		"body": "纸页自己翻开。\n\n左页写着：高启明\n身份确认：完整\n\n右页没有规则，也没有任何解释。只有一支笔，停在你的手边。\n\n这次不需要继续调查。",
		"action": "写下「高启明」"
	},
	{
		"title": "00:31",
		"body": "笔尖划过纸面。\n\n高启明。\n\n墨迹很快渗进纸纤维，像这个名字本来就在那里。\n你合上笔记。楼下的雨声没有任何变化。",
		"action": "等到明天"
	},
	{
		"title": "次日 / 09:04",
		"body": "突发新闻：涉暴力催收案件的高启明，今晨在住处突发心脏骤停死亡。\n\n陈岚发来一条很短的消息：\n“他们走了。”\n\n你盯着那本黑色笔记。它不是恶作剧。它是真的。",
		"action": "……"
	}
]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	resized.connect(_layout_card)
	_layout_card()
	_render_page()

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.025, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	card = PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.06, 0.095, 0.94)
	style.border_color = Color("537b8e")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(24)
	card.add_theme_stylebox_override("panel", style)
	add_child(card)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	card.add_child(rows)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Color("89cfe3"))
	rows.add_child(title)
	body = Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("font_size", 18)
	rows.add_child(body)
	action = Button.new()
	action.custom_minimum_size.y = 44
	action.add_theme_font_size_override("font_size", 18)
	action.pressed.connect(_advance)
	rows.add_child(action)

func _layout_card() -> void:
	if card == null: return
	var width: float = minf(size.x - 64.0, 760.0)
	var height: float = minf(size.y * 0.46, 330.0)
	card.size = Vector2(width, height)
	card.position = Vector2((size.x - width) * 0.5, size.y - height - 28.0)

func _render_page() -> void:
	var entry: Dictionary = PAGES[step]
	title.text = entry.title
	body.text = entry.body
	action.text = entry.action
	card.modulate.a = 0.0
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "modulate:a", 1.0, 0.28)
	if step == 2:
		title.add_theme_font_size_override("font_size", 30)
		var pulse := create_tween().set_loops()
		pulse.tween_property(action, "modulate:a", 0.72, 0.8)
		pulse.tween_property(action, "modulate:a", 1.0, 0.8)
	else:
		title.add_theme_font_size_override("font_size", 21)

func _advance() -> void:
	if step < PAGES.size() - 1:
		step += 1
		_render_page()
		return
	_show_title()

func _show_title() -> void:
	card.hide()
	var words := Label.new()
	words.text = "黑 页"
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	words.add_theme_font_size_override("font_size", 88)
	words.add_theme_color_override("font_color", Color("d2ebf1"))
	words.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	words.modulate.a = 0.0
	add_child(words)
	var subtitle := Label.new()
	subtitle.text = "第一章  /  消失在站台的人"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.set_anchors_preset(Control.PRESET_CENTER)
	subtitle.position = Vector2(-250, 78)
	subtitle.size = Vector2(500, 36)
	subtitle.modulate.a = 0.0
	add_child(subtitle)
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(words, "modulate:a", 1.0, 0.8)
	tween.tween_property(subtitle, "modulate:a", 1.0, 1.2)
	await get_tree().create_timer(1.65).timeout
	GameState.apply({"set": {"prologue.completed": true}})
	finished.emit()
	queue_free()
