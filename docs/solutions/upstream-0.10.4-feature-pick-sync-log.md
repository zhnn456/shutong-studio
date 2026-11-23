# 上游 0.10.4 功能级摘取记录

- 日期：2026-11-23
- 工作分支：`sync/f1-upstream-0.10.4`（基于 `unstable` @ `3fb57a9c`）
- 上游来源：`origin` = `looplj/reveric`（`unstable` 分支，已发布 `v0.10.4`）
- 上游 HEAD：`cb78d8ae fix(chat): refine expanded layout and markdown readability`

## 1. 决策背景：整体合并已经不可行

上次同步基线是 0.9.0（`fcd73dbd`，2026-11-12）。到本次拉取为止：

| 指标 | 数值 |
|---|---|
| 上游领先提交 | 106 |
| 我们领先提交 | 109 |
| 上游改动文件 | 976 |
| 我们改动文件 | 711（+60875 / −7733 行） |
| 双方都改过的文件 | 609（占我们改动 85.7%） |
| 直接 merge 的冲突文件 | **441** |

`git merge-tree` 试算结果：一次性合并要人工解决 441 个文件的冲突，且其中大量是我们重写过的 UI 模块，回归成本不可控。

**结论：放弃 git 层的整体 merge，改为功能级摘取。** 上游从此只作为参考实现与功能来源，不再追求"和上游一致"。

## 2. 本轮摘取的功能

| 上游提交 | 功能 | 文件数 / 与我们重合 | 结果 |
|---|---|---|---|
| `54729615` | Run 工具分页读应用日志 | 13 / 8 | 已摘入 |
| `bfb0495f` | 章节正文朗读（选区朗读 + 阅读页 + 朗读对话框） | 25 / 9 | 已摘入 |
| `69efbc8a` | 应用更新走 R2 | 9 / 2 | 只摘实现，默认源不切换 |

保留未摘（附理由）：

- `2fcca815` 写作记忆 v2（33 文件）：与我们的记忆/插件层改动面重叠大，需要单独一轮移植；它对 P0-1 上下文预算只是缓解，不是根因修复。
- `7d41aae1` 生图自定义数量与尺寸、`fec83c8c` gpt-image 修复：29/19、12/10，与我们 provider 改造撞车，暂缓。
- `be975784` 画布多文件导入、`cb78d8ae` 聊天展开布局：不在小说创作主线。
- 移动端（`050f4113` 等）：我们不发移动端。

## 3. 冲突处理记录

### 3.1 日志分页（`54729615`）

冲突 2 个文件：

- `lib/shared/widgets/ai/tools/tool_card_descriptor.dart`：两边都在 `_runActionKeys` 里加条目。取并集：保留我们的 `('production','canvas-preview')` 多行写法，并加入上游的 `('debug','log')`。
- `lib/shared/services/ai/tools_run.dart`：上游新增 `_runDebugLogs` 与 `_otherCommandHint` 两个方法，冲突块出现在 `_runContextHelp` 之前。解析时用正则删冲突标记，把整块（含方法定义）一起删掉了，导致 `run` 表的 `('debug','log')` 调用还在、定义没了。

  处理方式：从上游原始文件 `git show 54729615:lib/shared/services/ai/tools_run.dart` 中按行号区间重新插回 `_runDebugLogs`；`_otherCommandHint` 因为我们的 `_runCommands` 结构与上游不同、没有调用点，直接不引入（避免死代码告警）。

  教训：解析"整块新增方法"的冲突时，不能按 `<<<<<<<` 到 `>>>>>>>` 直接丢弃，必须先确认同名定义在文件里是否已存在。

### 3.2 章节朗读（`bfb0495f`）

冲突 2 个文件：

- `lib/desktop/widgets/workspace/chapter_editor.dart`：import 取并集（`horizontal_wheel_scroll.dart` + 我们的 `reveric_button.dart`）；构造函数参数与字段取并集（我们的 `onWriteChapter / onSettleChapter / onDraftOutline / onReviewChapter / settleListed` 与上游的 `onNarrateSelection` 并存）。第一次合并时 `onNarrateSelection` 被重复声明成两个 `this.` 形参，靠 `dart analyze` 的 `duplicate_field_formal_parameter` 抓出来。
- `lib/desktop/widgets/workspace/novel_workspace_panel.dart`：上游 hunk 认为 `ChapterEditor(...)` 在 `onAddSelectionToChat` 之后就结束，我们的版本后面还有 5 个回调。取并集：把这 5 个回调保留，末尾补 `onNarrateSelection: canNarrateSelection ? (text) => showNovelNarration(...) : null`；`WorldManualPanel` 的尾巴恢复原样。

### 3.3 R2 更新源（`69efbc8a`）

