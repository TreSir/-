# 框架使用指南：从改一句台词到做出完整分支

适用版本：当前自研 V2 框架（Godot 4.x / GDScript）。

这份指南按“要做什么 → 改哪里 → 例子 → 运行后会怎样”组织。日常写故事主要编辑 JSON；写新小游戏或新指令时才需要 GDScript。

> 本文代码分为“完整文件”和“局部片段”。局部片段要合并到对应对象/数组，不能直接覆盖整份文件。JSON 使用英文双引号，不支持注释；最后一项后面不加逗号。

## 1. 先运行现有演示

1. 在 Godot 打开 `project-src/project.godot`。
2. 按 **F5** 运行整个项目。主场景是 `scenes/main.tscn`。
3. 点“继续”，会获得旧钥匙和两杯热茶。
4. 点“背包”查看、使用道具，点“图鉴”查看已发现内容。
5. 选择帮助守塔人，体验嵌入的小游戏；选择离开，体验另一种结局。

当前演示有三条主要路线：

| 操作 | 结果 |
| --- | --- |
| 留下来，并收集三个信号 | 灯火相连 |
| 留下来，但在小游戏中放弃 | 一起等待 |
| 直接离开 | 海岸独行 |

灯塔只是示例题材，可以替换。当前没有附带 AI 美术或真实视频素材。

## 2. 先认识六个概念

| 名称 | 可以怎么理解 | 例子 |
| --- | --- | --- |
| 章节 | 一组有顺序、有跳转的剧情节点 | `prologue` |
| 节点 | 一步剧情动作 | 说一句话、给一道选择、进入小游戏 |
| ID | 程序识别内容的稳定名字 | `arrival`、`old_key` |
| op | 节点要执行的指令 | `say`、`choice`、`minigame` |
| Flag | 会影响故事的状态变量 | 好感度、是否修复设备 |
| effects | 一次剧情动作对状态的修改 | 好感度 +1、扣钥匙、给信件 |

`prologue.arrival` 表示“prologue 章节中的 arrival 节点”。

台词可以经常修改，ID 尽量稳定。存档靠节点 ID 找到玩家之前停在哪里。

### 2.1 文件速查

| 需求 | 编辑位置 |
| --- | --- |
| 改台词、选项、剧情顺序 | `data/chapters/prologue.json` |
| 加章节、改起点 | `data/game.json` |
| 新增好感度、布尔开关等变量 | `data/flags.json` |
| 新增角色名字 | `data/characters.json` |
| 新增/调整结局 | `data/endings.json` |
| 新增道具、图鉴正文 | `data/catalog.json` |
| 翻译文本 | `data/locales.json` |
| 调对话框位置、字号、颜色 | `scenes/main.tscn` |
| 新增小游戏 | `scenes/minigames/` 与 `scripts/minigames/` |
| 新增剧情指令 | `scripts/commands/` |

**当前使用的是 data/ 下的 V2 数据。** `story/demo.json` 是旧版示例，不是现在 F5 运行的剧本。

`res://` 表示项目目录，比如 `res://data/flags.json` 对应 `project-src/data/flags.json`。
`user://` 表示玩家数据目录，用于存档，不在项目源代码目录里。

## 3. 第一课：改一句台词

打开 `data/chapters/prologue.json`，找到 `arrival` 节点：

```json
{
  "id": "arrival",
  "op": "say",
  "speaker": "narrator",
  "text": "今天的海风，比往常更加安静。",
  "next": "gifts"
}
```

字段含义：

- `id`：这个节点的名字。
- `op: say`：显示对话，等玩家点击继续。
- `speaker`：characters.json 中声明的角色 ID。
- `text`：要显示的文字。`\n` 表示换行。
- `next`：玩家点击继续后去哪个节点。

**看到的结果：** 开场显示新台词，点击继续后仍然进入原来的发放道具流程。

开发运行时保存 JSON，约一秒后会尝试热重载。如果你当前正在其他节点，不会自动跳回这句台词；重开或用调试跳转查看。

