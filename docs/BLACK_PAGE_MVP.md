# 《黑页》首章可玩切片 · 使用与编辑指南

依据项目中的 [核心策划案 V0.2](black_page_design.md) 实现第 55～57 节的首个可玩闭环。案件具体对白、行动安排和首章结局文案为本次新增的演示草稿，可以直接修改。

## 1. 怎样运行

用 Godot 打开本项目的 `project.godot`，按 **F5**。默认入口是 `scenes/black_page/main.tscn`。先出现启动页：开始游戏、继续游戏、设置；无存档时继续游戏不可用。开始游戏会进入“第一次书写”序章，再进入调查中心。

旧灯塔演示仍在 `scenes/main.tscn`，打开那个场景按 F6 可单独运行。注意：Godot 编辑器的 F6 是“运行当前场景”，游戏获得键盘焦点后 F6 才是黑页的数据重载。

当前包含：可玩的“第一次书写”序章、1 个案件、3 个人物档案（许妍、陈东/周文远、林墨）、5 条线索、一个监控排序小游戏、每日三次行动、限时证词、落笔、次日反馈、手动存读档，以及四个首章主题结局和一个低信息兜底结果。主角以第一人称呈现，没有独立人物档案。

这是短流程原型，不是文档目标的 3～5 小时完整游戏，也尚未填充到 20～30 分钟。当前对白可较快读完。场景采用可替换的程序绘制占位图，尚无正式角色立绘、音效或视频素材。

## 2. 实际操作示例（含剧透）

### 路线一：先知道他是谁，再决定是否落笔

1. 点击“案件 → 还原公交站监控”，确认调查。按 **23:38 → 23:42 → 23:46** 选择画面；选错可以重新排序。
2. 点击“记录结果，返回房间”。获得监控线索，剩余两次行动。
3. 核对物流公司员工证：陈东身份确认变为 **70%**。
4. 请林墨核查旧身份：身份降为 **52%**，员工证可信度变为“伪造”。第三次行动结束后自动进入第二天。
5. 查阅晨曦福利院合照：真实姓名变为 **周文远**，身份 **100%**，真相仅 **15%**。
6. 此时可以手动保存，方便之后比较路线。
7. 继续赴约听完整证词：真相变为 **85%**，许妍状态变为“隐藏”。
8. 打开“黑页 → 封存黑页”，确认后进入次日，得到首章“合上黑页”。

### 路线二：得到名字就落笔

在上面的第 5 步后打开黑页，选择周文远，确认“落笔”。他不会立刻死亡。回房间后点击“结束今天”，下一天的手机新闻才会公布结果。

人物状态变为死亡、案件冻结、林墨怀疑增加。完整证词的入口关闭，但“打捞旧手机中的残留语音”会出现，仍可继续调查。它只提供 **40%** 真相，线索正文和可信度也不同。

之后封存黑页得到“错误的正义”，保留黑页得到“审判者”。这里是首章缩小版判定，正式长篇中“多次使用/多名关键人物”等阈值还需要重新设计。

### 路线三：相信了错误身份

第一天就尝试写下“陈东”。本切片采用确定性规则：**身份不到 100% 不生效**。下一天名字被划掉，错误书写次数增加，人物仍然存活，调查可以继续。没有采用随机概率。

落笔时会保存当时的名字和身份判断。落笔后再获得新证据，不会把之前的错误名字自动改成正确名字。

### 路线四：错过证词

完整证词只在第三天及以前可调查。进入第四天时若仍未获得它，改走残缺语音路线，不会卡死。即使一直等待，也可以在第二天后结束首章，得到“未完的调查”。

### 隐藏线索

获得完整证词后可核对旧档案上的黑色页角。此前没有成功杀人，再选择封存，会得到“页角之外”。这只是笔记本隐藏主线的开场钩子，不代表文档中的最终秘密已经写完。

## 3. 时间、取消与保存

