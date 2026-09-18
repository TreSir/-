extends RefCounted
## 断链的收场：剧情的必要条件不再成立时，这条世界线已经走不下去了。
##
## **这不是「游戏结束」**——设计文档刻意不叫这个名字。它是一块说明加一条退路：
## 先说清为什么走不下去（原因来自剧情数据自己声明的 `broken` 文案），
## 再把玩家送回「还没有写那一笔」的时候。
##
## 文案只在这里有一份：面板、日志、以后新加的出口都读它。散在各处就会漂，
## 而「断链时玩家看到什么」正是最不能漂的一处——他正站在一个坏掉的世界里。

const TITLE := "因果链已断裂"
const ROLLBACK := "回溯至使用死亡笔记之前"

## 断链面板的正文。
##
## `rollback_ready` 决定给不给回溯那条路：有检查点就直说可以退回去；
## 没有就**直说没有**，并指出还有别的出口（菜单读档 / 重新开始）——
## 玩家绝不能面对一个没有出口的死胡同。
static func body(reason: String, rollback_ready: bool) -> String:
	var lines: Array = []
	if not reason.is_empty(): lines.append(reason)
	lines.append("这条世界线无法继续走下去。")
	lines.append("可以回溯到使用死亡笔记之前——那一笔还没有写下。" if rollback_ready
			else "没有可以回溯的检查点。你仍然可以从菜单读档，或者重新开始这一章。")
	return "\n".join(lines)