### 3.1 新增一个角色

在 `data/characters.json` 的顶层对象中加入：

```json
"lina": {
  "name": "莉娜"
}
```

然后把某个对话节点的 `speaker` 改成 `"lina"`。

这是合并片段，要保留现有的 narrator、keeper；角色 ID 不等于玩家看到的名字。以后可以把“莉娜”改成其他显示名，剧本继续使用 lina。

## 4. 第二课：添加选择和好感度

现成 Flag `trust` 已在 flags.json 中声明：

```json
"trust": {
  "type": "int",
  "default": 0,
  "min": 0,
  "max": 10
}
```

含义是：整数，初始为 0，范围 0～10。

下面是可放进节点数组的局部片段；例子中的 next 使用现有 prologue 章节节点：

```json
{
  "id": "my_choice",
  "op": "choice",
  "speaker": "keeper",
  "text": "你愿意留下来吗？",
  "options": [
    {
      "text": "我愿意帮忙",
      "effects": {
        "add": {"trust": 1}
      },
      "next": "repair_intro"
    },
    {
      "text": "对不起，我得走了",
      "next": "film"
    }
  ]
}
```

把前一个节点的 next 指向 my_choice，玩家才会走到这里；**只添加节点不会自动插入剧情**。

选择第一项会让 trust 增加 1，再去修复介绍；第二项不改变量。

### 4.1 set 和 add 的区别

```json
{
  "set": {"trust": 3},
  "add": {"courage": 1}
}
```

- set 是直接赋值：无论之前是多少，trust 变成 3。
- add 是在原值基础上增加：courage 原来是 2，执行后就是 3。
- 同一次 effects 中先 set，再 add。

上述对象是 **effects 的内容**，使用时放在选项的 effects，或一个 `op: set` 节点中。

当前不会自动把越界数值截断到最大值。例如 trust 已经是 10，再加 1 会报错。要在剧情设计中避免可无限刷数值的循环。

### 4.2 声明一个“是否见过角色”的开关

向 flags.json 添加：

```json
"met_lina": {"type": "bool", "default": false}
```

在见面时用效果：

```json
"effects": {"set": {"met_lina": true}}
```

条件中用：

```json
"conditions": [{"flag": "met_lina", "value": true}]
```

布尔值使用 `true`/`false`，不是字符串 `"true"`/`"false"`。必须先声明变量，再在剧本里引用。

## 5. 第三课：控制选项是否出现

### 5.1 好感度足够才显示

```json
{
  "text": "询问她一直隐瞒的事情",
  "conditions": [
    {"flag": "trust", "op": ">=", "value": 2}
  ],
  "next": "repair_intro"
}
```

trust 小于 2 时，选项不显示。

### 5.2 同时满足好感度和持有道具

```json
"conditions": [
  {"flag": "trust", "op": ">=", "value": 2},
  {"item": "old_key", "op": ">=", "value": 1}
]
```

条件数组表示 **全部成立（AND）**。

当前没有直接的 OR 条件语法。需要“条件 A 或条件 B”时，可以用两个连续 branch 节点，任意一个成功都跳到同一目标。

至少保留一个无条件选项，避免玩家所有选项都不可用。

### 5.3 自动判定，不让玩家选择

```json
{
  "id": "trust_check",
  "op": "branch",
  "conditions": [
    {"flag": "trust", "op": ">=", "value": 1}
  ],
  "then": "repair_intro",
  "else": "film"
}
```

它不会显示选择按钮，条件成立走 then，否则走 else。

## 6. 第四课：道具系统

把道具理解为两部分：

1. **定义**：名字、描述、类型、最多持有多少，在 catalog.json。
2. **数量**：这个周目玩家实际持有什么，在 GameState 和进度存档。

### 6.1 在剧情中发放现有道具

```json
{
  "id": "give_tea",
  "op": "set",
  "effects": {
    "inventory": {"tea": 2}
  },
  "next": "invitation"
}
```

