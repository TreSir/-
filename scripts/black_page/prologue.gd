extends Control
## 序章：在进入调查中心之前，先用一小段可玩流程证明「笔记本是真的」。
##
## 改造点：
## 1. 补上两张背景图（楼道纸盒 / 摊开的黑页），此前只有一层纯色遮罩。
## 2. 底部那张硬定位的方块卡片，换成通栏渐隐字幕带——这是策划案里「底部剧情文本」的位置。
## 3. 加打字机、点击任意处推进、页码点阵、自动与跳过。
## 4. 结尾的章节标题卡独立成屏，不再复用对话卡，也去掉了字号突变与按钮脉冲。
##
## 注意 `_advance()` 保持「无条件翻页」语义：它是给测试和程序化调用用的。
## 玩家的点击走 `_tap()`，那一层才有「先补完打字再翻页」的两段式行为。

signal finished

const UI = preload("res://scripts/black_page/ui_style.gd")
const BG_DOOR = preload("res://assets/backgrounds/black_page_prologue_door_v1.png")
const BG_NOTE = preload("res://assets/backgrounds/black_page_prologue_notebook_v1.png")

## 序章文本在 `res://data/black_page/prologue.json`——**改剧情去改那个文件**。
##
## 切分规则：`body` 里**每个换行 = 底部对话框里的一次点击**，空行忽略。
## 一段太长读不完时，直接在句子之间插一个换行就行。
## 一页读完（最后一段也打完）才会提示 `action`，再点一下才翻到下一页。
##
## 这个文件在 data/ 下，和 actions.json 一样**支持 F6 热重载**（不用重启）。
const PROLOGUE_PATH := "res://data/black_page/prologue.json"

var pages: Array = []

## 读序章文本。字段缺了给默认值；文件缺失或结构不对就退回下面那份内置文本并告警，
## 保证序章在任何情况下都能跑完，不会卡住。
##
## 每页字段（都是可选的，缺了走默认）：
##   title / body / action / bg
##   body  —— 换行符分段（一段一次点击）；`<br>` 是段内换行，不额外点击
##   bg    —— 只认 "door" / "note"
##   speed —— 这一页的打字速度（字/秒）。**不写就按全局 UI.TYPE_SPEED**
func _load_pages() -> Array:
	var file := FileAccess.open(PROLOGUE_PATH, FileAccess.READ)
	if file == null:
		push_warning("序章文本打不开：%s" % PROLOGUE_PATH)
		return BUILTIN_PAGES
	var raw := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary) or not (parsed.get("pages") is Array):
		push_warning("序章文本结构不对：%s" % PROLOGUE_PATH)
		return BUILTIN_PAGES
	var out: Array = []
	for entry in parsed["pages"]:
		if not (entry is Dictionary): continue
		out.append({
			"title": str(entry.get("title", "")),
			"body": str(entry.get("body", "")),
			"action": str(entry.get("action", "")),
			"bg": str(entry.get("bg", "door")),
			# 可选。0 表示「没配」→ 用全局 UI.TYPE_SPEED。
			"speed": float(entry.get("speed", 0.0)),
		})
	if out.is_empty():
		push_warning("序章文本没有有效页：%s" % PROLOGUE_PATH)
		return BUILTIN_PAGES
	return out

## 这一页的打字速度：页里配了 speed 就用它，没配（或配成 0）就用全局。
func _speed_of(entry: Dictionary) -> float:
	var value := float(entry.get("speed", 0.0))
	return value if value > 0.0 else UI.TYPE_SPEED

## F6 热重载时调用：重读 JSON，并把当前这一页按新文本重画。
func reload_pages() -> void:
	if _finishing or not is_inside_tree():
		return
	pages = _load_pages()
	_render_page()

