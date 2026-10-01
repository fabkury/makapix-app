# Simplified Chinese (zh) review, pack 1 (messages 1–550)

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| settingsModerationPolicy | medium | 管理政策 reads as "management/administration policy"; the page is the content-moderation policy. | 管理政策 | 内容管理政策 |
| timeAgoMinutes, timeAgoHours, timeAgoDays, timeAgoWeeks, timeAgoMonths, timeAgoYears | low | The only messages in all three packs with no half-width space between a number and Chinese (house rule; compare `{n} 字节`, `{max} 个`). The no-space form is common in compact timestamps, so either keep it as a deliberate, documented exception or add the space. | {n}分钟前 | {n} 分钟前 (likewise 小时前, 天前, 周前, 个月前, 年前) |
| commentsLikesLoadError | low | "无法加载点赞的用户" is slightly awkward; the sheet is the list of who liked. | 无法加载点赞的用户。 | 无法加载点赞列表。 |
| downloadLayers | low | Half-width parentheses in Chinese text; elsewhere the pack uses full-width （）. | 图层文件 (.mkpx) | 图层文件（.mkpx） |
| mentionNoMatch | low | 同名用户 means "users with the same name"; the case is "no user matches what you typed". | 没有可提及的同名用户。 | 没有找到可提及的匹配用户。 |
| playerMirrorBoth | low | 两者 ("the two of them") is stiff as a mirror option; 双向 is the usual word next to 水平 / 垂直. | 两者 | 双向 |
| monitoredViolence | low | 暴力描绘 is literal; 暴力内容 matches the neighboring 政治内容 / 露骨内容. | 暴力描绘 | 暴力内容 |
| onboardingPasswordBody | low | "你使用临时密码登录。" can read as an instruction ("sign in with the temporary password"); the English states a past fact. | 你使用临时密码登录。请设置自己的密码以完成。 | 你是用临时密码登录的。请设置自己的密码以完成。 |
| notifMentionDescription | low | 简介 is also the profile Bio (profileBio); with no title, "在简介中" can read as the mentioner's own bio. Naming the artwork removes the doubt. | {who} 在简介中提及了你 | {who} 在作品简介中提及了你 |
| aboutVersion | low | Half-width parentheses around the build number in Chinese text. | 版本 {version} ({build}) | 版本 {version}（{build}） |
| profileReputationTooltip | low | "在 Club 的活跃度获得" is clumsy (活跃度 is a score, not something you earn through). | 声望：{points}，通过在 Club 的活跃度获得 | 声望：{points}，通过在 Club 中的活动获得 |
| statUnique7d | low | No space between the digit and 天 (house rule: half-width space between Chinese and digits). | 独立访客（7天） | 独立访客（7 天） |
| statsByCountry, statsByDevice, statsByType, statsByEmoji | low | "按X的浏览量 / 按表情的回应" is unidiomatic; 按… needs a verb (统计) or the breakdown goes in parentheses. | 按国家/地区的浏览量 · 按设备的浏览量 · 按类型的浏览量 · 按表情的回应 | 按国家/地区统计浏览量 · 按设备统计浏览量 · 按类型统计浏览量 · 按表情统计回应 |

## Systemic notes

- **Overall quality is high.** Glossary terms are applied consistently throughout the pack (帖子, 回应, 再创作, 屏蔽, 管理员, 话题标签, 个人主页, 关注, 粉丝, 代表作, 声望). Placeholders and select branches are intact. Plural messages are flattened to a single form with no `plural` wrapper, which is correct for Chinese. No register problems: 你 throughout, no stray exclamation marks. Nothing rated high or medium apart from one item.
- **"Moderation" has no fixed rendering.** It appears as 管理政策 (policy), 内容管理 (menu), and 管理工作 / 管理审计日志 (pack 2). Bare 管理 reads as "administration/management". Recommend 内容管理 wherever "moderation" is the noun: 内容管理政策, 内容管理审计日志. Keep 管理员 for "moderator" as the glossary says, and keep 管理评论 for the verb "moderate".
- **Spacing rule exceptions.** The half-width space between Chinese and digits is applied almost everywhere. The exceptions are the six compact `timeAgo*` timestamps and 7天 in statUnique7d. Unspaced compact timestamps (5分钟前) are common in mainland apps. If they are kept, record them in GLOSSARY.md as a deliberate exception; 7天 should get the space either way.
- **Half-width parentheses** remain in two Chinese strings in this pack (downloadLayers, aboutVersion). Everywhere else the pack uses full-width （）. (The coordinate pair `({x}, {y})` in pack 3's placeSummary is reasonable to keep half-width.)
- **简介 serves both profile Bio and artwork description.** That is acceptable in their own fields. In sentences with no other context (notifications, mention settings), say 作品简介 so it can't be read as the mentioner's bio.
