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
