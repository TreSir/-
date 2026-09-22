# 《黑页》

基于 Godot 4.7 与 GDScript 开发的 2D 手绘动漫风悬疑视觉小说。

玩家在调查失踪案、整理证据和与人物交涉的同时，可以使用一本以真实姓名改变人物生死的黑色笔记。项目强调三件事：**剧情数据易编辑、系统边界可扩展、错误状态尽早暴露。**

## 当前状态

当前仓库是可运行的纵向切片，不是完整成品。

| 已实现 | 规划中 |
| --- | --- |
| 启动页、序章、第一章开场与首案调查 | 第二、三章及终章的完整数据 |
| 数据驱动台词、条件、跳转和对话选择 | 更多调查地点与人物演出 |
| 场景调查、线索、案件、人物图鉴 | 资金图谱、证据质询、档案拼合等小游戏 |
| 黑页落笔、延迟死亡、错误姓名 | 跨三章的最终结局条件 |
| 普通存档、落笔检查点、断链回溯 | 存档迁移与多槽位界面 |
| 演出时间轴、音频、转场、打字机 | 完整美术、发行包与平台适配 |
| JSON 热重载与加载期校验 | 面向策划的可视化剧情编辑器 |

完整剧情以 [《黑页》完整剧情大纲](docs/黑页_完整剧情大纲.md) 为制作基线；当前工程边界以本 README 和仓库代码为准，[架构与死亡笔记玩法设计](docs/Godot_悬疑侦查游戏_架构与死亡笔记玩法设计.md) 只保留设计背景与长期方向。

## 快速开始

要求：

- Godot 4.7.x；当前工程特性版本为 `4.7`
- Python 3，仅用于运行静态架构审计

运行方式：

1. 使用 Godot 打开仓库根目录的 `project.godot`。
2. 按 `F5` 启动主场景。
3. 首次拉取或资源发生变化时，先执行一次资源导入。

```bash
godot --headless --path . --import
godot --path .
```

主场景为 `res://scenes/black_page/main.tscn`，基准视口为 `1280 × 720`。

## 架构概览

```text
data/black_page/*.json
        │  加载、类型与引用校验
        ▼
DataLoader ──► NarrativeRunner / Rules / 各领域系统
        │                       │
        │                       ▼
        └──────────────► Investigation
                                │ 唯一游戏写入口
                                ▼
                    GameState + SaveManager + EventBus
                                │
                                ▼
              Main UI / PerformanceDirector / MiniGameManager
```

### 四层职责

| 层 | 主要位置 | 负责什么 |
| --- | --- | --- |
| 数据层 | `data/black_page/` | 剧情、Flag、人物、线索、案件、结局、演出和小游戏配置 |
| 核心层 | `scripts/core/` | 剧情解释、规则求值、案件、图鉴、黑页、存档格式和通用组件 |
| 服务层 | `scripts/services/` | `GameState` 世界状态与真正跨场景的 `EventBus` |
| 表现层 | `scripts/black_page/`、`scenes/` | UI、输入、场景、动画、音频、演出和小游戏承载 |

`scripts/black_page/investigation.gd` 是应用门面：表现层通过它读取和修改游戏状态。它负责事务提交、行动锁、案件结算、黑页结算、存档和热重载，但不负责绘制 UI。

当前只把 `GameState`、`EventBus` 和可选的 Godot MCP Runtime 注册为 Autoload。其他系统按场景生命周期实例化，不为“调用方便”滥用全局单例。

## 不可破坏的工程约束

1. **只有 `investigation.gd` 可以提交 GameState 修改。**核心规则可以计算候选状态，表现层不能直接写 Flag。
2. **表现层不读取 JSON 文件。**所有内容统一经过 `data_loader.gd` 编译和校验。
3. **所有 Flag 必须先在 `flags.json` 声明类型、默认值和范围或枚举。**拼错变量名必须在加载期报错。
4. **状态修改采用事务。**先复制快照、应用效果、验证全部世界约束，再整体提交；失败时原状态保持不变。
5. **异步调查使用 ticket。**过期的小游戏或调查回调不能污染新世界状态。
6. **同一时间最多一个活动案件。**宏观章节单线，案件内部允许自由调查。
7. **小游戏只返回标准结果。**剧情分支由 NarrativeRunner 根据结果 Flag 判断，小游戏不能直接跳剧情。
8. **死亡笔记执行前创建独立检查点。**关键因果断裂时由 FailureManager 提供回溯，不覆盖普通存档。
9. **UI 只消费状态。**图鉴解锁、人物死亡、线索取得和结局判定均由数据效果或领域系统产生。

## 剧情数据

所有普通剧情都写在 `data/black_page/stories.json`，由同一个 `NarrativeRunner` 从上到下解释。序章、章节对白和系统剧情不另建第二套播放器。

### 支持的剧情命令

| 命令 | 用途 |
| --- | --- |
| `say` | 播放一段或多段台词 |
| `choice` | 显示经过条件过滤的对话选项，并应用效果或跳转 |
| `effect` | 修改声明过的 Flag 或道具数量 |
| `clue` | 取得线索并触发线索附带效果 |
| `unlock` | 解锁人物图鉴 |
| `unlockinfo` | 解锁人物的一条档案信息 |
| `if` | 根据 Flag 或道具条件跳转 |
| `goto` | 跳转到同一剧情的其他节点 |
| `sequence` | 等待一段重点演出完成 |
| `minigame` | 等待小游戏返回标准结果 |

### 对话选择示例

```json
{
  "choice": {
    "prompt": "林墨：她失联前，有没有留下异常信息？",
    "options": [
      {
        "text": "把断线电话原样告诉他。",
        "effects": {
          "set": {"story.chapter1_report_style": "honest"},
          "add": {"linmo_trust": 5}
        },
        "goto": "report_honest"
      },
      {
        "text": "先查监控。",
        "goto": "report_direct"
      }
    ]
  }
}
```

