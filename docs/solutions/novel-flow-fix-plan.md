# 小说创作流程：问题核对与修复规划

> 依据：`_test_0614/实测记录.md` + `_test_0614/评估与优化建议.md`（0.6.14 真机实测），
> 本文对每条结论在当前 `unstable`（已含上游 0.10.0 三批 + 自有改造）做了**代码级复核**，
> 只把"仍然存在"的问题纳入修复范围，并给出可落地的工程锚点与验收标准。

---

## 一、结论

写作内核（写前读回 / 写后回写 / 多智能体核验 / Fair-Play 规则注入）是真闭环，不动。
拖体感的是**外围流程**：向导失控、上下文不裁剪、静默等待、静默改写、下一步靠模型自觉。

| # | 问题 | 0.6.14 实测 | 当前 unstable 代码复核 | 判定 |
|---|---|---|---|---|
| 1 | 向导 3 轮变 8 轮，无轮次进度、无出口 | 8 轮，点「取消」才收口 | `assets/bundled_skills/setup/SKILL.md` 无任何轮次上限；`setup_phase_gate.dart` 只按**会话数 ≤3** 控制是否注入，不控轮次；全仓无 `setup_round` 状态 | **仍存在** |
| 2 | 上下文不裁剪，越写越卡 | 第 32 轮 `messages=107 / chars=21649` | `agent_context_manager.dart:26` 压缩阈值 = 上下文窗口 80%（deepseek 64k → 约 51k token）；`chat_turn_runner.dart:1520`、`spawn_agent_handler.dart:333` 均用它。21649 字≈1.5 万 token，远低于阈值 → 永不触发压缩 | **仍存在** |
| 3 | 问卷只有「取消」，无「跳过向导」 | 第 8 轮靠取消跳过后才收口 | `lib/shared/widgets/ai/tools/ask_user_card.dart:398/413` 只有 cancel；取消只置当前卡为 cancelled，不影响向导是否继续 | **仍存在** |
| 4 | 跨章静默改写，不主动告知 | 第 1 章 3182→3360 三次变化 | 有 `change_commits` + `change_history_panel`（被动面板），写入侧无任何主动事件 | **仍存在** |
| 5 | 执行流混入英文残片 | `external_fire` / `fine. Check` | 推理流直接展示，未见任何非中文清洗 | **仍存在** |
| 6 | 导出只在作品卡片右键 | `novel_list.dart:246` | 桌面端仍只有该入口（移动端另有 `library_page.dart:1137`） | **仍存在** |
| 7 | 「下一步」靠 AI 自觉 | 建议卡时有时无 | `chapter-write-pipeline` 技能第 4 步只要求"列待回填清单等确认"；`SuggestNextAction` 只在 `setup` 技能收尾"挂一次"，无硬闸门 | **部分存在** |

补充两条实测没说但同源的判断：

- **"静默 90 秒"不是网络问题**：写正文时子 agent 反复 `编辑 章节` 5+ 次、每次都是完整 tool round，界面只有"思考中"。缺的是**步骤级进度**，不是超时兜底。
- **书名"未命名作品"**：建书即落盘、书名靠向导第 4 轮才写，中间态没有任何提示。这条并入 P0-A 的向导改造顺手解决（建书即给临时书名 + 顶部标"草稿"）。

---

## 二、修复原则

1. **硬约束放 Dart 侧，提示词只做引导**。轮次封顶、上下文阈值、下一步卡都由代码保证，不能靠模型"记得"。
2. **不新增框架**，全部复用现有底座：`novel_states`（`novel_onboarding`）、AskUser 卡片、`AgentContextManager` 压缩、`change_commits` diff 与回滚、`SuggestNextAction`、`NovelExportDialog`、`compaction_card`。
3. 每项都要有 **自动化测试 + 真机走查**，缺一不算完。

---

## 三、P0（第一批，按此顺序做）

### P0-A 向导封顶 3 轮 + 常驻出口 + 轮次可见

改动点：

- `A1` 状态扩展：`lib/shared/services/novel_actions.dart:203`（写 `novel_onboarding`）改为写入
  `{status: eligible|in_progress|completed|skipped, round, maxRounds: 3}`；新增读取方给 prompt/工具用。
- `A2` 轮次计数：`lib/shared/services/ai/tools_ask_user.dart` 每次成功出卡且 setup 段激活（`SetupPhaseGate.shouldShow` 为真）时 `round++` 并回写。
- `A3` 硬闸门（核心）：`round >= maxRounds` 时 AskUser **不再渲染新问卷**，直接返回工具结果
  「向导已达 3 轮上限：把已确认内容落盘后直接进入写作，剩余问题留到写作中按需追问」。
- `A4` 提示词预算：`assets/bundled_skills/setup/SKILL.md` 顶部写明
  「最多 3 轮 AskUser：①根决策+结构项 ②元数据+写作约束 ③能力配置；第 3 轮必须先落盘再问」。
