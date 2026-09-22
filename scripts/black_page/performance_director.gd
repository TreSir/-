extends Node
## 演出导演：把 sequences.json 的**时间轴**演出来——什么时刻、哪些事同时发生。
##
## 与 core/narrative_runner.gd 的分工（对应设计文档 §7）：
##   执行器决定**发生什么**（哪段剧情、什么时候来一段演出），
##   导演决定**怎么演**（音效 / 音乐 / 幕布 / 震屏 / 闪白）。
## 导演不碰状态、不认识剧情，只认识一串「at + 动作」。
##
## **done 保证被调用且只调一次**：正常演完调；被新的 play 打断、或被 stop()
## 也调（打断也算演完）。等它的人（执行器要 ack 才能继续）不会永远卡住。

## 时间轴认识的**动作**集合。**data_loader 的校验直接读这张表**——
## 和 narrative_runner.COMMANDS 一个规矩：加动作只改这里一处。
const UI = preload("res://scripts/black_page/ui_style.gd")
const INK_BLEED = preload("res://assets/shaders/ink_bleed.gdshader")

const ACTIONS := ["sfx", "bgm", "fade_in", "fade_out", "shake", "flash", "wait", "title_card"]

## 震屏幅度（像素）。抖的是整棵界面，幅度大了像画面坏了。
const SHAKE_AMPLITUDE := 14.0
const FLASH_PEAK := 0.85

var sfx: Node
var music: Node
## 震屏对象：整棵界面（整个屏幕都在抖）。
var stage: Control
## 导演自带的遮罩：幕布（黑）压底、闪光（白）在上。
## 不和转场抢同一块遮罩——两者可能同时要用（演出结束时剧情还要淡出）。
var curtain: ColorRect
var flash: ColorRect
var _title_layer: Control

var _running := false
## 时间轴里还没演完的步骤数；归零 = 整段演完。
var _pending := 0
var _done: Callable = Callable()
## 纪元号：stop() 一加，上一场演出所有还没到点的延迟回调全部作废。
var _epoch := 0
var _tweens: Array = []
var _stage_base := Vector2.ZERO

## 建好自带的遮罩并指定舞台。遮罩后加的在上面，所以要在搭完界面之后再调。
func attach(stage_node: Control) -> void:
	stage = stage_node
	curtain = ColorRect.new()
	curtain.name = "PerformanceCurtain"
	curtain.color = Color(0, 0, 0, 0)
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(curtain)
	flash = ColorRect.new()
	flash.name = "PerformanceFlash"
	flash.color = Color(1, 1, 1, 0)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(flash)

## 演一段。sequence 是 sequences.json 里的一条（loader 已经校验过形状）。
## 没 attach 舞台就跳过（done 照调，等它的人不卡住）。
func play(sequence: Dictionary, done: Callable) -> bool:
	if stage == null:
		push_warning("演出导演：还没有 attach 舞台，演出「%s」跳过" % str(sequence.get("name", "")))
		if done.is_valid(): done.call()
		return false
	stop()
	_running = true
	_done = done
	_stage_base = stage.position
	_pending = (sequence.get("steps", []) as Array).size()
	if _pending == 0:
		_finish()
		return true
	for step in sequence.steps:
		_delay(float((step as Dictionary).get("at", 0.0)), _perform.bind(step as Dictionary))
	return true

## 中断当前演出（没在演就什么都不做）：延迟全部作废、幕布/闪光清干净、
## 舞台回原位，并把 done 调掉——等这段演出的人得往下走。
func stop() -> void:
	if not _running:
		_clear_title_layer()
		return
	_epoch += 1
	_running = false
	_pending = 0
	_clear_tweens()
	if stage != null: stage.position = _stage_base
	if curtain != null: curtain.color.a = 0.0
	if flash != null: flash.color.a = 0.0
	_clear_title_layer()
	_call_done()

func busy() -> bool:
	return _running

## 延迟一会儿再回调；纪元号对不上（演出已被 stop / 被新演出顶掉）就丢掉。
func _delay(seconds: float, callback: Callable) -> void:
	var era := _epoch
	if seconds <= 0.0:
		callback.call()
		return
	get_tree().create_timer(seconds).timeout.connect(func():
		if era == _epoch: callback.call())

func _perform(step: Dictionary) -> void:
	var action := ""
	var argument: Variant = null
	for key in step:
		if str(key) != "at":
			action = str(key)
			argument = step[key]
	var duration := _act(action, argument)
	if duration > 0.0:
		_delay(duration, _step_done)
	else:
		_step_done()

## 做一个动作，返回它的时长（秒）。瞬时的动作返回 0，时间轴不用为它留空。
func _act(action: String, argument: Variant) -> float:
	match action:
		"sfx":
			if sfx == null:
				push_warning("演出导演：没有音效播放器，sfx「%s」跳过" % str(argument))
				return 0.0
			sfx.play(str(argument))
			return 0.0
		"bgm":
			if music == null:
				push_warning("演出导演：没有音乐播放器，bgm「%s」跳过" % str(argument))
				return 0.0
			var track := str(argument)
			if track.is_empty(): music.fade_out()
			else: music.play_track(track)
			return 0.0
		"fade_in": return _fade_to(0.0, maxf(float(argument), 0.01))
		"fade_out": return _fade_to(1.0, maxf(float(argument), 0.01))
		"flash": return _flash(float(argument))
		"shake": return _shake(float(argument))
		"wait": return float(argument)
		"title_card": return _title_card(argument as Dictionary)
		_:
			push_warning("演出导演：不认识的动作「%s」已跳过" % action)
			return 0.0

