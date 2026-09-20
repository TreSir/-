# Godot 图文悬疑侦查游戏：整体架构与玩法逻辑设计

> 版本：重构基线 v1.0  
> 引擎：Godot  
> 游戏类型：图文剧情推进 / 悬疑侦查 / 强剧情演出 / 剧情小游戏 / 死亡笔记世界干预

---

## 1. 项目核心设计原则

本项目的整体架构围绕一个核心思想展开：

> **GameState 记录“世界现在是什么样子”，NarrativeRunner 根据当前状态决定“接下来发生什么”。**

在此基础上，将剧情逻辑、演出表现、小游戏互动、图鉴、案件、死亡笔记等系统拆分，避免所有逻辑堆积在一个剧情脚本中。

整个游戏可以理解为以下几个角色：

- **GameState**：世界记忆
- **NarrativeRunner**：剧情大脑 / 总调度者
- **PerformanceDirector**：演出导演
- **MiniGameManager**：剧情互动入口
- **CaseManager**：案件状态管理
- **CharacterCodexManager**：角色图鉴管理
- **DeathNoteSystem**：世界状态修改器
- **SaveManager**：存档与回溯
- **FailureManager**：剧情链断裂后的失败处理
- **UI**：显示层，不负责决定游戏逻辑

---

# 2. 总体架构

```text
                         剧情数据
                            ↓
                     NarrativeRunner
                            │
          ┌─────────────────┼─────────────────┐
          ↓                 ↓                 ↓
      Dialogue       PerformanceDirector   MiniGameManager
                          │                     │
                       Timeline              Gameplay
                          │                     │
                       Finished               Result
                          │                     │
                          └─────────┬───────────┘
                                    ↓
                                 GameState
                                    ↑
              ┌─────────────────────┼─────────────────────┐
              │                     │                     │
        CaseManager       CharacterCodexManager      DeathNoteSystem
                                                        │
                                                        ↓
                                               CharacterState 修改
                                                        │
                                                        ↓
                                                NarrativeRunner
```

---

# 3. GameState：整个游戏的核心状态层

## 3.1 定位

GameState 是整个游戏最重要的数据中心。

它不负责“播放剧情”，也不负责“显示 UI”，而是负责记录：

> **玩家目前所处世界的真实状态。**

所有能够影响后续剧情的结果，最终都应该落入 GameState。

---

## 3.2 GameState 建议记录的内容

```text
GameState
├── story_flags
├── story_variables
├── current_story_node
├── active_case_id
├── case_states
├── character_states
├── clue_states
├── codex_states
├── location_states
├── mini_game_results
└── global_progress
```

例如：

```text
story_flags:
    met_police = true
    investigated_hospital = false
    knows_autopsy_result = true

character_states:
    police_lin:
        discovered = true
        alive = true

    doctor_wang:
        discovered = true
        alive = false

case_states:
    case_001:
        status = COMPLETED

    case_002:
        status = ACTIVE
```

---

## 3.3 重要原则

以后设计任何功能时，都可以问一句：

> **“这个功能是在改变游戏状态，还是只是在表现游戏状态？”**

如果只是表现：

```text
镜头
角色立绘
音效
UI
动画
```

不应该直接修改剧情逻辑。

如果会影响后续剧情：

```text
获得线索
角色死亡
图鉴解锁
案件完成
知道某个秘密
做出某个选择
```

最终都应该更新 GameState。

---

# 4. NarrativeRunner：剧情总调度系统

## 4.1 定位

NarrativeRunner 负责解释剧情数据，并决定当前应该执行什么。

它是整个游戏的“剧情执行器”。

---

## 4.2 NarrativeRunner 负责的内容

```text
Dialogue
Choice
Condition
Effect
Goto
PlaySequence
PlayMiniGame
AddClue
UnlockCharacter
UnlockCharacterInfo
SetFlag
SetVariable
StartCase
CompleteCase
CheckStoryRequirement
```

---

## 4.3 NarrativeRunner 不负责的内容

NarrativeRunner 不应该直接承担：

```text
摄像机移动
角色动画
屏幕震动
音效具体播放
小游戏内部逻辑
图鉴 UI 刷新
死亡笔记规则验证
存档文件写入
```

它只负责：

> **调用对应系统。**

---

# 5. 剧情采用数据驱动

剧情不要大量写死在 GDScript 中。

推荐将剧情配置成：

```text
StoryNode
├── Dialogue
├── Choice
├── Condition
├── Effect
├── PlaySequence
├── PlayMiniGame
└── Goto
```

示例：

