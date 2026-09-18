extends Node
## 跨场景事件总线。只有真正跨场景的事件才在这里加信号——
## 单个场景内部的事情用局部信号，别往这里堆。
##
## 这里曾经堆着 game_started / flags_changed / inventory_changed / unlock_requested /
## story_reloaded / custom_event 六个信号，但全项目**零监听**：状态变化实际上都靠
## investigation.gd 的 changed 信号驱动界面刷新。全部删掉，只留真正有人听的结局信号。
signal ending_reached(id: String, entry: String)
