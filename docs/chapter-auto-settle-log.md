# 正文保存后自动沉淀（纯代码）与骨架看板

日期：2026-11-24 ・ 版本：0.6.17 ・ 分支：feat/upstream-skeleton

## 一、为什么做

原来「沉淀」这一步只能靠 chronicler（AI agent）在聊天里跑一遍，作者写完一章后：
概览页一直提示「有正文未沉淀」，章节状态停在草稿，下一章写前的上下文也读不到本章发生了什么。
用户要求改成**代码的智能**：保存正文就自动沉淀，不调 AI、不花钱、不出幻觉。

## 二、算法从哪来（不是自研）

用户硬要求：一律优先用 GitHub / 开源社区现成方案，不自己造轮子。选型过程：

| 候选 | 协议 | 结论 |
| --- | --- | --- |
| [cn-dev/chinese-summary](https://github.com/cn-dev/chinese-summary) 1.0.5（npm） | MIT | **采用**。纯机器算法、零依赖、字级 n-gram 绕开中文分词、TextRank + 位置加权 + TF-IDF + MMR，README 明确写「不调 AI、不装分词器、不联网」 |
| ml_text_summarizer（pub.dev，纯 Dart） | MIT | 备选。只支持英/土耳其语停用词，中文分句不适用，未采用 |
| ai_text_summary（pub.dev） | MIT | 排除。内部调用 OpenAI，与「不靠 AI」直接冲突 |
| sumy / jieba（Python） | — | 排除。Flutter 桌面端无法运行 Python 进程 |

所以做的是**移植**，不是发明：
`lib/shared/services/text_summary/chinese_summary.dart` 逐段照搬上游公式与默认参数
（分句规则、相似度 `|A∩B|/(log|A|+1+log|B|+1)`、TF-IDF `log((n+1)/(df+1))+1`、
位置权重 1.5/1.2/1.1/1.05、TextRank d=0.85 迭代 30 次、MMR λ=0.7）。
上游源码留在 `third/upstreams/chinese-summary/package/src/chinese-summary.ts`，可直接对照。

未移植：上游 level 1（子句极致压缩成一句话）与 level 2（多轮重排）。
章节梗概要的是"能读懂的几句"，压成一句没有意义。

## 三、沉淀出来的是什么

`lib/shared/services/chapter_auto_settle.dart` 在摘要引擎之上产出六项，全部可核查、无改写：

| 字段 | 来源 | 落到哪 |
| --- | --- | --- |
| brief | 选中的高分句按原文顺序拼接，约 200 字 | `chapter_nodes.brief` |
| events | 每段取最高分句，2–6 条 `{title, summary, state_change}` | `chapter_nodes.events` |
| tension | 冲突词密度 × 感叹/问号密度 × 短句比例，映射 1–10 | `chapter_nodes.tension` |
| emotion | 20 词情绪表命中次数取前 2 | `chapter_nodes.emotion` |
| cast | 人物卡姓名与别名在正文中出现的名单 | 仅返回，暂不落库 |
| hook | 最后一句，截断 60 字 | 仅返回，暂不落库 |

`state_change` 只在句中出现「于是/从此/决定/答应/必须/再也…」这类推进词时才填，
否则留空——**不编状态变化**。

## 四、怎么挂上去、怎么防止乱写

挂载点在 `novel_content.dart` 的 `_writeChapterContent`（正文所有写入路径的公共出口：
编辑器自动保存、移动端保存、AI 写入）。三道闸门：

1. 只处理普通章节（非卷），正文 ≥ 400 字（`chapterAutoSettleMinWords`）。
2. **已有 brief 且不是"从本章正文抽出来的"** → 视为作者或 AI 的成果，只把状态补成已沉淀，**一个字段都不改**。
   判定方式 `briefLooksExtracted`：把 brief 切句，逐句在正文里找原文，命中率 ≥60% 才算自动生成。
   这样不需要额外存"谁写的"，也不会覆盖人工成果。
3. 算出来的 brief/events/emotion 与库里完全一致 → 不写库（避免每次自动保存都落一次盘）。

失败一律 catch 后记日志，绝不影响正文保存本身。

状态推进：`draft/writing → reviewed`（已沉淀）。已发布的章节不动。

## 五、骨架看板

`lib/desktop/widgets/workspace/skeleton_board.dart`，入口在概览页「写作进度」卡右上角的
「骨架看板 ›」文字按钮（`novel_overview.dart`）。

- 左侧卷卡：卷名、章数、已写、字数、三条覆盖率（章纲 / 已沉淀）与进度条。
- 右侧章行：章号 + 标题 + 梗概（没有梗概时退回显示章纲）+ 字数 + 状态；
  缺章纲、待沉淀、字数低于目标 60% 各有小标签。
- 数据全部来自已加载的章节树（`chapterTreeProvider`），不新增查询、不新增 provider，
  所以正文一保存，看板数字自己就变。

## 六、涉及文件

| 文件 | 变更 |
| --- | --- |
| `lib/shared/services/text_summary/chinese_summary.dart` | 新增，MIT 上游移植 |
| `lib/shared/services/chapter_auto_settle.dart` | 新增，沉淀产出与闸门判定 |
| `lib/shared/services/novel_content.dart` | `_writeChapterContent` 末尾调用沉淀 |
| `lib/desktop/widgets/workspace/skeleton_board.dart` | 新增，看板 |
| `lib/desktop/widgets/workspace/novel_overview.dart` | 加看板入口 |
| `lib/shared/localization/locale_keys.dart` + 两份 `workspace.json` | 15 条新文案 |
| `test/chapter_auto_settle_test.dart` | 新增 5 个回归用例 |
| `third/upstreams/chinese-summary/` | 上游源码留档 |

## 七、回滚

整份回滚（把自动沉淀与看板一起撤掉）：

```powershell
git revert <本次提交>
```

只关掉自动沉淀、保留看板：在 `novel_content.dart` 的 `_writeChapterContent` 里删掉
`await _autoSettleChapter(...)` 一行即可，其余代码留着不会有副作用。
已经沉淀过的章节数据留在库里（brief/events/tension/emotion），不会丢稿。

## 八、维护约定

- 改选句参数或字段含义，必须把 `chapterAutoSettleVersion`（当前 `auto_settle.v1`）+1，
  否则已沉淀的章节会因为"结果没变"而不再重算。
- 上游若升级算法，先更新 `third/upstreams/chinese-summary`，再改移植文件，并在本文档记差异。
- 不要在没有上游依据的情况下改相似度/TextRank/MMR 的公式。