```text
Dialogue("许妍", "这里好像有人来过。")

PlaySequence("Xuyan_CheckRoom")

PlayMiniGame("SearchRoom")

IF MiniGameResult == SUCCESS
    AddClue("blood_trace")
    SetFlag("found_blood_trace", true)
    Goto("story_102")
ELSE
    Goto("story_103")
```

核心原则：

> **程序负责解释剧情，剧情内容由数据决定。**

---

# 6. 剧情逻辑采用命令流

普通剧情采用“从上向下执行”的命令流：

```text
Dialogue
↓
Choice
↓
SetFlag
↓
AddClue
↓
PlaySequence
↓
PlayMiniGame
↓
Goto
```

命令流特别适合：

- 对话
- 选项
- 条件判断
- Flag
- 线索
- 跳转
- 等待玩家点击
- 小游戏结果
- 案件推进

---

# 7. PerformanceDirector：重点剧情演出系统

## 7.1 定位

剧情运行器决定：

> **发生什么。**

PerformanceDirector 决定：

> **这件事情怎么演出来。**

两者必须分离。

---

## 7.2 典型调用

```text
NarrativeRunner
↓
PlaySequence("Xuyan_Attacked")
↓
PerformanceDirector
↓
演出完成
↓
Finished
↓
NarrativeRunner 继续
```

---

## 7.3 演出系统负责

```text
角色显示 / 隐藏
角色移动
角色表情
背景变化
镜头移动
镜头缩放
屏幕震动
闪白
淡入淡出
BGM
SFX
特效
动画
```

---

# 8. 重点演出采用 Timeline / Sequence

重点场面适合使用时间轴。

例如：

```text
0.0s  镜头开始推进
0.1s  灯光熄灭
0.3s  玻璃破碎
0.3s  屏幕震动
0.35s 许妍转头
0.5s  闪白
0.8s  镜头停止
```

时间轴擅长处理：

> **“什么时候发生”以及“哪些事情同时发生”。**

因此当前推荐：

- 普通剧情：命令流
- 高张力演出：时间轴

两者结合，而不是二选一。

---

# 9. MiniGameManager：剧情小游戏系统

## 9.1 小游戏不是演出

演出：

```text
剧情 → 播放 → Finished
```

小游戏：

```text
剧情 → 玩家操作 → Result → 剧情判断
```

所以 MiniGameManager 与 PerformanceDirector 平级。

---

## 9.2 基本流程

```text
NarrativeRunner
↓
PlayMiniGame("LockPicking")
↓
MiniGameManager
↓
加载小游戏 Scene
↓
玩家操作
↓
返回 MiniGameResult
↓
卸载小游戏
↓
NarrativeRunner 根据结果继续
```

---

## 9.3 小游戏不允许直接决定剧情

错误方式：

```gdscript
if success:
    goto_story_120()
else:
    goto_story_130()
```

正确方式：

```text
小游戏：
    Result = SUCCESS
```

然后：

```text
NarrativeRunner:

IF Result == SUCCESS
    AddClue("room_key")
    Goto("story_120")
ELSE
    Goto("story_130")
```

这样小游戏可以被多个剧情复用。

---

# 10. MiniGameResult

不要把小游戏结果限制成：

```text
success = true / false
```

推荐统一结果结构：

```text
MiniGameResult
├── result_type
├── score
└── data
```

例如：

```text
result_type:
    PERFECT
    SUCCESS
    PARTIAL_SUCCESS
    FAILED
    CANCELLED
```

示例：

```text
result_type = PARTIAL_SUCCESS
score = 65

data:
    clue_found = "shoe_print"
    mistakes = 2
```

---

# 11. 小游戏在 Godot 中的组织

建议每个小游戏都是独立 Scene：

```text
MiniGames/
├── LockPicking/
│   └── LockPickingGame.tscn
├── SearchRoom/
│   └── SearchRoomGame.tscn
├── EvidencePuzzle/
│   └── EvidencePuzzleGame.tscn
├── Interrogation/
│   └── InterrogationGame.tscn
└── QTE/
    └── QTEGame.tscn
```

统一约定：

```gdscript
func start(context):
    pass

signal finished(result)
```

MiniGameManager 负责：

```text
加载
启动
暂停主剧情
接收 Result
卸载
恢复剧情
```

---

# 12. 角色图鉴系统

## 12.1 图鉴不是 UI 自己判断解锁

角色图鉴的解锁应该由剧情 Effect 驱动。

例如：

```text
Dialogue("林警官", "你就是报案人？")

UnlockCharacter("police_lin")
```

流程：

```text
NarrativeRunner
↓
UnlockCharacter
↓
CharacterCodexManager
↓
更新 GameState
↓
发出 Signal
↓
Codex UI 刷新
```

