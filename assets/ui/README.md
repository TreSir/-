# 《黑页》UI 图标集

这套图标用于左侧调查导航与“进度与设置”菜单。整体采用手绘 2D 动漫悬疑风：
冷青灰和纸白为主色，只用少量哑金强调，透明背景，不包含文字。

## 文件结构

- `black_page_ui_icons_sheet_v1.png`：16 图标母版，按 4×4 排列，保留用于统一改版和追溯。
- `icons/*.png`：游戏直接加载的拆分图标，统一为 256×256 RGBA PNG。

母版顺序从左到右、从上到下为：

| 行 | 图标 |
| --- | --- |
| 1 | `case`、`people`、`clue`、`notebook` |
| 2 | `save`、`load`、`restart`、`reload` |
| 3 | `rain`、`music`、`sfx`、`fullscreen` |
| 4 | `text_size`、`text_speed`、`history`、`close` |

## 接入约定

所有界面只通过 `scripts/black_page/ui_style.gd` 的语义键取图标，不应在业务脚本里硬编码 PNG 路径。
新增或替换图标时，只改 `ICON_TEXTURES` 映射即可。位图资源不可用时，样式层会回退到程序化线框图标。

## 生成描述摘要

生产级 4×4 Godot UI 图标表；透明背景；简洁的高级手绘 2D 动漫悬疑风；精细钢笔线条、轻微墨迹质感；
冷青灰、柔和纸白与少量哑金；统一笔画、统一视觉重量；24–32 px 下仍清楚；无文字、无标签、无水印、无底板和外发光。
