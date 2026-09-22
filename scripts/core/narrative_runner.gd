extends RefCounted
## 剧情执行器：把「指令流剧情」（data/black_page/stories.json）从头播到尾。
##
## **职责**：按节点/指令推进剧情——说台词、写状态、给线索、认识人物、条件跳转。
## **不管**：台词怎么演（打字机 / 对话框是表现层的事）、数据从哪来（bundle）、
##           状态怎么存（那是 investigation / GameState 的事）。
##
## 这是全项目**唯一**的剧情机制：序章和第一章都写成指令流。
## 重点场面的演出（音效 / 音乐 / 震屏 / 闪白）不在这里——剧情用 `sequence`
## 指令把执行权交给演出导演（performance_director.gd），演完它再回来。
## 状态写入一律过 game 的口子（铁律 1 对谁都成立）。
signal finished
## **因果链断了**（设计文档 §26）：剧情走到一个节点，它的必要条件已经不再成立。
## 发它 = 这段剧情演不下去了，收场。它和 finished 是两种收场，不能合并：
## 等 finished 的人要「继续往下」，等 broken 的人要「拿出路」——
## 而且 broken **不补发 finished**，调用方靠 broken_reason 分辨。
signal broken(reason: String)

## 执行器认识的指令集合。**data_loader 的校验直接读这张表**——
## 加指令只改这里一处：不会出现「数据写了、引擎不认识」的静默丢弃，
## 也不会出现「引擎支持、数据校验先拦下来」。
const COMMANDS := ["say", "choice", "effect", "clue", "unlock", "unlockinfo", "if", "goto", "scene", "sequence", "minigame"]

## 节点认得的字段。**data_loader 的校验也读这张表**（和 COMMANDS 一个规矩）：
##   steps    —— 这个节点要做的动作（指令步，一步一条）
##   requires —— 进入这个节点必须成立的条件；不成立 = 断链
##   broken   —— 断链时给玩家看的正文（原因）。有 requires 就必须有它：
##              断链时说不出为什么，玩家只会觉得游戏坏了。
const NODE_FIELDS := ["steps", "requires", "broken"]

## 单次 play 最多执行多少步。指令里有 if / goto，数据写错成环就转不出去——
## 到顶告警收尾，不把游戏卡死在一次 play 里。
const STEP_LIMIT := 500

var story_id := ""
var node_id := ""
var index := 0
var error := ""
## 这段剧情断在哪儿（空串 = 没断过）。main 靠它分辨「演完了」和「走不下去」——
## 同步断链时 busy() 是 false，光看忙碌状态会把断链当成演完。
var broken_reason := ""

## investigation。**剧情写状态必须经它**——全项目唯一的写口。
var game: Node
## 表现回调：func(lines: Array, done: Callable)。执行器说「这几句要演，演完叫我」；
## 怎么演是表现层的事，执行器不碰 UI。
var display: Callable = Callable()
## 对话选项回调：func(prompt: String, labels: Array, selected: Callable)。
##
## 执行器只把“玩家能看见的题目与选项文字”交给表现层；条件、效果和跳转仍留在
## 核心层。UI 选完只回传可见选项的序号，不能自己改旗标或决定去哪个节点。
var present_choice: Callable = Callable()
## 场景表现回调：func(scene_id: String, done: Callable)。执行器只声明“看向哪里”，
## 贴图、转场和输入遮罩仍由表现层处理；转场完成后回调 done 才继续剧情。
var present_scene: Callable = Callable()
## 演出回调：func(sequence: Dictionary, done: Callable)。重点演出（演出导演）走它，
## 和 display 一个约定——演出时长归导演管，执行器只等 done。
var performer: Callable = Callable()
## 小游戏回调：func(minigame_id: String, done: Callable)。玩家操作归小游戏经理，
## 执行器只等 done——**结果不从这里回传**：它落进 GameState（note_minigame），
## 剧情用 if 查 `minigame.<id>.type` 自己判断（设计文档 §9.3：小游戏不决定剧情）。
var play_minigame: Callable = Callable()

var _running := false
## 当前是否停在 choice 上，以及经过 requires 过滤后的可见选项。
## 保存的是原始选项数据，但只存在执行器内部，不交给 UI。
var _awaiting_choice := false
var _choice_options: Array = []

## 开播一段剧情。失败返回原因（同时写进 error），成功返回空串。
## 数据没加载 / 未知剧情 / 上一段还没演完，都在这里拒绝。
## 旧账先清：上一次的 error 和断链原因都不许漏进这一段。
func play(id: String) -> String:
	error = ""
	broken_reason = ""
	_clear_choice()
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
	# 选择题只能由 choose() 放行。背景点击 / 残留的台词回调都不能替玩家选。
	if not _running or _awaiting_choice: return
	index += 1
	_run()

## 表现层回传一次玩家选择。返回空串表示成功；非法回传不会推进剧情，玩家仍可选择。
func choose(option_index: int) -> String:
	if not _running or not _awaiting_choice:
		return "当前没有等待选择的剧情"
	if option_index < 0 or option_index >= _choice_options.size():
		return "选择序号超出范围"
	var option: Dictionary = _choice_options[option_index]
	_clear_choice()
	var label := str(option.get("text", ""))
	game.log_narrative("选择：" + label)
	_write(game.apply_effects(option.get("effects", {})))
	var target := str(option.get("goto", ""))
	if not target.is_empty():
		_go_to(target)
	else:
		index += 1
	_run()
	return ""

