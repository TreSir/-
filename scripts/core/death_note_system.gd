extends RefCounted
## 死亡笔记的世界规则：一个名字**能不能写**、写下去**会兑现成什么**。
##
## 三条规矩集中在这里，只有这一份：
##   1. 落笔的资格（认识 / 没死 / 没写过）——界面上的提示与落笔时的校验读同一份；
##   2. 「知道真名」的定义（identity == 100）——这一笔记不记得上，由它判；
##   3. 结算时的世界变化（写对：目标死 + 记代价 + 跑 death_effects；写错：一道划痕）。
##
## 它**不是又一处状态**：状态仍归 GameState，写仍归 investigation。
## 这里只回答「这一笔会被接受吗、兑现成什么」，自己不碰 GameState——
## realize 改的是事务里的候选副本，提交与否由调用方决定。
##
## 为什么不让 investigation 自己写：这三条规矩会被三处读到——黑页上的提示、
## write_name 的校验、end_day 的兑现。各写一份迟早漂，漂了就会出现
## 「界面点亮了、落笔却被拒绝」这种自相矛盾。

## 写空了的那一笔：名字被划掉，世界什么消息都没有。
## 身份不足的落笔**不是错误**，是这个世界里真实会发生的一种结果——
## 「查明白了再下笔」全靠它教。
const SCRATCH := "黑页上的「%s」被一道细痕划掉。\n没有相关死亡消息。那道痕迹却留在纸上。"

## 现在为什么不能写这个名字；能写就返回空串。
##
## 只回答「名字本身」的规矩。首章落幕、调查进行中这类全局闸门是
## investigation 的守卫（它才知道行动锁和结局），不归这里。
static func write_error(bundle: Dictionary, flags: Dictionary, pending: Array, id: String) -> String:
	if not bundle.people.has(id): return "未知人物：" + id
	if flags.get("person." + id + ".discovered") != true: return "你还没有见过这个人。"
	if flags.get("person." + id + ".status") == "dead": return "这个人已经死了。"
	for entry in pending:
		if entry.get("person") == id: return "这个名字已经在黑页上。"
	return ""

## 「知道真名」的定义：身份确认度满了才写得动这个人。
## 落笔时记的 `valid` 读的就是它——**别处不许再判一次**。
static func knows_true_name(flags: Dictionary, id: String) -> bool:
	return flags.get("person." + id + ".identity") == 100

## 兑现一条落笔记录，返回这条记录该说给玩家的那句正文。
##
## 写对：目标死、`writes` / `erosion` 记上、跑数据里的 `death_effects`
## （波及别人的连锁写在那儿，不在这儿）。
## 写错：只记一笔错账（`wrong_writes`），世界不变。
##
## 状态怎么变是这里说了算，**事务（快照 / 校验 / 提交）在 investigation**：
## 这里改的是候选副本，出了任何问题整体不换上去。
static func realize(candidate: Dictionary, bundle: Dictionary, entry: Dictionary, apply_effects: Callable) -> String:
	var id := str(entry.get("person", ""))
	if bool(entry.get("valid")) and bundle.people.has(id):
		candidate.flags["person." + id + ".status"] = "dead"
		candidate.flags.writes += 1
		candidate.flags.erosion += 1
		apply_effects.call(candidate, bundle.people[id].get("death_effects", {}))
		return str(bundle.people[id].get("death_text", "……"))
	candidate.flags.wrong_writes += 1
	return SCRATCH % str(entry.get("name", id))
