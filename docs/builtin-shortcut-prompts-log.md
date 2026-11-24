# 内置快捷方式提示词改造记录

## 为什么改

「快捷方式」页里的 8 个内置动作，提示词原文只有一句话（例如「请润色当前章节，保持原有剧情与作者声音，优化节奏、表达和细节。」）。一句话无法约束输出结构、不能防 AI 腔、不带校准流程，实测产出接近「大纲的扩写版」。

本次把这 8 条全部换成完整提示词：带角色定位、输入清单、硬规则、执行流程、输出格式、自检与落盘要求。

## 改了哪些文件

| 文件 | 改动 |
|---|---|
| `lib/shared/models/builtin_shortcut_prompts.dart` | 新建。8 条完整提示词集中在此维护。 |
| `lib/shared/models/ai_shortcut_action.dart` | 内置表改为引用常量；`BuiltinAiShortcutAction` 新增 `promptRevision`。 |
| `lib/shared/services/initialization/shortcut_action_seeds.dart` | 整份重写：支持按版本升级旧提示词，并保护用户手改过的条目。 |

## 升级机制（关键）

原来的 seed 只在「库里没有这条」时插入，所以已安装用户的旧一句话提示词永远不会被替换。现在：

1. 每条内置动作带 `promptRevision`，本次为 `2`；本机已应用的版本记录在 `SharedPreferences` 的 `builtin_shortcut_prompt_revision`。
2. 启动时若本机版本低于当前内置版本，逐条判断：
   - 库里文本**等于旧版原文** → 视为用户没改过，升级为新版；
   - 库里文本**不等于旧版原文** → 视为用户手改过，**保留用户版本，不覆盖**；
   - 库里已是新版 → 跳过（幂等）。
3. 升级只改 `prompt` 与 `updatedAt`，`name`、开关状态、排序、位置范围都保持用户当前值。

维护约定：以后只要动了任一内置提示词，就把对应条目的 `promptRevision` 加 1。

## 来源与授权

| 来源 | 协议 | 使用方式 | 状态 |
|---|---|---|---|
| MyNovel（`chinese-longnovel-skill`，76★） | MIT | 方法论照搬：大纲生成、分阶段细化、正文生成的全套校准与硬约束；文件工作区指令改写为本地集合与工具。 | 已核实（本地 `third/upstreams/chinese-longnovel-skill`） |
| Humanizer-zh（Copyright (c) 2026 歸藏） | MIT | 去 AI 味规则来源，随 MyNovel 内置（`正文自然化提示词.md`）；本次提炼为「润色本章」的 12 条清单。 | 已核实（同上目录，含 LICENSE 哈希） |
| ailabs-393 / ai-labs-claude-skills（storyboard-manager） | MIT | 人物弧光框架：伤口 ghost、谎言 lie、want vs need、正向/平直/负向弧、压力测试六问、弱角色红旗。 | 已核实（仓库 LICENSE 为 MIT） |
| webnovel-writer（`lingfengQAQ/webnovel-writer`，6.4k★） | **GPL-3.0** | **未使用**。仅参考其公开的问题意识（五维审查、爽点密度量化）。文本与代码一律未复制。 | 已核实为 GPL，故排除 |
| Mochocyang / QMAI（`foreshadowing-suspense` 等） | 未核实 | 未引用。 | 待核实，不采用 |

**排除理由**：GPL-3.0 具传染性，把其文本并入闭源商业产品会触发开源义务。用户要求「只拿宽松协议」，故按 MIT 素材落地。

## 回滚

- **推荐**：整份撤回本次改造（提示词 + 升级机制），不动开书骨架与更新浮窗：
  ```powershell
  git revert <本次 commit>
  ```
- 只回滚某一条：把 `builtin_shortcut_prompts.dart` 里对应常量换回 `_legacyBuiltinPrompts` 中的原文，并把该条 `promptRevision` 改回 `1`。本机已记录版本为 2 时不会再次覆盖；若想让它重新生效，删 `SharedPreferences` 的 `builtin_shortcut_prompt_revision` 键。
- 注意：如果用户手改过该条，库里文本已不等于旧版原文，升级逻辑本来就不会覆盖，回滚也不需要额外处理。

## 待办（未做）

- 8 条提示词尚未实机跑一遍验证产出质量（需要装包后用真实书稿测）。
- 「骨架看板」仍未开工。