## 内置兜底文本（prologue.json 正常时不会用到）。
const BUILTIN_PAGES := [
	{
		"title": "雨夜 ／ 00:17",
		"body": "楼道的声控灯灭了又亮。\n门缝下方，有人塞进来一个没有署名的纸盒。\n\n纸盒里是一册黑色笔记，封面干净得像从来没有被人碰过。",
		"action": "查看手机",
		"bg": "door"
	},
	{
		"title": "未读消息 ／ 1",
		"body": "本地新闻：催收员高启明因非法拘禁、暴力威胁多名租户被立案调查。\n\n今天下午，他仍带人堵在受害者陈岚的住处。陈岚在语音里只说了一句：\n“他们说，明天会再来。”\n\n他的名字、照片和住址，被人整理得过于完整。",
		"action": "打开黑色笔记",
		"bg": "door"
	},
	{
		"title": "黑页",
		"body": "纸页自己翻开。\n\n左页写着：高启明\n身份确认：完整\n\n右页没有规则，也没有任何解释。只有一支笔，停在你的手边。\n\n这次不需要继续调查。",
		"action": "写下「高启明」",
		"bg": "note"
	},
	{
		"title": "00:31",
		"body": "笔尖划过纸面。\n\n高启明。\n\n墨迹很快渗进纸纤维，像这个名字本来就在那里。\n你合上笔记。楼下的雨声没有任何变化。",
		"action": "等到明天",
		"bg": "note"
	},
	{
		"title": "次日 ／ 09:04",
		"body": "突发新闻：涉暴力催收案件的高启明，今晨在住处突发心脏骤停死亡。\n\n陈岚发来一条很短的消息：\n“他们走了。”\n\n你盯着那本黑色笔记。它不是恶作剧。它是真的。",
		"action": "……",
		"bg": "note"
	}
]

var step := 0
var title: Label
var body: Label
var card: Control

var _backdrop: TextureRect
var _catcher: Button
var _body_scroll: ScrollContainer
var _top: HBoxContainer
var _dots: HBoxContainer
var _hint: Label
var _auto := false
var _auto_clock := 0.0
var _auto_link: Button
var _auto_tween: Tween
var _reveal := 0.0
var _full := ""
var _finishing := false
var _done := false
var _card_tween: Tween
var _beats: Array = []
var _beat := 0
## 当前这一页的打字速度（字/秒）。页里没配 speed 就是 UI.TYPE_SPEED。
var _speed := UI.TYPE_SPEED


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	pages = _load_pages()
	_build()
	resized.connect(_layout)
	_layout()
	_render_page()

func _build() -> void:
	_backdrop = TextureRect.new()
	_backdrop.texture = BG_DOOR
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)

	# 全屏点击接收层：放在最底层，上面的控件用 IGNORE 让点击落下来。
	# 这样「点击任意处继续」不会和 _unhandled_input 打架。
	_catcher = Button.new()
	_catcher.flat = true
	_catcher.focus_mode = Control.FOCUS_NONE
	_catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var blank := UI.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0)
	for state in ["normal", "hover", "pressed", "focus"]:
		_catcher.add_theme_stylebox_override(state, blank)
	_catcher.pressed.connect(_tap)
	add_child(_catcher)

	_top = HBoxContainer.new()
	_top.add_theme_constant_override("separation", 22)
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top)
	# 顶栏不再写「序章 · 第一次书写」——不需要告诉玩家这是序章，让他自己看就是了。
	var top_spacer := Control.new()
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.add_child(top_spacer)
	_auto_link = _top_link("自动", func(): _auto = not _auto; _refresh_auto())
	_top.add_child(_auto_link)
	_top.add_child(_top_link("跳过 ▸▸", _show_title))

	# 底部对话框：和主界面共用同一个组件——底边钉死，长文本向上长。
	card = UI.dialogue_box()
	add_child(card)
	card.add_child(UI.dialogue_scrim())

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 0)
	margin.add_theme_constant_override("margin_right", 0)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 30)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title = UI.label("", UI.SIZE_SMALL, UI.ACCENT)
	title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	head.add_child(title)
	var head_spacer := Control.new()
	head_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(head_spacer)
	_dots = HBoxContainer.new()
	_dots.add_theme_constant_override("separation", 6)
	_dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for _index in pages.size():
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(26, 3)
		pip.color = Color(0.4941, 0.6980, 0.7686, 0.20)
		_dots.add_child(pip)
	head.add_child(_dots)
	column.add_child(head)

	column.add_child(UI.spacer(16))
	# 正文放进可滚动区域：上下两边（标题行 / 脚注）固定，正文超出就用滚轮看。
	_body_scroll = ScrollContainer.new()
	_body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 滚轮归 ScrollContainer；左键点击转发给 _tap()，这样「点一下推进」在框里也管用。
	_body_scroll.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_tap())
	column.add_child(_body_scroll)
	body = UI.flow("", UI.SIZE_BODY, Color("dae6ec"))
	_body_scroll.add_child(UI.narrow(body, 0.62))

	column.add_child(UI.spacer(14))
	var foot := HBoxContainer.new()
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(UI.label("点击任意处继续", UI.SIZE_MICRO, UI.TEXT_MUTE))
	var foot_spacer := Control.new()
	foot_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(foot_spacer)
	_hint = UI.label("▸", UI.SIZE_SMALL, UI.ACCENT)
	foot.add_child(_hint)
	column.add_child(foot)

	var pulse := create_tween().set_loops()
	pulse.tween_property(_hint, "modulate:a", 0.42, 1.2).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_hint, "modulate:a", 1.0, 1.2).set_trans(Tween.TRANS_SINE)

