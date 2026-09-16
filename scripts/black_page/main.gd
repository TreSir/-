extends Control
## 《黑页》主界面。
##
## 形态：**整张场景图 + 底部剧情字幕带 + 常驻左侧栏**。
##   · **案件 / 人物 / 线索 / 黑页 是四个独立的系统功能**，常驻在左侧栏，随时可点开查看。
##     它们不属于剧情流，不允许塞进对话选项里。
##   · 剧情在底部字幕带推进：点一下画面出一句。主界面**不摆任何推进按钮**。
##   · 调查从「案件」面板里发起，选中后**场景整张切换**——第一人称去看，不是翻数据表。
##   · 调查正文读完即结算（读到就必须提交，不能免费读完再取消），不需要额外确认按钮。
##   · 存档 / 读取 / 重开 / 雨声 / 背景音乐收在最下面的 ☰。
##
## 兼容性约束（tests/black_page_smoke.gd 依赖，改动前先看这里）：
##   · 节点名保留：shell / header / notice / modal / modal_rows / launch / prologue / game。
##   · refresh() 后 header.text 必须含「第 N 天」。
##   · _confirm 产出 modal_rows：0 标题、1 正文、2 确认按钮、3 返回按钮
##     （_ask_write 会直接改 2 和 3 的文字）。
##   · 小游戏：0 标题、1 小游戏实例、2 返回按钮。
##   · 调查结果：0 标题、1 正文、2 提交按钮。

const Investigation = preload("res://scripts/black_page/investigation.gd")
const Room = preload("res://scripts/black_page/room.gd")
const Prologue = preload("res://scripts/black_page/prologue.gd")
const Launch = preload("res://scripts/black_page/launch.gd")
const RainAmbience = preload("res://scripts/black_page/rain_ambience.gd")
const BgmPlayer = preload("res://scripts/black_page/bgm_player.gd")
## 一次性音效播放器（嗡 / 铃声 / 砰 / 翻页……）。和 BGM、雨声各走各的。
const SfxPlayer = preload("res://scripts/core/sfx_player.gd")
## 热区建层与 UV 换算的共用组件——序章那套也用它。
const HotspotLayer = preload("res://scripts/core/hotspot_layer.gd")
## 逐字显示。序章那套也是同一个组件——打字机全项目只此一份。
const Typewriter = preload("res://scripts/core/typewriter.gd")
const AudioTracks = preload("res://scripts/black_page/audio_tracks.gd")
const Store = preload("res://scripts/core/save_store.gd")
const UI = preload("res://scripts/black_page/ui_style.gd")
const Scenes = preload("res://scripts/black_page/scenes.gd")
const Hotspots = preload("res://scripts/black_page/hotspots.gd")

const PERSON_STATUS := {"normal": "正常", "missing": "下落不明", "fugitive": "逃亡", "injured": "受伤", "dead": "死亡", "arrested": "被捕", "hidden": "隐藏", "left": "离开城市"}
const CASE_STATUS := {"undiscovered": "未发现", "investigating": "调查中", "blocked": "暂无调查方向", "clear": "真相基本明确", "frozen": "冻结"}
const RELIABILITY := {"reliable": "可靠", "dubious": "存疑", "contradictory": "矛盾", "forged": "伪造"}
const DAY_TIMES := ["23:40", "18:40", "14:20", "09:10"]
const MAX_FREE_ACTIONS := 3

var game = Investigation.new()
var scene_id := Scenes.ROOM
var shell: Control
## HUD 的共同父节点。顶栏／左侧栏／字幕带都挂在它下面，
## 于是“收起 HUD”就是切这一个节点——**不需要逐个列举**。
var _hud_layer: Control
## 顶栏（黑页／房间 · 第N天 · 剩余行动）。
## 留这个引用只为让测试能断言它**确实挂在 hud 层里**（漏挂就会漏收）。
var _topbar: Control
var header: Label
var notice: Label
var modal: Control
var modal_rows: VBoxContainer
var prologue: Prologue
var launch: Launch
var rain: RainAmbience
var music: BgmPlayer
var sfx: SfxPlayer
var rain_muted := false
var music_muted := false
var nav_buttons: Dictionary = {}

var _scene_layer: TextureRect
var _hotspot_layer: HotspotLayer
var _fade: ColorRect
var _catcher: Button
var _speaker: TextureRect
var _speaker_tween: Tween
var _rail: VBoxContainer
var _crumb: Label
var _pips: HBoxContainer
var _menu_layer: Control
var _menu_panel: VBoxContainer
var _menu_button: Button
var _logo_button: Button
## 打开热区轮廓，用来人工核对锚点坐标（运行时用 MCP 设 true 截图，平时关着）。
var hotspot_debug := false
var _modal_panel: PanelContainer
var _modal_scroll: ScrollContainer
var _queue: Array = []
var _on_done: Callable = Callable()
## 逐字显示当前这一句。求「该显示什么」交给 Typewriter——打字机全项目只此一份。
var _typer := Typewriter.new()
## 当前这批叙述的打字速度。用 _say() 的 speed 参数覆盖，默认取全局。
var _beat_speed := UI.TYPE_SPEED
var _in_room := true
var _open_panel := ""


func _ready() -> void:
	name = "BlackPage"
	_build()
	game.name = "Investigation"
	add_child(game)
	game.changed.connect(refresh)
	# 结局是这一周的终点：音乐收掉，让最后那段文字自己说话。
	EventBus.ending_reached.connect(func(_id: String, _entry: String):
		if is_instance_valid(music): music.fade_out(3.0))
	var error: String = game.open()
	if not error.is_empty(): _message(error)
	else:
		_show_launch()

# ── 界面搭建 ─────────────────────────────────────────────────────────────
func _build() -> void:
	theme = UI.build_theme()

	var background: Control = get_node_or_null("RoomBackground")
	if background == null:
		background = Room.new()
		background.name = "RoomBackground"
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(background)

	var veil := ColorRect.new()
	veil.color = UI.VEIL
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	# 场景层：调查时整张换掉，盖住房间图。
	_scene_layer = TextureRect.new()
	_scene_layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scene_layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_scene_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scene_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene_layer.hide()
	add_child(_scene_layer)

	# 全屏点击层：推进底部剧情。放最底层，上层控件用 IGNORE 让点击落下来。
	_catcher = Button.new()
	_catcher.flat = true
	_catcher.focus_mode = Control.FOCUS_NONE
	_catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var blank := UI.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0)
	for state in ["normal", "hover", "pressed", "focus"]:
		_catcher.add_theme_stylebox_override(state, blank)
	_catcher.pressed.connect(_advance_story)
	add_child(_catcher)

	_build_hotspots()

	# HUD 层：**所有游戏内界面元素的共同父节点**——顶栏、左侧栏、底部字幕带。
	# 显隐是一刀切的（_reveal_hud 只切这一个节点），所以属于 HUD 的东西
	# **必须挂进来**，不能挂在主节点上——顶栏以前就是这么漏出来的。
	_hud_layer = Control.new()
	_hud_layer.name = "HudLayer"
	_hud_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud_layer)

	_build_topbar()
	_build_rail()
	_build_speaker()
	_build_shell()

	# 转场遮罩：场景切换时压黑一下再亮回来。盖住 HUD，但菜单和弹层在它上面。
	_fade = ColorRect.new()
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)

	_build_menu()
	_build_modal()

