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
## 热区建层与 UV 换算的共用组件——房间那套也用它，别再各写一份。
const HotspotLayer = preload("res://scripts/core/hotspot_layer.gd")
## 逐字显示。主界面那套也是同一个组件——打字机全项目只此一份。
const Typewriter = preload("res://scripts/core/typewriter.gd")
## 进度条宽度。**写死**：跟着页数涨的话，32 页就会横贯整屏。
const PROGRESS_W := 132.0
## 墨迹渗出。黑页上的字靠它「像墨一样渗出来」，见 assets/shaders/ink_bleed.gdshader。
const INK_SHADER = preload("res://assets/shaders/ink_bleed.gdshader")
const BG_DOOR = preload("res://assets/backgrounds/black_page_prologue_door_v1.png")
const BG_NOTE = preload("res://assets/backgrounds/black_page_prologue_notebook_v1.png")

## 序章文本在 `res://data/black_page/prologue.json`——**改剧情去改那个文件**（支持 F6 热重载）。
##
## 它由 `data_loader` 统一加载并规范化，见 `bundle.prologue`——
## **全项目只有一条数据管线**，序章不再自己 FileAccess + JSON.parse_string。
## 每页字段的白名单在 data_loader.gd 的 PROLOGUE_FIELDS（写错字段会在加载时告警）。
##
## body 里换行符分段（一段一次点击）；`<br>` 是段内换行，不额外点击。
var pages: Array = []

## main.gd 从 `game.bundle.prologue` 注入进来。空的话退到内置文本，保证序章永远能跑完。
var source: Array = []

## main.gd 注入的调查模块。**序章写状态必须经它**——不越过游戏模块直接改底层状态。
var game: Node
## main.gd 注入的音乐播放器。序章的音乐是「若有若无，然后消失」（策划案 §九），
## 所以页面可以自己声明对音乐的要求，见 。
var music: Node
## main.gd 注入的音效播放器。音效是**事件型**的（分页触发一次，不循环）。
var sfx: Node
## main.gd 注入的文字速度倍率（玩家档位）。
## **乘在页面 speed 之上**——页面里配的 speed 是演出意图（越接近 23:47 越慢），
## 那属于内容，不该被玩家偏好抹掉；玩家的档位只是整体调快调慢。
var type_scale := 1.0

## main.gd 注入的记录回调：把看过的正文交给「剧情回顾」。
## 不在这里自己存一份——回顾要收全（序章 + 第一章），只能有一个地方收。
var record: Callable = Callable()

func _load_pages() -> Array:
	if source.is_empty():
		push_warning("序章数据没注入（bundle.prologue 为空），先用内置文本兜底")
		return BUILTIN_PAGES
	return source.duplicate(true)

## 这一页的打字速度：页里配了 speed 就用它，没配（或配成 0）就用全局。
func _speed_of(entry: Dictionary) -> float:
	var value := float(entry.get("speed", 0.0))
	return (value if value > 0.0 else UI.TYPE_SPEED) * type_scale

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
## 黑幕：给 background = "black" 的页用。
## 只把贴图置空的话，序章这层是透明的，底下的主界面会透上来。
var _blackout: ColorRect
var _catcher: Button
var _body_scroll: ScrollContainer
var _top: HBoxContainer
## 进度：**一条定宽细线**，不是「一页一个小点」。
##
## 小点写法在 5 页的序章里刚好，32 页就变成横贯整屏的虚线了——
## 页数一多，小点既占地方又读不出信息（32 个小点谁也数不清）。
var _progress_fill: ColorRect
var _hint: Label
var _auto := false
var _auto_clock := 0.0
var _auto_link: Button
var _auto_tween: Tween
## 逐字显示当前这一段。求「该显示什么」交给 Typewriter。
var _typer := Typewriter.new()
var _finishing := false
var _done := false
var _card_tween: Tween
var _beats: Array = []
var _beat := 0
## 当前这一页的打字速度（字/秒）。页里没配 speed 就是 UI.TYPE_SPEED。
var _speed := UI.TYPE_SPEED

