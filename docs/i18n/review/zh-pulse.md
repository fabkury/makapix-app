# zh review: Pulse pack (pulse-zh.jsonl, 15 messages)

| key | severity | problem | current | proposed |
|---|---|---|---|---|
| pulseTitle | high | 动态 is already the glossary word for "feed" and is used that way throughout app_zh.arb (“推荐”动态, 公开动态, 动态顶部, 在动态中显示为新帖). Naming the Pulse page 动态 too gives two different pages one name; a user cannot tell the activity timeline from the artwork feeds. | 动态 | 脉动 |
| pulseComingSoon | high | Follows pulseTitle: as written it reads "the feeds are coming soon", which is false (the feeds exist). Also 尽在一处 is stiff; 尽在这里 is the usual phrase. | 动态即将上线：社区里发生的一切，尽在一处。 | 脉动即将上线：社区里发生的一切，尽在这里。 |
| pulseLikes | low | 回应 with an artwork as a direct object reads awkwardly; the shipped notifications use the pattern 对…回应 (notifReaction: {who} 对 {title} 回应了 {emoji}). | `<b>{who}</b> 回应了 {count} 个作品` | `<b>{who}</b> 对 {count} 个作品作出了回应` |
| pulseMore | low | The measure word 个 is wrong for some of the cards this line closes (comments take 条, badges take 枚, as pulseComments and pulseBadges themselves write). A neutral counter fits every card. | 还有 {count} 个 | 还有 {count} 项 |

## Systemic notes

- **Pulse must not share a name with the feed.** The glossary gives feed = 动态, and about a dozen shipped messages rely on it. Pick a distinct name for Pulse (proposed: 脉动, short, close to the English image, and unused in app_zh.arb; 新鲜事 is a plainer alternative), add it to the glossary's Club table, and use it in pulseTitle and pulseComingSoon.
- **No plural wrapper**: the plural messages are written as plain strings with {count}, like the shipped pmdArtworks. All placeholders and the `<b>{who}</b>` tags are present and intact in every message.
- **Spacing and punctuation** are correct throughout: a half-width space between Chinese and placeholders or digits, full-width colon and comma.
- **Terms checked and consistent** with the glossary and the shipped file: 作品, 发布, 再创作, 评论, 播放器 with 注册 (as on the Players page), 徽章, 声望, 推荐 (pulsePromoted matches notifPromoted 已被推荐).