## 左侧栏：案件 / 人物 / 线索 / 黑页 是四个**独立的系统功能**，常驻在此，随时可点开。
## 存档/读取/重开/雨声/音乐收在最下面的 ☰。
func _build_rail() -> void:
	_rail = VBoxContainer.new()
	_rail.add_theme_constant_override("separation", 2)
	_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_rail.offset_top = UI.TOPBAR_H
	_rail.offset_bottom = -18
	_rail.custom_minimum_size.x = UI.RAIL_W
	_hud_layer.add_child(_rail)

	var entries := [
		["案件", "case", func(): _open_case()],
		["人物", "people", func(): _open_people()],
		["口袋", "pocket", func(): _open_pocket()],
		["黑页", "notebook", func(): _open_notebook()],
	]
	for entry in entries:
		var button := UI.nav_item(str(entry[0]))
		button.pressed.connect(entry[2])
		_rail.add_child(button)
		nav_buttons[str(entry[1])] = button

	_rail.add_child(UI.stretch())

	_menu_button = UI.icon_button("菜单", "菜单")
	_menu_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_menu_button.pressed.connect(_toggle_menu)
	_rail.add_child(_menu_button)

	var build := UI.label("BUILD 0.2", UI.SIZE_MICRO - 1, Color("3f4d56"))
	build.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rail.add_child(build)

func _build_topbar() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	row.offset_left = 30
	row.offset_right = -30
	row.offset_top = (UI.TOPBAR_H - 28) * 0.5
	row.offset_bottom = row.offset_top + 28
	_hud_layer.add_child(row)
	_topbar = row

	var logo := Button.new()
	logo.text = "黑　页"
	logo.flat = true
	logo.add_theme_font_override("font", UI.serif())
	logo.add_theme_font_size_override("font_size", UI.SIZE_SMALL + 2)
	logo.add_theme_color_override("font_color", UI.TEXT_BRIGHT)
	logo.add_theme_color_override("font_hover_color", UI.ACCENT)
	var none := UI.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0)
	for state in ["normal", "hover", "pressed", "focus"]:
		logo.add_theme_stylebox_override(state, none)
	logo.pressed.connect(_enter_room)
	row.add_child(logo)
	_logo_button = logo

	var slash := UI.label("／", UI.SIZE_SMALL, UI.TEXT_MUTE)
	slash.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slash)
	_crumb = UI.label("", UI.SIZE_SMALL, UI.TEXT_DIM)
	_crumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_crumb)

	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)

	header = UI.label("", UI.SIZE_SMALL, UI.TEXT_DIM)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(header)

	row.add_child(_vsep())
	var caption := UI.label("剩余行动", UI.SIZE_MICRO, UI.TEXT_MUTE)
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(caption)
	_pips = HBoxContainer.new()
	_pips.add_theme_constant_override("separation", 5)
	_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for _index in MAX_FREE_ACTIONS:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(20, 4)
		_pips.add_child(pip)
	row.add_child(_pips)

func _vsep() -> ColorRect:
	var sep := ColorRect.new()
	sep.color = UI.HAIR
	sep.custom_minimum_size = Vector2(1, 18)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sep

## 说话人立绘：站在对话框右侧。只在「这一句有人说话」时出现，旁白时不出现。
func _build_speaker() -> void:
	_speaker = TextureRect.new()
	_speaker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_speaker.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_speaker.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_speaker.offset_right = -56
	_speaker.offset_bottom = -(UI.DIALOG_H - 72)
	_speaker.offset_left = _speaker.offset_right - 340
	_speaker.offset_top = _speaker.offset_bottom - 460
	_speaker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speaker.modulate.a = 0.0
	_speaker.hide()
	add_child(_speaker)

## 显示当前这段的叙述者（没有就收起来）。
func _set_speaker(line: String) -> void:
	var person_id := _speaker_of(line)
	if person_id.is_empty():
		_speaker.hide()
		return
	var texture := _portrait_texture(person_id)
	if texture == null:
		_speaker.hide()
		return
	_speaker.texture = texture
	_speaker.show()
	if _speaker_tween != null and _speaker_tween.is_valid():
		_speaker_tween.kill()
	_speaker_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_speaker_tween.tween_property(_speaker, "modulate:a", 1.0, 0.28)

## 从句子开头认说话人：写成「许妍：……」就会显示许妍的立绘。
## 认不出来（比如「经办人说：……」这种一次性的路人）就不显示立绘。
func _speaker_of(line: String) -> String:
	for id in game.bundle.people:
		var name_text := str(game.bundle.people[id].name)
		if line.begins_with(name_text + "：") or line.begins_with(name_text + ":"):
			return str(id)
	return ""

## 底部对话框：上下两边都固定，中间是一个可滚动区域。
## 正文从固定高度起排、往下长；超出框高之后用滚轮往下看，框本身纹丝不动。
func _build_shell() -> void:
	shell = UI.dialogue_box()
	_hud_layer.add_child(shell)
	shell.add_child(UI.dialogue_scrim())

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", UI.MARGIN_L)
	margin.add_theme_constant_override("margin_right", UI.MARGIN_R)
	# 上边距撑出正文的起始高度——正文不会跑到屏幕中间去。
	margin.add_theme_constant_override("margin_top", 112)
	margin.add_theme_constant_override("margin_bottom", 30)
	shell.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 滚轮归 ScrollContainer 自己；左键点击转发出去，这样在框里点也能推进剧情。
	scroll.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_advance_story())
	margin.add_child(scroll)

	notice = UI.flow("", UI.SIZE_UI, Color("dae6ec"))
	scroll.add_child(notice)

func _process(delta: float) -> void:
	# 打字机：剧情文本逐字出。没走完之前，点击只会把这一句补完，不会推进。
	_typer.tick(delta)
	notice.text = _typer.visible_text()

func _is_typing() -> bool:
	return not _typer.is_done()

func _finish_typing() -> void:
	_typer.complete()
	notice.text = _typer.visible_text()