## 这段剧情还在演吗（在等台词 ack，或在等一段演出）。
## 调用方「演完调我」的回调不区分同步演完 / 根本没开播，就靠它判断。
func busy() -> bool:
	return _running

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
		var node: Dictionary = nodes[node_id]
		# 节点入口的必要条件检查（设计文档 §26）。只在**进入**节点时查一次
		# （index == 0）：条件在节点内部变化是剧情自己的事，不半路把剧情掐掉。
		# 空 steps 的节点也要先过这一关——「只是来站一下」的节点正是闸门。
		if index == 0:
			var required: Array = node.get("requires", [])
			if not required.is_empty() and not game.matches(required):
				_break(str(node.get("broken", "")))
				return
		var steps: Array = node.steps
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
			"choice":
				_choice(step[command])
				return
			"scene":
				_scene(step[command])
				return
			"sequence":
				_sequence(step[command])
				return
			"minigame":
				_minigame(step[command])
				return
			"effect":
				_write(game.apply_effects(step[command]))
			"clue":
				_write(game.add_clue(str(step[command])))
			"unlock":
				# 认识一个人走口子（不是裸写旗标）：图鉴的小红点由口子统一点。
				_write(game.unlock_person(str(step[command])))
			"unlockinfo":
				var info: Dictionary = step[command]
				_write(game.unlock_person_info(str(info.get("person", "")), str(info.get("field", ""))))
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

## 显示一个数据驱动的对话选择。requires 不成立的选项不会交给表现层；加载器要求
## 至少有一个无条件兜底，所以正常数据不会走到“无项可选”。
func _choice(raw: Variant) -> void:
	var data: Dictionary = raw
	_choice_options.clear()
	for raw_option in data.get("options", []):
		var option: Dictionary = raw_option
		if game.matches(option.get("requires", [])):
			_choice_options.append(option)
	if _choice_options.is_empty():
		_fail("对话选择没有可用选项")
		return
	if not present_choice.is_valid():
		_fail("没有注入对话选择表现回调")
		return
	_awaiting_choice = true
	var prompt := str(data.get("prompt", ""))
	game.log_narrative(prompt)
	var labels: Array = []
	for option in _choice_options:
		labels.append(str((option as Dictionary).get("text", "")))
	present_choice.call(prompt, labels, Callable(self, "choose"))

## 声明式换景。没有表现回调时安静跳过，和 sequence / minigame 的降级规则一致。
func _scene(raw: Variant) -> void:
	var id := str(raw)
	if not present_scene.is_valid():
		push_warning("剧情执行器：没有注入场景回调，场景「%s」只跳过" % id)
		ack()
		return
	present_scene.call(id, ack)

## 来一段重点演出，**等它演完再继续**（设计文档 §7：演出的时长归演出系统管，
## 剧情在这里暂停）。和台词一样：没有演出回调就告警跳过，不能卡住剧情。
func _sequence(raw: Variant) -> void:
	var id := str(raw)
	var sequences: Dictionary = game.bundle.get("sequences", {})
	if not sequences.has(id):
		push_warning("剧情执行器：没有这段演出「%s」，已跳过" % id)
		ack()
		return
	if not performer.is_valid():
		push_warning("剧情执行器：没有注入演出回调，演出「%s」只跳过" % id)
		ack()
		return
	performer.call(sequences[id], ack)

## 来一局小游戏，**等玩家打完再继续**（设计文档 §9.2：剧情暂停 → 玩家操作 →
## 结果进状态 → 剧情继续）。和演出一样：没接回调 / 未知小游戏就告警跳过，不卡剧情。
func _minigame(raw: Variant) -> void:
	var id := str(raw)
	if not game.bundle.get("minigames", {}).has(id):
		push_warning("剧情执行器：没有这个小游戏「%s」，已跳过" % id)
		ack()
		return
	if not play_minigame.is_valid():
		push_warning("剧情执行器：没有注入小游戏回调，小游戏「%s」只跳过" % id)
		ack()
		return
	play_minigame.call(id, ack)

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
	_clear_choice()
	_running = false
	finished.emit()

## 断链收场：记下原因、发 broken。**不发 finished**——
## 「演完了」和「走不下去了」是两种收场，调用方要分开对待
## （前者继续往下走，后者要拿出路），合并成一个信号就等于把这两种事混作一谈。
## 原因取自剧情数据里节点自己的 `broken` 文案：为什么断，只有这一段剧情说得清。
func _break(reason: String) -> void:
	_clear_choice()
	_running = false
	broken_reason = reason
	push_warning("剧情执行器：因果链已断裂——%s" % reason)
	broken.emit(reason)

## 失败收场：记下 error；**已经开播的剧情**还要发 finished——
## 对调用方（main._play_story / 演出链）来说「演完了」是**收场**，不分正常还是出错，
## 等它的人不能永远卡着。还没开播就被拒绝（play() 的早退）不算收场，不发。
func _fail(message: String) -> String:
	error = message
	var was_running := _running
	_clear_choice()
	_running = false
	push_warning("剧情执行器：" + message)
	if was_running: finished.emit()
	return message

func _clear_choice() -> void:
	_awaiting_choice = false
	_choice_options.clear()
