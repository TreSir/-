# 《黑页》架构规约

> 这份文档是**改代码的规矩**，不是介绍。加功能、改数据、拆结构之前先读它。
> 与代码不一致时，**以本文档为准去改代码**；确实要变规矩，先改本文档再改代码。

---

## 一、一句话

**表现层永远不碰状态，只调 `investigation` 的公开方法。**

这条撑住了整个项目：引擎层零 UI 依赖，所以能 headless 跑完 80 项测试。

---

## 二、三层结构（严格单向）

```
表现层  scripts/black_page/*.gd          ← 界面、演出、输入
   │  只调 investigation 的公开方法
   ▼
引擎层  investigation.gd + services/ + core/   ← 规则、状态、存档。零 UI 依赖
   │  唯一持有者：GameState
   ▼
数据层  data/black_page/*.json + data_loader.gd  ← 声明式内容
```

### 三条铁律

| # | 规矩 | 怎么验证 |
| --- | --- | --- |
| **1** | **只有 `investigation.gd` 能写 `GameState`** | 全项目 grep `GameState.`，只应命中 `investigation.gd` |
| **2** | **界面不读数据文件**，一律走 `game.bundle` / `game.xxx()` | grep 界面层有没有 `FileAccess` / `JSON.parse_string` |
| **3** | **数据只经 `data_loader` 加载并校验** | grep 加载列表；界面层不该有 `preload("res://data/...")` |

> 第 2、3 条以前被违反过：序章曾经自己 `FileAccess` + `JSON.parse_string` 读剧本，
> 结果是字段写错**静默什么都不显示**。已经统一进 `data_loader`。

---

## 三、目录与职责

### `scripts/black_page/` —— 黑页自己（13 个）

| 文件 | 职责 | 关键约束 |
| --- | --- | --- |
| `main.gd` | 主界面。场景切换、底部对话、中央选项、侧栏、弹层、转场、输入分发 | 只调 `game.xxx()`；不读数据文件 |
| `prologue.gd` | 序章演出。逐页推进，支持四种演出卡片 | 剧本从 `bundle.prologue` 拿；写状态走 `game.apply_state()` |
| `investigation.gd` | **游戏逻辑中枢**。行动可用性、结算、落笔、结束一天、结局判定 | **唯一允许写 `GameState` 的地方** |
| `data_loader.gd` | 编译 `data/black_page/*.json` → `bundle`；字段校验 + 跨文件引用检查 + 规范化 | 加数据文件必须同时改这里的加载列表 |
| `ui_style.gd` | 视觉令牌 + 控件工厂。所有 UI 构件从这儿造 | 颜色/字号/间距只在这里定义 |
| `scenes.gd` | 场景表：场景 id → 名称 + 贴图 | 加场景要同时配 `transitions.json` |
| `hotspots.gd` | 房间背景上的可点热区（UV 比例） | `target` 必须能在 `main._hotspot_pressed` 里找到分支 |
| `timeline.gd` | 监控排序小游戏 | 继承 `core/minigame.gd` |
| `launch.gd` | 启动页 | — |
| `room.gd` | 房间背景：正式插画 + 程序化雨丝/暗角 | 只管画面，热区归 `main.gd` |
| `bgm_player.gd` | 背景音乐，双缓冲淡入淡出 | 换曲目去改 `audio_tracks.gd` |
| `rain_ambience.gd` | 雨声环境音 | 同上 |
| `audio_tracks.gd` | 音频素材清单 | **换曲目只改这里** |

### `scripts/services/` —— 全局服务（2 个 Autoload）

| 文件 | 职责 |
| --- | --- |
| `game_state.gd` | **状态的唯一持有者**。`flags` / `inventory`，提供 `snapshot` / `validate_snapshot` / `restore` / `apply` |
| `event_bus.gd` | 跨场景事件总线。**只有真正跨场景的事件才在这里加信号** |

> 曾经有 5 个 Autoload，其中 3 个（`save_service` / `collections` / `localization`）是空转的，已删。
> **加 Autoload 前先问：这个状态真的跨场景吗？** 单场景内部的事情用局部信号。

