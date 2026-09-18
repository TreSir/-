extends Node
const Investigation = preload("res://scripts/black_page/investigation.gd")
const Loader = preload("res://scripts/black_page/data_loader.gd")
const Runner = preload("res://scripts/core/narrative_runner.gd")
const MiniGameResult = preload("res://scripts/core/minigame_result.gd")
## 图鉴读模型与案件状态机：断言直接量它们（界面走的也是这两份）。
const CodexManager = preload("res://scripts/core/codex_manager.gd")
const CaseManager = preload("res://scripts/core/case_manager.gd")
const Rules = preload("res://scripts/core/rules.gd")
const Store = preload("res://scripts/core/save_store.gd")
## 断链的收场文案：断链面板上该出现哪几个字，断言读的就是这一份。
const FailureManager = preload("res://scripts/core/failure_manager.gd")
const UI = preload("res://scripts/black_page/ui_style.gd")
var checks := 0
var failures := 0
## 检查数门槛。**报 PASS 不等于跑完**——解析错误会让后面的 check 静默跳过，
## 而 PASS/FAIL 只看 failures，于是出现「PASS (53 checks)」这种假通过。
## 加断言或删断言后，这个数要跟着改。贴着总数减一：最后一条 check 就是门槛自己，
## 它跑到的时候还没把自己数进去。
const UI_CHECK_FLOOR := 248
var game = Investigation.new()

func _ready() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("BLACK_PAGE CHECK FAILED: " + message)

## 在指定坐标模拟一次真实的左键点击（按下 + 抬起）。
##
## 必须走 viewport.push_input 而不是直接 emit pressed：只有真实事件才会经过
## Godot 的 GUI 命中测试，才能发现「某个全屏 Control 挡在上面把点击吃掉」这类问题。
##
## in_local_coords 必须传 true：默认 false 时事件坐标按【窗口】坐标解释，
## 会被 stretch 变换（1152x720 → 1280x800）再换算一次，导致命中位置整体偏移。
## 造一个「左键按下」事件，用来直接喂给 gui_input，测热区能不能点。
func _left_click() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event

func _click_at(ui: Node, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.global_position = position
	event.pressed = true
	ui.get_viewport().push_input(event, true)
	var release := event.duplicate() as InputEventMouseButton
	release.pressed = false
	ui.get_viewport().push_input(release, true)

func act(id: String) -> void:
	check(game.begin_action(id).is_empty(), "begin " + id)
	# 小游戏类行动：结算闸门读的是状态里的小游戏结果（打完时由小游戏经理写进去）。
	# 这里替经理记一笔，模拟「先打完、再提交」的真实顺序。
	var action: Dictionary = game.bundle.actions[id]
	if str(action.kind) == "minigame":
		check(game.note_minigame(str(action.minigame), {"type": "success", "score": 100}).is_empty(),
			"minigame result " + id)
	check(game.complete_action(game.ticket).is_empty(), "complete " + id)

## 造一个 ESC 按键事件，直接喂给 _unhandled_key_input。
## 键盘事件不走 GUI 命中测试，不需要 push_input——直接调就是玩家的真实路径。
func _esc() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	return event

## 按文字找弹层里的按钮。**不按索引**：面板里摆了哪些东西是内容的一部分，
## 索引会随内容漂，文字不会——测试想点的是「那个写着回溯的按钮」。
## 两种摆法都认：文字在 Button 自己身上（primary / ghost 按钮），
## 或在一个子 Label 里（action_row 的行标题与灰掉的提示词）。
func _button(ui: Node, text: String) -> Button:
	for child in ui.modal_rows.get_children():
		if child is Button and (child.text == text or _has_text(child, text)): return child
	return null

## 节点子树里有没有这句话（子串匹配）。用来断言「灰掉的那一行写了原因」
## 这类拼装控件——action_row 的文字在子控件里，不是 Button.text。
func _has_text(node: Node, text: String) -> bool:
	if node is Label and node.text.contains(text): return true
	for child in node.get_children():
		if _has_text(child, text): return true
	return false

## 存档写盘读盘就是过一趟 JSON：数字回来时是 float，而 GDScript 的字典相等
## **按类型**比（`{"day": 2} != {"day": 2.0}`）。比较「从磁盘回来的快照」时
## 两边都过这一趟，比的是内容——哪一项没退干净照样瞒不过去。
func _json_round_trip(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data))

func identity_route() -> void:
	act("camera")
	act("badge")
	check(game.person_flag("zhou", "identity") == 70, "initial identity")
	act("archive")
	check(game.person_flag("zhou", "identity") == 52 and game.flag("clue.badge.reliability") == "forged", "contradictory evidence lowers identity")
	act("photo")
	check(game.person_name("zhou") == "周文远" and game.person_flag("zhou", "truth") == 15, "identity independent of truth")
	# 没有每日行动预算（舍弃行动点，重构文档 §18）：同一天想查几次查几次，
	# 时间也不会自己走——日子由玩家在顶栏自己推。
	check(game.flag("day") == 1, "investigations never advance the day")

