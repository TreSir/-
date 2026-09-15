# 剧本与内容编辑指南

所有例子基于 data/game.json 引用的数据，改文件保存后可在运行中的开发版查看效果。

## Flag

```json
{
  "trust": {"type":"int","default":0,"min":0,"max":10},
  "has_confessed": {"type":"bool","default":false},
  "route": {"type":"string","default":"none","values":["none","friend","alone"]}
}
```

支持 int / float / bool / string，可用 values 限定枚举。引用未声明变量、赋错类型或超出范围会报错，不会临时创建拼错名字的新变量。

## 章节和对话

```json
{
  "id":"chapter_2",
  "nodes":[
    {"id":"start","op":"say","speaker":"keeper","text":"欢迎回来。","next":"question"},
    {"id":"question","op":"choice","text":"现在准备好了吗？","options":[
      {"text":"准备好了","effects":{"add":{"trust":1}},"next":"prologue.repair_intro"},
      {"text":"还没有","next":"start"}
    ]}
  ]
}
```

同章节 next 可用短 ID；跨章节用完整 chapter.node。把新章节路径加入 game.json 的 chapters。
角色名称定义在 characters.json；文本以 @ 开头时视为翻译 key。背景和立绘可在显示节点上加 background/portrait 资源路径，每个节点独立设置以保证读档重建一致。

## 条件

```json
[
  {"flag":"trust","op":">=","value":2},
  {"item":"old_key","op":">=","value":1}
]
```

数组中条件为 AND。省略条件或空数组表示总是成立。支持 ==、!=、>=、>、<=、<，大小比较只支持数值。
choice 的 options 可以设置 conditions；branch 用 conditions、then、else。注意为选择保留至少一个可行出口。

## 效果

```json
{
  "set":{"has_confessed":true},
  "add":{"trust":1},
  "inventory":{"old_key":-1,"letter":1},
  "unlock":["keeper"]
}
```

用于 set 命令或选项的 effects。set 先执行，add 再执行；Flag 与背包整体校验后一起提交。
道具数量不能负数或超过 max_stack，0 会移除该背包项。不要在 say 等纯展示节点放发奖操作。

## 道具与图鉴

catalog.json 的 items 定义道具，entries 定义图鉴。
道具可设置 usable、consume、effects、entry（获得时解锁）、use_unlock（使用后解锁）。
max_stack 为正整数。只需添加配置即可出现在背包/图鉴逻辑中；目前界面以分类标签展示。

新增图鉴条目可用人物、地点、道具、线索、结局等 category；secret=true 时锁定状态显示 ???。
entries 的 description 是解锁后正文，未解锁不会显示。永久图鉴与当前周目背包相互独立。

## 结局

```json
{"id":"reunion","priority":120,"conditions":[{"flag":"trust","op":">=","value":8}],"title":"重逢","text":"你们再次相见。"}
```

把条目加入 endings.json。到 ending 命令时按 priority 从高到低选第一个满足条件的结局。
id 与 priority 不能重复；必须有一个条件为空且优先级最低的兜底结局。
新结局如需出现在图鉴，可增加对应 entries 项并在结局填 entry。无需新增终章分支节点。

## 小游戏

```json
{"id":"repair","op":"minigame","scene":"res://scenes/minigames/signal_game.tscn","config":{"target":3},
 "result_map":{"success":"puzzle.success","score":"puzzle.score"},"next":"film"}
```

场景脚本继承 scripts/core/minigame.gd，覆盖 begin(config, story_variables)。
完成时 finish({"success":true,"score":3})，宿主销毁场景并推进剧情。

## 视频

```json
{"id":"film","op":"video","path":"res://assets/video/opening.ogv","skippable":true,
 "result_map":{"played":"film.played","skipped":"film.skipped"},"next":"finale"}
```

演示 path="" 自动跳过。真实资源存在时使用 VideoStreamPlayer 播放；不合法路径在加载校验时报错。
结果映射可省略；声明的目标 Flag 必须存在。

## 报错示例

```text
res://data/chapters/prologue.json:39: 未知 Flag：trsut
```

文件和行号来自 JSON token source map，不是简单查找相同字符串。重复 JSON 键也会被拒绝。
修正错误并保存后，开发版会重新尝试加载；如果修改了当前节点身份或状态定义，需要先处理兼容性或重开游戏。