func _top_link(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.flat = true
	button.custom_minimum_size = Vector2(0, 30)
	button.add_theme_font_size_override("font_size", UI.SIZE_MICRO)
	button.add_theme_color_override("font_color", UI.TEXT_MUTE)
	button.add_theme_color_override("font_hover_color", UI.ACCENT)
	button.add_theme_color_override("font_pressed_color", UI.ACCENT)
	var none := UI.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0)
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, none)
	button.pressed.connect(callback)
	return button

func _layout() -> void:
	if card == null or not is_inside_tree():
		return
	var s := size.y / 720.0
	var side := size.x * 0.083

	_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top.offset_left = side
	_top.offset_right = -side
	_top.offset_top = 26 * s
	_top.offset_bottom = 26 * s + 34

	var margin := card.get_child(1) as MarginContainer
	if margin != null:
		margin.add_theme_constant_override("margin_left", int(side))
		margin.add_theme_constant_override("margin_right", int(side))
	title.add_theme_font_size_override("font_size", int(UI.SIZE_SMALL * s))
	body.add_theme_font_size_override("font_size", int(17.0 * s))
	# 对话框高度固定、底边钉死——不按页数或文本长度去挪动整个框。
	UI.layout_dialogue(card, UI.DIALOG_H)

func _render_page() -> void:
	if step < 0 or step >= pages.size():
		return
	var entry: Dictionary = pages[step]
	title.text = entry.title
	_speed = _speed_of(entry)
	# 这一页正文按换行切成若干「段」，一段一次点击。
	# 太长的一整段读起来累，也看不完——所以正文里用 \n 分行就等于切分。
	_beats = _lines_of(str(entry.body))
	_beat = 0
	_show_beat()
	if entry.bg == "note":
		_backdrop.texture = BG_NOTE
	else:
		_backdrop.texture = BG_DOOR
	for index in _dots.get_child_count():
		var pip := _dots.get_child(index) as ColorRect
		pip.color = UI.ACCENT if index <= step else Color(0.4941, 0.6980, 0.7686, 0.20)
	_auto_clock = 0.0
	card.modulate.a = 0.0
	if _card_tween != null and _card_tween.is_valid():
		_card_tween.kill()
	_card_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_card_tween.tween_property(card, "modulate:a", 1.0, 0.24)

## 把一段正文按换行拆成「一段一次点击」的列表。空行忽略。
func _lines_of(text: String) -> Array:
	var out: Array = []
	for raw in text.split("\n"):
		var line := str(raw).strip_edges()
		if not line.is_empty(): out.append(line)
	if out.is_empty(): out.append("……")
	return out

## 显示当前这一段，打字机从头开始。
##
## 段内换行用 `<br>`（不是 \n）——`\n` 是分段，`<br>` 只是把句子挪到下一行，不多点一次。
func _show_beat() -> void:
	_full = str(_beats[_beat]).replace("<br>", "\n")
	_reveal = 0.0
	body.text = ""
	if _body_scroll != null:
		_body_scroll.scroll_vertical = 0
	_hint.text = ""