## 演出层。三层都加在 _catcher 之上——热区要能抢到点击，卡片要盖住背景。
var _visual_layer: Control
var _hotspot_layer: Control
var _choice_layer: VBoxContainer


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

	_blackout = ColorRect.new()
	_blackout.color = Color.BLACK
	_blackout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blackout.visible = false
	add_child(_blackout)

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

	# 演出层：卡片 / 热区 / 选项。都在 _catcher 之上，否则热区点不到。
	_visual_layer = Control.new()
	_visual_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_visual_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_visual_layer)

	_hotspot_layer = HotspotLayer.new()
	add_child(_hotspot_layer)

	_choice_layer = VBoxContainer.new()
	_choice_layer.add_theme_constant_override("separation", 10)
	_choice_layer.alignment = BoxContainer.ALIGNMENT_END
	_choice_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_choice_layer)

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
	# 「跳过」= 跳过整段序章，直接交接给第一章。
	_top.add_child(_top_link("跳过 ▸▸", _finish))

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
	# 进度：一条定宽细线（走过的部分亮起来）。定宽是关键——
	# 宽度不能跟着页数涨，否则 32 页就会横贯整屏。
	var bar := Control.new()
	bar.name = "Progress"
	bar.custom_minimum_size = Vector2(PROGRESS_W, 3)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := ColorRect.new()
	track.color = Color(0.4941, 0.6980, 0.7686, 0.16)
	track.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(track)
	_progress_fill = ColorRect.new()
	_progress_fill.color = UI.ACCENT
	_progress_fill.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_progress_fill.offset_right = 0.0
	_progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_progress_fill)
	head.add_child(bar)
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
	# 演出层跟着窗口尺寸重排（热区是 UV 比例，必须重算）。
	_layout_visual()
	_layout_hotspots()
	_layout_choices()

func _render_page() -> void:
	if step < 0 or step >= pages.size():
		return
	var entry: Dictionary = pages[step]
	title.text = str(entry.title)
	_speed = _speed_of(entry)

	# 这一页的 set 在**进入这一页时**写入：和玩家点了几下无关。
	# 走 game 的口子而不是直接改 GameState——flag 名写错会带原因返回。
	var changes: Dictionary = entry.get("set", {})
	if not changes.is_empty() and game != null:
		var error: String = game.apply_state(changes)
		if not error.is_empty():
			push_warning("序章第 %d 页 set 失败：%s" % [step, error])

	# 这一页正文按换行切成若干「段」，一段一次点击。
	# 太长的一整段读起来累，也看不完——所以正文里用 \n 分行就等于切分。
	_beats = _lines_of(str(entry.body))
	_beat = 0
	_show_beat()

	_apply_backdrop(str(entry.background))
	_apply_page_music(entry.get("music", {}))
	_play_page_sfx(entry.get("sfx", ""))
	_clear_layers()
	_render_visual(entry.get("visual", {}))
	_render_hotspots(entry.get("hotspots", []))
	_render_choices(entry.get("choices", []))

	# 标题卡独立成屏，不挂底部字幕带。
	var is_title := str((entry.get("visual", {}) as Dictionary).get("type", "")) == "title"
	card.visible = not is_title
	# 标题卡要**全黑**：底部的字幕带和顶部的「自动／跳过」都得收掉。
	# 只藏字幕带的话，屏幕上还剩着顶栏那几个字，就不是全黑了。
	_top.visible = not is_title

	# 进度条：走过多少页就亮多少。定宽，不跟着页数涨。
	if _progress_fill != null:
		var ratio := float(step + 1) / float(maxi(pages.size(), 1))
		_progress_fill.offset_right = PROGRESS_W * ratio
	_auto_clock = 0.0
	if _card_tween != null and _card_tween.is_valid():
		_card_tween.kill()
	if is_title:
		card.modulate.a = 1.0
		return
	card.modulate.a = 0.0
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
	_typer.set_line(str(_beats[_beat]), _speed)
	if record.is_valid(): record.call(_typer.full_text())
	body.text = ""
	if _body_scroll != null:
		_body_scroll.scroll_vertical = 0
	_hint.text = ""