玩家获得两杯热茶。获得时会自动解锁该道具定义的 entry 图鉴。

**不要把发奖 effects 放在 say 节点上。** 纯展示节点不会执行发奖，应该像上面一样用独立 set 节点。

### 6.2 交出钥匙，获得信件

```json
{
  "text": "用旧钥匙打开档案柜",
  "conditions": [
    {"item": "old_key", "op": ">=", "value": 1}
  ],
  "effects": {
    "inventory": {
      "old_key": -1,
      "letter": 1
    }
  },
  "next": "letter_found"
}
```

正数是获得，负数是消耗。数量降到 0 后，道具从背包移除。
同一 effects 会先整体校验：如果钥匙不足或信件数量超限，不会发生“钥匙扣了，信却没拿到”的部分提交。

### 6.3 新增一个消耗品

向 `catalog.json → items` 添加：

```json
"mint": {
  "name": "薄荷糖",
  "category": "消耗品",
  "description": "吃下后，鼓起一点勇气。",
  "max_stack": 5,
  "usable": true,
  "consume": true,
  "effects": {
    "add": {"courage": 1}
  }
}
```

然后在剧情 set 节点的 effects 中放：

```json
"inventory": {"mint": 2}
```

**运行结果：** 背包显示两颗薄荷糖。点“使用”，数量减一，courage 加一。
如果 courage 加一会越界，这次使用失败，薄荷糖不会被扣除。

### 6.4 关键道具与可反复阅读的线索

| 配置 | 行为 |
| --- | --- |
| 不写 usable，或设为 false | 背包不能直接使用，由剧情选项消耗或判断 |
| usable=true、consume=true | 使用后消耗一份 |
| usable=true、consume=false | 使用后仍然保留，可用于阅读信件等 |

当前背包以文字、分类和数量展示。尚未实现格子拖拽、装备槽或道具合成；如果后面需要，这些可以作为独立玩法扩展。

## 7. 第五课：图鉴系统

图鉴与背包不同：**道具被消耗不代表玩家忘记发现过它**。

### 7.1 添加秘密线索

向 `catalog.json → entries` 添加：

```json
"tower_secret": {
  "name": "灯塔的旧约定",
  "category": "线索",
  "description": "每年这个时候，守塔人都会点亮一盏额外的灯。",
  "secret": true
}
```

在发现秘密的剧情节点使用：

```json
{
  "id": "discover_secret",
  "op": "set",
  "effects": {
    "unlock": ["tower_secret"]
  },
  "next": "repair_intro"
}
```

未解锁时名字显示 ???、正文隐藏；解锁后可在图鉴查看。

### 7.2 获得道具时收录，使用道具时阅读

道具可以同时配置：

```json
"entry": "item_letter",
"use_unlock": "letter_story"
```

以现有 letter 为例：

- 获得信件 → 收录“未寄出的信”。
- 在背包中使用信件 → 解锁“写给远方”的线索正文。

这两个 ID 必须已经存在于 entries。

### 7.3 哪些内容会随读档回退？

| 内容 | 读旧档 | 重新开始 |
| --- | --- | --- |
| Flag，例如好感度 | 恢复存档值 | 恢复默认值 |
| 背包数量 | 恢复存档数量 | 清空，再按剧情发放 |
| 已发现图鉴 | 保留 | 保留 |

所以玩家可以多周目探索，逐步收齐图鉴。

## 8. 第六课：多结局不堆满分支

剧本末尾只需一个节点：

```json
{"id": "finale", "op": "ending"}
```

具体结局交给 endings.json 判定。现有逻辑是：

| 优先级 | 条件 | 结局 |
| --- | --- | --- |
| 100 | trust ≥ 1，而且小游戏成功 | 灯火相连 |
| 50 | trust ≥ 1 | 一起等待 |
| 0 | 无条件 | 海岸独行 |

按优先级从高到低检查，选第一个满足条件的条目。小游戏成功时通常也满足第二条，但第一条优先，所以仍得到“灯火相连”。