### `scripts/core/` —— 与内容无关的机制（4 个）

| 文件 | 职责 |
| --- | --- |
| `rules.gd` | 纯函数式的旗标规则求值。`data_loader` / `investigation` / `game_state` 共用 |
| `json_source.gd` | JSON 读取 + source map（报错能定位到文件与行号） |
| `save_store.gd` | 存档文件读写 |
| `minigame.gd` | 小游戏基类。子类自己 emit 一次 `finish({...})` |

---

### 怎么判断一段代码该放哪：三条判据，按顺序问

**① 把「黑页」这个词换掉，这段代码还成立吗？**

成立 → 通用，进  或 ；不成立 → 业务，留在 。

| 通用（换游戏也能用） | 业务（绑死黑页） |
| --- | --- |
|  条件求值 |  三次行动 / 落笔 / 侵蚀度 |
|  JSON + 行号 |  颜色字号（这是黑页的视觉语言） |
|  存档读写 |  场景表 |
|  逐字显示 |  的热区表 |
|  UV 热区层 |  /  的演出 |
|  小游戏契约 | |
|  强类型状态 | |
|  事件总线 | |

**② 同一个机制，出现第二次了吗？**

**出现第二次就该提取。** 第二次出现是真实需求，不是猜的。

已经按这条提取出来的：

| 组件 | 原来重复在哪 |
| --- | --- |
|  |  与  各写一套逐字显示，连「先补完再翻页」都重复 |
|  | 序章与房间各写一套 UV 热区，**连换算都重复了一份** |

**③ 只有一个使用者，而且看得到未来也不会有第二个？**

→ **就地写，别通用。**

### 强行通用的三个症状（出现任一就说明提早了）

1. **参数比使用者还多**
2. **为了照顾 A，B 得传一堆用不上的东西** → 正确做法是把 A 的装饰做成**可选回调**，
   排除在公共路径之外（ 的  就是这么处理的：
   房间要悬停辉光与调试标签，序章不需要，所以它不在公共参数里）。
3. **改一处要动三个文件**

### 提取出来放哪



## 四、数据管线（全项目**只有一条**）

```
data/black_page/*.json
      │
      │  data_loader.compile()
      │    · 逐文件读 + 字段类型校验
      │    · 跨文件引用检查（clues/people/cases 的引用必须可解析）
      │    · 规范化成运行时形状
      ▼
   bundle（内存字典）
      │
      ├──▶ investigation.gd    （读 bundle 判断与结算）
      ├──▶ prologue.gd         （读 bundle.prologue 演序章）
      └──▶ main.gd             （读 bundle 画界面）
      │
      ▼
   GameState（唯一状态真相源，Autoload）
      │  changed 信号
      ▼
   main.gd（刷新界面）
```

**加一个新数据文件要动三处**：`data/` 下建 json → `data_loader` 的加载列表 → 需要校验就加校验函数。
漏了第一步或第二步，都会在启动时直接报错（这是设计如此）。

---

## 五、`investigation` 的公开 API（表现层只能用这些）

### 读

| 方法 | 用途 |
| --- | --- |
| `flag(id)` / `owns(id)` / `person_flag(id, field)` | 查状态 |
| `person_name(id)` | 显示名（按身份确认度决定用真名还是假名） |
| `matches(conditions)` | 条件求值（`requires` 那套） |
| `available(action_id)` | 这条行动现在能不能做 |
| `snapshot()` / `flags_snapshot()` | 整份状态 / 只读旗标快照 |
| `bundle` | 编译后的数据 |

### 写（**只有这几个口子**）

| 方法 | 用途 | 说明 |
| --- | --- | --- |
| `new_game()` / `load_game()` / `save_game()` | 开局 / 读档 / 存档 | — |
| `begin_action(id)` / `cancel_action()` | 开始 / 取消行动 | 二者都会 `ticket += 1` |
| `complete_action(token, result)` | 结算行动 | **必须带发起时的 token** |
| `write_name(id)` | 落笔（延迟结算，进 `pending`） | — |
| `end_day()` | 结束一天，兑现所有 pending | 事务式，失败则状态零变化 |
| `finish_case(choice)` | 抉择 + 结局判定 | — |
| `reveal_ui(keys)` / `apply_state(changes)` | 点亮侧栏入口 / 剧情写状态 | 给「非行动」的脚本化段落用 |
| `reload_data()` | F6 热重载 | 被拒绝时返回原因 |

