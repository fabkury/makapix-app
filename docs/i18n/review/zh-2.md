# Review: Simplified Chinese (zh), pack 2 (messages 551–1100)

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| postHashtagsHelper | medium | The tag parser splits only on the ASCII comma (`edit_post_details_page.dart` `parseHashtags`), but a Chinese IME types the full-width "，" by default, so "用逗号分隔" leads users to merge all their tags into one. Say which comma. | 用逗号分隔。 | 用英文逗号（,）分隔。 |
| postHashtagsHint | low | The sample hashtags stay English; a Chinese user sees no example of a Chinese tag. Keep the ASCII commas (see above). | pixelart, animation, fantasy | 像素画, 动画, 奇幻 |
| pmdNoLicenseShort | low | "无许可" out of context reads as "not permitted / unlicensed"; the standard short Chinese for "all rights reserved" is 版权所有, same length class. | 无许可 | 版权所有 |
| reportResolvedOn | low | The parenthetical subject is awkward ("感谢你的举报（一条评论）"); put the subject after a colon (full-width punctuation also avoids the Chinese–Latin spacing problem when {subject} is a @handle). | 感谢你的举报（{subject}），我们已审核。 | 感谢你的举报，我们已审核：{subject}。 |
| reportWhy | low | "你为什么要举报？" can read as challenging the user ("why would you report this?"). Neutral form used by Chinese apps asks for the reason. | 你为什么要举报？ | 你举报的原因是什么？ |
| reportSentBody | low | Bare "感谢，" is abrupt; "谢谢" is the natural standalone thanks. | 感谢，管理员会进行审核。 | 谢谢，管理员会进行审核。 |
| mentionNobody | low | As an option answering "谁可以提及我", the fragment "任何人都不能" is clumsy; 没有人 is the natural choice-list answer. | 任何人都不能 | 没有人 |
| modHubNote | medium | "pulse" (a dashboard page) is rendered 动态, which is the glossary word for feed; a moderator will read it as "feeds". | …其余功能（举报、动态、审计日志、指标）… | …其余功能（举报、实时概况、审计日志、指标）… |
| monitoredShown | low | A status badge, but "显示" reads as the verb/button "Show"; the settings summary (settingsMonitoredHashtagsSummary) already says 已显示. | 显示 | 已显示 |
| monitoredHidden | low | Same as above: a state badge, not an action. | 隐藏 | 已隐藏 |
| playersNameHint | low | The possessive 的 makes the sample name sound like a sentence; device names are written as compounds. | 客厅的屏幕 | 客厅屏幕 |
| mentionReasonFollowing | medium | "你关注了" is an unfinished clause ("you followed …"); as a status label next to a user it should read as a state, pairing with 关注了你. | 你关注了 | 已关注 |
| tipAirbrush | low | "柔和和雾状" puts two 和 back to back, which reads clumsily. | 拖动喷涂主色。点状、柔和和雾状的上色效果各不相同。 | 拖动喷涂主色。点状、柔和、雾状三种效果各不相同。 |
| tipCopyPaste | medium | Much longer than the English and adds content ("选区的剪贴板", "由你摆放位置"); at about 55 characters it risks overflowing the two-line band on a phone. | 选区的剪贴板：复制、剪切、粘贴、清除。可从图层或合成后的帧复制。粘贴会放下一个可移动的草稿，由你摆放位置。 | 复制、剪切、粘贴或清除选区。可从图层或整帧复制。粘贴会放下可移动的草稿。 |
| tipResize | medium | The context says the tip must name the Scale button by its label (optScale = 自由缩放); "拖动设定任意倍率" does not, so the user cannot match tip to button. | 缩放图层或帧：½×、2×，或拖动设定任意倍率。（整个画布：☰ 菜单。） | 缩放图层或帧：½×、2×，或用“自由缩放”拖动。（整个画布：☰ 菜单。） |
| tipInvert | medium | The Invert tool is 反相 (toolInvert, optInvertFrame/Layer/Selection); 反转 here is inconsistent and sits one character from 翻转 (Flip), the distinction the glossary protects. | 反转图像的颜色。 | 反相图像的颜色。 |
| optInvertColors | medium | Same inconsistency: the button beside the 反相帧 / 反相图层 labels says 反转. | 反转颜色 | 反相颜色 |
| optWrap | low | 循环 is the word for an animation loop (publishLoopSeconds uses it); for pixels that wrap around the canvas edges 环绕 is clearer. | 循环 | 环绕 |
| optPerfect | medium | "完美" alone says nothing about what the chip does; Chinese pixel-art tools call this 像素完美 (pixel-perfect). | 完美 | 像素完美 |
| optContrastLetter | low | 比 out of context suggests 比例 (optRatio, another slider label in the same options row); 对 is the head character of 对比度 and does not collide. | 比 | 对 |
| mirrorChipH | medium | A space between two Chinese words is not Chinese typography, and the order is English. Natural compound, same length. | 镜像 水平 | 水平镜像 |
| mirrorChipV | medium | Same as mirrorChipH. | 镜像 垂直 | 垂直镜像 |
| mirrorChipBoth | medium | Same spacing problem, and the chip says 水平+垂直 while the tip (mirrorChipTip) and the sheet option (mirrorModeBoth) call this mode 双向. | 镜像 水平+垂直 | 双向镜像 |

Overall the pack is accurate and reads as natural mainland UI Chinese: the glossary terms (帖子, 动态, 回应, 再创作, 创作脉络, 屏蔽, 封禁, 管理员, 播放器, 图层, 帧, 选区, 主色, 阈值, 慢速) are used consistently, every placeholder is intact, the Chinese–Latin spacing and full-width punctuation are correct throughout, and no finding is of high severity.

## Systemic notes

- **Invert is 反相, everywhere.** The tool (toolInvert) and the frame/layer/selection labels use 反相, but tipInvert and optInvertColors say 反转. 反转 is one character away from 翻转 (Flip), the very pair the glossary says must stay distinct. Use 反相 for color inversion in every message (反选 stays for inverting a selection); worth adding to the glossary's Flip vs. Invert note for zh.
- **Chinese users type the full-width comma.** Any instruction to "separate with commas" must say the ASCII comma (英文逗号) as long as `parseHashtags` splits only on `,`; better still, the parser should also split on "，" (and "、"), which would let the helper stay plain 用逗号分隔. This affects every input that splits on commas, not just hashtags.
- **State labels vs. action labels.** Badges, chips, and status labels that describe a state should carry 已 (已显示, 已隐藏, 已关注), so they do not read as the buttons that perform the action; the pack already does this well elsewhere (已推荐, 已就绪, 已过期), and the few exceptions above should follow.
- **Tips must quote the option labels verbatim.** Most tips do (对角, 阈值, 慢速, 点状/柔和/雾状, 矩形/椭圆/套索), but tipResize paraphrases 自由缩放. When an `opt*` label changes, grep the `tip*` messages for the old word.
- **No spaces between Chinese words.** The half-width space belongs only between Chinese and Latin letters or digits; the mirror chips (镜像 水平) copy English word order and spacing. Chinese labels are compounds (水平镜像).
- **动态 is reserved for "feed".** It must not be reused for other English words (pulse, activity, dynamic); a moderator will read it as the feeds.
- **Plural messages are written two ways.** Eight messages in this pack drop the ICU plural wrapper ("{count} 天后过期"), three keep `{count, plural, other{…}}`. Both are correct for Chinese and render the same; if the project wants the brief's "only `other`" form as a rule, normalize them, but this is not a user-facing defect.