### 8.1 新加一个更高优先级的结局

向 endings.json 数组添加一个对象：

```json
{
  "id": "brave_reunion",
  "priority": 120,
  "conditions": [
    {"flag": "trust", "op": ">=", "value": 1},
    {"flag": "courage", "op": ">=", "value": 2},
    {"flag": "puzzle.success", "value": true}
  ],
  "title": "隐藏结局 · 勇敢的重逢",
  "text": "这一次，你先向远方发出了邀请。"
}
```

不必改 finale 节点。满足新条件时，新结局排在原来的优先级 100 之前。

如果还想把它收入图鉴，先新增 entries 条目，再给结局添加 `"entry": "你的图鉴ID"`。

注意：

- id 和 priority 都不能重复。
- 必须有且只有一个空条件兜底结局。
- 兜底结局必须拥有最低优先级。
- 改结局条件会影响后续到达终章的判定，已经解锁的图鉴仍保留。

## 9. 完整实战：复制一份可以运行的短剧本

本指南附带完整文件：**[examples/tutorial.json](examples/tutorial.json)**。

它直接复用当前项目已有的角色、Flag、道具、图鉴、小游戏与结局定义，不需要再声明新的内容。

操作：

1. 把 `docs/examples/tutorial.json` 复制成 `data/chapters/tutorial.json`。
2. 在 game.json 的 chapters 数组里保留原章节，再加入新章节：
3. 把 start 改为 `tutorial.start`。
4. 重新开始游戏。

game.json 中只调整下面两项，其余内容保留：

```json
"start": "tutorial.start",
"chapters": [
  "res://data/chapters/prologue.json",
  "res://data/chapters/tutorial.json"
]
```

保留 prologue 是因为当前 node_aliases 中还引用它，用于旧存档迁移。
不要把上面这个片段当成整个 game.json。也不需要因这次练习改剧情 id 或 version。

完整剧本如下：

```json
{
  "id": "tutorial",
  "nodes": [
    {
      "id": "start",
      "op": "say",
      "speaker": "narrator",
      "text": "你在灯塔门口遇到了守塔人。",
      "next": "supplies"
    },
    {
      "id": "supplies",
      "op": "set",
      "effects": {
        "inventory": {
          "old_key": 1,
          "tea": 1
        },
        "unlock": [
          "keeper",
          "lighthouse"
        ]
      },
      "next": "decision"
    },
    {
      "id": "decision",
      "op": "choice",
      "speaker": "keeper",
      "text": "能帮我修复信号装置吗？你也许能在档案柜里找到线索。",
      "options": [
        {
          "text": "用钥匙打开档案柜，再帮忙修复",
          "conditions": [
            {
              "item": "old_key",
              "op": ">=",
              "value": 1
            }
          ],
          "effects": {
            "inventory": {
              "old_key": -1,
              "letter": 1
            },
            "add": {
              "trust": 1
            }
          },
          "next": "found"
        },
        {
          "text": "离开灯塔",
          "next": "finale"
        }
      ]
    },
    {
      "id": "found",
      "op": "say",
      "speaker": "narrator",
      "text": "你找到一封未寄出的信。\n先打开背包使用它，再查看图鉴中的线索。也可以喝掉热茶。",
      "next": "trial"
    },
    {
      "id": "trial",
      "op": "minigame",
      "scene": "res://scenes/minigames/signal_game.tscn",
      "text": "收集三个信号，修复装置。",
      "config": {
        "target": 3
      },
      "result_map": {
        "success": "puzzle.success",
        "score": "puzzle.score"
      },
      "next": "finale"
    },
    {
      "id": "finale",
      "op": "ending"
    }
  ]
}
```

试玩检查：

1. 开场继续后拿到钥匙和热茶。
2. 选择打开档案柜，钥匙消失，出现信件。
3. 在 found 节点先开背包：喝茶、阅读信件，再看图鉴。
4. 继续进入小游戏。
5. 成功、放弃、开场直接离开，分别得到三种结局。