func _build_menu() -> void:
	_menu_layer = Control.new()
	_menu_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_menu_layer)

	var catcher := Button.new()
	catcher.flat = true
	catcher.focus_mode = Control.FOCUS_NONE
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var blank := UI.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0)
	for state in ["normal", "hover", "pressed", "focus"]:
		catcher.add_theme_stylebox_override(state, blank)
	catcher.pressed.connect(_close_menu)
	_menu_layer.add_child(catcher)

	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 0)
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_right = -30
	panel.offset_left = panel.offset_right - 236
	panel.offset_top = UI.TOPBAR_H + 6
	panel.offset_bottom = panel.offset_top + 360
	_menu_layer.add_child(panel)
	_menu_panel = panel
	_render_menu_rows()

	_menu_layer.hide()

## 菜单行每次重建而不是就地改文字：开关类条目要显示「开/关」，
## 重建一次比抱着单个 Label 的引用可靠，也不会漏掉分隔线。
func _render_menu_rows() -> void:
	for child in _menu_panel.get_children():
		_menu_panel.remove_child(child)
		child.queue_free()
	var head := UI.label("进度与设置", UI.SIZE_MICRO, UI.TEXT_DIM)
	head.custom_minimum_size.y = 30
	head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_menu_panel.add_child(head)
	_menu_panel.add_child(UI.rule())
	_add_menu_row(_menu_panel, "保存进度", "", func():
		var error: String = game.save_game()
		_message(error, "已保存当前进度。"))
	_menu_panel.add_child(UI.rule(0.6))
	_add_menu_row(_menu_panel, "读取存档", "", func(): _confirm("读取存档", "当前未保存进度将被替换。", func(): _message(game.load_game(), "已读取存档。")))
	_menu_panel.add_child(UI.rule(0.6))
	_add_menu_row(_menu_panel, "重新开始", "", func(): _confirm("重新开始", "当前未保存进度将被替换。已有手动存档会保留。", _restart_game))
	_menu_panel.add_child(UI.rule(0.6))
	_add_toggle_row("雨声：%s" % ("关" if rain_muted else "开"), _toggle_rain)
	_menu_panel.add_child(UI.rule(0.6))
	_add_toggle_row("背景音乐：%s" % ("关" if music_muted else "开"), _toggle_music)
	if OS.is_debug_build():
		_menu_panel.add_child(UI.rule(0.6))
		_add_menu_row(_menu_panel, "重载数据", "F6", func(): _message(game.reload_data(), "已重载调查数据。"))
	_menu_panel.add_child(UI.rule(0.6))
	_add_menu_row(_menu_panel, "回到房间", "", _enter_room)

## 开关类条目：点完不关菜单，直接原地重画，方便连着调。
func _add_toggle_row(text: String, callback: Callable) -> void:
	var row := UI.menu_row(text, "")
	row.pressed.connect(func():
		callback.call()
		# 延后一帧再重建：立刻 remove_child 会把正在派发 pressed 的按钮一起回收。
		_render_menu_rows.call_deferred())
	_menu_panel.add_child(row)

func _toggle_rain() -> void:
	rain_muted = not rain_muted
	if is_instance_valid(rain):
		rain.set_muted_by_player(rain_muted)

func _toggle_music() -> void:
	music_muted = not music_muted
	if is_instance_valid(music):
		music.set_muted_by_player(music_muted)

func _add_menu_row(parent: Node, text: String, hint: String, callback: Callable) -> void:
	var row := UI.menu_row(text, hint)
	row.pressed.connect(func():
		_close_menu()
		callback.call())
	parent.add_child(row)

func _toggle_menu() -> void:
	if _menu_layer.visible: _close_menu()
	else: _menu_layer.show()

func _close_menu() -> void:
	if _menu_layer != null: _menu_layer.hide()

func _build_modal() -> void:
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(modal)

	var scrim := ColorRect.new()
	scrim.color = Color(0.0118, 0.0235, 0.0353, 0.72)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(center)

	_modal_panel = PanelContainer.new()
	_modal_panel.custom_minimum_size = Vector2(888, 0)
	_modal_panel.add_theme_stylebox_override("panel", UI.box(Color(0.0392, 0.0667, 0.0902, 0.97), UI.HAIR_STRONG, 18, 0))
	center.add_child(_modal_panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 30)
	pad.add_theme_constant_override("margin_right", 30)
	pad.add_theme_constant_override("margin_top", 28)
	pad.add_theme_constant_override("margin_bottom", 28)
	_modal_panel.add_child(pad)

	_modal_scroll = ScrollContainer.new()
	_modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pad.add_child(_modal_scroll)
	modal_rows = VBoxContainer.new()
	modal_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_rows.add_theme_constant_override("separation", 18)
	_modal_scroll.add_child(modal_rows)

	modal.hide()

# ── 剧情推进 ─────────────────────────────────────────────────────────────
## 播一段叙述。点一下画面推进一句；**最后一句读完、再点一下才执行 on_done**。
## 调查的结算、回房间都挂在 on_done 上——主界面不摆任何推进按钮。
##
## `speed` 传 0（默认）就用全局 `UI.TYPE_SPEED`；
## 某条调查想快/慢，可以在 actions.json 里给它配 `"speed"`。
func _say(lines: Array, on_done: Callable = Callable(), speed: float = 0.0) -> void:
	_queue = lines.duplicate()
	_on_done = on_done
	_beat_speed = speed if speed > 0.0 else UI.TYPE_SPEED
	_show_next_beat()

func _show_next_beat() -> void:
	if _queue.is_empty():
		var done := _on_done
		_on_done = Callable()
		if done.is_valid(): done.call()
		return
	# 段内换行用 <br>，不是 \n——\n 是分段（点一次），<br> 只挪到下一行，不多点一次。
	_typer.set_line(str(_queue.pop_front()), _beat_speed)
	notice.text = ""
	_set_speaker(_typer.full_text())

func _advance_story() -> void:
	_close_menu()
	# 打字机没走完时，第一次点击只把这一句补完。
	# 否则玩家可以在没读完的情况下就把剧情推过去，选择也会提前冒出来。
	if _is_typing():
		_finish_typing()
		return
	# 队列空了但还挂着 on_done 时也要放行——否则结算那一步永远触发不到。
	if _queue.is_empty() and not _on_done.is_valid():
		return
	_show_next_beat()

