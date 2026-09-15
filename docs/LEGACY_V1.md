# 第一版原型说明（历史参考）

此文档仅对应旧的 `story/demo.json` 与 `story_runner.gd` 原型。当前主场景使用 V2 框架，请查看项目根目录 README.md。

Godot 4.x + GDScript。打开 `project.godot`，按 **F5** 运行灯塔演示。
提供对话、条件选项、变量、条件跳转、多结局、视频入口、可插拔小游戏、单槽存读档和永久结局记录。

## 文件分工

```text
story/demo.json                 剧情内容、选项、分支和结局
scenes/main.tscn                 可在编辑器中调整的游戏界面
scripts/ui/main.gd              显示剧情、承载视频与小游戏、存读档按钮
scripts/core/story_runner.gd    剧情流程与状态，不依赖界面
scripts/core/save_store.gd      JSON 存储与格式版本校验
scripts/core/minigame.gd        小游戏公共接口
scenes/minigames/signal_game.tscn  点击收集信号的示例小游戏
scripts/minigames/signal_game.gd   示例小游戏逻辑
tests/smoke.gd                  轻量验证脚本
```

## 编辑剧情

复制 `story/demo.json`，在 `main.tscn` 根节点的 `story_path` 属性选择新文件。
`id` 为剧情唯一标识，`version` 为存档兼容版本，`start` 指定起始节点，`defaults` 定义变量初值。
`nodes` 的键是稳定节点 ID；`next`、`then`、`else` 都引用这些 ID。

| type | 用途 | 主要字段 |
| --- | --- | --- |
| `say` | 显示对话，等待继续 | `speaker`, `text`, `next` |
| `choice` | 显示满足条件的选项 | `text`, `options` |
| `set` | 更新变量后自动跳转 | `effects`, `next` |
| `branch` | 按条件跳转 | `conditions`, `then`, `else` |
| `video` | 播放过场后继续 | `path`, `skippable`, `result_key`, `next` |
| `minigame` | 加载独立小游戏场景 | `scene`, `config`, `result_key`, `next` |
| `ending` | 展示并记录结局 | `ending_id`, `title`, `text` |

选项格式：

```json
{
  "text": "告诉她真相",
  "conditions": [{"var": "trust", "op": ">=", "value": 2}],
  "effects": {"add": {"trust": 1}, "set": {"told_truth": true}},
  "next": "confession"
}
```

`conditions` 是 AND：全部成立才可用，省略或空数组表示始终成立。
支持 `==`, `!=`, `>=`, `>`, `<=`, `<`；比较大小只用于数字。
至少保留一个始终可用的选项，避免玩家无路可走。数值变量在 `defaults` 中声明。
`effects.set` 先执行，再执行 `effects.add`。状态仅使用 JSON 支持的值，不放 Godot 对象。

任意显示节点可加 `background`、`portrait` 图片路径，例如 `res://assets/backgrounds/coast.png`。
当前实现每个节点独立指定画面，省略时清空，保证从任意节点读档时画面一致。
长剧情可以拆成多个剧情文件；跨文件章节跳转尚未实现，目前每次运行加载一个文件。

## 多结局

在选择时修改变量，末尾用 `branch` 导向不同 `ending`。新增结局只需新增节点和跳转。
演示路线：留下并收集三次信号 → 灯火相连；留下后放弃 → 一起等待；直接离开 → 海岸独行。
结局记录与进度存档独立，重新开始或读旧档不会撤销已经解锁的结局。
当前界面显示解锁数量；结局图鉴 UI 可基于 `unlocked` 继续扩展。

## 视频

把 Godot 能加载的 `VideoStream` 资源路径填入 `video.path`。建议先用 `.ogv`（Ogg Theora）。
演示没有附带视频，`path` 为空时自动跳过。MP4 不能作为此框架开箱即用的保证，需要额外解码扩展或提前转码。
播放自然结束返回 `played=true, skipped=false`；主动跳过或空路径返回 `played=false, skipped=true`。
若 `result_key` 是 `film`，可在后续条件中读取 `film.played`、`film.skipped`。
无效资源会显示错误和继续按钮，避免中断整个剧情。

## 新增小游戏

1. 新建独立 `.tscn`，根节点为 `Control`，脚本继承 `res://scripts/core/minigame.gd`。
2. 覆盖 `begin(config, story_variables)`；入参为副本，可自由使用，不会直接改剧情变量。
3. 完成时调用 `finish({"success": true, "score": 100})`，只会发出一次结果。
4. 在剧情节点填入 `scene`、`config`、`result_key` 和 `next`。

宿主负责加载、显示、销毁场景。结果自动存入 `<result_key>.<字段>`，例如 `puzzle.success`。
小游戏自身负责暂停计时器、取消外部任务等清理逻辑；常规子节点随场景销毁。
重开和读档会销毁旧小游戏，并忽略旧场景延迟回传的结果。

## 存档与维护

- 保存目录：`user://saves/`，可通过 Godot 的“打开用户数据文件夹”查看。
- `slot_1.json`：剧情 ID/版本、当前节点、变量快照；后续增加槽位可复用 `SaveStore`。
- `endings.json`：按剧情 ID 保存已经解锁的结局。
- 视频和小游戏按**节点起点**恢复，不记录视频播放秒数或小游戏内部进度。
- 保存先写临时文件，再替换正式文件；读档检查格式、剧情版本和节点是否存在。
- 仅改文案可保留版本；删除节点、改变变量意义时提高剧情 `version`，或自行添加存档迁移。
- 导出时须在 Godot 导出预设的“非资源文件过滤”中加入 `story/*.json`（使用其他目录时相应调整），确保剧情 JSON 被打包。
- 新节点类型：在 runner 中补验证/流程，在 UI 的 `_present` 中补显示。不要把玩法代码塞进剧情引擎。

## 简单验证

```text
godot --headless --path <项目目录> --script res://tests/smoke.gd
godot --headless --path <项目目录> --quit-after 5
```

第一条覆盖三条结局、状态恢复、存档替换、小游戏结果回传；测试只写专用临时存档并在结束时删除。
第二条验证主场景启动。实际视频解码需放入视频文件后再运行确认。
