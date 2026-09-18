extends RefCounted
## 音频素材清单。
##
## 全部来自 OpenGameArt 的 CC0 / CC-BY 素材，已统一处理成无缝循环 + 响度标准化
## （雨声 -20 LUFS，音乐 -22 LUFS），所以引擎里只管调音量，不用再动电平和接缝。
## 完整来源与授权见 assets/audio/CREDITS.md。
##
## ★ 想换默认曲目，只改下面这三行常量就行，其它地方不用动。

## 雨 + 远处闷雷。**当前的默认雨声**——用户听过几种之后挑中的。
const RAIN_THUNDER := "res://assets/audio/rain_thunder.ogg"

## 细雨。更安静的备选。
const RAIN_LIGHT := "res://assets/audio/rain_light.ogg"

## 最早的默认轨。素材原始是「School day / Rain」= **雨天的学校**，
## 录音里带环境声和低频轰鸣，不适合「深夜出租屋」，所以换掉了。
const RAIN_DEFAULT := "res://assets/audio/rain_steady.ogg"
## 启动页背景音乐。
const MUSIC_MENU := "res://assets/audio/bgm_contemplation.ogg"
## 进入游戏后的背景音乐（比菜单更轻、更稀疏）。
const MUSIC_GAME := "res://assets/audio/bgm_empty_city.ogg"

## 备选雨声，供替换 RAIN_DEFAULT。
const RAIN_ALTERNATIVES := {
	"steady": "res://assets/audio/rain_steady.ogg",      # 平稳细雨
	"light": "res://assets/audio/rain_light.ogg",        # 更轻、更细
	"heavy": "res://assets/audio/rain_heavy.ogg",        # 密集大雨
	"thunder": "res://assets/audio/rain_thunder.ogg",    # 雨 + 远处闷雷（当前默认）
}

## 备选背景音乐，供替换 MUSIC_MENU / MUSIC_GAME。
const MUSIC_ALTERNATIVES := {
	"contemplation": "res://assets/audio/bgm_contemplation.ogg",     # 沉静、克制（菜单默认）
	"empty_city": "res://assets/audio/bgm_empty_city.ogg",           # 空城、冷（游戏内默认）
	"mysterious": "res://assets/audio/bgm_mysterious.ogg",           # 悬疑氛围
	"mysterious_calm": "res://assets/audio/bgm_mysterious_calm.ogg", # 神秘而平静
	"dungeon": "res://assets/audio/bgm_dungeon.ogg",                 # 低频暗流、压迫
	"noir_piano": "res://assets/audio/bgm_noir_piano.ogg",           # 忧郁爵士钢琴（偏短，16s）
}

## 音效（一次性短音）。走 core/sfx_player.gd，和 BGM / 雨声各走各的。
##
## 来源：前 6 个是**程序生成**的（本项目自己合成，无版权问题）；
## 时钟滴答来自 OpenGameArt 的 CC0 素材（ticking clock, by bart）。
const SFX_PHONE_BUZZ := "res://assets/audio/sfx_phone_buzz.wav"
const SFX_PHONE_RING := "res://assets/audio/sfx_phone_ring.wav"
const SFX_IMPACT := "res://assets/audio/sfx_impact.wav"
const SFX_PAGE_TURN := "res://assets/audio/sfx_page_turn.wav"
const SFX_BOOK_CLOSE := "res://assets/audio/sfx_book_close.wav"
const SFX_UI_CLICK := "res://assets/audio/sfx_ui_click.wav"
const SFX_CLOCK_TICK := "res://assets/audio/sfx_clock_tick1.wav"