---

# 13. 角色图鉴采用分阶段解锁

不要只设计：

```text
未解锁
已解锁
```

悬疑游戏更适合逐步更新人物信息。

例如：

```text
林警官

姓名            ✓
职业            ✓
个人经历        □
与案件关系      □
隐藏秘密        □
```

剧情可以触发：

```text
UnlockCharacter("police_lin")

UnlockCharacterInfo(
    "police_lin",
    "old_case_relation"
)
```

---

# 14. CharacterData 与 CharacterCodexState 分离

## CharacterData

表示角色的完整静态资料：

```text
id
name
portrait
occupation
description
完整背景
完整秘密
```

## CharacterCodexState

表示玩家目前知道多少：

```text
unlocked
unlocked_fields
new_flag
```

原则：

> **CharacterData = 角色实际上是什么。**  
> **CharacterCodexState = 玩家目前知道什么。**

---

# 15. 案件系统：不做多案件并行

目前版本明确舍弃：

> **多个案件同时调查。**

原因：

- 剧情线程容易混乱
- 状态管理大幅复杂
- NPC 跨案件状态难管理
- 存档复杂
- 测试组合爆炸
- 玩家也更容易遗忘案件信息

---

# 16. 当前采用：Hub + 单活动案件

游戏主界面 / 房间作为 Hub。

结构：

```text
序章
↓
案件 01
↓
回到房间 Hub
↓
公共剧情
↓
案件 02
↓
Hub
↓
案件 03
↓
……
↓
最终主线
```

GameState 中只允许：

```text
0 或 1 个 Active Case
```

CaseManager 管理：

```text
案件是否解锁
案件是否完成
当前案件
案件结果
```

例如：

```text
Case_001 = COMPLETED
Case_002 = ACTIVE
Case_003 = LOCKED
```

---

# 17. 案件内部允许自由调查

宏观结构保持单线。

微观调查可以自由：

```text
案件开始
│
├── 警察局
├── 医院
├── 案发现场
└── 嫌疑人家
```

玩家可以选择调查顺序。

最终通过条件进入下一阶段：

```text
获得关键线索 A
+
询问角色 B
+
调查地点 C
↓
解锁后续剧情
```

总结：

> **宏观单线，微观自由。**

---

# 18. 舍弃行动点系统

原设计：

```text
每天 3 次行动
调查一次消耗 1 点
```

当前版本决定舍弃。

原因：

如果没有真正的时间压力和资源选择，行动点只会变成：

> **人为限制玩家调查。**

而不是有意义的策略。

当前版本改为：

> **剧情节点、线索条件、调查完成度驱动案件推进。**

以后如果确实需要时间压力，可以重新考虑：

- 限时事件
- 某些证据会消失
- NPC 仅特定时段出现
- 特殊调查只能尝试一次

而不是默认给所有调查增加行动点。

---

# 19. DeathNoteSystem：死亡笔记系统

## 19.1 定位

死亡笔记不是普通道具。

它是：

> **World State Modifier / 世界状态修改器。**

玩家使用死亡笔记后，真正改变的是 GameState。

例如：

```text
CharacterState:

doctor_wang.alive
true
↓
false
```

---

# 20. 死亡笔记的核心玩法原则

当前确定：

> **所有满足死亡笔记规则、且玩家已经具备必要认知条件的角色，都允许真正被写死。**

不要因为角色“重要”就在系统层硬性禁止死亡。

否则死亡笔记会失去核心吸引力。

---

# 21. 死亡笔记规则

具体世界观规则未来可以继续调整。

当前架构只需要支持类似：

```text
必须已经见过目标
必须知道真实姓名
必须能够明确确认目标身份
必须符合死亡笔记的其他规则
```

DeathNoteSystem 负责：

```text
验证目标
↓
验证规则
↓
确认执行
↓
修改 CharacterState
↓
发出 character_died
```

---

# 22. CharacterState 建议结构

```text
CharacterState
├── discovered
├── alive
├── death_note_used
├── death_reason
├── death_time
└── custom_state
```

例如：

```text
police_lin:
    discovered = true
    alive = false
    death_note_used = true
```

---

# 23. 不做完整“死亡组合剧情重组”

这是当前项目非常重要的一条边界。

如果 10 个角色都可以生 / 死：

```text
2^10 = 1024 种组合
```

不可能为所有组合制作完整定制剧情。

因此明确：

> **允许所有人死亡，但不承诺所有死亡组合都有完整的新剧情线。**

---

# 24. 死亡影响分为三类

## A. 可兼容死亡

角色死亡不会破坏主线。