- 调查确认后显示内容，点击“记录结果”时一次性提交线索、Flag 和行动消耗。
- 读到调查正文后必须提交结果；不能免费读完再取消。
- 小游戏尚未完成时可以返回，不消耗行动；成功后进入结果页。
- 第三次调查提交后自动结算。结果与次日消息都会保留在调查日志里。
- 阅读人物、线索和黑页不消耗行动。落笔不占调查次数，同一人物不能同时排队两次。
- “结束今天”可提前结束一天，剩余行动不结转。
- “合上笔记，继续调查”只返回房间；“封存黑页/保留黑页”才是结束首章，并进行最后一次次日结算。
- 当前为一个**手动存档槽**，不会自动覆盖存档。读取和重新开始都需确认。
- 存档在 `user://saves/black_page_slot_1.json`，包含 Flag、线索、落笔队列、最近日志。调查过程中不允许存档，小游戏中间位置不保存。
- Windows 上当前项目通常对应 `%APPDATA%/Godot/app_userdata/ProjectSrc/saves/`。

## 4. 日常编辑哪些文件

| 内容 | 文件 | 例子 |
| --- | --- | --- |
| 调查名称、正文、条件、奖励 | `data/black_page/actions.json` | 改 `photo.text` 修改发现真名时的文字 |
| 线索正文、类型、关联人物、效果 | `data/black_page/clues.json` | 改 `archive.effects` 调整身份反转 |
| 人物身份与死亡后果定义 | `data/black_page/people.json` | 改 `zhou.death_text` 修改次日新闻 |
| 案件介绍、当前疑点 | `data/black_page/cases.json` | 疑点通过 `requires` 随线索隐藏或出现 |
| 每日一次性事件 | `data/black_page/events.json` | 改 `deadline.requires` 调整期限 |
| 结局顺序、条件、文案 | `data/black_page/endings.json` | 优先级数字越大越先判定 |
| 强类型声明及开局状态 | `data/black_page/flags.json` | 人物身份、真相、状态的实际默认值在这里 |

`people.json` 中的初始 `identity/truth/status` 和 `clues.json` 中的 `reliability` 是内容说明；**运行时初值以 `flags.json` 为准**。修改开局值要改对应 Flag。重载保留当前进度，因此要通过“重新开始”观察新默认值。

开发运行时点击“重载数据”或按 F6。校验成功才替换数据，不重复领取奖励；错误提示含文件和行号。黑页模块目前采用**手动热重载**，原 V2 剧本播放器仍支持自动监听重载。

## 5. 示例：添加一条调查方向

以下例子在获得照片后新增一段林墨对话，不增加第六条线索。

先在 `flags.json` 顶层添加：

```json
"action.compare_notes.done": { "type": "bool", "default": false }
```

再在 `actions.json` 顶层添加：

```json
"compare_notes": {
  "name": "与林墨核对调查笔记",
  "kind": "dialogue",
  "case": "missing",
  "requires": [
    { "item": "photo", "op": ">=", "value": 1 },
    { "flag": "person.linmo.status", "op": "!=", "value": "dead" }
  ],
  "clues": [],
  "text": "林墨翻过照片。\n“名字对上了，但我们仍要找出许妍为什么跟他走。”",
  "effects": { "add": { "linmo_trust": 5 } }
}
```

重载后，已有照片且林墨存活时会出现该行动。行动仍消耗一次，完成后不再出现。JSON 对象之间注意加逗号。

条件是 AND：所有条件必须同时满足。支持 `==`、`!=`、`>=`、`>`、`<=`、`<`。省略 `op` 表示 `==`；省略 `value` 表示 `true`。

效果使用原框架的 `set`（指定值）和 `add`（数值增减）。Flag 不允许拼错、混用类型或超出范围。线索发放用 `clues` 字段，按 ID 去重，并且只在首次获得时执行该线索自身的效果。

## 6. 示例：新增线索与结局

新增线索时：