**界面需要新能力时：先在 `investigation` 上加方法，不要在界面里绕过它。**

---

## 六、数据 schema 与命名约定

### 实体状态靠命名约定挂 flag

```
person.<id>.{status,identity,truth,discovered}
clue.<id>.reliability
action.<id>.done
case.<id>.status
event.<id>.done
ui.<key>                       ← 侧栏入口是否点亮
```

**所有 flag 必须在 `flags.json` 里声明**（typed，带 `default` / `min` / `max` / `values`）。
`data_loader` 会检查「每个实体状态 flag 都有声明」，漏了直接启动报错。

### 结算核心 flag 的类型锁死

`day` / `actions_left` / `writes` / `wrong_writes` / `erosion` = `int`，
`decision` / `ending` = `string`。改类型会被 `data_loader` 拒绝。

### 文件清单

| 文件 | 内容 |
| --- | --- |
| `flags.json` | 所有旗标的类型与默认值 |
| `people.json` | 人物（假名 / 真名 / 身份 / 描述） |
| `clues.json` | 线索（含 `people` 字段，图鉴的关联靠它推导） |
| `actions.json` | 调查方向（`requires` / `clues` / `effects` / `text`） |
| `cases.json` | 案件 |
| `events.json` | 定时事件 |
| `endings.json` | 结局。**必须有且仅有一个无条件兜底，且优先级最低** |
| `codex.json` | 人物图鉴的档案条目（每条带 `at` 阈值） |
| `transitions.json` | 转场（`cut` / `fade` / `slide`；优先级 **单条行动 > 目标场景 > 全局默认**） |
| `prologue.json` | 序章剧本 |

---

## 七、两条必须记住的机制

### 1. 事务提交：先算在副本上，全过了再换进去

`complete_action` / `end_day` **从不直接改 `GameState`**：

```
snapshot() → 在副本上改 → validate_snapshot() → 全过才 restore()
```

失败返回错误字符串，**状态零变化**。加任何新结算逻辑都必须沿用这个模式，
**不要直接写 flags**。

### 2. ticket 令牌：丢弃过期回调

`begin_action` / `cancel_action` 都会 `ticket += 1`。异步回调（小游戏 `completed` 等）
必须捕获发起时的 token：

```gdscript
var token := game.ticket
... async ...
if token != game.ticket: return    # 这次行动已经被取消/替换，丢弃
```

**任何新的异步流程都要带 token。**

### 游戏循环

```
一天 = 3 次行动
选调查方向（不满足 requires 的方向**不显示**，不是灰掉）
  → 场景整张切换 → 正文逐句读 → **读完即提交，无取消**（「读 = 代价」）
  → 扣行动、拿线索、跑 effects
行动归零 → 自动 end_day()
```

**落笔 = 延迟结算**：`write_name` 只往 `pending` 队列塞记录，当场世界不变；
`end_day` 才兑现——写对（`identity == 100`）→ 目标 `status=dead`、`writes+1`、`erosion+1`、跑 `death_effects`；
写错 → `wrong_writes+1`，只留一道划痕。`erosion` / `wrong_writes` 是喂给结局的账本。

---

## 八、序章的演出组件

序章不走「行动」那套，用一套**声明式演出**（`prologue.json` 的每页字段）：

| 字段 | 含义 |
| --- | --- |
| `background` | `res://` 路径 / `"black"` 纯黑 |
| `visual` | 演出卡片：`notebook`（纸页写字）/ `profile`（手机聊天卡）/ `article`（新闻卡）/ `title`（独立成屏） |
| `hotspots` | 第一人称热区，`rect` 是 **UV 比例** `[x,y,w,h]`，点击把 `response` 播成正文 |
| `choices` | 轻量分支，点选写入自己的 `set` 并把 `response` 播出来 |
| `set` | **进入这一页时**写入状态 |
| `speed` | 页级打字速度（不写就用全局 `UI.TYPE_SPEED`） |