冲突 1 个文件 `lib/shared/providers/update_providers.dart`：上游把默认源换成 `R2UpdateSource`，我们的更新清单走自有 GitHub Releases（`zhnn456/shutong-studio`）。

处理：**保留我们的 GitHub Releases 作为默认源**，只把 R2 实现（`lib/shared/services/update/sources/r2_update_source.dart`）、清单脚本、测试摘进来备用。对应地把上游新增的「默认源是 R2」测试改为「默认源是 GitHubReleasesSource」。

## 4. 验证

- `dart analyze`：改动文件无 error/warning，仅剩仓库原有的 `deprecated_member_use` / `use_build_context_synchronously` info。
- 朗读相关测试（`test/desktop/features/narration`、`narration_test.dart`、`narration_service_test.dart`、`chapter_editor_test.dart`）：**34 条全部通过**，其中 `chapter_editor_test.dart:457` 直接断言「朗读选中内容」按钮把选区传给回调。
- 更新链路测试：`update_providers_test.dart` + `r2_update_source_test.dart` **17 通过 / 1 失败**。
- 日志分页测试：`tools_run_test.dart` + `run_subcommand_localization_test.dart` **62 通过 / 1 失败**。
- 基线复核（在 `3fb57a9c` 的临时 worktree 里跑同两条）：**同样失败**，确认以下两条是既有问题，不是本次摘取引入：
  1. `ffmpeg frames validates input and obeys files.read permission`：期望 `permission_denied`，实际 `invalid_argument`（我们的媒体权限校验顺序与上游测试预期不同）。
  2. `startup and overlapping refreshes share one request`：期望合并请求计数 1，实际 0（`latestReleaseProvider` 的 dedupe 与测试预期不一致）。
- 构建：`flutter build windows --release` → `√ Built`，耗时 **190.3 s**，新 exe `2026-11-23 06:22:13`。
- 启动验证：新 exe 正常启动，作品列表与章节编辑正常加载。

## 5. 待办

1. 把 `sync/f1-upstream-0.10.4` 合回 `unstable`（本地合并，未推送）。
2. 修掉上面两条既有测试失败（媒体权限顺序、更新 dedupe），它们会持续污染回归信号。
3. 下一轮候选：写作记忆 v2 手工移植；生图自定义尺寸留到 provider 改造收敛之后。
4. 以后每次只按「功能价值 + 冲突面」挑选，不再尝试整体对齐上游。

---

# f2：剧本 / 画布整批对齐 + 小说逐项核对

- 日期：2026-11-23（同日晚间轮）
- 工作分支：`sync/f2-screenplay-canvas`（基于 `unstable`，f1 已 ff 合入）
- 用户指令：「剧本和画布功能可以全部按照上游修改，小说的功能需要核对之后再决定是否合并」；并明确**禁止以"依赖太多"为由剔除任何上游新增功能**

## 6. 做法：签出 + 依赖闭包补齐（而不是删功能）

基线仍是 441 冲突级别，所以剧本/画布没有走 merge，而是按路径从上游整批 `git checkout origin/unstable -- <path>`，再用 `dart analyze` 报错反推依赖闭包逐文件补齐。

第一批签出：`lib/desktop/features/{screenplay,production,storyboard,canvas}`、`lib/mobile/features/screenplay`、`assets/bundled_skills/{screenplay-tools,canvas-composition,canvas-work-tools}`、`assets/official_skills/{screenplay-production,screenplay-writing}`。

第二批（编译反推）：`shared/services/production`、`shared/widgets/production`、`shared/models/{canvas_*,transcription}`、`canvas_providers.dart(.g)`、`production_* provider`、`canvas_service.dart`、`tools_{canvas,production,production_schema,screenplay}.dart`、`desktop/features/canvas_gallery`。

### 6.1 一次纠偏（重要）

中途曾判断「`canvas_gallery`（画布广场发布）、`models/transcription`、`transcription_action`、`transcription_service` 是上游全新功能、会拖出一大串未移植依赖」，于是把这批文件删掉"降噪"。用户当场否决：**做软件不该剔除上游新增功能**。

处理：所有被删文件全部 `git checkout origin/unstable --` 恢复，改为**补齐依赖闭包**。此后规则固定为：**功能一律保留，缺口靠补依赖 + 补 i18n + 补 schema 解决，不允许走删除路线。**

依赖闭包用脚本递归解析 `import/export`（相对路径与 `package:reveric/` 路径），本地缺失即从上游签出，自动补入 9 个文件：

