# 字体素材

| 项目内文件 | 字体 | 授权 | 用在哪 |
| --- | --- | --- | --- |
| `longcang.ttf` | 有字库龙藏体（Long Cang） | SIL OFL 1.1 | **剧情正文**：对话框 + 回顾。入口是 `scripts/black_page/ui_style.gd` 的 `STORY_FONT` |
| `noto_serif_sc.otf` | Noto Serif SC Regular（思源宋体） | SIL OFL 1.1 | 备选正文。**本地留着对比用，没入库**（11 MB，代码不引用），需要时从上游重新下载 |

界面控件（按钮 / 菜单 / 标签 / 标题）不走这里的文件，走 `ui_style.gd` 的
`sans()` / `serif()` 系统字体链。

## 授权（两款都是 SIL Open Font License 1.1）

- 可以随游戏分发、可以嵌入、可以商用；不收费，也不强制署名（来源仍建议保留下面那串）。
- 唯一实质约束：**不能单独把字体当产品卖**；改过字体必须换名字再分发。游戏只是「带上」它，不碰这条。
- OFL 要求随字体分发许可证副本：发布时把 OFL 1.1 全文放进游戏的许可证清单里。

### 来源与字体内嵌的版权串

- `longcang.ttf` — `Copyright 2018 The LongCang Project Authors`，作者 ZhongQi（有字库），
  上游 <https://github.com/googlefonts/longcang>，经 Google Fonts 分发。
- `noto_serif_sc.otf` — `© 2017-2024 Adobe`，Noto CJK 项目（与思源宋体同源），
  上游 <https://github.com/notofonts/noto-cjk>（`Serif/SubsetOTF/SC`）。

## 覆盖情况

字集取的是 `data/black_page/*.json` 里出现过的全部非 ASCII 字符，共 **615 个**；
拿两款字体的 cmap 对：都是 **0 缺字**。所以正文不会出现「一句话里混两种字面」。
`story()` 仍挂着 `sans()` 兜底——以后文案添了生僻字时不至于出豆腐块。

## 体积与子集化

全量文件：龙藏体 4.9 MB、思源宋体 11.1 MB。真要瘦身可以按字集切子集
（`pyftsubset --text-file=...`）：实测霞鹜文楷 24.4 MB 切到 615 字后是 0.23 MB，
同理会落到几百 KB。代价是**以后加新文案要重新切一次**，所以发布前再切、开发期用全量。

## 换字体

只改 `ui_style.gd` 顶部的 `STORY_FONT` 一行，其余代码不用动。
想彻底回到系统字体，就把 `notice` 和回顾行上的 `UI.story()` 覆盖删掉。

## 之前的「怨霊」（已移除）

正文最早用暗黒工房的「怨霊」（`onryou.ttf`）。它是日文字体，只收 JIS 第一 / 第二水準，
615 字里缺 166 个（27%），运行时逐字掉回系统雅黑——同一句话两种字面，就是这个原因换掉的。
文件还在 git 历史里，需要时 `git checkout <提交> -- assets/fonts/onryou.ttf` 取回。
授权提醒：怨霊允许嵌进作品里分发，但**字体文件本身不得再配布**。