恢复原演示时，把 start 改回 `prologue.arrival`。练习期间不要覆盖你希望保留的正式进度存档。

## 10. 第七课：新增章节与背景立绘

### 10.1 新建章节

一个新章节最少可以这样写：

```json
{
  "id": "chapter_2",
  "nodes": [
    {
      "id": "start",
      "op": "say",
      "speaker": "narrator",
      "text": "第二天，你再次来到灯塔。",
      "next": "prologue.invitation"
    }
  ]
}
```

保存到 `data/chapters/chapter_2.json`，把路径加入 game.json 的 chapters。
在其他章节中写 `"next": "chapter_2.start"`，就能跳进来。

### 10.2 设置背景和立绘

先把真实图片放进项目，例如：

```text
assets/backgrounds/coast_evening.png
assets/portraits/keeper_normal.png
```

再给显示节点加：

```json
"background": "res://assets/backgrounds/coast_evening.png",
"portrait": "res://assets/portraits/keeper_normal.png"
```

资源必须存在。下一显示节点如果仍要相同画面，需要继续填写这两个字段；**当前不自动继承上一节点画面**。

主场景目前是一张背景和一个立绘槽位，多角色同屏、立绘移动动画还需扩展表现层。

## 11. 第八课：接入自己的小游戏

现有小游戏是“收集三次信号”。下面用“选中正确按钮”说明如何替换。

### 11.1 创建独立场景

新建 `scenes/minigames/answer_game.tscn`：

```text
AnswerGame（Control，根节点设为全矩形）
└─ VBoxContainer
   ├─ Prompt（Label）
   ├─ Correct（Button）
   └─ Wrong（Button）
```

给根节点挂脚本 `scripts/minigames/answer_game.gd`：

```gdscript
extends "res://scripts/core/minigame.gd"

func begin(config: Dictionary, _story_variables: Dictionary) -> void:
    $VBoxContainer/Prompt.text = str(config.get("question", "哪个方向是海岸？"))
    $VBoxContainer/Correct.text = "向东"
    $VBoxContainer/Wrong.text = "向西"

    $VBoxContainer/Correct.pressed.connect(
        func(): finish({"success": true, "score": 1})
    )
    $VBoxContainer/Wrong.pressed.connect(
        func(): finish({"success": false, "score": 0})
    )
```

场景树的名字要与脚本路径一致。begin 在节点加入树后调用；finish 会保证只发一次完成结果，宿主负责销毁场景。

### 11.2 剧情中引用它

```json
{
  "id": "answer_trial",
  "op": "minigame",
  "scene": "res://scenes/minigames/answer_game.tscn",
  "text": "判断海岸所在的方向。",
  "config": {
    "question": "海岸在地图的哪一侧？"
  },
  "result_map": {
    "success": "puzzle.success",
    "score": "puzzle.score"
  },
  "next": "finale"
}
```

result_map 的左边是小游戏返回字段，右边是剧情 Flag：

| 小游戏返回 | 剧情收到 |
| --- | --- |
| success=true | puzzle.success=true |
| score=1 | puzzle.score=1 |

config 和传入的 Flag 都是副本。小游戏不能通过直接修改它们来改变剧情，应该通过 finish 回传结果。
未映射的返回字段忽略；映射字段没返回时使用对应 Flag 默认值；类型/范围不合法会报错。

**存档行为：** 在小游戏中保存，读档会重新开始这个小游戏，不恢复做到一半的内部状态。

## 12. 第九课：视频过场

先放入 Godot 能加载的真实视频资源，再引用：

```json
{
  "id": "film",
  "op": "video",
  "path": "res://assets/video/opening.ogv",
  "skippable": true,
  "result_map": {
    "played": "film.played",
    "skipped": "film.skipped"
  },
  "next": "finale"
}
```

- 自然播完：played=true，skipped=false。
- 主动跳过：played=false，skipped=true。
- path 为空：自动跳过，方便先搭流程后补素材。
- skippable=false：不显示跳过按钮。
- 读档、重建当前视频节点：从视频开头开始。