func _run() -> void:
	add_child(game)
	# 槽位隔离：冒烟测试**绝不碰真实存档**——进度槽和落笔检查点槽都换成 smoke 槽，
	# 否则跑一次测试就会把玩家的自动检查点覆盖掉。
	game.checkpoint_slot = "black_page_smoke_checkpoint"
	var error: String = game.open()
	check(error.is_empty(), "content compiles: " + error)
	if not error.is_empty():
		get_tree().quit(1)
		return
	check(game.bundle.clues.size() == 5 and game.bundle.people.size() == 3, "MVP content")
	check(not game.available("photo"), "evidence gates")
	check(not game.begin_action("photo").is_empty(), "locked action rejected")
	identity_route()
	var identity_checkpoint: Dictionary = game.snapshot()
	check(game.reload_data().is_empty() and game.snapshot() == identity_checkpoint, "hot reload preserves rewards and state")
	check(game.write_name("zhou").is_empty(), "confirmed write")
	check(game.person_flag("zhou", "status") != "dead", "death is delayed")
	check(not game.write_name("zhou").is_empty(), "duplicate pending write rejected")
	var written: Dictionary = game.snapshot()
	var store = Store.new()
	check(store.write("black_page_smoke_roundtrip", written).is_empty(), "save write")
	check(store.write("black_page_smoke_roundtrip", written).is_empty(), "save overwrite")
	# ── 死亡笔记：守卫 / 检查点 / 回溯（设计文档 §28）───────────────────────
	# 能不能写、为什么不能写，只有一份判断——黑页面板上显示的就是它。
	check(game.write_error("zhou").contains("黑页上") and game.write_error("linmo").contains("见过")
			and game.write_error("nobody").contains("未知人物"),
		"the write guard explains itself through the rule the notebook shows")
	# 落笔之前先自动存一份检查点：「写错了也不会毁档」靠的就是它。
	check(game.checkpoint_ready(), "a confirmed write lays down the rollback checkpoint")
	check(game.end_day().is_empty() and game.person_flag("zhou", "status") == "dead" and int(game.flag("day")) == 2,
		"the night realizes the written name")
	check(game.write_error("zhou").contains("已经死了"), "the dead cannot be written again")
	# 回溯：世界必须回到**那一笔还没有写下**的时候——死人、天数、纸上的墨迹全部退回去。
	# 快照全等是这里最硬的断言：哪一项没退干净都瞒不过去（回溯读的是磁盘上的检查点，
	# 两边都过一趟 JSON 才是同一把尺子）。
	check(game.roll_back().is_empty() and _json_round_trip(game.snapshot()) == _json_round_trip(identity_checkpoint),
		"rolling back returns the world to exactly where it was before the write")
	check(game.person_flag("zhou", "status") != "dead" and int(game.flag("day")) == 1 and game.pending.is_empty()
			and game.available("testimony") and not game.available("fallback"),
		"rollback undoes the death, the day and the ink; the routes come back")
	game.new_game()
	# 新开一局要清掉上一局的检查点：不然「回溯」会把新世界退到别人的剧情里。
	check(not game.checkpoint_ready(), "a new game leaves no rollback checkpoint behind")
	check(game.restore(store.read("black_page_smoke_roundtrip").get("data", {})).is_empty(), "JSON save restores pending write")
	# 「有没有可续的存档」= **能不能真的续**，不是「文件读不读得出来」：
	# 内容过不了校验的存档，开始页不该摆出「继续游戏」。
	check(game.has_save("black_page_smoke_roundtrip"), "has_save accepts a restorable save")
	store.write("black_page_smoke_roundtrip", {"schema": 999, "content": "black_page_mvp2",
		"state": {"flags": {}, "inventory": {}}, "pending": [], "journal": []})
	check(not game.has_save("black_page_smoke_roundtrip"), "has_save rejects a save that fails validation")
	check(game.end_day().is_empty() and game.person_flag("zhou", "status") == "dead", "next-day death")
	check(game.flag("writes") == 1 and game.flag("linmo_suspicion") > 0 and game.flag("testimony_lost"), "death cascades")
	check(game.available("fallback") and not game.available("testimony"), "soft failure opens fallback")
	act("fallback")
	# 线索变体：打捞来的语音和赴约听来的证词正文不同——由线索自己在数据里声明变体，
	# 界面不问来路。这条守的是「界面里没有 testimony 特判」。
	check(game.clue_description("testimony") == game.bundle.clues.testimony.variants[0].description
			and game.clue_description("testimony") != game.bundle.clues.testimony.description,
			"fallback route swaps the clue body via the declared variant")
	check(game.person_flag("zhou", "truth") == 40, "fallback does not reveal full truth")
	var dead_checkpoint: Dictionary = game.snapshot()
	check(game.finish_case("seal").is_empty() and game.flag("ending") == "wrong", "wrong justice ending")
	game.restore(dead_checkpoint)
	check(game.finish_case("keep").is_empty() and game.flag("ending") == "judge", "judge ending")
	game.restore(identity_checkpoint)
	act("testimony")
	check(game.clue_description("testimony") == game.bundle.clues.testimony.description,
			"uninterrupted route keeps the base clue body")
	# 首章落幕要「至少进入第 2 天」：日子由玩家自己推，restore 把日子拉回了第 1 天，
	# 所以先验闸门拦得住，再自己推一天。
	check(not game.finish_case("seal").is_empty(), "the chapter cannot end before the first night")
	check(game.end_day().is_empty() and game.flag("day") == 2, "the day only turns when the player ends it")
	var full_checkpoint: Dictionary = game.snapshot()
	check(game.finish_case("seal").is_empty() and game.flag("ending") == "closed", "abstain and next-day ending")
	game.restore(full_checkpoint)
	act("notebook")
	check(game.finish_case("seal").is_empty() and game.flag("ending") == "secret", "priority hidden ending")
	game.new_game()
	# 陈东要**查过公交站监控才认识**（discovered 默认 false），所以先走 camera
	act("camera")
	check(game.write_name("zhou").is_empty(), "unconfirmed writing allowed")
	game.end_day()
	check(game.flag("wrong_writes") == 1 and game.person_flag("zhou", "status") != "dead", "wrong identity fails softly")
	game.new_game()
	# 林墨同理：向林墨交代过来源才认识（cooperate 会写 discovered）
	act("cooperate")
	game.write_name("linmo")
	game.end_day()
	act("camera")
	act("badge")
	check(not game.available("archive") and game.available("archive_public"), "dead contact replaced by public records route")
	act("archive_public")
	check(game.owns("archive") and game.available("photo"), "public records keep identity route open")
	game.restore(identity_checkpoint)
	# 时限事件在「进入第 4 天」的夜间结算里兑现（events.json 的 deadline）：
	# 日子得由玩家一天天推过去——从第 1 天推三次。
	game.end_day()
	game.end_day()
	game.end_day()
	check(not game.available("testimony") and game.available("fallback"), "missed deadline preserves route")
	var before: Dictionary = game.snapshot()
	var invalid: Dictionary = before.duplicate(true)
	invalid.state.flags.day = -1
	check(not game.restore(invalid).is_empty() and game.snapshot() == before, "corrupt state restore atomic")
	invalid = before.duplicate(true)
	invalid.pending = [{"person": "typo"}]
	check(not game.restore(invalid).is_empty() and game.snapshot() == before, "corrupt pending record rejected")
	invalid = before.duplicate(true)
	invalid.schema = 999
	check(not game.restore(invalid).is_empty(), "future schema rejected")
	game.new_game()
	game.begin_action("camera")
	# 结果先记好：这样这条断言证明的就是**过期凭据本身**拦住了提交，
	# 而不是「没通过小游戏」被顺带拦下。
	game.note_minigame("monitor_rebuild", {"type": "success", "score": 100})
	var token: int = game.ticket
	game.cancel_action()
	check(not game.complete_action(token).is_empty() and not game.owns("camera"), "stale callback cannot grant rewards")

	# ── 小游戏结果的标准形状（§10）──────────────────────────────────────
	# 词表和形状只有 core/minigame_result.gd 一份：小游戏、数据校验、
	# 结算闸门都读它——三处各写一份的话，改一个词就会有一处静默不认。
	var normalized: Dictionary = MiniGameResult.normalize({"success": true})
	check(normalized.type == "success" and normalized.score == 100 and normalized.data is Dictionary,
		"legacy {success} results normalize into the standard shape")
	normalized = MiniGameResult.normalize({"type": "还没有这个词", "score": 250})
	check(normalized.type == "failed" and normalized.score == 100,
		"an unknown result type falls back to failed and the score is clamped")
	check(MiniGameResult.passed("partial") and not MiniGameResult.passed("cancelled") and not MiniGameResult.passed(""),
		"the passing set covers partial but not cancelled / failed / empty")
	# 结果落进状态的唯一入口（小游戏经理走的就是它）。
	check(not game.note_minigame("no_such_game", {}).is_empty(), "recording an unknown minigame is rejected")
	game.new_game()
	check(game.begin_action("camera").is_empty(), "begin an investigation for the minigame gate check")
	check(not game.complete_action(game.ticket).is_empty() and not game.owns("camera"),
		"a minigame action cannot be committed before the minigame is passed")
	check(game.note_minigame("monitor_rebuild", {"type": "partial", "score": 60}).is_empty()
			and str(game.flag("minigame.monitor_rebuild.type")) == "partial"
			and int(game.flag("minigame.monitor_rebuild.score")) == 60,
			"a played result lands in the state through the game facade")
	check(game.complete_action(game.ticket).is_empty() and game.owns("camera"),
		"the recorded result is what the commit gate reads")

	# ── 图鉴（§12-14）与案件（§15-17）：解锁 / 结案都走口子 ──────────────
	# 单活动案件是**世界不变量**：同时两个「进行中」要被体检拦下。
	# 先用合成声明表直接量这条不变量，再确认它接在共用体检里（写路径都绕不过）。
	var case_defs := {
		"case.a.state": {"type": "string", "default": "locked", "values": ["locked", "active", "completed"]},
		"case.b.state": {"type": "string", "default": "locked", "values": ["locked", "active", "completed"]},
	}
	check(not CaseManager.snapshot_error({"case.a.state": "active", "case.b.state": "active"}, case_defs).is_empty(),
		"two running cases violate the single-active invariant")
	check(CaseManager.snapshot_error({"case.a.state": "active", "case.b.state": "locked"}, case_defs).is_empty(),
		"one running case passes the invariant")
	check(not Rules.snapshot_error({"flags": {"case.a.state": "active", "case.b.state": "active"}, "inventory": {}},
			case_defs, {"items": {}}).is_empty(),
		"the invariant is enforced inside the shared snapshot health check")
	game.new_game()
	check(game.flag("case.missing.state") == "locked" and game.case_outlook("missing").is_empty(),
		"a case starts locked with no outcome in reach")
	check(not game.complete_case().is_empty(), "closing without a running case is rejected")
	check(game.apply_effects({"set": {"case.missing.state": "active"}}).is_empty()
			and CaseManager.active_case(game.bundle, game.flags_snapshot()) == "missing",
		"the case is activated by a data effect and the active case is readable")
	# 图鉴：三个人口都要有校验；重复解锁无害；小红点由解锁动作自己点、打开页清掉。
	check(not game.unlock_person("typo").is_empty(), "unlocking an unknown person is rejected")
	check(not game.unlock_person_info("zhou", "no_such_field").is_empty(), "unlocking an unknown codex field is rejected")
	check(not game.unlock_person_info("zhou", "station_seen").is_empty(), "a field cannot be unlocked before the person is known")
	check(game.unlock_person("zhou").is_empty() and game.person_flag("zhou", "discovered") == true,
		"unlock_person marks the person discovered")
	check(game.person_flag("zhou", "codex_new") == true, "a fresh unlock raises the codex-new flag")
	check(game.mark_codex_read("zhou").is_empty() and game.person_flag("zhou", "codex_new") == false,
		"opening the person page clears the new flag")
	check(game.unlock_person("zhou").is_empty() and game.person_flag("zhou", "codex_new") == false,
		"re-unlocking an already known person raises nothing")
	check(game.unlock_person_info("zhou", "station_seen").is_empty()
			and game.person_flag("zhou", "info.station_seen") == true
			and game.person_flag("zhou", "codex_new") == true,
		"unlocking one codex field raises the new flag")
	game.mark_codex_read("zhou")
	check(game.unlock_person_info("zhou", "station_seen").is_empty() and game.person_flag("zhou", "codex_new") == false,
		"re-unlocking an already read field is harmless and raises nothing")
	# 线索效果也是解锁的来路之一：数据里写的 discovered / info.<条目> 自动点小红点，
	# 不靠每个数据作者记得补一笔。
	game.new_game()
	act("camera")
	var zhou_rows: Array = CodexManager.rows(game.bundle, game.flags_snapshot(), "zhou")
	check(game.person_flag("zhou", "discovered") == true and game.person_flag("zhou", "info.station_seen") == true
			and game.person_flag("xu", "info.timeline") == true,
		"clue effects unlock codex entries")
	check(game.person_flag("zhou", "codex_new") == true and game.person_flag("xu", "codex_new") == true,
		"every unlock path raises the new flag, clue effects included")
	check(zhou_rows.size() == 5 and zhou_rows[0].unlocked == true and zhou_rows[1].unlocked == false,
		"the codex read model reports exactly the unlocked fields")
	check(zhou_rows[0].title == "公交站的男人", "the read model carries the declared title")
	# 结案：结果由案件数据里的 outcomes 裁定（条件 → 结果），调用方只说「结案了」。
	game.new_game()
	check(game.apply_effects({"set": {"case.missing.state": "active"}}).is_empty(), "activate for the closing test")
	act("camera")
	act("badge")
	act("archive")
	act("photo")
	act("testimony")
	check(game.case_outlook("missing") == "explained", "the outcome rule points at the explained result")
	check(game.complete_case().is_empty() and game.flag("case.missing.state") == "completed"
			and game.flag("case.missing.result") == "explained",
		"completing the case records the data-declared outcome")
	check(not game.complete_case().is_empty(), "a completed case cannot be closed twice")
	check(game.case_outlook("missing").is_empty(), "a finished case has no outlook")
	# 首章落幕 = 结案：finish_case 自己把进行中的案件推完（结果按数据裁定）。
	game.new_game()
	check(game.apply_effects({"set": {"case.missing.state": "active"}}).is_empty(), "activate for the chapter-end test")
	act("camera")
	act("badge")
	act("archive")
	# 落幕要「至少进入第 2 天」：日子不再自己走，玩家先推一天。
	check(game.end_day().is_empty(), "the player ends the first day")
	check(game.finish_case("seal").is_empty() and game.flag("case.missing.state") == "completed"
			and game.flag("case.missing.result") == "unresolved",
		"finishing the chapter closes the running case with the fallback outcome")
	game.new_game()

	# ── 叙事执行器（stories.json）的契约 ─────────────────────────────────
	# 临时剧情挂在**真实 game** 上跑（不是另起一套 mock）：六种指令全走一遍。
	# 打完就删——测试数据不进游戏内容；状态回滚到检查点，不干扰后面的用例。
	game.bundle.stories.smoke_gate_on = {
		"name": "契约·走 then",
		"start": "gate",
		"nodes": {
			"gate": {"steps": [{"if": {
				"requires": [{"flag": "day", "op": ">=", "value": 1}],
				"then": "grant", "else": "quiet"}}]},
			"quiet": {"steps": [{"effect": {"set": {"linmo_suspicion": 9}}}]},
			"grant": {"steps": [
				{"effect": {"add": {"linmo_trust": 5}}},
				{"clue": "camera"},
				{"unlock": "linmo"},
				{"unlockinfo": {"person": "linmo", "field": "remembers"}},
				{"goto": "talk"}]},
			"talk": {"steps": [{"say": ["契约台词一", "契约台词二"]}]},
		},
	}
	game.bundle.stories.smoke_gate_off = {
		"name": "契约·走 else",
		"start": "gate",
		"nodes": {
			"gate": {"steps": [{"if": {
				"requires": [{"flag": "day", "op": ">=", "value": 99}],
				"then": "grant", "else": "quiet"}}]},
			"grant": {"steps": [{"effect": {"set": {"linmo_trust": 1}}}]},
			"quiet": {"steps": [
				{"effect": {"set": {"linmo_suspicion": 7}}},
				{"say": "契约台词（else）"}]},
		},
	}
	game.bundle.stories.smoke_loop = {
		"name": "契约·绕圈",
		"start": "hole",
		"nodes": {"hole": {"steps": [{"goto": "hole"}]}},
	}
	var contract_checkpoint: Dictionary = game.snapshot()
	var runner = Runner.new()
	var spoken: Array = []
	runner.game = game
	runner.display = func(lines: Array, done: Callable):
		spoken.append_array(lines)
		done.call()
	check(runner.play("smoke_gate_on").is_empty() and spoken == ["契约台词一", "契约台词二"],
		"runner walks if → effect → clue → unlock → unlockinfo → goto → say")
	check(int(game.flag("linmo_trust")) == 35 and game.owns("camera") and game.person_flag("linmo", "discovered") == true
			and game.person_flag("linmo", "info.remembers") == true,
		"runner writes state only through the game facade")
	check(runner.play("smoke_gate_off").is_empty() and int(game.flag("linmo_suspicion")) == 7,
		"runner takes the else branch when conditions fail")
	# 没有表现回调也要跑完：台词只进日志不演出，但不能卡住剧情。
	runner.display = Callable()
	var logged: int = game.journal.size()
	check(runner.play("smoke_gate_off").is_empty() and game.journal.size() == logged + 1,
		"say without a display still logs and moves on")
	# 半路坏掉的剧情（打点成环）也要发 finished——它是「收场」信号，不分正常还是出错；
	# 等它的人（_play_story 的 done / 演出链）靠它放行，不能只在正常演完时才响。
	var ended := [0]
	runner.finished.connect(func(): ended[0] += 1, CONNECT_ONE_SHOT)
	check(runner.play("smoke_loop").contains("上限") and ended[0] == 1 and not runner.busy(),
		"runaway story stops at the step limit instead of hanging and still reports finished")
	# 节点必要条件（设计文档 §26）：进节点时条件不成立 = **因果链断了**——
	# 发 broken 收场、**不补发 finished**（「演完了」和「走不下去了」是两种收场，
	# 等 finished 的人要往下走，等 broken 的人要拿出路），原因取自节点自己的 broken 文案。
	game.bundle.stories.smoke_gated = {
		"name": "契约·必要条件",
		"start": "gate",
		"nodes": {"gate": {
			"requires": [{"flag": "day", "op": ">=", "value": 99}],
			"broken": "契约·世界线断了",
			"steps": [],
		}},
	}
	var breaks: Array = []
	var finishes: Array = []
	runner.broken.connect(func(reason: String): breaks.append(reason))
	runner.finished.connect(func(): finishes.append(1))
	check(runner.play("smoke_gated").is_empty() and breaks == ["契约·世界线断了"]
			and finishes.is_empty() and not runner.busy() and runner.broken_reason == "契约·世界线断了",
		"a node whose requirement fails breaks the chain, and broken is not finished")
	# 条件成立时同一个节点照常跑过去——闸门不是墙。
	game.bundle.stories.smoke_gated.nodes.gate.requires = []
	check(runner.play("smoke_gated").is_empty() and breaks.size() == 1 and finishes == [1]
			and runner.broken_reason.is_empty(),
		"the same node plays through once its requirement holds")
	# 收场是「一次 play 一次」：再播一遍时 broken_reason 先清后断，
	# 上一回的旧原因不会跟着漏进来。
	game.bundle.stories.smoke_gated.nodes.gate.requires = [{"flag": "day", "op": ">=", "value": 99}]
	breaks.clear()
	check(runner.play("smoke_gated").is_empty() and breaks == ["契约·世界线断了"] and finishes == [1],
		"a later run clears the previous broken_reason before it can break again")
	game.bundle.stories.erase("smoke_gated")
	# 演出（sequence 指令）的契约：执行器**停在演出上等**——演出演完（ack）
	# 才继续后面的步骤。这就是设计文档 §7 那条「剧情可以暂停在一段演出上」。
	game.bundle.sequences.smoke_play = {"name": "契约·演出", "steps": [{"at": 0.0, "wait": 0.05}]}
	game.bundle.stories.smoke_show = {
		"name": "契约·演出等待",
		"start": "show",
		"nodes": {"show": {"steps": [{"sequence": "smoke_play"}, {"say": "演出之后"}]}},
	}
	var after: Array = []
	var performed: Array = []
	var release := [Callable()]
	runner.display = func(lines: Array, done: Callable):
		after.append_array(lines)
		done.call()
	runner.performer = func(sequence: Dictionary, done: Callable):
		performed.append(str(sequence.get("name", "")))
		release[0] = done
	check(runner.play("smoke_show").is_empty() and performed == ["契约·演出"] and after.is_empty(),
		"runner pauses on a sequence and waits for the performance")
	(release[0] as Callable).call()
	check(after == ["演出之后"], "runner continues once the performance acks")
	# 没有演出回调也一样：告警跳过，不能卡住剧情。
	runner.performer = Callable()
	var logged_after: int = game.journal.size()
	check(runner.play("smoke_show").is_empty() and after == ["演出之后", "演出之后"] and game.journal.size() == logged_after + 1,
		"sequence without a performer is skipped, not stuck")
	# 小游戏（minigame 指令）的契约同上：执行器**停在那一局上等**，
	# 打完（或被打断）放行才继续。结果**不从回调参数进剧情**——进的是状态，
	# 剧情要用就用 if 查（设计文档 §9.3：小游戏不允许直接决定剧情）。
	game.bundle.minigames.smoke_game = {
		"name": "契约·小游戏",
		"scene": "res://scenes/black_page/timeline.tscn",
		"config": {"prompt": "契约", "segments": ["一", "二"], "order": [0, 1]},
	}
	game.bundle.stories.smoke_minigame = {
		"name": "契约·小游戏等待",
		"start": "show",
		"nodes": {"show": {"steps": [{"minigame": "smoke_game"}, {"say": "小游戏之后"}]}},
	}
	var after_game: Array = []
	var played: Array = []
	var release_game := [Callable()]
	runner.display = func(lines: Array, done: Callable):
		after_game.append_array(lines)
		done.call()
	runner.play_minigame = func(id: String, done: Callable):
		played.append(id)
		release_game[0] = done
	check(runner.play("smoke_minigame").is_empty() and played == ["smoke_game"] and after_game.is_empty(),
		"runner pauses on a minigame and waits for the played result")
	(release_game[0] as Callable).call()
	check(after_game == ["小游戏之后"], "runner continues once the minigame releases it")
	# 没有小游戏回调也一样：告警跳过，不能卡住剧情。
	runner.play_minigame = Callable()
	var logged_game: int = game.journal.size()
	check(runner.play("smoke_minigame").is_empty() and after_game.size() == 2 and game.journal.size() == logged_game + 1,
		"minigame without a callback is skipped, not stuck")
	game.bundle.stories.erase("smoke_minigame")
	game.bundle.minigames.erase("smoke_game")
	game.bundle.stories.erase("smoke_show")
	game.bundle.sequences.erase("smoke_play")
	check(game.restore(contract_checkpoint).is_empty(), "contract story state rolls back")
	game.bundle.stories.erase("smoke_gate_on")
	game.bundle.stories.erase("smoke_gate_off")
	game.bundle.stories.erase("smoke_loop")

	var loader = Loader.new()
	var compiled: Dictionary = loader.compile()
	# ★ 字段表驱动的**结构性断言**：表里声明的每个字段，都必须真的出现在编译结果里。
	# 守的是「校验」和「拷贝」读同一张表这个性质本身——以前这两件事写在两个地方，
	# 只改一处就会静默丢数据（music / sfx 丢过一次：音效一个都不响，而测试全绿）。
	var not_copied: Array = []
	for key in Loader.PROLOGUE_FIELDS:
		if not (compiled.prologue[0] as Dictionary).has(str(key)):
			not_copied.append(str(key))
	check(not_copied.is_empty(), "every declared scripted field reaches the page (%s)" % str(not_copied))
	# 回归：loader 必须把 music / sfx **真的拷进**页面。
	# 只有字段白名单是不够的 —— 不拷就等于数据被静默丢弃：
	# 音乐和音效一个都不会响，而测试依然全绿。
	var prologue_pages: Array = compiled.prologue
	var with_music := 0
	var with_sfx := 0
	for pg in prologue_pages:
		if not (pg.get("music", {}) as Dictionary).is_empty(): with_music += 1
		if not str(pg.get("sfx", "")).is_empty(): with_sfx += 1
	check(with_music >= 2 and with_sfx >= 6,
		"compiled scripted carries music and sfx (%d music, %d sfx)" % [with_music, with_sfx])
	var bad: Dictionary = compiled.actions.badge.duplicate(true)
	bad.effects = {"set": {"linmo_trsut": 30}}
	check(not loader._validate_row("actions", "badge", bad, compiled) and loader.error.contains("actions.json:") and loader.error.contains("linmo_trsut"), "reference error has source location")
	# 剧情数据（stories.json）的校验：引用错 / 未知指令 / 效果写错旗标，
	# 都要在**编译期**带文件位置报出来——不能等到运行时才静默跳过那一步。
	var broken: Dictionary = compiled.duplicate(true)
	broken.stories.chapter1_open.nodes.morning.steps = [{"goto": "nowhere"}]
	check(not loader._compile_stories(broken) and loader.error.contains("stories.json:") and loader.error.contains("nowhere"),
		"story node reference error has source location")
	broken = compiled.duplicate(true)
	broken.stories.chapter1_open.nodes.morning.steps = [{"dance": 1}]
	check(not loader._compile_stories(broken) and loader.error.contains("未知指令"),
		"unknown story command is rejected at compile time")
	broken = compiled.duplicate(true)
	broken.stories.chapter1_open.nodes.morning.steps = [{"effect": {"set": {"no_such_flag": 1}}}]
	check(not loader._compile_stories(broken) and loader.error.contains("no_such_flag"),
		"story effect references are validated")
	# 节点字段照执行器的 NODE_FIELDS 校验，和指令表一个规矩：未知字段**报错不忽略**——
	# 把 requires 拼成 require，静默的后果就是闸门永远不响。
	broken = compiled.duplicate(true)
	broken.stories.chapter1_open.nodes.morning.dance = 1
	check(not loader._compile_stories(broken) and loader.error.contains("未知字段"),
		"an unknown story node field has source location")
	# 闸门断了要说得出为什么（设计文档 §26）：写了 requires 就必须写 broken。
	broken = compiled.duplicate(true)
	broken.stories.chapter1_open.nodes.morning.requires = [{"flag": "day", "op": ">=", "value": 99}]
	check(not loader._compile_stories(broken) and loader.error.contains("必须写 broken"),
		"a gated node must say why the chain would break")
	# 必要条件本身照常校验：引用没声明过的旗标照样拦住。
	broken = compiled.duplicate(true)
	broken.stories.chapter1_open.nodes.morning.requires = [{"flag": "no_such_flag", "value": true}]
	broken.stories.chapter1_open.nodes.morning.broken = "断了"
	check(not loader._compile_stories(broken) and loader.error.contains("no_such_flag"),
		"a node requirement is validated against the declared flags")
	# 演出数据（sequences.json）的校验：动作名 / 素材 / 参数在加载期就报出来，
	# 剧情引用不存在的演出同样拦住——都不等运行时。
	broken = compiled.duplicate(true)
	broken.sequences.ink_settles.steps = [{"at": 0.0, "teleport": 1.0}]
	check(not loader._compile_sequences(broken) and loader.error.contains("sequences.json:") and loader.error.contains("teleport"),
		"unknown performance action has source location")
	broken = compiled.duplicate(true)
	broken.sequences.ink_settles.steps = [{"at": 0.0, "sfx": "res://assets/audio/no_such_sfx.wav"}]
	check(not loader._compile_sequences(broken) and loader.error.contains("no_such_sfx"),
		"missing sound file is caught at compile time")
	broken = compiled.duplicate(true)
	broken.stories.chapter1_open.nodes.morning.steps = [{"sequence": "no_such_sequence"}]
	check(not loader._compile_stories(broken) and loader.error.contains("no_such_sequence"),
		"story sequence references are validated")
	# 小游戏数据（minigames.json）的校验：场景 / 参数 / 结果声明在加载期就报出来；
	# 结果类型词表读的是代码里那一张（MiniGameResult.TYPES）——数据少写一个也拦住。
	broken = compiled.duplicate(true)
	broken.minigames.monitor_rebuild.scene = "res://scenes/black_page/no_such_scene.tscn"
	check(not loader._compile_minigames(broken) and loader.error.contains("minigames.json:") and loader.error.contains("no_such_scene"),
		"missing minigame scene has source location")
	broken = compiled.duplicate(true)
	broken.flags["minigame.monitor_rebuild.type"].values = ["success", "failed"]
	check(not loader._compile_minigames(broken) and loader.error.contains("少了结果类型"),
		"the result vocabulary must cover every type the code knows")
	broken = compiled.duplicate(true)
	broken.stories.chapter1_open.nodes.morning.steps = [{"minigame": "no_such_game"}]
	check(not loader._compile_stories(broken) and loader.error.contains("no_such_game"),
		"story minigame references are validated")
	# 图鉴数据（codex.json）：每条档案要有声明过的解锁旗标、人物与图鉴双向对齐；
	# 剧情 unlockinfo 引用错条目同样在编译期报出来。
	broken = compiled.duplicate(true)
	broken.codex.zhou.fields[0].id = "no_such_field"
	check(not loader._compile_codex(broken) and loader.error.contains("codex.json:") and loader.error.contains("no_such_field"),
		"a codex field without a declared unlock flag has source location")
	broken = compiled.duplicate(true)
	broken.codex.erase("linmo")
	check(not loader._compile_codex(broken) and loader.error.contains("linmo"),
		"the codex must cover every person")
	broken = compiled.duplicate(true)
	broken.people.erase("linmo")
	check(not loader._compile_codex(broken) and loader.error.contains("图鉴里的人物不存在"),
		"the codex cannot mention a stranger")
	broken = compiled.duplicate(true)
	broken.stories.chapter1_open.nodes.morning.steps = [{"unlockinfo": {"person": "zhou", "field": "no_such_field"}}]
	check(not loader._compile_stories(broken) and loader.error.contains("no_such_field"),
		"story unlockinfo references are validated")
	# 案件数据（cases.json）：状态词表要覆盖三档、结果要在词表里、最后一条裁定无条件兜底——
	# 不然「切不进去的状态」和「结案落个空结果」都会静默发生。
	broken = compiled.duplicate(true)
	broken.flags["case.missing.state"].values = ["locked", "active"]
	check(not loader._validate_row("cases", "missing", broken.cases.missing, broken) and loader.error.contains("少了状态"),
		"the case state vocabulary must cover every state the code knows")
	broken = compiled.duplicate(true)
	broken.cases.missing.outcomes[0].result = "no_such_result"
	check(not loader._validate_row("cases", "missing", broken.cases.missing, broken) and loader.error.contains("no_such_result"),
		"a case outcome must name a declared result")
	broken = compiled.duplicate(true)
	broken.cases.missing.outcomes.back().requires = [{"flag": "day", "op": ">=", "value": 1}]
	check(not loader._validate_row("cases", "missing", broken.cases.missing, broken) and loader.error.contains("兜底"),
		"the last outcome must be unconditional")
	await _ui()
	# 检查数本身就是一道门槛。
	# 有解析错误时，后面的 check 会静默地不执行，而 PASS/FAIL 只看 failures ——
	# 于是出现「PASS (53 checks)」这种假通过。所以把「跑满」也断言掉。
	check(checks >= UI_CHECK_FLOOR, "the whole suite ran (%d checks, floor %d)" % [checks, UI_CHECK_FLOOR])
	print("BLACK_PAGE: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)

func _ui() -> void:
	var ui = load("res://scenes/black_page/main.tscn").instantiate()
	add_child(ui)
	await get_tree().process_frame
	check(is_instance_valid(ui.launch) and not ui._hud_layer.visible, "launch page gates game")
	# 截图必须去掉 --headless 跑：dummy 渲染器不会发 frame_post_draw，会永远卡在下一句上。
	if "--capture-render" in OS.get_cmdline_user_args():
		await get_tree().create_timer(2.9).timeout
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("user://screenshots")
		get_viewport().get_texture().get_image().save_png("user://screenshots/black_page_launch.png")
	# 槽位隔离：这一局的落笔检查点也进 smoke 槽——`new_game()` 会删掉检查点文件，
	# 忘了换槽位就是「跑一次测试抹掉玩家的存档」。
	ui.game.checkpoint_slot = "black_page_smoke_checkpoint"
	ui._start_new_game()
	await get_tree().create_timer(0.6).timeout
	check(is_instance_valid(ui.scripted) and not ui._hud_layer.visible, "opening scripted gates investigation hub")
	# HUD 的成员**必须都挂在 _hud_layer 下**：显隐是一刀切的（只切这一个节点），
	# 挂在别处就不会跟着收——顶栏以前就是这么在序章里一直露着日期的。
	# 这条断言守的是**结构**，不是某个节点的 visible 值。
	check(ui.shell.get_parent() == ui._hud_layer
			and ui._topbar.get_parent() == ui._hud_layer
			and ui._rail.get_parent() == ui._hud_layer,
		"every hud member lives under the hud layer")
	# 序章的音乐是「若有若无，然后消失」：页面声明要求，播放器由 main 注入。
	# 音频在 headless 下听不到，但「有没有递进去」能验。
	check(is_instance_valid(ui.scripted.music), "prologue gets the music player injected")
	check(is_instance_valid(ui.scripted.sfx), "prologue gets the sfx player injected")
	# 页级 speed：配了就用它，没配走全局 TYPE_SPEED。
	# 新剧本里 index=14（wait_2332）配了 speed 34。
	ui.scripted.step = 14
	ui.scripted._render_page()
	check(ui.scripted._speed == 34.0, "page speed overrides the global typing speed")
	ui.scripted.step = 0
	ui.scripted._render_page()
	check(ui.scripted._speed == UI.TYPE_SPEED, "page without speed falls back to the global")
	# 演出组件要真的建出来：index=1 是出租屋那一页，挂了 5 个热点
	ui.scripted.step = 1
	ui.scripted._render_page()
	check(ui.scripted._hotspot_layer.get_child_count() == 5, "hotspot page builds its hotspots")
	# 真点一下热区：正文要换成那条 response。
	# 这是玩家的真实操作路径——只数子节点个数证明不了点得动。
	ui.scripted._hotspot_layer.get_child(0).gui_input.emit(_left_click())
	await get_tree().process_frame
	check(ui.scripted._typer.full_text().contains("显示器"),
		"clicking a hotspot plays its response text")
	# 真点一下推进：第一下只把打字补完、**不翻页**（两段式），这是序章手感的关键
	ui.scripted._render_page()
	ui.scripted._tap()
	check(not ui.scripted._is_typing(), "first tap completes the typing instead of advancing")
	# index=3 是许妍那页，挂了 3 个回复选项
	ui.scripted.step = 3
	ui.scripted._render_page()
	check(ui.scripted._choice_layer.get_child_count() == 3, "choice page builds its options")
	# 真点一下选项：要把它自己那条 set 写进去
	ui.scripted._choice_layer.get_child(0).pressed.emit()
	await get_tree().process_frame
	check(str(ui.game.flag("prologue.reply")) == "have_time",
		"picking a choice writes its own flag")
	# 文字速度档位是**倍率**，不是绝对值：序章页面里配的 speed 是演出意图
	# （越接近 23:47 打得越慢），那属于内容，不能被玩家的偏好抹掉。
	ui.scripted.type_scale = 2.0
	check(is_equal_approx(ui.scripted._speed_of({"speed": 21.0}), 42.0),
		"player type scale multiplies the authored page speed")
	ui.scripted.type_scale = ui._type_scale()
	ui.scripted.step = 0
	ui.scripted._render_page()
	# 自动模式要在按钮上看得出来，不然玩家不知道自己处在什么状态
	ui.scripted._auto = true
	ui.scripted._refresh_auto()
	check(ui.scripted._auto_link.text == "自动中", "auto mode marks itself on the button")
	ui.scripted._auto = false
	ui.scripted._refresh_auto()
	check(ui.scripted._auto_link.text == "自动", "auto mode reverts the button label")
	# 截图模式：序章几种演出各拍一张，方便肉眼验收
	# （房间热点 / 聊天卡 / 纸页写字 / 新闻卡 / 标题卡）。
	# 每张等一小会儿让打字机推进，拍到的才是真实画面。
	if "--capture-render" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute("user://screenshots")
		for shot in [[1, "prologue_room"], [3, "prologue_chat"], [7, "prologue_rules"],
				[10, "prologue_article"], [25, "prologue_title"]]:
			ui.scripted.step = shot[0]
			ui.scripted._render_page()
			await get_tree().create_timer(0.9).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
				"user://screenshots/black_page_%s.png" % shot[1])
		ui.scripted.step = 0
		ui.scripted._render_page()
	# 把整段序章走完：32 页，逐页推进到序章自己被释放。
	# `_advance()` 是「无条件翻页」，和玩家点击走的 `_tap()` 不是一层。
	var prologue_guard := 0
	while is_instance_valid(ui.scripted) and prologue_guard < 40:
		ui.scripted._advance()
		await get_tree().process_frame
		prologue_guard += 1
	check(prologue_guard >= 32, "every scripted page was walked (%d)" % prologue_guard)
	# 剧情回顾：序章的正文必须被记下来——玩家点快了要能翻回去看。
	# 记在 main 而不是序章自己：回顾要收全（序章 + 第一章），只能有一个地方收。
	check((ui._history as Array).size() >= 32, "prologue text lands in the review history")
	if "--capture-render" in OS.get_cmdline_user_args():
		await get_tree().create_timer(1.1).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://screenshots/black_page_chapter.png")
	await get_tree().create_timer(1.6).timeout
	check(not is_instance_valid(ui.scripted) and ui.shell.visible and ui.game.flag("prologue.completed"), "prologue completes and hands over to the hub")
	# 开场白现在是**数据剧情**（stories.json 的 chapter1_open）：经由执行器播出来，
	# 正文落进日志，「已播过」写进旗标——以前这段字硬编码在 investigation.new_game() 里。
	check(ui.game.flag("story.chapter1_open.done"), "the opening story marks itself done through the game facade")
	check(is_instance_valid(ui.story) and ui.story.story_id == "chapter1_open", "the opener goes through the narrative runner")
	check(not ui.game.journal.is_empty() and str(ui.game.journal[0]).contains("天亮了"),
		"opening text comes from stories.json and lands in the journal")
	# 读完这一句（第一下补完打字、第二下翻过它），再重播一次：
	# 已经播过的剧情**不再重播**，闸门是剧情数据自己的 if，不是界面里的特判。
	ui._advance_story()
	ui._advance_story()
	var journal_size: int = ui.game.journal.size()
	ui._play_story("chapter1_open")
	await get_tree().process_frame
	check(ui.game.journal.size() == journal_size, "a finished story does not replay its text")
	# 案件解锁也是剧情 Effect 驱动的（stories.json 的 chapter1_open 里那条 effect）：
	# 界面不问来路，只读状态——「0 或 1 个进行中」由案件管理器把关。
	check(ui.game.flag("case.missing.state") == "active" and ui.game.flag("case.missing.result") == "",
		"the opening story activates the case through a data effect")
	check(ui.header.text.contains("第 1 天"), "room UI starts")
	# 顶栏不再有行动点（舍弃行动点，重构文档 §18）：右侧是「进入次日」，
	# 时间唯一的推进口。点击流程放在界面测试末尾验（这里先验它摆出来了）。
	check(is_instance_valid(ui._next_day) and ui._next_day.visible and ui._next_day.text.contains("次日"),
			"the top bar offers the only way to turn the page")
	if "--capture-render" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("user://screenshots")
		get_viewport().get_texture().get_image().save_png("user://screenshots/black_page_room.png")
	# 演出导演（PerformanceDirector）：真实数据 + 真实节点上跑一段演出——
	# 演完回调恰好一次、幕布/闪光回透明、舞台回原位；中途 stop() 也收得干净。
	check(is_instance_valid(ui.director) and ui.story.performer.is_valid(),
			"the story is wired to the performance director")
	var stage_base: Vector2 = ui.position
	# 用数组当计数器：GDScript 的 lambda 捕获**值**，`shots += 1` 加的是捕获的副本。
	var shots := [0]
	check(ui.director.play(ui.game.bundle.sequences.ink_settles, func(): shots[0] += 1),
			"the director takes a real sequence")
	check(ui.director.busy() and shots[0] == 0, "performance is running before its callback")
	if "--capture-render" in OS.get_cmdline_user_args():
		# 闪白 + 震动的峰值就在 0.12s 附近：抓这一帧看叠层有没有画上去。
		await get_tree().create_timer(0.12).timeout
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("user://screenshots")
		get_viewport().get_texture().get_image().save_png("user://screenshots/black_page_ink_performance.png")
	await get_tree().create_timer(1.6).timeout
	check(shots[0] == 1 and not ui.director.busy(), "performance calls back exactly once")
	check(ui.position == stage_base and ui.director.curtain.color.a == 0.0 and ui.director.flash.color.a == 0.0,
			"after a performance the stage and the overlays are settled")
	ui.director.play(ui.game.bundle.sequences.ink_settles, func(): shots[0] += 1)
	await get_tree().create_timer(0.2).timeout
	ui.director.stop()
	check(shots[0] == 2 and not ui.director.busy() and ui.position == stage_base,
			"stop() ends a performance, restores the stage and still calls back")
	ui._toggle_menu()
	if "--capture-render" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://screenshots/black_page_menu.png")
	ui._close_menu()
	# 左侧栏不是开局全给的：序章最后一页只解锁「人物」和「口袋」，
	# 「案件」要碰房间里的显示器、「黑页」要碰桌上那本笔记。
	# 这类问题来自「全屏容器默认 MOUSE_FILTER_STOP 盖在上面吃点击」，
	# 直接调方法测不出来，必须模拟真实鼠标点击。
	await get_tree().process_frame
	check(ui.nav_buttons["people"].visible and ui.nav_buttons["pocket"].visible, "people and pocket unlock from scripted data")
	check(not ui.nav_buttons["case"].visible and not ui.nav_buttons["notebook"].visible, "case and notebook stay hidden until touched")
	await get_tree().create_timer(0.6).timeout

	_click_at(ui, ui.nav_buttons["people"].get_global_rect().get_center())
	await get_tree().process_frame
	await get_tree().process_frame
	check(ui.modal.visible and ui._open_panel == "people", "side rail opens the people panel on a real click")
	# 图鉴正文（codex.json）必须真的进到 bundle 里，单人页才有的显示
	check(ui.game.bundle.has("codex") and not ui.game.bundle.codex.is_empty(), "codex data loaded")
	ui._open_person("zhou")
	await get_tree().process_frame
	await get_tree().process_frame
	check(ui.modal.visible and ui._open_panel == "people", "person codex page opens")
	if "--capture-render" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://screenshots/black_page_people.png")
	# 碰房间里的显示器：点亮「案件」入口（带解锁动画）并打开案件面板
	ui._hotspot_pressed({"target": "monitor"})
	check(ui.game.flag("ui.case") and ui.nav_buttons["case"].visible and ui.nav_buttons["case"].modulate.a < 1.0, "monitor reveals the case nav with animation")
	await get_tree().process_frame
	await get_tree().process_frame
	check(ui.modal.visible and ui._open_panel == "case", "case panel opens")
	if "--capture-render" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://screenshots/black_page_case.png")
	ui._close_modal()
	# 三条杠
	_click_at(ui, ui._menu_button.get_global_rect().get_center())
	await get_tree().process_frame
	check(ui._menu_layer.visible, "hamburger opens the menu on a real click")
	_click_at(ui, ui._menu_button.get_global_rect().get_center())
	await get_tree().process_frame
	check(not ui._menu_layer.visible, "clicking outside closes the menu")
	# 顶栏的「黑页」点回房间
	_click_at(ui, ui._logo_button.get_global_rect().get_center())
	# 回房间会走转场，等它走完再看场景
	await get_tree().create_timer(1.0).timeout
	check(ui.scene_id == "room", "top bar breadcrumb responds to a real click")

	# 碰桌上那本笔记：点亮「黑页」入口，并把场景切走
	ui._hotspot_pressed({"target": "notebook"})
	check(ui.game.flag("ui.notebook") and ui.nav_buttons["notebook"].visible and ui.nav_buttons["notebook"].modulate.a < 1.0, "desk notebook reveals the notebook nav with animation")
	await get_tree().create_timer(0.3).timeout
	check(ui.scene_id == "notebook", "opening the notebook switches the scene")
	if "--capture-render" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://screenshots/black_page_notebook.png")
	ui._close_modal()
	ui._enter_room()
	await get_tree().process_frame

	# 小游戏：经理把场景装进弹层、打完把结果落进状态，再走结果页（正文 + 提交）。
	# _investigate 里有转场（异步），要等它走完再取弹层内容
	ui._investigate("camera")
	await get_tree().create_timer(1.0).timeout
	check(ui.minigames.busy(), "the minigame manager owns the running round")
	var activity = ui.modal_rows.get_child(1)
	activity._select(0)
	check(activity.selected.is_empty(), "minigame incorrect choice resets")
	for index in [1, 2, 0]: activity._select(index)
	await get_tree().process_frame
	await get_tree().process_frame
	check(str(ui.game.flag("minigame.monitor_rebuild.type")) == "success" and not ui.minigames.busy(),
		"the played result lands in the state before the report shows")
	check(ui.modal_rows.get_child_count() == 4, "a finished minigame shows the report page")
	ui.modal_rows.get_child(2).pressed.emit()
	check(ui.game.owns("camera") and ui.game.flag("day") == 1 and not ui.modal.visible, "UI minigame reward once and return")
	await get_tree().process_frame

	# 图鉴跟着线索长：查过监控 = 认识了这个男人 + 两条档案解锁；
	# 「新」标记由解锁动作自己点出来——打开单人页就算看过。
	check(ui.game.person_flag("zhou", "discovered") == true and ui.game.person_flag("zhou", "info.station_seen") == true
			and ui.game.person_flag("zhou", "codex_new") == true,
		"the camera clue unlocks the codex and raises the new flag")
	var zhou_rows: Array = CodexManager.rows(ui.game.bundle, ui.game.flags_snapshot(), "zhou")
	check(zhou_rows.size() == 5 and zhou_rows[0].unlocked == true and zhou_rows[4].unlocked == false,
		"the panel sees exactly the unlocked codex fields")
	ui._open_person("zhou")
	await get_tree().process_frame
	check(ui._open_panel == "people" and ui.game.person_flag("zhou", "codex_new") == false,
		"opening the person page clears the new flag")
	ui._close_modal()
	await get_tree().process_frame

	# 调查：场景整张切换 → 底部逐句读 → 读完自动结算回房间（主界面没有推进按钮）
	ui._investigate("badge")
	await get_tree().create_timer(1.0).timeout
	check(ui.scene_id != "room", "investigation switches the scene")
	if "--capture-render" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://screenshots/black_page_scene.png")
	# 每次点击之间留一点时间：转场期间遮罩会吃掉点击，不能只等一帧
	var guard := 0
	while ui.scene_id != "room" and guard < 24:
		_click_at(ui, Vector2(200, 200))
		await get_tree().create_timer(0.12).timeout
		guard += 1
	check(ui.scene_id == "room" and ui.game.owns("badge") and ui.game.flag("day") == 1, "reading the report settles the action and returns to the room")

	# ── 行动锁不许在任何「退出路径」上漏掉 ─────────────────────────────────
	# 锁（game.active_action）不释放，玩家就卡在「不能开始新调查、不能存档、
	# 不能重载数据」的死角里，只有重新开始能出去。四条退出路径各验一次。
	ui.game.new_game()
	check(ui.game.begin_action("camera").is_empty(), "begin an investigation for the ESC check")
	ui._open_minigame("camera")
	await get_tree().process_frame
	check(ui.modal.visible and not ui.game.active_action.is_empty(), "the minigame modal holds the action lock")
	ui._unhandled_key_input(_esc())
	await get_tree().process_frame
	await get_tree().process_frame
	check(ui.game.active_action.is_empty() and not ui.modal.visible and ui.scene_id == "room",
		"ESC on an investigation modal releases the lock and returns to the room")
	check(ui.game.flag("day") == 1 and ui.game.available("camera"),
		"abandoning an investigation advances no time and keeps the route")
	# 打断的那一局也要留痕：记 cancelled——剧情 / 结算用 if 查得到「玩家退出了」。
	check(str(ui.game.flag("minigame.monitor_rebuild.type")) == "cancelled" and not ui.minigames.busy(),
		"an abandoned minigame is recorded as cancelled")
	# 结果页上的「返回」：小游戏已经通过，也可以不记账就走——不发线索、方向不标记完成。
	check(ui.game.begin_action("camera").is_empty(), "begin an investigation for the report check")
	ui._open_minigame("camera")
	await get_tree().process_frame
	var round_game = ui.modal_rows.get_child(1)
	for index in [1, 2, 0]: round_game._select(index)
	await get_tree().process_frame
	await get_tree().process_frame
	check(str(ui.game.flag("minigame.monitor_rebuild.type")) == "success" and ui.modal_rows.get_child_count() == 4,
		"a passed minigame records its result and shows the report")
	ui.modal_rows.get_child(3).pressed.emit()
	await get_tree().process_frame
	check(ui.game.active_action.is_empty() and not ui.game.owns("camera") and not ui.modal.visible
			and ui.game.available("camera"),
		"backing out of the report releases the lock without taking the reward")
	# 菜单的「回到房间」
	check(ui.game.begin_action("camera").is_empty(), "begin an investigation for the menu check")
	ui._return_to_room()
	await get_tree().process_frame
	check(ui.game.active_action.is_empty() and ui.scene_id == "room", "return-to-room releases the action lock")
	# 调查途中拐去看黑页：合上黑页同样要落回房间、放掉锁
	check(ui.game.begin_action("camera").is_empty(), "begin an investigation for the notebook check")
	ui._open_notebook()
	await get_tree().create_timer(0.3).timeout
	check(ui.scene_id == "notebook" and not ui.game.active_action.is_empty(), "the notebook opens over an in-flight investigation")
	ui.modal_rows.get_child(ui.modal_rows.get_child_count() - 1).pressed.emit()
	await get_tree().create_timer(0.9).timeout
	check(ui.game.active_action.is_empty() and ui.scene_id == "room" and not ui.modal.visible,
		"closing the notebook mid-investigation returns to the room and releases the lock")

	# ── 顶栏「进入次日」：时间唯一的推进口 ─────────────────────────────────
	# 没有行动预算了（舍弃行动点，重构文档 §18），房间不会自己翻页——
	# 这一步必须由玩家按，而且按之前要确认（黑页的账在夜里兑现，不可逆）。
	check(ui._next_day.visible and int(ui.game.flag("day")) == 1, "the day-end button waits in the top bar")
	_click_at(ui, ui._next_day.get_global_rect().get_center())
	await get_tree().process_frame
	check(ui.modal.visible and ui.modal_rows.get_child_count() == 4, "turning the page asks for confirmation first")
	ui.modal_rows.get_child(3).pressed.emit()
	await get_tree().process_frame
	check(not ui.modal.visible and int(ui.game.flag("day")) == 1, "backing out leaves the day untouched")
	_click_at(ui, ui._next_day.get_global_rect().get_center())
	await get_tree().process_frame
	ui.modal_rows.get_child(2).pressed.emit()
	await get_tree().process_frame
	check(int(ui.game.flag("day")) == 2 and ui.header.text.contains("第 2 天") and not ui.modal.visible,
		"confirming turns the page to the next day")

	# ── 断链面板：世界少了必要条件，收场要拿出路（设计文档 §26 / §28）────────
	# 首章落幕先过 chapter1_end 的闸门：林墨还在，才有人接得住查出来的东西。
	# 把他写死、夜里兑现，再按「封存黑页」——收场断在闸门上，
	# 玩家拿到的是断链面板（说明 + 回溯），而不是照常落幕。
	check(ui.game.unlock_person("linmo").is_empty() and ui.game.write_name("linmo").is_empty(),
		"the contact goes on the page before the night realizes him")
	ui._open_notebook()
	await get_tree().create_timer(0.3).timeout
	var open_row: Button = _button(ui, "写下「林墨」")
	check(open_row != null and open_row.disabled and _has_text(open_row, "这个名字已经在黑页上。"),
		"a pending name cannot be written twice, and the greyed row says exactly why")
	ui.modal_rows.get_child(ui.modal_rows.get_child_count() - 1).pressed.emit()
	await get_tree().create_timer(0.9).timeout
	check(ui.scene_id == "room", "closing the notebook returns to the room")
	check(ui.game.end_day().is_empty() and ui.game.person_flag("linmo", "status") == "dead",
		"the night takes the name written on the page")
	ui._open_notebook()
	await get_tree().create_timer(0.3).timeout
	var dead_row: Button = _button(ui, "写下「林墨」")
	check(dead_row != null and dead_row.disabled and _has_text(dead_row, "这个人已经死了。"),
		"the dead cannot be written again, and the greyed row says exactly why")
	var seal: Button = _button(ui, "封存黑页")
	check(seal != null, "the notebook offers the chapter close once the first night has passed")
	seal.pressed.emit()
	await get_tree().process_frame
	_button(ui, "确认").pressed.emit()
	await get_tree().process_frame
	check(ui.modal.visible and _has_text(ui.modal_rows, "林墨不在了。"),
		"a broken chain shows the panel that says what is missing")
	var roll: Button = _button(ui, FailureManager.ROLLBACK)
	check(roll != null, "the checkpoint exists, so the panel offers the way back")
	check(ui.game.flag("ending") == "" and int(ui.game.flag("day")) == 3,
		"a broken chain is not an ending, and the world stays where it broke")
	_button(ui, "先留在这里").pressed.emit()
	await get_tree().process_frame
	check(not ui.modal.visible and ui.game.flag("ending") == "" and ui.game.person_flag("linmo", "status") == "dead",
		"staying moves nothing, so the way back can be entered again")
	ui._end_chapter("seal")
	await get_tree().process_frame
	check(ui.modal.visible and _button(ui, FailureManager.ROLLBACK) != null,
		"the broken panel can be re-entered")
	_button(ui, FailureManager.ROLLBACK).pressed.emit()
	await get_tree().create_timer(1.0).timeout
	check(ui.game.person_flag("linmo", "status") != "dead" and int(ui.game.flag("day")) == 2
			and ui.game.pending.is_empty() and ui.scene_id == "room" and not ui.modal.visible,
		"rolling back returns the world to before the write")
	ui._end_chapter("seal")
	await get_tree().process_frame
	check(ui.game.flag("ending") == "uncertain", "with the chain intact the chapter closes")
	ui.free()