## 回房间。
##
## `note_*` 是为了修一个顺序坑：调用方想「回房间 + 显示一句提示」时，
## 如果直接 `_enter_room(); _message(...)`，这句提示会被转场后的台词覆盖掉。
## 所以提示要等转场结束、台词落下去之后再打，这里统一收口。
func _enter_room(note_error: String = "", note_success: String = "") -> void:
	if game.bundle.is_empty(): return
	_close_menu()
	_close_modal()
	# 从「黑页时刻」回来，音乐拿回来（没淡出过的话 play_track 自己会早退）。
	if is_instance_valid(music): music.play_track(AudioTracks.MUSIC_GAME)
	_in_room = true
	await _transition_to(Scenes.ROOM)
	_say([_latest_line()])
	if not note_error.is_empty() or not note_success.is_empty():
		_message(note_error, note_success)

## 序章结束后走这里。序章自己已经把该解锁的入口写进状态（人物 / 口袋），
## 案件和黑页要玩家在房间里碰实体才出现——所以这里只管进房间。
func _reveal_game() -> void:
	_reveal_hud(true)
	_enter_room()

## 把最近一条叙述性日志当成「当前台词」。
func _latest_line() -> String:
	var index: int = game.journal.size() - 1
	while index >= 0:
		var body := _narrative_of(str(game.journal[index]))
		if not body.is_empty():
			return body
		index -= 1
	return "雨还在下。桌上那本黑色笔记没有任何动静。"

func _narrative_of(entry: String) -> String:
	var lines: Array = []
	for raw in entry.split("\n"):
		var line := str(raw).strip_edges()
		if line.is_empty(): continue
		if line.begins_with("获得线索："): continue
		if line.begins_with("第 ") and line.ends_with(" 天"): continue
		lines.append(line)
	return "\n".join(lines)

func _beats(text: String) -> Array:
	var lines: Array = []
	for raw in text.split("\n"):
		var line := str(raw).strip_edges()
		if not line.is_empty(): lines.append(line)
	if lines.is_empty(): lines.append("……")
	return lines

## 立刻换场景。用在「不需要转场」的地方（比如翻开黑页只是看个东西）。
func _apply_scene(id: String) -> void:
	if not Scenes.has(id): id = Scenes.ROOM
	scene_id = id
	# 房间复用 RoomBackground（自带雨丝与压暗）；其他场景用场景层整张盖上去。
	_scene_layer.visible = id != Scenes.ROOM
	if _scene_layer.visible:
		_scene_layer.texture = Scenes.texture_of(id)
	_crumb.text = Scenes.name_of(id)
	_sync_hotspots()

# ── 场景热区 ─────────────────────────────────────────────────────────────
## 热区层：盖在场景图上、垫在顶栏/侧栏之下。
## 放在 _catcher 之后是刻意的——Godot 后加的兄弟画在上面、先命中输入，
## 所以点到热区会被它自己吃掉，不会顺带把 _catcher 的「推进剧情」也触发。
func _build_hotspots() -> void:
	_hotspot_layer = HotspotLayer.new()
	_hotspot_layer.name = "HotspotLayer"
	add_child(_hotspot_layer)
	_scene_layer.resized.connect(_layout_hotspots)
	_hotspot_layer.resized.connect(_layout_hotspots)

## 按当前场景重建热区。热区表里只有 room，所以其他场景这里自然是空。
##
## 建层与 UV→屏幕的换算交给共用的 `core/hotspot_layer.gd`——那里全项目只此一份。
## 这个函数只负责提供「房间热区长什么样」的装饰。
func _sync_hotspots() -> void:
	if _hotspot_layer == null: return
	var texture: Texture2D = Scenes.texture_of(scene_id)
	if texture == null:
		_hotspot_layer.clear()
		return
	_hotspot_layer.setup(Hotspots.for_scene(scene_id),
		Vector2(texture.get_width(), texture.get_height()),
		_hotspot_pressed, _decorate_hotspot)

## 房间热区的装饰：悬停时一点青光 + 细描边，以及调试用的标签。
## 黑页的调子要克制，平时完全隐形——所以这些**不进公共路径**，只作为可选回调传进去。
func _decorate_hotspot(box: Control, item: Dictionary) -> void:
	box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	box.tooltip_text = str(item.get("label", ""))

	# 悬停反馈：一点青光 + 细描边。
	var glow := Panel.new()
	glow.name = "Glow"
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.add_theme_stylebox_override(
		"panel", UI.box(Color(0.62, 0.86, 0.95, 0.06), UI.ACCENT, 8, 0, 1))
	glow.modulate.a = 0.0
	box.add_child(glow)
	box.set_meta("glow", glow)

	var tag := UI.label(str(item.get("id", "")), UI.SIZE_MICRO, UI.ACCENT)
	tag.name = "Tag"
	tag.visible = hotspot_debug
	tag.position = Vector2(6, 4)
	box.add_child(tag)

	box.mouse_entered.connect(func():
		var t := box.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t.tween_property(glow, "modulate:a", 1.0, 0.14))
	box.mouse_exited.connect(func():
		var t := box.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t.tween_property(glow, "modulate:a", 0.0, 0.22))

## 热区层自己管定位。这里只处理调试开关：打开时让所有辉光与标签显形。
func _layout_hotspots() -> void:
	if _hotspot_layer == null: return
	_hotspot_layer.relayout()
	if not hotspot_debug: return
	for child in _hotspot_layer.get_children():
		var box := child as Control
		var glow: Panel = box.get_meta("glow", null)
		if glow != null: glow.modulate.a = 1.0
		var tag: Label = box.get_node_or_null("Tag")
		if tag != null: tag.visible = true

## 热区触发。锚点只负责「打开什么」，内容一律复用侧栏那套入口，
## 这样热区和侧栏永远不会走出两套不同的状态。
##
## 第一次碰某个实体时顺带把对应侧栏入口点亮——功能跟着探索长出来，不是开局全给。
func _hotspot_pressed(uv: Dictionary) -> void:
	match str(uv.get("target", "")):
		"notebook":
			_unlock_nav("notebook")
			_open_notebook()
		"monitor":
			_unlock_nav("case")
			_open_case()
		"phone": _open_pocket()
		"clues": _open_clues()
		"people": _open_people()
		_: _open_case()

## 点亮一个侧栏入口，并做一个淡入的解锁动画（玩家能感觉到「这里多了一个入口」）。
## 已经亮着就直接返回，重复点同一个热区不会重放动画。
func _unlock_nav(key: String) -> void:
	if bool(game.flag("ui." + key)):
		return
	var error: String = game.reveal_ui([key])
	if not error.is_empty():
		push_warning("解锁侧栏入口失败：%s" % error)
		return
	var button: Button = nav_buttons.get(key)
	if button == null:
		return
	button.modulate.a = 0.0
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "modulate:a", 1.0, 0.45)