## 演出卡片的入场：轻轻淡出来。**别做位移**——位置由 _layout_visual 管，
## 动画去动 position 会和它打架。黑页的调子也要克制，不做弹跳。
func _fade_in(node: Control, delay := 0.0, dur := 0.45) -> void:
	node.modulate.a = 0.0
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "modulate:a", 1.0, dur).set_delay(delay)

## 热区的悬停反馈。
##
## 序章的热区**平时完全隐形**（靠正文点出可点的东西），但鼠标扫上去必须有回应，
## 否则玩家不知道自己指到了什么。所以这里只给一圈极淡的青边，
## 不做房间那套辉光、也不做调试标签——那些不该出现在序章。
func _decorate_hotspot(box: Control, _item: Dictionary) -> void:
	box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var ring := Panel.new()
	ring.name = "Ring"
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.add_theme_stylebox_override(
		"panel", UI.box(Color(0, 0, 0, 0), UI.ACCENT, 1, 6, 0))
	ring.modulate.a = 0.0
	box.add_child(ring)
	box.mouse_entered.connect(func():
		var t := box.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t.tween_property(ring, "modulate:a", 0.5, 0.12))
	box.mouse_exited.connect(func():
		var t := box.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t.tween_property(ring, "modulate:a", 0.0, 0.2))

## 清空三层演出。每次翻页先全清，避免上一页的卡片和热区残留。
func _clear_layers() -> void:
	for layer in [_visual_layer, _hotspot_layer, _choice_layer]:
		if layer == null: continue
		for child in layer.get_children():
			layer.remove_child(child)
			child.queue_free()

## 应用这一页声明的音乐要求。
##
## 序章的音乐是「若有若无，然后消失」——策划案 §九 的原话是
## 「房间里**原本若有若无的音乐**已经停了」，所以它归数据管，不写死在代码里：
##
##   {"play": "res://assets/audio/x.ogg", "db": -26.0, "fade": 5.0}   放（db 越低越若有若无）
##   {"stop": true, "fade": 4.0}                                     淡出停掉
func _apply_page_music(spec: Variant) -> void:
	if music == null or not (spec is Dictionary): return
	var changes: Dictionary = spec
	if changes.is_empty(): return
	var fade := float(changes.get("fade", 3.0))
	if bool(changes.get("stop", false)):
		music.fade_out(fade)
		return
	var track := str(changes.get("play", ""))
	if track.is_empty(): return
	music.play_track(track, fade, float(changes.get("db", -20.0)))

## 放这一页声明的音效。**事件型**：进这一页响一次，不循环、不淡入淡出。
##
##   "sfx": "res://assets/audio/sfx_impact.wav"              一个
##   "sfx": ["res://.../a.wav", "res://.../b.wav"]           同时几个
##
## 缺素材会安静跳过（和 BGM / 雨声一个规矩），不阻断剧情。
func _play_page_sfx(spec: Variant) -> void:
	if sfx == null: return
	if spec is String:
		if not (spec as String).is_empty(): sfx.play(spec)
		return
	if spec is Array:
		for path in spec:
			sfx.play(str(path))

## 背景：`"black"` 是纯黑（开场与标题卡），其余按 res:// 路径加载；旧写法 door / note 兜底。
func _apply_backdrop(value: String) -> void:
	var path := value
	if path == "door": path = "res://assets/backgrounds/black_page_prologue_door_v1.png"
	elif path == "note": path = "res://assets/backgrounds/black_page_prologue_notebook_v1.png"
	# "black" 必须**画成黑的**。只把贴图置空的话这一层是透明的，
	# 底下的主界面（房间插画 + HUD）会透上来——策划案 §二 要的是黑屏。
	if path == "black" or path.is_empty():
		_backdrop.texture = null
		_blackout.visible = true
		return
	_blackout.visible = false
	if not ResourceLoader.exists(path):
		_backdrop.texture = null
		return
	_backdrop.texture = load(path)
	_blackout.visible = false

