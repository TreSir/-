# 音频素材来源与授权

本项目所有音频均来自 [OpenGameArt.org](https://opengameart.org)，全部为 **CC0（公共领域）** 或
**CC-BY**（需署名）授权，可商用。原始文件未经修改即可直接替换；下面列出每个文件对应的
原始作品、作者与协议。

> 处理说明：所有文件统一做过两件事——① 用等功率交叉淡化把接缝做成无缝循环（雨声取录音里
> 最平稳的一段，音乐整曲循环并裁掉首尾的淡入淡出）；② EBU R128 响度标准化（雨声 −20 LUFS，
> 音乐 −22 LUFS）并把真峰值压在 −1.5 dBFS 以内。除此之外没有加任何合成音。
> 想换回原始素材，见每行末尾的原始文件名。

## 雨声

| 项目内文件 | 原始作品 / 作者 | 协议 | 原始文件 |
| --- | --- | --- | --- |
| `rain_steady.ogg` | [School day / Rain / Sun / Loop](https://opengameart.org/content/school-day-rain-sun-loop) — KiluaBoy | CC0 | `SchoolDayRain.ogg` |
| `rain_light.ogg` | [Light rain and heavy rain](https://opengameart.org/content/light-rain-and-heavy-rain) — haruta | CC0 | `light_rain_and_heavy_rain.mp3` |
| `rain_heavy.ogg` | [Heavy Rain](https://opengameart.org/content/heavy-rain) — Pro Sensory | CC0 | `heavy_rain_mastered.mp3` |
| `rain_thunder.ogg` | [rain and thunders](https://opengameart.org/content/rain-and-thunders) — kindland | CC0 | `Dark_Rainy_Night(ambience).ogg` |

## 背景音乐

| 项目内文件 | 原始作品 / 作者 | 协议 | 原始文件 |
| --- | --- | --- | --- |
| `bgm_contemplation.ogg` | [Contemplation](https://opengameart.org/content/contemplation-0) — Joth | CC0 | `Contemplation.mp3` |
| `bgm_empty_city.ogg` | [EmptyCity: Background Music](https://opengameart.org/content/emptycity-background-music) — yd | CC0 | `EmptyCity.ogg` |
| `bgm_dungeon.ogg` | [Dungeon Ambience](https://opengameart.org/content/dungeon-ambience) — yd | CC0 | `dungeon002.ogg` |
| `bgm_mysterious.ogg` | [Mysterious Ambience (song21)](https://opengameart.org/content/mysterious-ambience-song21) — cynicmusic | CC0（该作品同时以 CC-BY 3.0 / CC-BY-SA 3.0 / GPL 3.0 发布，此处选用 CC0 条款） | `song21.mp3` |
| `bgm_mysterious_calm.ogg` | [Mysterious Calm](https://opengameart.org/content/mysterious-calm) — bart | **CC-BY 3.0** | `mysterious_calm.ogg` |
| `bgm_noir_piano.ogg` | [Jazzy Vibes #89 - Melancholic Jazz Piano](https://opengameart.org/content/jazzy-vibes-89-melancholic-jazz-piano) — Tri-Tachyon | **CC-BY 4.0** | `piano.freesound.mp3` |

### ⚠️ 署名义务

`bgm_mysterious_calm.ogg` 和 `bgm_noir_piano.ogg` 是 CC-BY，**发布游戏时必须在鸣谢名单里署名**。
建议在制作人员名单里加一行：

```
Ambience & music:
  "Mysterious Calm" by bart — CC-BY 3.0 — via OpenGameArt.org
  "Jazzy Vibes #89 - Melancholic Jazz Piano" by Tri-Tachyon — CC-BY 4.0 — via OpenGameArt.org
```

其余 8 个文件是 CC0，没有署名义务（但保留这份清单方便日后溯源）。
如果不想承担署名义务，把默认曲目换成上表里任意一个 CC0 文件即可（改
`scripts/black_page/audio_tracks.gd`，见下）。

## 一、如何替换曲目

`scripts/black_page/audio_tracks.gd` 顶部三个常量控制默认播放：

```gdscript
const RAIN_DEFAULT := "res://assets/audio/rain_steady.ogg"
const MUSIC_MENU   := "res://assets/audio/bgm_contemplation.ogg"
const MUSIC_GAME   := "res://assets/audio/bgm_empty_city.ogg"
```

同文件里的 `RAIN_ALTERNATIVES` / `MUSIC_ALTERNATIVES` 列出了全部备选，
挑一个换上去即可，其它代码不用动。

## 二、循环长度

| 文件 | 循环长度 |
| --- | --- |
| rain_steady | 45 s |
| rain_light | 40 s |
| rain_heavy | 45 s |
| rain_thunder | 48 s |
| bgm_contemplation | 115 s |
| bgm_empty_city | 90 s |
| bgm_dungeon | 90 s |
| bgm_mysterious | 35 s |
| bgm_mysterious_calm | 143 s |
| bgm_noir_piano | 16 s（原曲只有 23 s，偏短，适合当事件音乐而非长循环） |

所有文件都是 44.1 kHz / 立体声 / Ogg Vorbis（q6）。