**字段白名单在 `data_loader.gd` 的 `PROLOGUE_FIELDS`**，`visual.type` 只认上面四种。
写错会 `push_warning`——不再是静默失败。

正文分段规则：**换行 = 分成一段（一次点击）**；`<br>` = 段内换行（不额外点击）。

### ⚠️ 剧情文案与演出指示必须分开

策划案（`black_page_design.md`）是**给你我看的工作文档**，里面混着三类东西。
往 `prologue.json` 里写的时候必须分清，**分类错了玩家就会读到制作备注**。

| 类别 | 例子 | 写进哪 |
| --- | --- | --- |
| **剧情文案** | 「你把门在身后关上，潮湿的城市被隔在外面。」 | `body` / `title` / `action` / `choices[]` / `visual.text` ✓ |
| **演出指示** | 「黑屏」「先听见雨声」「几秒以后，钥匙插入门锁」「画面慢慢亮起」 | **引擎字段**：`background` / `music` / `speed` / `visual`。**不能进 `body`** ✗ |
| **系统说明** | 「玩家可以点击：电脑、手机、窗户、桌面、床」 | 不写进游戏，那是制作备注 |

**判断方法：这句是「主角能感知到的东西」，还是「要引擎做什么」？**

| 原句 | 判定 | 理由 |
| --- | --- | --- |
| 雨声反而更清楚了 | ✓ 进 `body` | 主角的感知 |
| 先听见雨声。很轻，没有音乐。 | ✗ 不进 | 这是在要求引擎「放雨声、别放音乐」 |
| 房间里原本若有若无的音乐已经停了 | ✓ 进 `body` | 主角注意到的**变化**，有戏剧作用 |
| 没有音乐。 | ✗ 不进 | 单纯的**状态说明**，玩家不需要被告知 |

**还有一条：`body` 里不能写游戏里没发生的事。**

策划案写「雨声停止」，但雨声播放器当时并不受序章控制——
把它写进正文，就是让主角感知到一件没发生的事。
**要么把它实现出来，要么别写。**
（这条是实际踩过的：`next_you_write` 原来有「画面陷入黑暗，雨声也在同一刻停了」，
而当时雨声根本没停。）

---

## 九、加功能的规矩

### 先问自己：这是哪一类？

```
是「多一段剧情 / 多一条线索 / 多一个结局」？
   → 加数据。改 data/black_page/*.json，必要时同步 flags.json 声明。不动代码。

是「多一个可调查的地方」？
   → 加场景。scenes.gd 加常量 + TABLE 条目 → transitions.json 配转场
     → hotspots.gd 加热点（target 必须能在 main._hotspot_pressed 找到分支）。

是「多一种新玩法 / 新界面」？
   → 先看 investigation 有没有现成口子。没有就先在那里加方法，
     再在表现层实现界面。**不要为了界面方便去绕过 investigation。**

是「改现有规则」？
   → 只改 investigation 的结算逻辑，并补测试。表现层不该跟着动。

是「界面不好看 / 不顺手」？
   → 只改 ui_style.gd + 对应的界面文件。不碰引擎层。
```

### 每次改动的检查清单

- [ ] 表现层有没有新增 `GameState.` 直接访问？（铁律 1）
- [ ] 有没有新增 `FileAccess` / 拼 `res://data/...` 路径？（铁律 2、3）
- [ ] 新 flag 在 `flags.json` 里声明了吗？
- [ ] 新的异步流程带 `ticket` 了吗？
- [ ] 新的结算逻辑走 `snapshot → validate → restore` 了吗？
- [ ] `data_loader` 的加载列表更新了吗（新增数据文件时）？
- [ ] 冒烟测试**跑了 86 项**且全过？（见下）
- [ ] 新增图片后跑过 `godot --headless --path <项目> --import` 了吗？

---

## 十、测试与验收门槛

```bash
# 冒烟测试（headless）
godot --headless --path <项目> res://tests/black_page_smoke.tscn
# 期望输出：BLACK_PAGE: PASS (86 checks)
```

### ⚠️ 「PASS」不够，**必须核对检查数**