- `lib/desktop/features/editing/host.dart`
- `lib/shared/widgets/screenplay/director_workspace_host.dart`
- `lib/shared/services/canvas_gallery/{service,orchestrator}.dart`
- `lib/shared/providers/{canvas_gallery_providers,transcription}.dart`
- `lib/shared/models/user_message_presentation.dart`
- `lib/shared/services/ai/transcription/{client,decoders}.dart`

### 6.2 i18n 与基础设施

- `locale_keys.dart`：上游 5324 常量、我方 5456，缺 101 个 → 按原样追加到文件末尾（带横幅 `// ── 上游 0.10.4 新增（自动补齐，勿手工重排）`），不重排既有顺序。
- `assets/translations/{zh-CN,en}`：flatten 点号 key 补 192 条/语言（screenplay 32、production 48、editor 6、ai 5、tool 4、common 3、provider 2、assets 1）。
- 基础设施对齐（上游多为"仅新增行"，按需合入）：`theme/reveric_spacing.dart`、`database/daos/{asset,generation_task}.dart`、`models/generation/task.dart`、`models/production/media.dart`、`services/ai/trace_reporter_service.dart`、`services/ai/media/*`、`services/storyboard/service.dart`、`services/director/*`、`services/editing/*`、`models/editing/document.dart`、`desktop/features/editing/*`、`widgets/ai/chat/{chat_message_view,compaction_card,attachment_body,published_chat_image,chat_message_parts,session_switcher,floating,header}`、`widgets/ai/tools/character_image_tool_card.dart`、`widgets/ai/markdown_text.dart`、`widgets/settings/{provider_overview,provider_type_picker,provider_draft}.dart`、`services/object_storage/service.dart`、`services/anonymous_outbox_service.dart`。

### 6.3 schema：只做增量 v9，不动小说库

上游 `AiProvider` 是 drift 生成类，`asrModels` 是表列（上游 schema v10）。我方 `app` 库原 `currentSchemaVersion = 8`，且有上游没有的 `productCode` 列与不同的 v7/v8 迁移，因此不做整体替换：

- `AiProviders` 加 `asrModels`（`StringListConverter`，默认 `'[]'`）
- `currentSchemaVersion` 8 → 9，新增 `AppDatabaseMigrations.migrateToV9`（`addColumnIfMissing(db.aiProviders, db.aiProviders.asrModels)`），`onUpgrade` 加 `if (from < 9)`
- `build_runner build --delete-conflicting-outputs` 重生成（5967 outputs）
- `AppDatabase` / `NovelContentDatabase` 各加 `ephemeral(super.executor)` 构造（供画布广场只读沙箱）；**小说 schema 不动**

### 6.4 保留我们的 fork 定制

`lib/shared/models/ai_provider.dart` 取上游版后回插星辰AI 定制：`api88PrimaryBaseUrl = https://api.lk888.ai/v1`、`api88FallbackBaseUrl = https://api.lk666.ai/v1`、`api88ActiveBaseUrl / markApi88BaseUrlFallback / resetApi88BaseUrl`，`aiProviderFixedBaseUrl(api88)` 返回 active URL，显示名改回「星辰AI」（上游为 88API）。

## 7. 独立缺陷：星辰AI「图像模型 · 获取模型」只剩 `mj_imagine`

现象：用户截图显示网关返回 173（实测 199）个模型，「图像模型」列表只有 `mj_imagine`。

根因：`NewApiClient.modelIds(AiModelKind.image)` 只靠硬编码 `mj_imagine` + `supported_endpoint_types` 的 `image-generation / image-edit / gemini`；而 `api.lk888.ai/v1/models` 返回项只有 `{id, object, created, owned_by}`，**没有端点类型字段**，于是只剩硬编码那一条。上游同处逻辑相同（上游也有此限制，属共性缺陷）。

修复：新增顶层 `isGatewayImageModel(String modelId)`，按 `-` `_` `/` 拆分后的段命中 `image / images / imagine / midjourney / mj / imagen / ideogram / flux / dalle / seedream / seededit / recraft / banana`，或以 `mj- / dall-e / gpt-image / stable-diffusion / sdxl / sd3 / nano-banana / banana- / qwen-image / wanx / kolors / grok-image / doubao-seedream` 开头；image 分支改为 `mj_imagine || imageByName || 原端点判断`，chat 分支纳入 `imageByName` 以排除图像模型。

真机验证（进入「AI 供应商 → 星辰AI」，点「获取模型」）：

| 分类 | 结果 |
|---|---|
| 网关总模型 | 199 |
| 图像模型 | **26**（含 `banana-2 / 2-token / 2.1 / 2.1-token / pro / pro-token`、`doubao-seedream-*`、`tt-image-*`、`gk-image-2.0`、`wan2.x-image`、`minimax-h3-image`、`muse-image`、`win mj_imagine`） |
| 视频模型 | **20**（seedance、kling、hailuo-h3、vidu、wan3.0 系列等） |
| 聊天模型 | **160**（已排除图像/视频模型） |