## UV 比例 → 当前控件的像素矩形。热区和笔记本正文框都用它定位。
func _uv_to_rect(uv: Array, view: Vector2) -> Rect2:
	if uv.size() < 4: return Rect2()
	return Rect2(view.x * float(uv[0]), view.y * float(uv[1]),
		view.x * float(uv[2]), view.y * float(uv[3]))

func _render_visual(raw: Variant) -> void:
	if not (raw is Dictionary): return
	var spec: Dictionary = raw
	if spec.is_empty(): return
	match str(spec.get("type", "")):
		"notebook": _build_notebook_visual(spec)
		"profile": _build_profile_card(spec)
		"article": _build_article_card(spec)
		"title": _build_title_card(spec)

## 黑页上的字：贴在笔记本背景的纸页区域（rect 是 UV）。
##
## 用 ink_bleed 着色器让字**像墨一样渗出来**——策划案 §十一 写的是
## 「一点墨色从纸纤维里渗出来」「墨迹缓慢继续出现」。
## 淡入是「显示出来」，墨是「沿着纤维蔓开」，两者观感不一样，所以这里值得用 shader。
func _build_notebook_visual(spec: Dictionary) -> void:
	var label := UI.label(str(spec.get("text", "")), float(spec.get("size", 20)), Color("1b1b1b"))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_meta("uv", spec.get("rect", [0.22, 0.25, 0.27, 0.43]))
	var material := ShaderMaterial.new()
	material.shader = INK_SHADER
	material.set_shader_parameter("progress", 0.0)
	# 每页换一个纸纹，免得六页的纤维一模一样。
	material.set_shader_parameter("seed", float(step) * 13.7)
	label.material = material
	_visual_layer.add_child(label)
	_layout_visual()
	# 墨渗开约 1.8 秒。**别调快**——急了就看不出是墨，变成普通淡入了。
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(value: float):
		if is_instance_valid(material): material.set_shader_parameter("progress", value),
		0.0, 1.0, 1.8)

## 手机聊天卡：头像 + 名字 + 正文（对白气泡的位置感）。
func _build_profile_card(spec: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.box(Color(0.02, 0.04, 0.05, 0.86), Color(1, 1, 1, 0.10), 1, 12, 20))
	panel.set_meta("uv", [0.58, 0.14, 0.30, 0.46])
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var avatar := TextureRect.new()
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	avatar.custom_minimum_size = Vector2(64, 64)
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var portrait := str(spec.get("portrait", ""))
	if not portrait.is_empty() and ResourceLoader.exists(portrait):
		avatar.texture = load(portrait)
	head.add_child(avatar)
	head.add_child(UI.label(str(spec.get("heading", "")), UI.SIZE_BODY, UI.TEXT_BRIGHT))
	column.add_child(head)
	column.add_child(UI.flow(str(spec.get("detail", "")), UI.SIZE_SMALL + 1, Color("dae6ec")))
	_visual_layer.add_child(panel)
	_layout_visual()
	_fade_in(panel, 0.0, 0.5)

## 新闻 / 网页卡：栏目标签 + 头像 + 标题 + 正文。
func _build_article_card(spec: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.box(Color(0.02, 0.04, 0.05, 0.90), Color(1, 1, 1, 0.12), 1, 12, 24))
	panel.set_meta("uv", [0.50, 0.12, 0.40, 0.52])
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	column.add_child(UI.label(str(spec.get("eyebrow", "")), UI.SIZE_MICRO, UI.AMBER))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shot := TextureRect.new()
	shot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	shot.custom_minimum_size = Vector2(112, 112)
	shot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var portrait := str(spec.get("portrait", ""))
	if not portrait.is_empty() and ResourceLoader.exists(portrait):
		shot.texture = load(portrait)
	row.add_child(shot)
	var text_column := VBoxContainer.new()
	text_column.add_theme_constant_override("separation", 8)
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var headline := UI.label(str(spec.get("headline", "")), UI.SIZE_BODY + 2, UI.TEXT_BRIGHT)
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_column.add_child(headline)
	text_column.add_child(UI.flow(str(spec.get("copy", "")), UI.SIZE_SMALL, UI.TEXT_DIM))
	row.add_child(text_column)
	column.add_child(row)
	_visual_layer.add_child(panel)
	_layout_visual()
	_fade_in(panel, 0.0, 0.5)

