extends RefCounted
## 剧情执行器：把「指令流剧情」（data/black_page/stories.json）从头播到尾。
##
## **职责**：按节点/指令推进剧情——说台词、写状态、给线索、认识人物、条件跳转。
## **不管**：台词怎么演（打字机 / 对话框是表现层的事）、数据从哪来（bundle）、
##           状态怎么存（那是 investigation / GameState 的事）。
##
## 与 core/scripted.gd 的分工，两条不同的叙事路子：
##   scripted = **页数组**驱动的一次性演出（序章：背景 / 热区 / 选项 / 演出卡片），
##              作者写的是「一页一页的画面」。
##   runner   = **指令流**驱动的剧情段落（第一章起：说几句 → 写个状态 → 跳一段），
##              作者写的是「先做什么、再做什么」。
##   两者都只管播——状态写入一律过 game 的口子（铁律 1 对谁都成立）。
signal finished

## 执行器认识的指令集合。**data_loader 的校验直接读这张表**——
## 加指令只改这里一处：不会出现「数据写了、引擎不认识」的静默丢弃，
## 也不会出现「引擎支持、数据校验先拦下来」。
const COMMANDS := ["say", "effect", "clue", "unlock", "if", "goto"]

## 单次 play 最多执行多少步。指令里有 if / goto，数据写错成环就转不出去——
## 到顶告警收尾，不把游戏卡死在一次 play 里。
const STEP_LIMIT := 500

var story_id := ""
var node_id := ""
var index := 0
var error := ""

## investigation。**剧情写状态必须经它**——全项目唯一的写口。
var game: Node
## 表现回调：func(lines: Array, done: Callable)。执行器说「这几句要演，演完叫我」；
## 怎么演是表现层的事，执行器不碰 UI。
var display: Callable = Callable()

var _running := false

## 开播一段剧情。失败返回原因（同时写进 error），成功返回空串。
## 数据没加载 / 未知剧情 / 上一段还没演完，都在这里拒绝。
func play(id: String) -> String:
	error = ""
	if game == null or game.bundle.is_empty(): return _fail("游戏数据还没加载")
	if _running: return _fail("上一段剧情还没演完")
	var stories: Dictionary = game.bundle.get("stories", {})
	if not stories.has(id): return _fail("未知剧情：" + id)
	story_id = id
	node_id = str(stories[id].start)
	index = 0
	_running = true
	_run()
	return error

## 表现层把一批台词演完后调这个，执行器接着往下走。
func ack() -> void:
	if not _running: return
	index += 1
	_run()

## 主循环：能同步跑的就一口气跑完（effect / if / goto 一步接一步），
## 碰到 say 就停在原地——台词交给表现层，等它演完 ack() 再继续。
func _run() -> void:
	var budget := STEP_LIMIT
	while _running:
		if budget <= 0:
			_fail("剧情步数超过上限（疑似 if / goto 绕圈）")
			return
		budget -= 1
		var nodes: Dictionary = (game.bundle.get("stories", {}).get(story_id, {}) as Dictionary).get("nodes", {})
		if not nodes.has(node_id):
			# 编译期校验过节点存在；能到这儿是 F6 热重载把数据换了。
			_fail("剧情「%s」里没有节点「%s」" % [story_id, node_id])
			return
		var steps: Array = nodes[node_id].steps
		if index >= steps.size():
			# 节点跑完 = 这段剧情结束，不需要显式的 end 指令。
			_finish()
			return
		var step: Dictionary = steps[index]
		var command := str(step.keys()[0])
		match command:
			"say":
				_say(step[command])
				return
			"effect":
				_write(game.apply_effects(step[command]))
			"clue":
				_write(game.add_clue(str(step[command])))
			"unlock":
				_write(game.apply_state({"person." + str(step[command]) + ".discovered": true}))
			"goto":
				_go_to(str(step[command]))
				continue
			"if":
				var target := _branch_of(step[command])
				if not target.is_empty():
					_go_to(target)
					continue
			_:
				push_warning("剧情执行器：不认识的指令「%s」已跳过" % command)
		index += 1

## 说一批台词。**先记日志、再交给表现层**——
## 玩家中途退出读档时，这段文字已经留在日志里（配合「effect 写在 say 之前」，
## 读档回来不会重播整段）。
func _say(raw: Variant) -> void:
	var lines: Array = []
	if raw is String: lines.append(str(raw))
	else: lines.assign(raw)
	for line in lines:
		game.log_narrative(str(line))
	if not display.is_valid():
		# 没人接表现不等于这段剧情没发生：日志记过了，直接往下走。
		push_warning("剧情执行器：没有注入表现回调，台词只进日志不演出")
		ack()
		return
	display.call(lines, ack)

## 条件跳转该去哪个节点：条件成立走 then；不成立走 else；没写 else 返回空串 = 原地继续。
func _branch_of(condition: Dictionary) -> String:
	if game.matches(condition.get("requires", [])):
		return str(condition.get("then", ""))
	return str(condition.get("else", ""))

func _go_to(target: String) -> void:
	node_id = target
	index = 0

## 状态的写入失败不中断剧情（和「缺素材安静跳过」一个规矩），但必须出声——
## 静默吞掉的话，剧情会「看起来播完了、其实什么都没写」。
func _write(message: String) -> void:
	if not message.is_empty(): push_warning("剧情执行器：写状态失败——" + message)

func _finish() -> void:
	_running = false
	finished.emit()

func _fail(message: String) -> String:
	error = message
	_running = false
	push_warning("剧情执行器：" + message)
	return message