func _is_last_beat() -> bool:
	return _beat >= _beats.size() - 1

func _process(delta: float) -> void:
	if _full.is_empty() or body.text.length() >= _full.length():
		# 整页读完（最后一段也打完了），才提示这一页要做什么。
		# 没读完就冒出来，玩家还没看懂发生什么就能把剧情推过去，很假。
		if _is_last_beat() and _hint.text.is_empty() and not _full.is_empty() and step < pages.size():
			_hint.text = "%s  ▸" % pages[step].action
		if _auto and not _finishing:
			_auto_clock += delta
			if _auto_clock > 2.2 and _reveal > 0.0:
				_tap()
		return
	_reveal += delta * _speed
	var count := int(minf(_reveal, float(_full.length())))
	body.text = _full.substr(0, count)
	if _auto:
		_auto_clock = 0.0

## 自动模式必须在按钮上看得出来：文字变「自动中」、变亮、并且呼吸。
## 不然玩家点完之后根本不知道自己正处在什么状态。
func _refresh_auto() -> void:
	_auto_clock = 0.0
	if _auto_link == null: return
	_auto_link.text = "自动中" if _auto else "自动"
	_auto_link.add_theme_color_override("font_color", UI.ACCENT if _auto else UI.TEXT_MUTE)
	_auto_link.add_theme_color_override("font_hover_color", UI.ACCENT if _auto else UI.TEXT_BRIGHT)
	if _auto_tween != null and _auto_tween.is_valid():
		_auto_tween.kill()
	if not _auto:
		_auto_link.modulate.a = 1.0
		return
	# 呼吸：亮度在 0.5 ~ 1.0 之间来回，表示「正在自动往下走」。
	_auto_tween = create_tween().set_loops()
	_auto_tween.set_trans(Tween.TRANS_SINE)
	_auto_tween.tween_property(_auto_link, "modulate:a", 0.5, 0.7)
	_auto_tween.tween_property(_auto_link, "modulate:a", 1.0, 0.7)

func _is_typing() -> bool:
	return body.text.length() < _full.length()

## 玩家的点击：先补完打字 → 再一段一段过 → 最后才翻页。
func _tap() -> void:
	if _finishing:
		_finish()
		return
	if _is_typing():
		body.text = _full
		_reveal = float(_full.length())
		return
	# 这一页还有下一段就出下一段，没有了才翻页。
	if not _is_last_beat():
		_beat += 1
		_show_beat()
		return
	_advance()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed():
		return
	if event is InputEventKey and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		_tap()

## 无条件翻页：给测试与程序化调用用。玩家输入走 _tap()。
func _advance() -> void:
	if _finishing:
		return
	if step < pages.size() - 1:
		step += 1
		_render_page()
		return
	_show_title()

## 章节标题卡：**只有游戏名**，别的什么都没有。
## 字从略小缓慢放大，配合淡入——不做按钮、不做副标题、不做装饰线。
func _show_title() -> void:
	if _finishing:
		return
	_finishing = true
	card.hide()
	_top.hide()
	_full = ""

	# 标题卡把屏幕压成**全黑**，后面的场景图完全不参与。
	var scrim := ColorRect.new()
	scrim.color = Color.BLACK
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.modulate.a = 0.0
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var words := UI.heading("黑　页", int(UI.SIZE_CHAPTER * 0.72))
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.modulate.a = 0.0
	center.add_child(words)

	# 用字号补间做「缓慢变大」：比 scale 省事，也不用管 pivot_offset 什么时候才准。
	var tween := create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(scrim, "modulate:a", 1.0, 0.55)
	tween.tween_property(words, "modulate:a", 1.0, 0.9)
	tween.tween_method(
		func(value: float): words.add_theme_font_size_override("font_size", int(value)),
		UI.SIZE_CHAPTER * 0.72, float(UI.SIZE_CHAPTER), 1.5)

	await get_tree().create_timer(1.5).timeout
	_finish()

func _finish() -> void:
	if _done or not is_inside_tree():
		return
	_done = true
	GameState.apply({"set": {"prologue.completed": true}})
	finished.emit()
	queue_free()