1. 在 `clues.json` 新增包含 `name/type/description/case/people/reliability/effects` 的条目。
2. 在 `flags.json` 声明 `clue.新ID.reliability`，类型 string，允许值 `reliable/dubious/contradictory/forged`。
3. 在某个调查的 `clues` 数组放入新 ID。加载器会生成最大堆叠为 1 的道具定义，线索界面自动列出。

新增结局示例，插入 `endings.json` 数组：

```json
{
  "id": "trusted_witness",
  "name": "仍有人愿意作证",
  "priority": 75,
  "requires": [
    { "flag": "linmo_trust", "op": ">=", "value": 60 },
    { "flag": "writes", "value": 0 },
    { "flag": "decision", "value": "seal" }
  ],
  "text": "林墨把你的笔记放进案卷。\n调查还会继续。"
}
```

ID 与优先级不能重复。必须保留一个最低优先级、`requires: []` 的兜底结局。结局在最后一次次日结算后读取最新状态。

## 7. 示例：接入自己的小游戏

小游戏继承已有的 `scripts/core/minigame.gd`：

```gdscript
extends "res://scripts/core/minigame.gd"

func begin(config: Dictionary, story_variables: Dictionary) -> void:
    # 按 config 创建谜题，读取 story_variables 作为只读快照。
    pass

func on_puzzle_solved() -> void:
    finish({"success": true})
```

保存为独立场景，然后在行动中设置：

```json
"kind": "minigame",
"scene": "res://scenes/black_page/timeline.tscn",
"config": {
  "prompt": "按发生顺序排列画面。",
  "segments": ["23:46 离开站台", "23:38 离开便利店", "23:42 男子到达"],
  "order": [1, 2, 0]
}
```

当前宿主要求回传 `success: true` 才显示结果页；失败可在小游戏内部重试。奖励由调查系统统一结算，小游戏不要直接修改 GameState。取消、重开或读档后，旧完成回调会失效。

## 8. 与原框架的关系

四个职责仍然分开：

- **数据**：`data/black_page/*.json`。
- **加载/校验**：`scripts/black_page/data_loader.gd`，复用 V2 的 JSON 行号映射和 Rules。
- **状态/流程**：`scripts/black_page/investigation.gd`，复用唯一的 GameState、EventBus 和 SaveStore。调查、死亡和每日事件先在候选快照里计算，校验通过后提交。
- **表现**：`scripts/black_page/main.gd` 与房间绘图、独立小游戏场景。

外部功能可监听 `EventBus.custom_event` 的 `investigation_completed`、`notebook_written`、`day_settled`，结局使用原有 `ending_reached` 信号。

首章目前以调查正文页呈现 `dialogue/document`。尚未把每条调查挂接到 V2 的命令播放器；原播放器的长对话、分支选项、视频、自动剧本重载和调试控制台仍在原场景可用。黑页界面尚未接入视频、游戏内变量控制台、完整场景热点和自由关系图。线索页目前提供自动关联摘要。

黑页存档内容版本为 `schema: 1`，存储外壳沿用 SaveStore。新增有默认值的 Flag 可兼容旧快照；更名、删字段或改类型时应编写显式迁移并提升 schema。当前没有虚构的旧版黑页迁移，也不会把灯塔存档误载入黑页。

## 9. 验证

Godot 命令行：

```text
godot --headless --path 项目目录 res://tests/black_page_smoke.tscn
godot --headless --path 项目目录 res://tests/framework_v2.tscn
```

测试覆盖主调查链、独立身份/真相、次日落笔、失败与限时后备路线、多结局、损坏存档拒绝、存档往返、重载不重复奖励、过期回调，以及五个界面和小游戏的接入。测试存档使用独立的 `black_page_smoke_roundtrip`，不会覆盖玩家槽。

使用真实渲染截图检查可在测试命令末尾加 `-- --capture-render`，并去掉 `--headless`。截图输出至 `user://screenshots/black_page_*.png`。