现有项目尚无真实视频素材，实际解码还需要放入素材后验证。先使用 .ogv；不要假设 MP4 可以直接播放。

## 13. 第十课：本地化

直接写中文可以正常工作；要支持多语言时，把文本改成 key。

在 locales.json 的两个语言对象中分别加入：

```json
"zh_CN": {
  "keeper_question": "你愿意留下来吗？"
},
"en": {
  "keeper_question": "Will you stay?"
}
```

这是合并示意，保留已有语言表内容。剧本改用：

```json
"text": "@keeper_question"
```

中文模式显示中文，点击“中/EN”切换后显示英文。
英文缺失时回退到 zh_CN。不带 @ 的文本原样显示，不会自动翻译。
当前系统是简单 key 查表，不支持复数规则或 `{trust}` 等变量插值。

## 14. 第十一课：存档与迭代

### 14.1 目前保存什么

进度存档包含：剧情 ID、剧情版本、当前等待节点、Flag、背包数量、语言。
图鉴发现记录独立保存。

当前主界面只有一个存档槽位：`slot_1.json`。

在 Windows 当前项目名未改变时，玩家数据一般位于：

```text
%APPDATA%\Godot\app_userdata\ProjectSrc\saves\
```

具体以 Godot 的 user:// 目录为准。项目名称改变后用户目录也可能改变。

### 14.2 哪些修改要做迁移

| 修改 | 通常如何处理 |
| --- | --- |
| 改台词、改图片 | 保留稳定 ID，一般无需迁移 |
| 新增带默认值的 Flag | 读档会补默认值，仍应检查业务影响 |
| 重命名/删除节点 | 编写节点映射或迁移 |
| 重命名 Flag、改变类型或范围 | 编写明确的状态迁移 |
| 大幅改变故事结构 | 提升剧情 version，并实现对应迁移函数 |

当前已有 V1 → V2 迁移。未来 V2 → V3 需要在 `scripts/services/save_migrations.gd` 增加分支和函数。

**示意，不是现在需要执行的修改：**

```gdscript
# 在 migrate() 的版本分支中新增：
# 2: data = _v2_to_v3(data, bundle)

func _v2_to_v3(data: Dictionary, _bundle: Dictionary) -> Dictionary:
    var flags: Dictionary = data["state"]["flags"]
    if flags.has("trust"):
        flags["affinity"] = flags["trust"]
        flags.erase("trust")
    return data
```

如果真的这样迁移，还必须把 Flag 定义和所有剧情引用改为 affinity，并将 game.json.version 改为 3。
只改 version 不会自动完成业务迁移，缺少函数时加载会被拒绝。

## 15. 第十二课：热重载与调试

### 15.1 用热重载快速改台词

1. F5 启动，停在某句台词或某组选项。
2. 修改它对应 JSON 的 text。
3. 保存文件。
4. 约一秒后显示新内容；也可以在 F1 控制台输入 reload。

无效修改不会覆盖上一份可用剧本。当前节点被删除、当前 op 改变或当前状态不满足新 Flag 定义时，会拒绝热重载。

如果修改了 GDScript，或要测试从头发放道具的流程，重新运行更直接。

### 15.2 调试命令举例

按 F1 打开控制台：

```text
get
set trust 2
set puzzle.success true
jump prologue.finale
```

这样可以快速预览高优先级结局。还可以输入：

```text
nodes
history
reload
```

nodes 列出完整节点 ID；history 显示最近执行过的节点；reload 手动重载数据。

字符串 Flag 赋值必须使用 JSON 字符串。例如你已经声明 route 后：

```text
set route "friend"
```

跳转携带当前状态，**不是回到那个时间点的历史状态**。跳转目标之后的普通指令仍可能改变道具和 Flag。
进入调试预览后不写正式进度存档，预览结局不解锁结局；重新开始恢复正常玩法。

