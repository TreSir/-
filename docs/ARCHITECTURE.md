# 架构与扩展约定

目标是易编辑、可扩展、遇到坏数据可诊断。针对小团队采用四层组织，不引入容器框架、反射依赖注入或不必要的抽象。

## 分层

```text
data/                        声明式章节 / Flag / 角色 / 结局 / 图鉴 / 翻译
  ↓ JSON frontend + source map
scripts/core/                编译器、规则、校验上下文、命令注册表、解释器
scripts/commands/            独立命令对象，解释器只调用命令协议
  ↕
scripts/services/            GameState / EventBus / Localization / Collections / SaveService
  ↓ 只读 view model                 ↑ 玩家意图
scripts/presentation/        主界面、背包图鉴、小游戏宿主、开发控制台
```

`game_controller.gd` 是组装入口：把核心输出与服务状态转换成界面模型，处理按钮意图。
`game_view.gd` 不读写 Flag、不判断结局、不负责存档。小游戏继承 `scripts/core/minigame.gd`。
`core/save_store.gd` 是沿用 V1 的底层图鉴存储辅助，业务服务位于 `services/collections.gd`。

## AST 协议

JSON 编译器返回 `{bundle, errors}`。bundle 包含：

- `ast_version: 1`，`id`、`version`、`start`。
- `nodes`：以 `章节ID.节点ID` 为键的命令字典；节点使用 `op` 标识命令。
- 每个节点的 `_source`：`file`、`line`、JSON `pointer`、`chapter`。
- 已校验的 flags、characters、endings、catalog、locales。
- sources 仅用于开发时校验和热重载，不写进玩家存档。

同章节短目标自动展开为完整 ID。未来 DSL 前端应产生同样的节点和 source map，再复用命令校验与运行时协议；目前不提供 DSL 解析器。

## 新增指令：一个类

在 `scripts/commands/` 增加脚本，继承 `res://scripts/core/command.gd`。
注册表自动扫描该目录，拒绝同名命令。实际例子见 `emit.gd`：

```gdscript
extends "res://scripts/core/command.gd"
func command_name() -> String: return "camera_shake"
func is_checkpoint() -> bool: return false
func validate(c, node: Dictionary) -> void:
    c.target(node)
func execute(_runtime, node: Dictionary) -> Dictionary:
    EventBus.custom_event.emit("camera_shake", {})
    return {"status": "goto", "target": node.next}
```

剧本即可写：

```json
{"id":"shake","op":"camera_shake","next":"next_line"}
```

解释器无需修改。镜头服务监听事件即可实现行为。新的视觉组件需要自己实现监听者/视图，不意味着新增任意画面都能零代码出现。

命令返回协议：

| status | 行为 |
| --- | --- |
| goto | 用 target 跳转，自动执行下一命令 |
| wait | 用 view 显示内容，等待 submit |
| error | 停止推进，报告 message |
| hold | 命令接管控制流程，例如请求重开 |

自动执行命令必须 `is_checkpoint() == false`。等待命令的 execute 必须可重入、不能重复发放奖励，因为刷新、热重载和读档会重建等待视图。
需要改变状态的等待命令在 resume 中提交效果。内建 ending 的解锁事件在预览刷新时被抑制。
每次推进有 128 个自动命令上限，阻止错误循环冻结游戏。

## 服务接入

- `GameState.apply(effects)`：先校验完整候选状态，成功后一起提交，避免“已扣道具但 Flag 更新失败”。
- `EventBus.flags_changed / inventory_changed`：刷新相关 UI。
- `EventBus.unlock_requested`：图鉴收录请求。
- `EventBus.ending_reached`：结局事件；图鉴以监听者接入。
- `EventBus.custom_event`：成就、音频、画廊等可选扩展。
- `Collections.add_item/remove_item/use_item`：道具业务接口，返回空字符串表示成功。
- `Localization.text("@key")`：按当前语言取值，缺失时回退 zh_CN；不带 @ 的文本原样输出。

新增成就/音频时，新建服务或场景监听事件。不要往解释器加入系统专属的 if/else。

## 存档策略

`SaveService` 与 `Collections` 分别保存：

- `user://saves/slot_1.json`：格式版本、剧情版本、等待节点游标、Flag、背包、语言。
- `user://saves/collections.json`：按剧情 ID 保存永久发现记录。
- 旧 `endings.json` 会导入到新图鉴；原文件保留。

正式进度用 `format=2`。先写 .tmp、flush 并检查结果，再替换正式文件。格式错误、未知 Flag、越界道具、缺失节点、未来版本都返回错误；失败读档不部分改写状态。

`save_migrations.gd` 先把格式 1 包装转换成格式 2 数据，再按剧情版本逐步迁移。V1 → V2 用 `node_aliases` 把旧节点映射到章节完整 ID，新增 Flag 在恢复时补默认值。

后续迁移的做法：

1. 提升 game.json 的 version。
2. 新增一条从旧版本到新版本的迁移函数。
3. 明确重命名/删除的 Flag 和节点如何映射，必要时调整旧数值。
4. 用真实旧存档的匿名样本加入测试。缺少迁移函数时明确拒绝，不静默重置玩家进度。

## 小游戏与异步生命周期

小游戏根节点继承 Minigame，begin 接 config 与 Flag 副本，完成时 finish 一个普通 Dictionary。
命令的 result_map 只允许写入已声明 Flag；返回类型/范围不合法时拒绝整次更新，未返回字段恢复声明默认值。

宿主负责实例化和销毁。每次视图持有 generation 标识，重开/读档/热重载后的旧回调被丢弃，避免旧小游戏把新剧情推进。
保存处于小游戏/视频时，保存的是节点起点；不序列化小游戏内部计时器或视频秒数。
背包/图鉴模态窗口暂停树，关闭时恢复之前的暂停状态。

## 热重载原则

编译候选剧本 → 全量静态校验 → 检查当前节点与已有状态兼容 → 原子替换 → 只重建当前等待视图。
任何检查失败都保留之前的 bundle 和玩家状态。文件内容签名用于避免反复报同一个错误。
只在调试构建启用；发行版不扫描源文件。

## 调试边界

控制台仅在调试构建提供，不执行任意代码。set 走强类型校验；jump 是“携带当前变量定位节点”，并非撤销到过去。
跳转仍会执行目标之后的指令，因此可能改变临时道具/Flag；预览不解锁结局，也不保存正式进度。
实际项目不应让调试会话作为游戏玩法的一部分。