func _fade_to(target: float, seconds: float) -> float:
	var tween := create_tween()
	_tweens.append(tween)
	tween.tween_property(curtain, "color:a", target, seconds)
	return seconds

func _flash(seconds: float) -> float:
	var tween := create_tween()
	_tweens.append(tween)
	flash.color.a = 0.0
	tween.tween_property(flash, "color:a", FLASH_PEAK, seconds * 0.3)
	tween.tween_property(flash, "color:a", 0.0, seconds * 0.7)
	return seconds

func _shake(seconds: float) -> float:
	var base := stage.position
	var tween := create_tween()
	_tweens.append(tween)
	tween.tween_method(func(progress: float):
		var decay := 1.0 - progress
		stage.position = base + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * SHAKE_AMPLITUDE * decay,
		0.0, 1.0, seconds)
	tween.tween_callback(func(): stage.position = base)
	return seconds

## 全屏章节标题。标题文字沿纸纤维渗出，再整体淡去；剧情数据只给文字与节奏。
## 这不是启动页的特例：后续章节、结局和关键日期都能复用同一动作。
func _title_card(config: Dictionary) -> float:
	_clear_title_layer()
	var reveal := maxf(float(config.get("reveal", 1.2)), 0.01)
	var hold := maxf(float(config.get("hold", 1.0)), 0.01)
	var fade := maxf(float(config.get("fade", 0.5)), 0.01)

	_title_layer = Control.new()
	_title_layer.name = "PerformanceTitleCard"
	_title_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_title_layer.focus_mode = Control.FOCUS_ALL
	_title_layer.gui_input.connect(_title_card_input)
	stage.add_child(_title_layer)
	_title_layer.grab_focus.call_deferred()

	var backdrop := ColorRect.new()
	# 留一点原场景的轮廓，避免低亮度屏幕上看成程序卡死后的纯黑帧。
	backdrop.color = Color(0.004, 0.007, 0.011, 0.965)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_layer.add_child(backdrop)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.offset_left = -340.0
	column.offset_right = 340.0
	column.offset_top = -82.0
	column.offset_bottom = 82.0
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	_title_layer.add_child(column)

	var title := UI.heading(str(config.get("text", "")), UI.SIZE_DISPLAY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size.y = 92.0
	var ink := ShaderMaterial.new()
	ink.shader = INK_BLEED
	ink.set_shader_parameter("progress", 0.0)
	ink.set_shader_parameter("seed", randf_range(0.0, 100.0))
	title.material = ink
	column.add_child(title)

	var subtitle_text := str(config.get("subtitle", ""))
	if not subtitle_text.is_empty():
		var subtitle := UI.label(subtitle_text, UI.SIZE_SMALL, UI.TEXT_DIM)
		subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		subtitle.modulate.a = 0.0
		column.add_child(subtitle)
		var subtitle_tween := create_tween()
		_tweens.append(subtitle_tween)
		subtitle_tween.tween_interval(reveal * 0.68)
		subtitle_tween.tween_property(subtitle, "modulate:a", 1.0, reveal * 0.32)

	var skip_hint := UI.label("点击或按确认键跳过", UI.SIZE_MICRO, UI.TEXT_MUTE)
	skip_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	skip_hint.offset_left = -100.0
	skip_hint.offset_right = 100.0
	skip_hint.offset_top = -52.0
	skip_hint.offset_bottom = -24.0
	skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skip_hint.modulate.a = 0.0
	_title_layer.add_child(skip_hint)
	var hint_tween := create_tween()
	_tweens.append(hint_tween)
	hint_tween.tween_interval(0.35)
	hint_tween.tween_property(skip_hint, "modulate:a", 0.62, 0.25)

	var tween := create_tween()
	_tweens.append(tween)
	tween.tween_method(func(value: float): ink.set_shader_parameter("progress", value), 0.0, 1.0, reveal)
	tween.tween_interval(hold)
	tween.tween_property(_title_layer, "modulate:a", 0.0, fade)
	tween.tween_callback(_clear_title_layer)
	return reveal + hold + fade

## 标题卡是可跳过的演出，不是剧情闸门。吃掉本次输入再 stop，避免同一下点击
## 穿透到下一句，把清晨第一句也一并翻过去。
func _title_card_input(event: InputEvent) -> void:
	var confirm: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventKey:
		confirm = event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]
	if not confirm: return
	if is_instance_valid(_title_layer): _title_layer.accept_event()
	stop()

func _clear_title_layer() -> void:
	if is_instance_valid(_title_layer):
		_title_layer.queue_free()
	_title_layer = null

func _step_done() -> void:
	if not _running: return
	_pending -= 1
	if _pending <= 0: _finish()

func _finish() -> void:
	_running = false
	_call_done()

func _call_done() -> void:
	var done := _done
	_done = Callable()
	if done.is_valid(): done.call()

func _clear_tweens() -> void:
	for tween in _tweens:
		if tween != null and tween.is_valid(): tween.kill()
	_tweens.clear()