## 取这次转场的配置。优先级：**单条行动 > 目标场景 > 全局默认**。
## 都缺的时候给一份内置的兜底，保证转场不会因为配置写错就卡住。
func _transition_config(scene_id: String, action_id: String = "") -> Dictionary:
	var table: Dictionary = game.bundle.get("transitions", {})
	var merged: Dictionary = {
		"kind": "fade",
		"out": UI.TRANSITION_OUT,
		"in": UI.TRANSITION_IN,
		"color": "000000",
	}
	for layer in [table.get("default", {}), table.get("scenes", {}).get(scene_id, {}), table.get("actions", {}).get(action_id, {})]:
		for key in layer:
			merged[key] = layer[key]
	return merged

## 场景转场。这期间遮罩吃住输入（STOP），免得玩家在黑屏上看不见的时候把剧情点过去。
## 目标场景和当前一样时直接返回——所以「序章结束回房间」这种本来就在房间的不会白闪一下。
func _transition_to(id: String, action_id: String = "") -> void:
	if not Scenes.has(id): id = Scenes.ROOM
	if id == scene_id:
		return
	var config := _transition_config(id, action_id)
	var kind := str(config.get("kind", "fade"))
	var out_time := float(config.get("out", UI.TRANSITION_OUT))
	var in_time := float(config.get("in", UI.TRANSITION_IN))
	_fade.color = Color(str(config.get("color", "000000")))

	if kind == "cut":
		_apply_scene(id)
		return

	if kind == "slide":
		await _transition_slide(id, out_time, in_time)
		return

	await _transition_fade(id, out_time, in_time)

## 淡入淡出：压黑 → 换图 → 亮回来。
func _transition_fade(id: String, out_time: float, in_time: float) -> void:
	_fade.position = Vector2.ZERO
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var out := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	out.tween_property(_fade, "color:a", 1.0, out_time)
	await out.finished
	_apply_scene(id)
	var back := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	back.tween_property(_fade, "color:a", 0.0, in_time)
	await back.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE

## 横扫：一块色板从右边扫过来盖住画面 → 换图 → 继续向左扫出去。
func _transition_slide(id: String, out_time: float, in_time: float) -> void:
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var width := size.x
	_fade.color.a = 1.0
	var cover := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	cover.tween_property(_fade, "position:x", 0.0, out_time).from(width)
	await cover.finished
	_apply_scene(id)
	var reveal := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	reveal.tween_property(_fade, "position:x", -width, in_time)
	await reveal.finished
	_fade.position = Vector2.ZERO
	_fade.color.a = 0.0
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE

# ── 状态刷新 ─────────────────────────────────────────────────────────────
func _restart_game() -> void:
	game.new_game()
	_show_launch()

func _show_launch() -> void:
	if is_instance_valid(launch): return
	_close_menu()
	_close_modal()
	_reveal_hud(false)
	if not is_instance_valid(rain):
		rain = RainAmbience.new()
		rain.name = "RainAmbience"
		add_child(rain)
	rain.set_muted_by_player(rain_muted)
	if not is_instance_valid(music):
		music = BgmPlayer.new()
		music.name = "BgmPlayer"
		add_child(music)
	music.set_muted_by_player(music_muted)
	music.play_track(AudioTracks.MUSIC_MENU)
	if not is_instance_valid(sfx):
		sfx = SfxPlayer.new()
		sfx.name = "SfxPlayer"
		add_child(sfx)
	launch = Launch.new()
	launch.name = "Launch"
	launch.can_continue = not Store.new().read("black_page_slot_1").has("error")
	# 从游戏内退回来重开时，开关状态要跟着走，否则底栏会显示成反的。
	launch.rain_muted = rain_muted
	launch.music_muted = music_muted
	launch.start_requested.connect(_start_new_game)
	launch.continue_requested.connect(_continue_game)
	launch.rain_muted_changed.connect(func(value: bool):
		rain_muted = value
		rain.set_muted_by_player(value))
	launch.music_muted_changed.connect(func(value: bool):
		music_muted = value
		music.set_muted_by_player(value))
	add_child(launch)

## 关掉开始页。`into_prologue` 为真时**不切曲而是淡出**——
## 序章按策划案开场只有雨声、没有音乐，所以这里不能放游戏内底噪。
func _dismiss_launch(into_prologue := false) -> void:
	if is_instance_valid(launch):
		launch.close_to_game()
		launch = null
	if not is_instance_valid(music):
		return
	if into_prologue:
		music.fade_out(1.8)
		return
	# 进房间之后菜单曲就不合适了，换成更轻的游戏内底噪。
	music.play_track(AudioTracks.MUSIC_GAME)

func _start_new_game() -> void:
	game.new_game()
	# 顺序很重要：先把序章盖上去，再让开始页淡出。
	# 反过来做的话，中间那段「开始页已经没了、序章还没出来」的空档会露出房间，就是那一下闪。
	_show_prologue()
	_dismiss_launch(true)

func _continue_game() -> void:
	var error := game.load_game()
	if not error.is_empty():
		_message(error)
		return
	# 存档停在序章里的话，同样不能放音乐——序章是雨声的段落。
	# 注意 flag() 返回 Variant，这里必须显式声明类型，不能让 := 去推。
	var in_prologue: bool = not bool(game.flag("prologue.completed"))
	if in_prologue:
		_show_prologue()
	else:
		_reveal_game()
	_dismiss_launch(in_prologue)

func _show_prologue() -> void:
	if is_instance_valid(prologue): return
	_close_menu()
	_close_modal()
	_reveal_hud(false)
	prologue = Prologue.new()
	prologue.name = "Prologue"
	# 序章的剧本由 data_loader 统一加载、状态由 investigation 统一写。
	# 界面只管把这两个依赖递进去，自己不碰数据。
	prologue.source = game.bundle.get("prologue", [])
	prologue.game = game
	# 序章按页声明它要的音乐（「若有若无，然后消失」），播放器由这里递给它。
	prologue.music = music
	prologue.sfx = sfx
	prologue.finished.connect(func():
		prologue = null
		_reveal_game())
	add_child(prologue)

## 左侧栏和底部字幕带是同一条命：剧情演出时整条 HUD 一起收起。
func _reveal_hud(visible_now: bool) -> void:
	# 一刀切：HUD 的成员都挂在 _hud_layer 下，切它一个就够了。
	# 以前是逐个列举 shell / rail / topbar——**漏一个就漏一片**，
	# 顶栏就是这么在序章里一直露着日期和行动点的。
	_hud_layer.visible = visible_now
	# 热区跟着 HUD 一起收：序章演出时点背景不该有反应。
	if _hotspot_layer != null: _hotspot_layer.visible = visible_now
	# HUD 刚露出来时，侧栏条目要按当前进度重算一次，否则会带着上次的显示状态。
	if visible_now: _sync_nav()