处理：

```text
角色消失
图鉴更新
少量对白变化
相关场景状态变化
剧情继续
```

---

## B. 可处理的关键死亡

角色死亡会破坏部分路径，但可以通过一个很短的替代方案继续。

例如：

```text
正常：
王医生 → 提供尸检报告

死亡后：
王医生死亡
↓
找到遗留档案
↓
仍然获得尸检报告
```

只处理“关键剧情功能”，不重写整个案件。

---

## C. 致命死亡

角色死亡直接破坏当前剧情继续成立的必要条件。

例如：

```text
关键证人死亡
+
没有替代证据来源
↓
当前案件无法继续
```

此时：

```text
StoryBroken
```

---

# 25. Story Requirement：剧情必要条件

每个重要剧情节点可以声明必要条件。

例如：

```text
StoryNode_205

Requirements:
    CharacterAlive("police_lin")
    HasClue("autopsy_report")
```

NarrativeRunner 执行前检查：

```text
条件满足
↓
继续剧情

条件不满足
↓
StoryBroken
```

---

# 26. FailureManager：剧情链断裂处理

不要把这种情况简单包装成传统：

```text
GAME OVER
```

可以设计成符合世界观的提示：

```text
【因果链已断裂】

由于关键人物“林警官”死亡，
当前案件已经失去必要调查条件。

这条世界线无法继续沿原有逻辑追查真相。
```

提供：

```text
[回溯至使用死亡笔记之前]
```

---

# 27. 死亡笔记使用前自动 Checkpoint

这是死亡笔记系统非常关键的一部分。

流程：

```text
玩家打开死亡笔记
↓
选择目标
↓
准备确认写入
↓
SaveManager.CreateCheckpoint()
↓
执行死亡笔记
↓
修改 GameState
```

如果之后剧情断裂：

```text
StoryBroken
↓
FailureManager
↓
RestoreCheckpoint()
↓
回到写名字之前
```

---

# 28. 为什么死亡笔记必须自动回溯

否则玩家会产生：

> “我杀错一个人，是不是把十几个小时存档毁了？”

最终玩家反而不敢使用死亡笔记。

我们希望形成：

```text
尝试
↓
观察世界结果
↓
成功则继续
↓
错误则回溯
```

也就是说：

> **死亡笔记允许玩家真正破坏剧情，但游戏允许玩家回溯错误的因果。**

---

# 29. 死亡笔记完整流程

```text
玩家认识角色
↓
图鉴解锁角色身份
↓
满足死亡笔记规则
↓
打开死亡笔记
↓
选择角色
↓
SaveManager 创建 Checkpoint
↓
DeathNoteSystem 验证
↓
执行死亡
↓
CharacterState.alive = false
↓
更新 GameState
↓
相关系统收到 Signal
│
├── 图鉴更新
├── 场景人物消失
├── 对话条件改变
└── 剧情条件改变
↓
NarrativeRunner 继续
↓
检查 Story Requirement
       │
       ├── 满足 → 继续剧情
       │
       └── 不满足 → StoryBroken
                          ↓
                   FailureManager
                          ↓
                    RestoreCheckpoint
```

---

# 30. 死亡笔记的设计目标

死亡笔记不应该只是：

> “选择一个 NPC 然后看一段死亡动画。”

真正的核心是：

> **玩家通过调查认识世界，然后通过死亡笔记主动修改世界状态。**

所以整个循环是：

```text
调查
↓
认识人物
↓
掌握身份
↓
决定是否使用死亡笔记
↓
改变世界
↓
观察后果
↓
继续调查 / 回溯
```

这将成为游戏最核心的差异化玩法之一。

---

# 31. Signal / EventBus 使用原则

系统之间尽量避免互相硬引用。

可以使用 Godot Signal 或统一 EventBus。

例如：

```text
character_unlocked
character_info_updated
character_died
clue_added
case_started
case_completed
story_node_changed
mini_game_finished
story_broken
checkpoint_restored
```

典型流程：

```text
GameState 修改
↓
Signal
↓
UI / 其他系统响应
```

UI 不主动推断游戏状态。

---

# 32. SaveManager

至少需要支持两类存档：

## 正常存档

保存完整 GameState。

## DeathNote Checkpoint

死亡笔记执行前临时建立。

Checkpoint 至少保存：

```text
当前剧情节点
StoryFlags
StoryVariables
CharacterStates
CaseState
ClueState
CodexState
当前场景必要状态
```

---

# 33. 推荐 Godot Autoload

第一版可以考虑：

```text
Autoload
├── GameState
├── NarrativeManager
├── SaveManager
├── EventBus
├── CaseManager
├── CharacterCodexManager
├── DeathNoteSystem
└── FailureManager
```

