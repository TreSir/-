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
const ACTIONS := ["sfx", "bgm", "fade_in", "fade_out", "shake", "flash", "wait"]

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
	if not _running: return
	_epoch += 1
	_running = false
	_pending = 0
	_clear_tweens()
	if stage != null: stage.position = _stage_base
	if curtain != null: curtain.color.a = 0.0
	if flash != null: flash.color.a = 0.0
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