## 标题卡：整屏居中，不挂底部字幕带。
func _build_title_card(spec: Dictionary) -> void:
	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 18)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var primary := UI.label(str(spec.get("primary", "")), float(spec.get("primary_size", 72)), UI.TEXT_BRIGHT)
	primary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(primary)
	var secondary_text := str(spec.get("secondary", ""))
	var secondary: Label = null
	if not secondary_text.is_empty():
		secondary = UI.label(secondary_text, float(spec.get("secondary_size", 28)), UI.TEXT_DIM)
		secondary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		center.add_child(secondary)
	_visual_layer.add_child(center)
	_intro_title(center, primary, secondary)

## 标题卡的入场：**先浮出来，再慢慢放大一点点**。
##
## 策划案 §十二 写的是「一滴黑色墨水落下。墨迹慢慢扩散。形成标题」，
## 那种水墨扩散用代码做不像，但「缓慢浮出 + 极轻地放大」能拿到同一个"沉下去"的观感。
##
## 放大要等一帧拿到实际尺寸才设轴心，否则会从左上角往外涨。
func _intro_title(center: Control, primary: Label, secondary: Label) -> void:
	center.modulate.a = 0.0
	var appear := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	appear.tween_property(center, "modulate:a", 1.0, 1.5)
	await get_tree().process_frame
	if not is_instance_valid(primary) or not is_instance_valid(center): return
	if secondary != null and is_instance_valid(secondary):
		secondary.modulate.a = 0.0
		var sub := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		sub.tween_property(secondary, "modulate:a", 1.0, 1.2).set_delay(0.9)
	primary.pivot_offset = primary.size * 0.5
	primary.scale = Vector2(0.93, 0.93)
	var grow := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	grow.tween_property(primary, "scale", Vector2.ONE, 2.2)

## 轻量分支：按钮竖排。点选后把 response 当作正文播出来，并写入自己的 set。
func _render_choices(raw: Variant) -> void:
	if not (raw is Array) or raw.is_empty(): return
	var index := 0
	for item in raw:
		if not (item is Dictionary): continue
		var choice: Dictionary = item
		var button := UI.ghost_button(str(choice.get("text", "")))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func():
			var changes: Dictionary = choice.get("set", {})
			if not changes.is_empty() and game != null: game.apply_state(changes)
			_clear_layers()
			_show_response(str(choice.get("response", ""))))
		_choice_layer.add_child(button)
		_fade_in(button, 0.07 * index, 0.35)
		index += 1
	_layout_choices()

## 第一人称热区：`rect` 是 UV 比例，点一下把 `response` 播成正文。
## 建层与 UV→屏幕的换算交给共用的 hotspot_layer——房间那套用的是同一个组件。
func _render_hotspots(raw: Variant) -> void:
	if not (raw is Array) or raw.is_empty(): return
	var texture: Texture2D = _backdrop.texture
	if texture == null: return
	_hotspot_layer.setup(raw, Vector2(texture.get_width(), texture.get_height()),
		func(item: Dictionary):
			_clear_layers()
			_show_response(str(item.get("response", ""))), _decorate_hotspot)

## 把一个「回应」当成新的一段正文播出来——热区和选项共用这条路径。
func _show_response(text: String) -> void:
	if text.strip_edges().is_empty(): return
	_beats = _lines_of(text)
	_beat = 0
	_hint.text = ""
	_show_beat()

## 选项层贴在哪：正文栏上方、和正文同样的窄栏宽度，从下往上排。
func _layout_choices() -> void:
	if _choice_layer == null or not is_inside_tree(): return
	var side := size.x * 0.19
	_choice_layer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_choice_layer.offset_left = side
	_choice_layer.offset_right = -side
	_choice_layer.offset_top = -(UI.DIALOG_H + 240)
	_choice_layer.offset_bottom = -(UI.DIALOG_H + 16)

## 热区层自己管定位——UV→屏幕的换算在 core/hotspot_layer.gd 里，全项目只此一份。
func _layout_hotspots() -> void:
	if _hotspot_layer != null: _hotspot_layer.relayout()