- `A5` 卡片 UI：`ask_user_card.dart` 在 onboarding 期显示「第 X / 3 轮」，底部固定
  「跳过向导，直接开写」→ 取消当前卡 + `status=skipped` + 自动发一条"按已确认设定直接写第一章"的用户输入。
- `A6` 「取消」语义统一为"跳过本轮向导"，不再无限追问。
- `A7` `setup/SKILL.md` 去掉问卷里的「加入书架」选项（与右上按钮重复），只保留按钮。

验收：新建一本书 → 问卷 ≤3 张；点跳过 → 下一轮直接进正文；DB `novel_onboarding.status` ∈ {completed, skipped}；gate + 计数器有单测。

### P0-B 上下文预算化（单次请求 ≤12k token）

- `B1` 阈值下探：新增 `chatCompactTokenLimit`（默认 **12000**，设置页可选 8k/12k/20k），
  `chat_turn_runner.dart:1520` 与 `spawn_agent_handler.dart:333` 取
  `min(窗口 80%, chatCompactTokenLimit)`。
- `B2` 工具结果截断：`read` 章节/资源返回超过 4k 字截断，附「已省略 N 字，用 path/range 精读」。
- `B3` 章节收口摘要：一章写完后自动生成「章节摘要卡」（人物状态 / 新增伏笔 / 未解钩子 / 下一章入口）
  注入会话 summary，正文本体从上下文移除（DB 原文不动）。
- `B4` 可见：聊天头部显示「上下文 X / 12k」，接近阈值时用现有 `compaction_card` 提示已压缩。

验收：连写 3 章，日志里单次请求 token ≤12k；同一条"写第 2 章"任务的静默时长显著下降；有单测。

### P0-C 章节流水线按钮化（把"AI 自觉"换成产品流程）

- `C1` 编辑器/聊天面板顶部固定 4 步条：**写前简报 → 起草正文 → 审查 → 沉淀回填**，
  与 `chapter-write-pipeline` 技能四步一一对应；当前步高亮，点任一步发一条预置 prompt。
- `C2` 步进由工具事件驱动（写完章节 → 自动进"审查"），不依赖模型口述。
- `C3` **下一步硬闸门**：一章落盘后由 Dart 侧生成"下一步"卡（下一章 / 审稿 / 导出 / 开圆桌），
  模型没想起来也照常出现。

验收：写完一章必定出现下一步卡；不点流水线也能用普通对话。

---

## 四、P1（第二批）

| 项 | 做法 | 锚点 |
|---|---|---|
| 跨章改写主动提示 | 写入工具命中"非当前章节"的修改时发出 `ChangeNotice` 事件 → 聊天内提示卡「为保持时间线一致，修改了第 1 章的 X 处」+ diff 摘要 + 一键回滚到该 commit；「最近改动」角标高亮；设置项"跨章自动改写需我确认"默认提示不阻断 | `lib/shared/services/working_overlay.dart:693 autoSaveCommit`、`change_history_panel.dart` |
| 英文残片 | ① 展示层把连续 ≥6 个拉丁词折叠为「（推理省略）」，代码块/路径/JSON 白名单不折叠 ② 提示词加"全程中文，禁止英文思考片段" ③ 核验子代理默认下调 reasoning 档位 | `agent_config.dart`、聊天推理流组件 |
| 导出入口 | 编辑器工具栏 + 「进度」面板加「导出全文」，复用现有弹窗 | `novel_export_dialog.dart`、`story_progress_panel.dart` |

---

## 五、执行与验证

1. 分支 `feat/novel-flow-p0`，P0-A / P0-B / P0-C **分开提交**，先合 P0-A（改动最小、体感最大）。
2. 每项完成门槛：`flutter analyze` 0 error/0 warning + 定向单测全绿 + `flutter build windows --release` 成功。
3. 真机走查（需要你点，我这边主桌面接管拿不到权限）：
   新建一本书 → 数问卷张数 → 中途点「跳过」→ 写第 1、2 章 → 观察是否出现跨章改写提示 → 导出。
4. 三项全过后打 0.6.15 候选版本，再动 P1。

---

## 六、风险与取舍

- **3 轮封顶可能不够**：某些题材确实需要更多设定。兜底是"跳过 + 写作中按需追问"，能力不丢，只是不在开书阶段榨干用户。
- **摘要压缩会失真**：DB 原文完整保留，摘要卡可点开回原文；压缩前先落一次 commit。
- **跨章提示噪声**：只在"非当前章"触发，同章编辑不提示。
- **英文折叠误伤**：代码块、资源路径、JSON、英文书名白名单不折叠。

## 七、不做

自研小说模型；把向量 RAG 当主线（瓶颈在编排不在检索）；继续堆设定页类型。