## 16. 进阶：新增指令或监听事件

通常写内容不需要修改核心。已有 `emit` 可以通知其他模块：

```json
{
  "id": "arrival_effect",
  "op": "emit",
  "event": "entered_lighthouse",
  "payload": {"chapter": "prologue"},
  "next": "invitation"
}
```

一个新服务可以监听它：

```gdscript
extends Node

func _ready() -> void:
    EventBus.custom_event.connect(_on_event)

func _on_event(event_name: String, payload: Dictionary) -> void:
    if event_name == "entered_lighthouse":
        print("玩家进入灯塔，来自章节：", payload.get("chapter", ""))
```

把监听脚本挂到实际运行的节点，或注册为 Autoload；仅创建文件并不会开始监听。

未来可以让该监听者播放音效、处理成就或打开画廊。当前并未附带完整音频、成就、画廊业务系统。

### 16.1 一个新命令类

在 `scripts/commands/notify.gd` 新增：

```gdscript
extends "res://scripts/core/command.gd"

func command_name() -> String:
    return "notify"

func is_checkpoint() -> bool:
    return false

func validate(context, node: Dictionary) -> void:
    context.required(node, "message", TYPE_STRING)
    context.target(node)

func execute(_runtime, node: Dictionary) -> Dictionary:
    EventBus.notification.emit(node["message"])
    return {"status": "goto", "target": node["next"]}
```

重启运行后会被自动注册。剧本可以写：

```json
{"id":"notice","op":"notify","message":"你听见了远处的钟声。","next":"invitation"}
```

解释器无需添加新的分支。这个 notify 是即时通知，可能被下一节点状态栏更新覆盖；要让玩家必须读完并确认，直接使用 say，或实现等待型视图。

自动执行的指令要声明 is_checkpoint=false。等待型指令的 execute 必须可安全重建，不能一重绘就发一次奖励。
如果要新增独特的显示界面，还需要实现对应的表现层组件，命令注册不会自动生成 UI。

## 17. 常见问题

| 现象 | 常见原因与处理 |
| --- | --- |
| 改了台词没有效果 | 编辑了旧 story/demo.json；或当前没有停在被改节点 |
| 未知 Flag：trsut | 名字拼错，或未在 flags.json 声明 |
| 不存在的节点 | next 拼错，跨章节缺少章节 ID，或章节未加入 chapters |
| 选项不显示 | conditions 不满足；用 F1 get 检查实际状态 |
| 道具使用失败 | 数量不足、达到上限或效果使 Flag 越界 |
| 给 say 写 effects 却没发道具 | 用独立 set 节点，或把 effects 放在 choice 选项里 |
| 新结局一直触发不了 | 更高优先级结局先命中，或其条件没满足 |
| 图鉴重开后还在 | 这是跨周目设计，不随进度重置 |
| 读档后小游戏重新开始 | 当前只保存小游戏节点起点 |
| 修改范围后热重载失败 | 现有 Flag 值与新定义不兼容；需要迁移或重开 |
| 游戏内调试后不能保存 | 当前处于调试预览，重新开始恢复正常模式 |
| 导出后找不到剧情 | 导出预设需包含 data JSON；详见 README 的导出说明 |

报错如：

```text
res://data/chapters/prologue.json:39: 未知 Flag：trsut
```

表示检查该文件第 39 行附近。不要通过关掉校验绕过它，修正对应数据即可。

## 18. 建议的日常开发节奏

一次先完成一个可以玩的片段：

1. 写两到五个节点。
2. 增加这段需要的 Flag、道具、图鉴条目。
3. 把它连接到现有剧情中。
4. 跑一遍正常路线和另一种选择。
5. 保存一次、读档一次。
6. 最后再加入图片、视频和演出细节。

如果改了框架代码，可运行现有测试场景：

```text
godot --headless --path <project-src目录> res://tests/framework_v2.tscn
```

只改几句台词不需要每次跑完整测试。先把流程写顺，比一开始就堆很多分支更容易维护。

