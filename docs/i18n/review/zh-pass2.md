# Second-pass review: Simplified Chinese (zh)

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| layersPickBlend | medium | 非正常混合 reads as "abnormal blending"; the mode name 正常 must be marked as a name, not an adjective. | 非正常混合 | 非“正常”混合 |
| framesShiftClamped | low | "已从 {requested} 限制到此值" is clunky; say plainly that the typed number was out of range and was adjusted. | 移动 {count} 位（已从 {requested} 限制到此值） | 移动 {count} 位（{requested} 超出范围，已调整） |
| onboardingPasswordBody | low | "以完成" dangles without an object (finish what?); unchanged from before but still unnatural. | 你是用临时密码登录的。请设置自己的密码以完成。 | 你是用临时密码登录的。请设置自己的密码以完成设置。 |
| reportResolvedOn | low | "我们已审核：一条评论。" puts the vague subject after a colon as if it were a list item; reads awkwardly with the generic subject phrases (一条评论, 一个帖子). | 感谢你的举报，我们已审核：{subject}。 | 感谢你的举报，你举报的{subject}已审核完毕。 |
| postHashtagsHint | low | Half-width ", " separators in a Chinese example; Chinese users type ，or 、 (both fields accept them), so the hint should show the native separator. | 像素画, 动画, 奇幻 | 像素画，动画，奇幻 |
| cmdMirrorCycle | low | The off state is 关 here but the Mirror mode option (mirrorModeOff) says 关闭; name it as the option does. | 镜像（循环：关 · 水平 · 垂直 · 双向） | 镜像（循环：关闭 · 水平 · 垂直 · 双向） |

Checked 77 messages.
