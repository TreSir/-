extends RefCounted
## 黑页的场景表。
##
## 重构后的一层概念：**场景 = 此刻你正在看着什么**。
## 界面不再是一堆面板，而是「一张场景图 + 底部剧情 + 中央选项」：
##   · 底部字幕带负责推进剧情（主驱动）；
##   · 剧情推进到决策点时，屏幕中央冒出选项；
##   · 做出选择后，场景图整体切换——调查是「第一人称去看」，不是翻数据表。

const ROOM := "room"
const MONITOR := "monitor"
const ARCHIVE := "archive"
const NOTEBOOK := "notebook"
const PHONE := "phone"
const BADGE := "badge"
const PHOTO := "photo"
const MEETING := "meeting"
const INTERVIEW := "interview"

const TABLE := {
	ROOM: {"name": "房间", "texture": preload("res://assets/backgrounds/black_page_room_v1.png")},
	MONITOR: {"name": "显示器", "texture": preload("res://assets/backgrounds/black_page_scene_monitor.png")},
	ARCHIVE: {"name": "档案柜", "texture": preload("res://assets/backgrounds/black_page_scene_archive.png")},
	NOTEBOOK: {"name": "黑页", "texture": preload("res://assets/backgrounds/black_page_prologue_notebook_v1.png")},
	PHONE: {"name": "手机", "texture": preload("res://assets/backgrounds/black_page_scene_phone.png")},
	BADGE: {"name": "员工证", "texture": preload("res://assets/backgrounds/black_page_scene_badge.png")},
	PHOTO: {"name": "旧合照", "texture": preload("res://assets/backgrounds/black_page_scene_photo.png")},
	MEETING: {"name": "会面", "texture": preload("res://assets/backgrounds/black_page_scene_meeting.png")},
	INTERVIEW: {"name": "问询室", "texture": preload("res://assets/backgrounds/black_page_scene_interview.png")},
}

static func has(id: String) -> bool:
	return TABLE.has(id)

static func name_of(id: String) -> String:
	if not TABLE.has(id):
		return ""
	return TABLE[id]["name"]

static func texture_of(id: String) -> Texture2D:
	if not TABLE.has(id):
		return null
	return TABLE[id]["texture"]

## 把一条调查挂到它应该在的场景上。
## 先按行动 id 精确匹配，再退到 kind，最后回落到房间——保证任何行动都有画面。
##
## 一个场景可以服务多条调查，但**语义要对得上**：查证件要有证件的画面，
## 见人要有见面的地方。早先四条调查全塞进「档案柜」、三条全塞进「手机」，
## 玩家点了不同的东西却看到同一张图，那比缺图还糟。
const BY_ACTION := {
	"camera": MONITOR,
	"badge": BADGE,
	"archive": ARCHIVE,
	"archive_public": MONITOR,
	"photo": PHOTO,
	"testimony": MEETING,
	"fallback": PHONE,
	"cooperate": INTERVIEW,
	"notebook": NOTEBOOK,
}

static func for_action(action_id: String, kind: String) -> String:
	if BY_ACTION.has(action_id):
		return BY_ACTION[action_id]
	match kind:
		"minigame":
			return MONITOR
		"document":
			return ARCHIVE
		"dialogue":
			return PHONE
	return ROOM
