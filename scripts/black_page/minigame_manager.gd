extends Node
## 小游戏经理：装一个小游戏进弹层、等玩家打完、把标准结果落进状态、再把场景卸掉。
##
## 边界（对应设计文档 §9）：
##   剧情 / 调查决定**什么时候开一局**，
##   小游戏场景决定**怎么玩**，
##   经理管**生命周期与结果**——结果进 GameState，给什么由剧情 / 结算自己判。
## 所以这里不认识任何具体小游戏，也不认识「调查」「线索」。
##
## **done 保证被调用且只调一次**：打完调；被新一局顶掉、被弹层清出树
## （返回 / ESC / 回到房间）也调——等它的人（执行器 ack / 结算页）不会卡住。
const MiniGameResult = preload("res://scripts/core/minigame_result.gd")

## investigation。读 bundle 与 flags 快照、写结果（note_minigame）都走它——
## 铁律 1 对谁都成立：经理不碰 GameState。
var game: Node
## 装小游戏的容器（弹层里的列）。谁摆头部和按钮是调用方的事，经理只管往里放场景。
var container: Control

var _instance: Node
var _minigame_id := ""
var _done: Callable = Callable()
var _running := false

## 开一局。开不起来（没接线 / 未知 id / 场景没了）告警并按 cancelled 放行，
## 返回是否真的开起来了。
func run(minigame_id: String, done: Callable) -> bool:
	# 先收掉上一局：它等的人拿的是上一局的 done，不能被这一局顶掉。
	cancel()
	_done = done
	if game == null or container == null:
		push_warning("小游戏经理：还没有接线（game / container），小游戏「%s」跳过" % minigame_id)
		_call_done()
		return false
	var minigames: Dictionary = game.bundle.get("minigames", {})
	if not minigames.has(minigame_id):
		push_warning("小游戏经理：没有这个小游戏「%s」，跳过" % minigame_id)
		_call_done()
		return false
	var minigame: Dictionary = minigames[minigame_id]
	var packed: Resource = load(str(minigame.scene))
	if packed == null:
		push_warning("小游戏经理：场景「%s」加载不出来，跳过" % str(minigame.scene))
		_call_done()
		return false
	_minigame_id = minigame_id
	_running = true
	var instance: Node = (packed as PackedScene).instantiate()
	_instance = instance
	container.add_child(instance)
	if instance is Control:
		instance.custom_minimum_size.y = maxf(instance.custom_minimum_size.y, 460.0)
	# 被清出树 = 玩家退出了这局（返回 / ESC / 回到房间都走弹层清理）。
	# 延迟一拍再收：树正在拆的时候不要在里头发信号、动界面。
	# 认实例，不是认标志位——这一局的实例离开树才收这一局；
	# 光看 `_running` 的话，会误伤清空后新开的那一局。
	instance.tree_exiting.connect(func(): _cancel_if_current.call_deferred(instance))
	instance.completed.connect(_on_completed)
	instance.begin(minigame.config, game.flags_snapshot())
	return true

## 退出当前这一局（没在跑就什么都不做）。结果按 cancelled 落库——
## 「玩家退出了」是真事，剧情和结算都该看得到；等它的人照常被放行。
func cancel() -> void:
	if not _running: return
	_finish(MiniGameResult.normalize({"type": "cancelled"}))

func busy() -> bool:
	return _running

## 这一局的实例离开树了才收这一局。用 is_same 认对象：
## 到这一刻实例可能已经被释放（收场和拆树在同一帧），按引用比会炸。
func _cancel_if_current(who) -> void:
	if not _running or not is_same(_instance, who): return
	_finish(MiniGameResult.normalize({"type": "cancelled"}))

func _on_completed(raw: Variant) -> void:
	if not _running: return
	_finish(MiniGameResult.normalize(raw))

func _finish(result: Dictionary) -> void:
	_running = false
	var error: String = game.note_minigame(_minigame_id, result)
	if not error.is_empty(): push_warning("小游戏经理：结果没落进状态——" + error)
	if is_instance_valid(_instance):
		_instance.queue_free()
	_instance = null
	_call_done()

func _call_done() -> void:
	var done := _done
	_done = Callable()
	if done.is_valid(): done.call()