测试脚本只在 `failures == 0` 时报 PASS。**一旦有解析错误，后面的 check 全部不执行**，
而 failures 仍是 0 → 假 PASS。

实际踩过：`main.gd` 编译失败，输出 `PASS (53 checks)`——少了 27 项。
**验收标准是 `PASS (86 checks)` 这个完整字符串，不是「看到 PASS」。**

### 架构审计（改完一轮跑一次）

```bash
python tools/audit.py            # 0 = 干净；1 = 有真问题
python tools/audit.py --strict   # 连启发式提示也算失败
```

它检查 11 项，分四组：

| 组 | 检查 |
| --- | --- |
| **铁律** | 只有 `investigation` 能写 `GameState` / 表现层不读数据文件 |
| **一致性** | `data/*.json` 与 `data_loader` 加载列表对账 / 孤儿 `.uid` / 孤儿 `.import` |
| **死代码** | 没人调用的函数 / 没人引用的常量 / 没人用的信号 |
| **配置** | `project.godot` 是否指向已删文件 |
| **启发式** | 未引用素材 / 未被提及的旗标 / 英文残留注释 |

### ⚠️ 自动审计只能**提出候选**，每条都要人工甄别

实测踩过的假阳性（脚本里已做显式白名单）：

| 报出来的 | 真相 |
| --- | --- |
| 立绘「没人引用」 | 路径**动态拼**：`"black_page_portrait_%s%s.png" % [id, suffix]` |
| 旗标「从没被提及」 | 名字**动态拼**：`"person." + id + ".identity"` |
| 服务方法「没人调」 | 模块**内部**互调的辅助函数 |
| 注释里的 `FileAccess` | **注释不是引用**——脚本已剥注释行再匹配 |
| 英文「残留」 | 数学公式 `scale = max(view / tex)`，语言中立 |

**新增白名单前先想清楚「它是不是动态拼的」。** 光看报告就删，会删掉活的东西。

### 改图之后必须重新导入

```bash
godot --headless --path <项目> --import
```

Godot 的 `.godot/imported/` 有缓存，**替换磁盘上的 PNG 之后游戏里读到的还是旧图**。

---

## 十一、已知的坑

| 坑 | 说明 |
| --- | --- |
| `UI.box()` 返回 **StyleBox 不是节点** | 要面板得 `PanelContainer.new()` + `add_stylebox_override("panel", UI.box(...))` |
| `game.flag()` 返回 `Variant` | 不能用 `:=` 推类型，要写成 `var x: bool = not bool(game.flag(...))` |
| 每日行动次数是**硬编码 3** | `end_day()` 和 `data_loader` 校验各有一处，改要同时改 |
| `_apply()` 与 `GameState.apply` 有重复 | 事务模式造成的（一个只改副本、一个改完即提交），可接受，但别让它们跑偏 |
| 精灵图路径是**动态拼**的 | `"black_page_portrait_%s%s.png"`——静态扫描会误判为「没人用」 |

---

## 十二、这份文档怎么维护

- **改了分层、加了新目录、改了 API 口子 → 更新本文档**
- 文档与代码不一致时，**以文档为准**：要么改代码，要么先改文档再改代码
- 本文档描述的是**规矩**；具体某段剧情怎么写，看 `black_page_design.md`（剧情策划案）；
  **图怎么出、要什么规格、还缺哪些**，看 `ART_ASSETS.md`（美术资源策划案）

### 规矩要能被验证，否则只是愿望

| 规矩 | 谁来验证 |
| --- | --- |
| 三层单向、只有 `investigation` 写状态 | `tools/audit.py` |
| 数据只经 `data_loader` | `tools/audit.py`（loader 列表对账） |
| 结算走事务、异步带 token | 冒烟测试（损坏存档 / 过期回调那几项） |
| 切图能生效 | `godot --headless --path <项目> --import` |
| 整套没退化 | `PASS (86 checks)` 这个完整字符串 |

**改完代码跑这两条，都过才算完成：**

```bash
python tools/audit.py
godot --headless --path <项目> res://tests/black_page_smoke.tscn   # 期望 PASS (86 checks)
```