`PerformanceDirector` 和 `MiniGameManager` 是否必须 Autoload，可以根据场景生命周期再决定。

不要为了“全局方便”把所有东西都强行做成 Autoload。

---

# 34. 推荐目录结构

```text
res://
├── Core/
│   ├── Narrative/
│   ├── GameState/
│   ├── Save/
│   ├── Events/
│   └── Failure/
│
├── Systems/
│   ├── Cases/
│   ├── Codex/
│   ├── DeathNote/
│   ├── Clues/
│   └── Investigation/
│
├── Performance/
│   ├── Sequences/
│   ├── Camera/
│   ├── Audio/
│   ├── Characters/
│   └── Effects/
│
├── MiniGames/
│   ├── LockPicking/
│   ├── SearchRoom/
│   ├── EvidencePuzzle/
│   └── QTE/
│
├── Data/
│   ├── Stories/
│   ├── Characters/
│   ├── Cases/
│   ├── Clues/
│   └── Locations/
│
├── Scenes/
│   ├── Hub/
│   ├── Story/
│   └── Investigation/
│
└── UI/
    ├── Dialogue/
    ├── Codex/
    ├── Case/
    ├── DeathNote/
    └── Common/
```

---

# 35. 第一版重构优先级

建议不要一次性把全部系统写完。

按下面顺序重构。

## 第一阶段：核心骨架

先完成：

```text
GameState
NarrativeRunner
StoryData
SaveManager
```

目标：

> 最简单的一段剧情可以通过数据从头播放到尾。

---

## 第二阶段：Effect / Condition

增加：

```text
SetFlag
Condition
AddClue
UnlockCharacter
Goto
```

目标：

> 剧情已经能够根据 GameState 发生变化。

---

## 第三阶段：演出系统

加入：

```text
PerformanceDirector
Sequence
Timeline
```

目标：

> NarrativeRunner 可以等待一段重点演出完成后继续剧情。

---

## 第四阶段：小游戏

加入：

```text
MiniGameManager
MiniGameResult
```

目标：

> 剧情可以暂停 → 进入小游戏 → 得到结果 → 继续。

---

## 第五阶段：图鉴 / 案件

实现：

```text
CharacterCodexManager
CaseManager
```

仍然遵循：

```text
剧情 Effect
↓
GameState
↓
Signal
↓
UI
```

---

## 第六阶段：死亡笔记

最后再接：

```text
DeathNoteSystem
Checkpoint
StoryRequirement
FailureManager
```

因为死亡笔记高度依赖前面的 GameState、剧情条件和存档系统。

---

# 36. 当前最终核心原则

本次讨论已经确定以下原则：

1. **Godot 作为游戏引擎。**
2. **GameState 是世界状态核心。**
3. **NarrativeRunner 是剧情总调度者。**
4. **剧情逻辑采用命令流。**
5. **重点演出使用独立 PerformanceDirector。**
6. **重点演出采用 Timeline / Sequence。**
7. **小游戏与演出平级，而不是演出的子系统。**
8. **小游戏只返回 Result，不直接控制剧情。**
9. **角色图鉴由剧情 Effect 解锁。**
10. **图鉴支持资料逐步解锁。**
11. **不做多案件并行。**
12. **采用 Hub + 单 Active Case。**
13. **案件内部允许自由调查。**
14. **舍弃当前版本的行动点系统。**
15. **死亡笔记是世界状态修改器。**
16. **满足规则的角色原则上都可以被杀。**
17. **不为所有死亡组合制作完整新剧情。**
18. **死亡影响采用：兼容 / 局部替代 / 致命断链。**
19. **致命死亡允许剧情失败。**
20. **死亡笔记执行前自动创建 Checkpoint。**
21. **剧情断裂后允许玩家回溯到死亡笔记使用前。**
22. **UI 只显示状态，不负责决定世界逻辑。**

---

# 37. 一句话概括整个项目架构

> **玩家通过调查获得信息，NarrativeRunner 根据 GameState 推进剧情；重点情节交给 PerformanceDirector 表演，互动内容交给 MiniGameManager；玩家可以使用死亡笔记直接修改角色与世界状态，而剧情系统根据修改后的 GameState 继续推进、局部变化，或者在关键因果被破坏时进入 StoryBroken，并通过 Checkpoint 回溯。**

这份架构应作为后续 Godot 重构的第一版基线。后续新增功能时，优先判断它属于：

```text
状态
剧情逻辑
表现
互动
数据
```

再决定它应该进入哪个系统，避免职责重新混在一起。