func refresh() -> void:
	if game.bundle.is_empty(): return
	header.text = "第 %d 天   %s" % [int(game.flag("day")), DAY_TIMES[int(game.flag("actions_left"))]]
	_refresh_pips()
	_crumb.text = Scenes.name_of(scene_id)
	_sync_nav()
	# 房间空闲时把底部的「当前台词」刷新成最新一条。调查途中不动，免得盖掉正文。
	if not _in_room or not _queue.is_empty(): return
	var line := _latest_line()
	notice.text = line
	notice.add_theme_color_override("font_color", Color("dae6ec"))
	# 系统刷新直接落全文，不走打字机（这不是剧情推进，不需要逐字）。
	_typer.set_line_now(line)

func _refresh_pips() -> void:
	var left := int(game.flag("actions_left"))
	for index in _pips.get_child_count():
		var pip := _pips.get_child(index) as ColorRect
		pip.color = UI.ACCENT if index < left else Color(0.4941, 0.6980, 0.7686, 0.18)

## 侧栏高亮跟随「当前打开的是哪个面板」，而不是当前场景。
## 同时按「有没有可看的内容」决定条目显不显示——功能跟着剧情长出来，不是开局全摆上。
func _sync_nav() -> void:
	for key in nav_buttons:
		var button: Button = nav_buttons[key]
		var label := str(key)
		button.visible = _nav_available(label)
		var active: bool = label == _open_panel
		var glyph = button.get_meta("glyph")
		var caption: Label = button.get_meta("caption")
		var mark: ColorRect = button.get_meta("mark")
		glyph.set_active(active)
		caption.add_theme_color_override("font_color", UI.ACCENT if active else UI.TEXT_MUTE)
		mark.visible = active

## 这个侧栏入口有没有被剧情点亮。
##
## 开局四个入口**全是关的**（`ui.*` 默认 false）——第一张画面上不该有任何图标，
## 要等手机响了、消息读完、自言自语完，剧情把入口点亮，图标才一个个出现。
func _nav_available(key: String) -> bool:
	if game.bundle.is_empty(): return false
	return bool(game.flag("ui." + key))

# ── 调查 ─────────────────────────────────────────────────────────────────
## 从「案件」面板发起。选中后场景整张切走，正文在底部逐句朗读，读完即结算。
func _investigate(action_id: String) -> void:
	var error: String = game.begin_action(action_id)
	if not error.is_empty():
		_message(error)
		return
	var action: Dictionary = game.bundle.actions[action_id]
	_in_room = false
	await _transition_to(Scenes.for_action(action_id, str(action.kind)), action_id)
	if action.kind == "minigame":
		# 小游戏自己会清空并重新显示弹层，这里不要再关一次。
		_open_minigame(action_id)
		return
	_close_modal()
	_say(_beats(str(action.text)), _commit.bind(action_id), float(action.get("speed", 0.0)))

## 读到正文就必须提交——不能免费读完再取消，所以没有「先不记录」。
func _commit(_action_id: String) -> void:
	var error: String = game.complete_action(game.ticket, {})
	if not error.is_empty():
		_message(error)
		return
	_enter_room()

func _open_minigame(action_id: String) -> void:
	var action: Dictionary = game.bundle.actions[action_id]
	var token: int = game.ticket
	_clear_modal()
	modal.show()
	modal_rows.add_child(_modal_head("调查 ／ 监控", str(action.name)))
	var activity = load(action.scene).instantiate()
	if activity is Control:
		activity.custom_minimum_size.y = maxf(activity.custom_minimum_size.y, 460.0)
	modal_rows.add_child(activity)
	activity.completed.connect(func(result: Dictionary):
		if token == game.ticket: _show_report.call_deferred(action_id, token, result))
	activity.begin(action.config, game.flags_snapshot())
	var back := UI.ghost_button("返回（不消耗行动）")
	back.pressed.connect(func():
		game.cancel_action()
		_close_modal()
		_enter_room())
	modal_rows.add_child(back)
	_fit_modal(false)

func _show_report(action_id: String, token: int, result: Dictionary) -> void:
	if token != game.ticket: return
	_clear_modal()
	var action: Dictionary = game.bundle.actions[action_id]
	modal_rows.add_child(_modal_head("调查结果", str(action.name)))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(UI.narrow(UI.flow(str(action.text), UI.SIZE_BODY, Color("d3e0e7")), 0.24))
	body.add_child(UI.rule())
	var warn := UI.flow("记录结果后消耗 1 次行动，不能取消。", UI.SIZE_MICRO, UI.TEXT_MUTE)
	body.add_child(warn)
	modal_rows.add_child(body)
	modal_rows.add_child(UI.primary_button("记录结果，返回房间"))
	modal_rows.get_child(2).pressed.connect(func():
		var error: String = game.complete_action(token, result)
		if not error.is_empty():
			warn.text = error
			warn.add_theme_color_override("font_color", UI.AMBER)
			return
		_close_modal()
		_enter_room())
	_fit_modal()

# ── 左侧栏的四个系统面板 ─────────────────────────────────────────────────
func _begin_panel(key: String, chip_text: String, title_text: String) -> void:
	_open_panel = key
	_sync_nav()
	_clear_modal()
	modal.show()
	modal_rows.add_child(_modal_head(chip_text, title_text))

## `back` 传了就回上一层（图鉴 → 单人页），不传就是关掉整个弹层。
func _end_panel(label: String, back: Callable = Callable()) -> void:
	var close := UI.ghost_button(label)
	if back.is_valid():
		close.pressed.connect(func(): _clear_modal(); back.call())
	else:
		close.pressed.connect(_close_modal)
	modal_rows.add_child(close)
	_fit_modal()

## 口袋：这次调查拿到手的东西。
func _open_pocket() -> void:
	_begin_panel("pocket", "口袋", "你随身带着的东西")
	var rows := _clue_rows()
	if rows.is_empty():
		modal_rows.add_child(UI.flow("口袋里还是空的。", UI.SIZE_BODY, UI.TEXT_DIM))
	else:
		for row in rows: modal_rows.add_child(row)
	_end_panel("合上口袋")