## 视觉卡片的落位（笔记本按 rect 贴纸页；面板类走自己的 uv）。
func _layout_visual() -> void:
	if _visual_layer == null or not is_inside_tree(): return
	var view := _visual_layer.size
	if view.x <= 0.0: view = size
	var scale := size.y / 720.0
	for child in _visual_layer.get_children():
		var box := child as Control
		if box.has_meta("uv"):
			var uv: Variant = box.get_meta("uv", [])
			if (uv is Array) and (uv as Array).size() >= 4:
				var rect := _uv_to_rect(uv, view)
				box.position = rect.position
				if box is PanelContainer:
					# 面板类卡片：宽度按 UV 定，**高度跟着内容走**。
					# 但高度**必须等一帧再量**——宽度还没生效时，里面的自动换行标签
					# 会按「宽度 0」去换行，报出一个巨大的最小高度，把面板撑成一个大黑框。
					box.custom_minimum_size = Vector2(rect.size.x, 0.0)
					box.size = Vector2(rect.size.x, 0.0)
					_fit_panel_height.call_deferred(box)
				else:
					box.custom_minimum_size = rect.size
					box.size = rect.size
			# 笔记本上的字按字号缩放，和界面其它部分保持一致。
			if box is Label:
				(box as Label).add_theme_font_size_override("font_size",
					int(float(box.get_meta("size", 20)) * scale))
		elif box is PanelContainer:
			box.size = box.get_combined_minimum_size()

## 等宽度生效之后，把面板高度收到内容高度。
##
## 为什么不能当场量：PanelContainer 里的标签是自动换行的，宽度还没应用时
## 它们按「宽 0」换行，最小高度会算成一个荒谬的大值，当场用就会把面板撑成黑框。
func _fit_panel_height(box: Control) -> void:
	if not is_instance_valid(box): return
	await get_tree().process_frame
	if not is_instance_valid(box): return
	box.size.y = box.get_combined_minimum_size().y

func _is_last_beat() -> bool:
	return _beat >= _beats.size() - 1

func _process(delta: float) -> void:
	_typer.tick(delta)
	body.text = _typer.visible_text()
	if not _typer.is_done():
		# 还在打字：自动模式不计时，免得打完就跳。
		if _auto: _auto_clock = 0.0
		return
	# 整页读完（最后一段也打完了），才提示这一页要做什么。
	# 没读完就冒出来，玩家还没看懂发生什么就能把剧情推过去，很假。
	if _is_last_beat() and _hint.text.is_empty() and step < pages.size():
		_hint.text = "%s  ▸" % pages[step].action
	if _auto and not _finishing:
		_auto_clock += delta
		if _auto_clock > 2.2: _tap()

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
	return not _typer.is_done()

## 玩家的点击：先补完打字 → 再一段一段过 → 最后才翻页。
func _tap() -> void:
	if _finishing:
		_finish()
		return
	if _is_typing():
		# 点击的第一段行为：先把这一句补完，不翻页。
		_typer.complete()
		body.text = _typer.visible_text()
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
##
## 翻过最后一页就是序章结束。
## **不要在结尾再弹一次标题卡**——「黑页」这个标题在数据里已经有自己的一页
## （`game_title`，正文走完之后、许妍电话之前），那是它唯一该出现的地方。
## 旧版这里会调 _show_title() 把游戏名再放一遍，结果屏幕上弹了两次《黑页》，
## 而且第一次因为顶栏没收掉、看起来还不全黑。
func _advance() -> void:
	if _finishing:
		return
	if step < pages.size() - 1:
		step += 1
		_render_page()
		return
	_finish()

## 章节标题卡：**只有游戏名**，别的什么都没有。
## 字从略小缓慢放大，配合淡入——不做按钮、不做副标题、不做装饰线。
## 序章结束：把该写的状态写掉，交接给第一章。
func _finish() -> void:
	if _done or not is_inside_tree():
		return
	_done = true
	_finishing = true
	if game != null: game.apply_state({"prologue.completed": true})
	finished.emit()
	queue_free()