证据截图：`D:\shutong studio\_test_1117\w2f.jpg`（26 条图像模型列表）。

## 8. 小说（novel）：逐项核对结论

核对方法：`git diff HEAD origin/unstable -- "*novel*"` 逐文件分 hunk 判定「上游新增 / 我方独有」，再按「是否回退我方功能 + 依赖是否已具备」决定合并。

### 8.1 结论表

| 文件 | 差异性质 | 决定 |
|---|---|---|
| `novel_list.dart` | 上游新增画布作品菜单「发布到画布广场」（`publishCanvasFromShelf`） | **合并** |
| `novel_content_database.dart` | 上游 `close()` 增加 `identical(cachedDatabase.database, this)` 判断；新增 `ephemeral` 构造 | **合并**（`ephemeral` 已在 f2 补） |
| `mobile/pages/novel_chat_page.dart` | 上游把 AgentRule 统一到 `models/agent_rule.dart` + `formatForPrompt()` | **合并** |
| `desktop/pages/novel_editor.dart` | 上游新增 `expandedChatHeaderActionsKey`（聊天头部按钮注册标题栏手势排除区） | **合并**（连带 `expanded_chat_area.dart`、`chat/panel.dart` 透传） |
| `workspace/novel_overview.dart` | 上游是简化版（我方多 974 行：项目简介卡/创作片段/写作入口） | **不合并**（合并=回退我方总览） |
| `workspace/novel_workspace_panel.dart` | 上游 2 行，且删掉我们的目标/风格/世界观手册/带引用续写/章节状态回调 | **不合并** |
| `models/novel_workspace.dart` | 上游无 `world_manual` 章节 | **不合并**（保留世界观手册） |
| `services/{novel_goal,novel_style,novel_quota_gate}.dart`、`providers/novel_{goal,style}_provider.dart` | 仅我方有（小说目标、文风、免费额度门禁） | **保留，不引入上游** |
| `widgets/novel_create_submitter.dart`、`services/{novel_actions,demo_novel}.dart` | 上游无额度门禁 / `NovelFreeLimitException` 处理 | **保留我方** |
| `desktop/pages/novel_editor.dart` 的 chronicler prompt / `selectFirstWhenMissing` / 章节状态机 | 我方修复与增强（真实 chapter_id 定位、进页自动选中、draft→writing→reviewed→published） | **保留我方** |
| `mobile/pages/novel_editor_page.dart` | 上游抽出 `MobileWorkspaceHeader / MobileSectionChips`（+20 行，我方多 195 行） | **暂缓**：我方移动端结构更复杂，抽组件需单独一轮 |
| `docs/solutions/novel-flow-*.md` | 上游无（我方方案文档） | **保留** |

### 8.2 本轮实际落到代码的四处

1. 书架画布作品菜单增加「发布到画布广场」（`LocaleKeys.productionGalleryPublish` + `publishCanvasFromShelf`）
2. `NovelContentDatabase.close()` 增加 `identical` 判断，避免沙箱/临时库误关共享缓存
3. 移动端聊天 `userRules` 统一走 `agentRules.formatForPrompt()`，删除本地重复实现 `_formatMobileAgentRules`
4. 聊天头部操作区注册到标题栏手势排除区（`novel_editor.dart` → `ExpandedChatArea` → `AiChatPanel` → `ChatHeader.actionsGestureExclusionKey`），双击聊天头部按钮不再误触窗口最大化

## 9. 验证

- `dart analyze lib`：**0 error**（仅剩仓库既有 info）
- `flutter build windows --release`：`√ Built`，耗时 187.7 s
- 真机：启动正常，DB 迁移无报错，星辰AI 三类模型数量如上表；书架、剧本、画布页面可正常进入
- 未跑：全量 `flutter test`；f1 记录中的两条既有失败（`tools_run_test` 媒体权限、`update_providers_test` dedupe）仍在，与本次改动无关

## 10. 待办

1. `sync/f2-screenplay-canvas` 的 287 项变更尚未提交，提交后再考虑 ff 合回 `unstable`（不推送上游）
2. 移动端 `novel_editor_page` 的 `MobileWorkspaceHeader / MobileSectionChips` 抽取：单独一轮评估
3. `widgets/ai/chat` 里 `chat_side_panel.dart`、`composer.dart` 与我方定制度差异大，未整体替换；写作记忆 v2 是否跟进仍未决
4. 上游 v9（`anonymous_outbox_events` 结构变更）与 v10 迁移未采用，我方 app 库仍是"部分对齐"，是否完全一致待定