func _open_case() -> void:
	_begin_panel("case", "案件", "正在调查的事")
	var found := 0
	for id in game.bundle.cases:
		var status: String = game.flag("case." + id + ".status")
		if status == "undiscovered": continue
		found += 1
		var entry: Dictionary = game.bundle.cases[id]
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 14)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 12)
		head.add_child(UI.heading(str(entry.name), UI.SIZE_TITLE))
		var chip := UI.accent_chip(CASE_STATUS[status])
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(chip)
		column.add_child(head)
		column.add_child(UI.flow(str(entry.intro), UI.SIZE_SMALL + 1, Color("c6d5dd")))
		column.add_child(UI.rule())
		column.add_child(_label_micro("已知事实"))
		column.add_child(_clue_chips(id))
		column.add_child(_label_micro("仍未回答"))
		var asked := 0
		for question in entry.questions:
			if game.matches(question.get("requires", [])):
				asked += 1
				column.add_child(_bullet(str(question.text)))
		if asked == 0: column.add_child(UI.flow("暂时没有新的疑点。", UI.SIZE_SMALL, UI.TEXT_DIM))
		column.add_child(_label_micro("调查方向"))
		var listed := 0
		var left := int(game.flag("actions_left"))
		for action_id in game.bundle.actions:
			var action: Dictionary = game.bundle.actions[action_id]
			if action.case != id or not game.available(action_id): continue
			listed += 1
			var affordable: bool = left > 0
			var row := UI.action_row(str(action.name), "1 次行动" if affordable else "今日行动已用完", affordable)
			if affordable: row.pressed.connect(_investigate.bind(action_id))
			column.add_child(row)
		if listed == 0:
			column.add_child(UI.flow("暂时没有新的方向。可以等消息，或打开黑页作出决定。", UI.SIZE_SMALL, UI.TEXT_DIM))
		modal_rows.add_child(column)
	if found == 0:
		modal_rows.add_child(UI.flow("还没有接触到任何案件。", UI.SIZE_BODY, UI.TEXT_DIM))
	_end_panel("合上案卷")

## 人物图鉴：先是一排肖像卡，点进去才是这个人的档案。
func _open_people() -> void:
	_begin_panel("people", "人物图鉴", "你调查过的人")
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 18)
	flow.add_theme_constant_override("v_separation", 18)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var count := 0
	for id in game.bundle.people:
		if not bool(game.person_flag(id, "discovered")): continue
		count += 1
		var card := Button.new()
		card.text = ""
		card.custom_minimum_size = Vector2(178, 252)
		var none := UI.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0)
		for state in ["normal", "hover", "pressed", "focus"]:
			card.add_theme_stylebox_override(state, none)
		card.pressed.connect(_open_person.bind(str(id)))
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 10)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var art := TextureRect.new()
		art.texture = _portrait_texture(str(id))
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.custom_minimum_size = Vector2(178, 190)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(art)
		column.add_child(UI.label(game.person_name(id), UI.SIZE_BODY, UI.TEXT_BRIGHT))
		column.add_child(UI.label(PERSON_STATUS[game.person_flag(id, "status")], UI.SIZE_MICRO, UI.TEXT_DIM))
		card.add_child(column)
		flow.add_child(card)
	if count == 0:
		modal_rows.add_child(UI.flow("还没有记录任何人。", UI.SIZE_BODY, UI.TEXT_DIM))
	else:
		modal_rows.add_child(flow)
	_end_panel("合上图鉴")

## 单独一人的图鉴页：肖像 + 逐段解锁的档案 + 关联线索。
##
## 解锁定档全部从**现有状态**推导，不新增旗标：
##   · 肖像清晰度 ← `person.*.identity`（身份确认 %）
##   · 档案条目   ← `person.*.truth`（真相掌握 %）
func _open_person(id: String) -> void:
	var person: Dictionary = game.bundle.people[id]
	var identity := int(game.person_flag(id, "identity"))
	var truth := int(game.person_flag(id, "truth"))
	_begin_panel("people", "人物图鉴", game.person_name(id))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var art := TextureRect.new()
	art.texture = _portrait_texture(id)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.custom_minimum_size = Vector2(288, 384)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(art)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_label_micro("当前状态"))
	column.add_child(UI.flow("%s　／　身份确认 %d%%　／　真相掌握 %d%%" % [
		PERSON_STATUS[game.person_flag(id, "status")], identity, truth,
	], UI.SIZE_SMALL, UI.TEXT_DIM))
	if identity == 100:
		column.add_child(UI.flow("真实姓名：%s" % str(person.real_name), UI.SIZE_SMALL, UI.ACCENT))
	column.add_child(UI.rule())
	column.add_child(_label_micro("档案"))
	var locked := 0
	for entry in game.bundle.codex.get(id, {}).get("entries", []):
		if int(entry.get("at", 0)) <= truth:
			column.add_child(UI.label(str(entry.get("title", "")), UI.SIZE_BODY, UI.TEXT_BRIGHT))
			column.add_child(UI.flow(str(entry.get("text", "")), UI.SIZE_SMALL + 1, Color("c6d5dd")))
		else:
			locked += 1
	if locked > 0:
		column.add_child(UI.flow("还有 %d 条尚未确认。" % locked, UI.SIZE_SMALL, UI.TEXT_MUTE))
	column.add_child(UI.rule())
	column.add_child(_label_micro("关联线索"))
	var related := 0
	for clue_id in game.bundle.clues:
		var clue: Dictionary = game.bundle.clues[clue_id]
		if not game.owns(clue_id): continue
		if not str(id) in clue.get("people", []): continue
		related += 1
		column.add_child(UI.flow("· " + str(clue.name), UI.SIZE_SMALL, Color("c6d5dd")))
	if related == 0:
		column.add_child(UI.flow("暂时没有。", UI.SIZE_SMALL, UI.TEXT_DIM))
	row.add_child(column)
	modal_rows.add_child(row)
	_end_panel("返回图鉴", _open_people)

## 肖像按「身份确认 %」分三档：低于 50 重模糊，50~99 轻模糊，到 100 才清楚。
func _portrait_texture(person_id: String) -> Texture2D:
	var identity := int(game.person_flag(person_id, "identity"))
	var suffix := ""
	if identity < 50:
		suffix = "_locked"
	elif identity < 100:
		suffix = "_blur"
	var path := "res://assets/portraits/black_page_portrait_%s%s.png" % [person_id, suffix]
	if not ResourceLoader.exists(path):
		return null
	return load(path)

func _open_clues() -> void:
	_begin_panel("clue", "线索", "你掌握的线索")
	var rows := _clue_rows()
	if rows.is_empty(): modal_rows.add_child(UI.flow("还没有收集到线索。可以从公交站监控开始。", UI.SIZE_BODY, UI.TEXT_DIM))
	for row in rows: modal_rows.add_child(row)
	_end_panel("合上线索")

