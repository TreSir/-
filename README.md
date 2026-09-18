# 《黑页》

Godot 4.x / GDScript 的推理视觉小说原型。**打开 `project.godot`，按 F5 运行。**

主场景是 `res://scenes/black_page/main.tscn`。目前是**一个案件的短流程切片**：
调查、身份反转、限时线索、落笔及次日后果。完整三案长篇仍待制作。

- 内容全在 `data/black_page/*.json`——**改剧情不用动代码**
- **[架构规约](docs/ARCHITECTURE.md)**：改代码前先读它，那是这个项目的规矩
- [核心玩法与系统策划案](docs/black_page_design.md)：剧情内容怎么写

---

## 一句话架构

> **表现层永远不碰状态，只调 `investigation` 的公开方法。**

```
表现层   scripts/black_page/（14 个）          界面 · 演出 · 小游戏 · 输入
   │    只调公开方法
   ▼
引擎层   investigation.gd + services/ + core/  零 UI 依赖，可 headless 跑测试
   │
   ▼
数据层   data/black_page/*.json + data_loader.gd
```

**三条铁律**（都有脚本在查）：

| # | 规矩 |
| --- | --- |
| 1 | **只有 `investigation.gd` 能写 `GameState`** |
| 2 | 表现层不读数据文件（不 `FileAccess`、不 `JSON.parse_string`） |
| 3 | 数据只经 `data_loader` 加载并校验 |

**两条必须记住的机制**：

- **事务提交** —— `snapshot()` → 在副本上改 → `validate_snapshot()` → 全过才整体换入。失败返回错误，**状态零变化**
- **ticket 令牌** —— 异步回调要带发起时的 token，`token != game.ticket` 就丢弃

---

## 最常改的文件

| 想改什么 | 文件 |
| --- | --- |
| 序章剧本 | `data/black_page/prologue.json` |
| 剧情段落（说台词 / 写状态 / 给线索 / 跳转） | `data/black_page/stories.json` |
| 重点演出（打点时间轴） | `data/black_page/sequences.json` |
| 小游戏（场景 + 配置） | `data/black_page/minigames.json` |
| 调查方向（正文 / 条件 / 奖励） | `data/black_page/actions.json` |
| 旗标类型与默认值 | `data/black_page/flags.json` |
| 人物 | `data/black_page/people.json` |
| 线索 | `data/black_page/clues.json` |
| 案件 | `data/black_page/cases.json` |
| 定时事件 | `data/black_page/events.json` |
| 结局 | `data/black_page/endings.json` |
| 人物图鉴档案 | `data/black_page/codex.json` |
| 转场方式 | `data/black_page/transitions.json` |
| 场景（名称 / 贴图） | `scripts/black_page/scenes.gd` |
| 房间热区 | `scripts/black_page/hotspots.gd` |
| 视觉令牌（颜色 / 字号 / 间距） | `scripts/black_page/ui_style.gd` |
| 音频素材 | `scripts/black_page/audio_tracks.gd` |

**新增一个数据文件要动三处**：`data/` 下建 json → `data_loader.gd` 的加载列表 → 需要就加校验。
漏了会在启动时直接报错——这是设计如此，不是意外。

---

## 加内容的三条路

```
多一段剧情 / 线索 / 结局   →  加数据。改 JSON，不动代码
多一个可调查的地方         →  scenes.gd 加条目 + transitions.json + hotspots.gd
多一种玩法 / 新界面        →  先在 investigation 加方法，再在表现层做界面
                             ★ 不要为了界面方便绕过 investigation
```

---

## 验证

改完必须跑这两条，**都过才算完成**：

```bash
python tools/audit.py                                            # 期望 exit 0
godot --headless --path <项目> res://tests/black_page_smoke.tscn # 期望 PASS (158 checks)
```

⚠️ **验收标准是 `PASS (158 checks)` 这个完整字符串，不是「看到 PASS」。**
测试只在 `failures == 0` 时报 PASS；一旦有解析错误，后面的检查全部不执行，
failures 仍是 0 → **假 PASS**。改了测试要同步更新这个数字，以及
`docs/ARCHITECTURE.md` 里对应的说法。

`tools/audit.py` 查 12 项，分五组：铁律 / 一致性（data 与 loader 对账、孤儿文件）/
死代码（没人调的函数、常量、信号）/ 配置，外加一组启发式提示。
**启发式项会误报**（动态拼路径、动态拼旗标名、注释里的 `FileAccess`），
光看报告就删会删掉活的东西——每条都要人工甄别。

改了图片之后必须重新导入，否则游戏读到的还是缓存里的旧图：

```bash
godot --headless --path <项目> --import
```

---

## 开发时用得上的

- **F6** 热重载数据（仅调试构建），或走 ☰ → 重载数据。改 JSON 不用重启游戏
- **☰** 里收着：存档 / 读取 / 重新开始 / 雨声 / 背景音乐
- 存档目前**只有一个槽位**：`user://saves/black_page_slot_1.json`
  （写盘是「先写 `.tmp` 再改名」，不会写出半个存档）

---

## 当前边界

- 首章切片，不是完整游戏；三案长篇待制作
- AI 美术素材为占位性质，风格尚未统一
- 未做发行包验证。导出时需把 `data/**/*.json` 加入非资源文件包含过滤
- 音效与背景音乐已接入，均为 CC0 / CC-BY 可商用素材；
  **其中两首 CC-BY 曲目发布时必须署名**，清单见 `assets/audio/CREDITS.md`
