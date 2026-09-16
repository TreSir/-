extends Node
## 跨场景事件总线。只有真正跨场景的事件才在这里加信号——
## 单个场景内部的事情用局部信号，别往这里堆。
signal game_started
signal flags_changed
signal inventory_changed
signal unlock_requested(id: String)
signal ending_reached(id: String, entry: String)
signal story_reloaded
signal custom_event(name: String, payload: Dictionary)
