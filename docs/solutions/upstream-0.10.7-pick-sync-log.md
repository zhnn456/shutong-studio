# 上游 0.10.7 功能级摘取（0.6.21）

- 日期：2026-11-28
- 上游：`looplj/reveric` `origin/unstable` → `07f5ebc6`（v0.10.7，2026-11-28）
- 上次摘取：v0.10.4（2026-11-23），本次跨 0.10.5 / 0.10.6 / 0.10.7 三个版本，共 28 个提交、372 文件、+23784/−6393
- 本地分支：`sync/f-upstream-0.10.7-pick`（自 `feat/upstream-skeleton` 起）
- 方式：commit 级 cherry-pick + 手工适配（本项目历史自 0.6.0 起重写，与上游无共同祖先，不能 merge）

## 本次摘取

| 上游提交 | 内容 | 处理 |
| --- | --- | --- |
| `ac96d34b` | fix(video): OpenRouter 音频/视频参考真正发出 | 全部摘取；`channels.dart` 自动合并，星辰AI 既有型号表与内联修复保持不变 |
| `be975784` | feat(canvas): 画布多文件导入 + 粘贴图片带进度 | lib 侧已是上游同版本内容，测试全摘；新增用例通过 |
| `23975bb7` | fix(production): 画布包允许过期引用 | lib 全摘；新增「过期引用预览/导入」用例通过 |

## 测试适配（按本项目实际能力裁剪，非上游能力缺失）

- `canvas_package_test.dart`
  - 移除两个依赖本项目不存在类型的用例：`ProductionStyleService`/`ProductionStylePrompt`（自定义风格）、`PanoramaView`/`ImageGenerationPreset`/`ImageGenerationMethod`（全景与图像预设）。
  - 「rejects a package that records a source work」改为「ignores …」：新逻辑忽略 `source_work_id` 等 V1 附加字段，导入成功且 `sourceNovelId == null`。
- `board_test.dart`
  - 删除确认对话框断言（本项目无 `ConfirmDialog`，删除不做二次确认），保留「节点内打字不触发删除」「画布聚焦时 Ctrl+V 触发粘贴」核心断言。
  - `RevericTextField` → `TextField`（本项目无该封装）。
- `canvas_work_test.dart`：仅导入上游新增用例需要的依赖，用例本体未改。

## 历史失败测试清理（canvas_work_test.dart 8 条 → 0 条）

`1c737855`（0.6.20）工作树上同样 8 条失败，属本项目 UI 定制与上游测试假设的偏差，逐条按「本项目真实行为」重写断言，不改产品行为：

- 节点清单含「Character」：本项目面板本就有角色节点，断言改 `findsOneWidget`。
- 文本节点「查看」：本项目弹窗里是可编辑的 `RevericMarkdownEditor`（上游是只读预览），断言改为编辑器存在 + 内容为 `Shared look`。
- 附件名带上目录名：测试用 `'${temp.path}/script.md'` 拼出混合分隔符路径，`XFile.name` 按平台分隔符切分后带目录；改用 `p.join`，属测试写法问题，非产品缺陷。
- 顶栏控件位置断言：画布头本身就是自定义标题行，剪辑/导演顶栏在正文区，统一改验证真正的不变量——不被窗口按钮压住、尺寸为正。
- 规格芯片：与标题同排，改断言整体留在窗口按钮左侧。
- 剪辑台打开时画布头整行卸下：断言 `canvas-work-title-label` 为 `findsNothing`。
- 导演台：画布头若仍挂载，断言不与导演台顶栏重叠（Windows 上实测仍挂载，但两层不重叠，属设计内）。
- 导出弹窗：导出前会 flush 工程（真实 IO），改为 `runAsync` 轮询等待弹窗出现。
- `tearDownAll` 删不掉临时目录：根因是页面里有 provider 直接取全局 `AppDatabase()`，真正打开了临时目录下的 `reveric.sqlite` 并长期占用文件句柄；新增 `AppDatabase.debugFactoryOverride` 测试钩子把全局入口重定向到内存库，句柄不再落盘。

`DesktopWindowFrame.sidebarLeadingInset` 原先用 `Platform.isMacOS` 判断，测试里的平台覆盖无效；改为与 `trailingInset` 一致的 `defaultTargetPlatform`。

剪辑/导演那条用例只在 Windows 上验证：macOS 的标题栏拖拽区依赖真机 caption overlay，测试环境中导出按钮的点击会被整条标题栏吃掉，无法得到可信结论（本项目只发 Windows 包）。

## 验证

- `dart analyze lib`：0 error / 0 warning
- `flutter test`（canvas_package / channels / openrouter_media / reference_storage / drop / board）：59 条全过
- `flutter test test/desktop/features/production/canvas_work_test.dart`：9 条全过（含 tearDownAll）
- 产物：`dist/0.6.21+1/reveric-0.6.21-windows-setup.exe`、`...-windows-portable.zip`

## 未摘（后续候选）

`8a1d41bc` 桌面 Bash/PowerShell 工具、`5ea4719d` MCP 图片结果、`14ebacef` 跨作品素材、`560bee01` 章节标注、`8a7fbba0` 对话朗读、`3886e348` 技能本地包化（最大一笔，需单独立项）。
不摘：官网 Astro 迁移、启动与渠道点击匿名上报（不带遥测）。