## 黑页：**只做一件事——写下名字。**
## 身份、真相、状态那些都归「人物图鉴」，这里不重复显示。
func _open_notebook() -> void:
	# 翻开黑页是「世界安静下来」的时刻：音乐让位给雨声，回房间时再拿回来。
	if is_instance_valid(music): music.fade_out(1.6)
	# 翻开黑页在 transitions.json 里配的是 cut（不转场），这里统一走配置。
	await _transition_to(Scenes.NOTEBOOK)
	_begin_panel("notebook", "黑页", "纸页上没有规则，也没有劝告。")
	var listed := 0
	for id in game.bundle.people:
		if not bool(game.person_flag(id, "discovered")): continue
		listed += 1
		var writable: bool = game.can_write(id)
		var row := UI.action_row("写下「%s」" % game.person_name(id), "落笔" if writable else "身份不足", writable)
		if writable: row.pressed.connect(_ask_write.bind(str(id)))
		modal_rows.add_child(row)
	if listed == 0:
		modal_rows.add_child(UI.flow("纸上还没有可以写的名字。", UI.SIZE_BODY, UI.TEXT_DIM))
	if not game.pending.is_empty():
		modal_rows.add_child(UI.flow("纸上已有墨迹。后果还没有传来。", UI.SIZE_SMALL, UI.AMBER))
	if int(game.flag("day")) >= 2:
		var seal := UI.primary_button("封存黑页")
		seal.pressed.connect(func(): _confirm("封存黑页", "进入次日，接收最后的消息，然后结束首章。", func(): _message(game.finish_case("seal"))))
		modal_rows.add_child(seal)
		var keep := UI.ghost_button("保留黑页")
		keep.pressed.connect(func(): _confirm("保留黑页", "进入次日，接收最后的消息，然后结束首章。", func(): _message(game.finish_case("keep"))))
		modal_rows.add_child(keep)
	_end_panel("合上黑页", _enter_room)

func _label_micro(text: String) -> Label:
	return UI.label(text, UI.SIZE_MICRO, UI.ACCENT)

func _clue_chips(case_id: String) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	for clue in game.bundle.clues:
		if game.owns(clue) and str(game.bundle.clues[clue].case) == case_id:
			flow.add_child(UI.chip(str(game.bundle.clues[clue].name)))
	if flow.get_child_count() == 0:
		return UI.flow("还没有掌握任何事实。", UI.SIZE_SMALL, UI.TEXT_DIM)
	return flow

func _bullet(text: String) -> HBoxContainer:
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

func _clue_rows() -> Array:
	var out: Array = []
	for id in game.bundle.clues:
		if not game.owns(id): continue
		var clue: Dictionary = game.bundle.clues[id]
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 8)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 12)
		head.add_child(UI.heading(str(clue.name), UI.SIZE_TITLE))
		var chip := UI.chip(RELIABILITY[game.flag("clue." + id + ".reliability")])
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(chip)
		column.add_child(head)
		var description: String = clue.description
		if id == "testimony" and game.flag("action.fallback.done"): description = clue.fallback_description
		column.add_child(UI.flow(description, UI.SIZE_SMALL + 1, Color("c6d5dd")))
		column.add_child(UI.rule())
		out.append(column)
	return out

# ── 弹层 ─────────────────────────────────────────────────────────────────
func _modal_head(chip_text: String, title_text: String) -> VBoxContainer:
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.add_child(UI.accent_chip(chip_text))
	head.add_child(UI.heading(title_text, UI.SIZE_TITLE))
	return head

func _clear_modal() -> void:
	if modal_rows != null: _clear(modal_rows)

func _confirm(title_text: String, body: String, action: Callable) -> void:
	_open_panel = ""
	_sync_nav()
	_clear_modal()
	modal.show()
	modal_rows.add_child(_modal_head("确认操作", title_text))
	var body_label := UI.flow(body, UI.SIZE_BODY, UI.TEXT_DIM)
	body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal_rows.add_child(body_label)
	modal_rows.add_child(UI.primary_button("确认"))
	modal_rows.add_child(UI.ghost_button("返回"))
	modal_rows.get_child(2).pressed.connect(func(): _close_modal(); action.call())
	modal_rows.get_child(3).pressed.connect(_close_modal)
	_fit_modal()

func _close_modal() -> void:
	_open_panel = ""
	_sync_nav()
	if modal == null: return
	modal.hide()
	_clear_modal()

func _ask_write(id: String) -> void:
	_confirm("写下「%s」" % game.person_name(id), "一旦写下，无法撤销。\n后果不会立刻出现。", func():
		var error: String = game.write_name(id)
		_enter_room()
		_message(error))
	modal_rows.get_child(2).text = "落笔"
	modal_rows.get_child(3).text = "合上笔记"

## 让弹层贴合内容高度。
##
## 两个坑：
##  1. ScrollContainer 只按子节点最小高度摆放，VBox 里的 EXPAND 拿不到多余空间。
##  2. 自动换行的 Label 最小高度取决于当时的宽度；刚 add_child 完还没布局、宽度是 0，
##     量出来是天文数字。所以先撑起宽度、等一帧再量。
func _fit_modal(hug: bool = true) -> void:
	_modal_panel.custom_minimum_size = Vector2(888, 640)
	await get_tree().process_frame
	if not modal.visible or modal_rows.get_child_count() == 0:
		return
	var cap: float = size.y - 80.0
	var want: float = (modal_rows.get_combined_minimum_size().y + 56.0) if hug else 640.0
	_modal_panel.custom_minimum_size = Vector2(888, minf(want, cap))
	_modal_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if want > cap else ScrollContainer.SCROLL_MODE_DISABLED

# ── 工具 ─────────────────────────────────────────────────────────────────
func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _message(error: String, success: String = "") -> void:
	var text := error if not error.is_empty() else success
	if text.is_empty(): return
	notice.text = text
	notice.add_theme_color_override("font_color", UI.AMBER if not error.is_empty() else Color("d9e6ec"))
	# 提示直接落全文，不走打字机。
	_typer.set_line_now(text)
	if not error.is_empty(): push_warning(error)

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo: return
	if event.keycode == KEY_ESCAPE:
		if is_instance_valid(launch) or is_instance_valid(prologue): return
		if _menu_layer != null and _menu_layer.visible:
			_close_menu()
			get_viewport().set_input_as_handled()
			return
		if modal.visible:
			_close_modal()
			get_viewport().set_input_as_handled()
		return
	if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		if is_instance_valid(launch) or is_instance_valid(prologue) or modal.visible: return
		_advance_story()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_F6 and OS.is_debug_build():
		_message(game.reload_data(), "已重载调查数据。")
		# 序章文本和调查数据一起热重载：先把新数据递进去，再让它重画当前页。
		if is_instance_valid(prologue):
			prologue.source = game.bundle.get("prologue", [])
			prologue.reload_pages()