每个选项可以声明：

- `requires`：显示该选项必须满足的条件；
- `effects`：选择后通过统一状态入口执行的效果；
- `goto`：选择后进入的剧情节点。

加载器会校验条件中的 Flag、效果类型和目标节点，并要求每组选择至少保留一个无条件选项，避免运行时无路可走。界面只能展示文字并回传序号，不能自行决定效果或跳转。

### 条件与效果

```json
{
  "requires": [
    {"flag": "linmo_trust", "op": ">=", "value": 40},
    {"item": "camera", "op": ">=", "value": 1}
  ],
  "effects": {
    "set": {"person.xu.status": "hidden"},
    "add": {"linmo_trust": 5},
    "inventory": {"camera": 1}
  }
}
```

条件支持 `==`、`!=`、`>=`、`>`、`<=`、`<`；大小比较仅用于数值。`set` 必须写入合法类型，`add` 仅支持数值 Flag，道具增减使用 `inventory`。

## 数据文件索引

| 文件 | 内容 |
| --- | --- |
| `stories.json` | 剧情节点与命令流 |
| `flags.json` | 强类型状态声明、默认值、范围与枚举 |
| `people.json` | 人物静态资料、死亡文本与死亡连锁效果 |
| `codex.json` | 人物图鉴的分阶段资料 |
| `clues.json` | 线索、可信度、关联人物和取得效果 |
| `actions.json` | 调查行动、进入条件、正文与奖励 |
| `cases.json` | 案件状态、疑点与结案裁定 |
| `events.json` | 日期或状态触发事件 |
| `endings.json` | 按优先级判定的结局条件 |
| `sequences.json` | BGM、音效、淡入淡出、震动、闪白和等待 |
| `minigames.json` | 小游戏场景路径与启动参数 |
| `transitions.json` | 场景和行动级转场配置 |

新增数据文件时，需要同时加入 `data_loader.gd` 的加载列表并提供相应校验。普通剧情内容扩写不需要新增文件，也不需要修改 GDScript。

## 常用开发入口

| 需求 | 修改位置 |
| --- | --- |
| 增删剧情、对白或选择 | `data/black_page/stories.json` |
| 新增 Flag | `data/black_page/flags.json` |
| 新增调查行动 | `actions.json`，必要时补 `scenes.gd` 和 `transitions.json` |
| 新增人物或图鉴条目 | `people.json`、`codex.json`、`flags.json` |
| 新增重点演出 | `sequences.json`；新动作类型才修改 `performance_director.gd` |
| 新增小游戏 | 独立 Scene + `minigames.json`；实现统一 `finished(result)` 契约 |
| 调整视觉规范 | `scripts/black_page/ui_style.gd` |
| 调整房间热区 | `scripts/black_page/hotspots.gd` |
| 调整场景资源映射 | `scripts/black_page/scenes.gd` |
| 调整音频资源映射 | `scripts/black_page/audio_tracks.gd` |

调试构建中按 `F6`，或在游戏菜单中选择“重载数据”，可以在保留当前进度的情况下重新编译 JSON。结构或引用错误会带文件路径和数据位置返回，不会用坏数据覆盖当前 bundle。

## 存档与回溯

- 普通进度：`user://saves/black_page_slot_1.json`
- 黑页检查点：`user://saves/black_page_slot_checkpoint.json`
- 玩家偏好：独立保存，不随新游戏清空
- 当前存档结构：`schema = 1`，内容标识为 `black_page_mvp2`

存档读取会验证 Flag 类型、道具数量、单活动案件约束、待结算姓名、日志上限和结局 ID。结构不匹配时整份拒绝，不进行不完整恢复。

## 验证标准

每次修改代码或数据后运行：

```bash
python tools/audit.py
godot --headless --path . res://tests/black_page_smoke.tscn
```

当前验收结果应包含：

```text
BLACK_PAGE: PASS (... checks)
```

以进程退出码和完整 PASS 行为准，检查数量会随用例增长，不作为固定规范。测试中的部分 warning 来自故意执行的错误路径、断链和缺回调用例；出现脚本解析错误、资源加载失败或 `BLACK_PAGE CHECK FAILED` 才表示验收失败。

修改字体、图片或音频后，先重新导入资源再测试：

```bash
godot --headless --path . --import
```

## 完成定义

一项功能只有同时满足以下条件才算完成：

- 内容与代码职责放在正确层级；
- 新状态已在 `flags.json` 声明并经过校验；
- 异步路径不存在重复结算或遗留行动锁；
- 错误、取消、回溯和读档路径能够收场；
- `tools/audit.py` 退出码为 0；
- 冒烟测试完整通过；
- 对内容作者可见的新能力已在 README 或对应设计文档中说明。

## 目录结构

```text
project-src/
├── data/black_page/       # 可编辑内容数据
├── docs/                  # 架构、完整剧情与素材规范
├── scenes/black_page/     # 主场景与小游戏场景
├── scripts/core/          # 无 UI 的通用核心
├── scripts/services/      # GameState、EventBus
├── scripts/black_page/    # 本作应用门面与表现层
├── tests/                 # Headless 冒烟测试
├── tools/audit.py         # 静态架构审计
└── project.godot
```

## 素材与发布

美术素材目前包含 AI 辅助生成和占位资源，完整清单见 [美术资源说明](docs/ART_ASSETS.md)。音效与音乐包含 CC0 / CC-BY 素材；发布时必须按 [音频署名清单](assets/audio/CREDITS.md) 完成署名。

导出发行包前，还需要验证 JSON 数据被包含在构建中，并完成一次非编辑器环境的全流程测试。
