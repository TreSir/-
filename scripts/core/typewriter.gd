extends RefCounted
## 打字机：把「一段文字 + 速度」变成「此刻该显示到第几个字」。
##
## 为什么有这个文件：主界面（`main.gd`）和剧本引擎（`core/scripted.gd`）各写过一套逐字显示，
## 连「先补完打字、再允许翻页」的两段式逻辑都重复了。合成一套。
##
## 宿主只需要在 `_process` 里喂 delta：
##
##     var typer := Typewriter.new()
##     typer.set_line(text, speed)        # 起一句（speed 传 0 走默认）
##     ...
##     typer.tick(delta)                  # 每帧推进
##     label.text = typer.visible_text()  # 画
##     if typer.is_done():                # 这一句打完了，点击才允许翻页
##         ...
##     typer.complete()                   # 立刻补完（点击的第一段行为）
##
## 段内换行统一用 `<br>`（`\n` 是**分段**，分段由宿主自己切）。

## 默认速度（字/秒）。宿主可以按页覆盖。
const DEFAULT_SPEED := 48.0

var _line := ""
var _revealed := 0.0
var _speed := DEFAULT_SPEED

## 起一句新话。`speed <= 0` 时用默认速度。
## 传进来的文字里 `<br>` 会换成真正的换行。
func set_line(text: String, speed: float = 0.0) -> void:
	_line = text.replace("<br>", "\n")
	_revealed = 0.0
	_speed = speed if speed > 0.0 else DEFAULT_SPEED

## 在不动画的情况下直接给出整句（比如读档回填、旁白瞬时显示）。
func set_line_now(text: String, speed: float = 0.0) -> void:
	set_line(text, speed)
	complete()

## 每帧推进。宿主在 _process 里调。
func tick(delta: float) -> void:
	if is_done(): return
	_revealed += delta * _speed

## 立刻补完整句（点击时「先补完打字」的那一步）。
func complete() -> void:
	_revealed = float(_line.length())

## 当前该显示的文字。
func visible_text() -> String:
	if _line.is_empty(): return ""
	return _line.substr(0, int(minf(_revealed, float(_line.length()))))

## 整句显示完了吗？没打完时点击不应该翻页。
func is_done() -> bool:
	return _line.is_empty() or visible_text().length() >= _line.length()


func full_text() -> String:
	return _line
