# 上游 0.10.3 同步记录（B1–B4 已完成）

日期：2026-11-21　｜　分支：`unstable`（原 `sync/upstream-0.10.3`、`sync/b2-ai-contracts`、`sync/b3-settings-guides`、`sync/b4-data-channels`）
基线：同步前 `449b362`，打 tag `local-baseline-20261121`

## 一、执行前的固化

同步前把工作区 45 个文件拆成三个提交入库：

| 提交 | 内容 |
|---|---|
| `2da8aca` | feat(world)：世界观手册、内置样本库与侧栏入口 |
| `6df1544` | feat(flow)：章节流程状态机与对话链路收尾 |
| `2184b70` | docs：写作流程计划与上游同步记录 |

## 二、B1 零冲突修复（6 条）

| 上游 | 结果 | 冲突处理 |
|---|---|---|
| `c58a968` 章号顿号 | 直摘 | 无 |
| `1eefb0a` 排队回合复用占位 | 直摘 | 自动合并 |
| `45cb8b8` 排队消息打断当前回复 | 手工 | `sendQueuedMessageNow`：采用上游「先取消、等收尾、再走普通发送」的新流程，移除我们旧的 stage 方式；问卷卡互锁由 `send()` 内的 `cancelPendingAskUsersForNewMessage` 覆盖 |
| `5536899` 备份按归属恢复 | 手工 | `backup_service.dart` 仅 import 冲突：同时保留 `novel_quota_gate.dart` 与 `SubjectPhotoListConverter` |
| `8e11cad` 输入法下首行缩进吃字 | 直摘 | 自动合并（`chapter_editor.dart` 本地改动保留） |
| `dddca46` 事务卡死 | 手工 | 测试辅助函数引用了遥测提交才有的 `onGenerationAttempt`，已移除该参数 |

附带清理：`novel_overview` 未用变量、两处未用 import、`chapter_briefing_context` 三个未用常量、测试 import 的多余 show 名。

## 三、B2 AI 工具契约与归属（3 条）

| 上游 | 结果 | 冲突处理 |
|---|---|---|
| `48e4b69` /works 契约 | 手工 | `tools_support.dart` 画布资源白名单改 `works`/`characters`；资源搜索按上游 `collectSelf && globMatches`；两份测试与 SKILL.md 取上游 |
| `c7dffd8` 跨书交接 | 手工 | `chat_next_action.judge` 采用上游新签名（含 `allowFeatures`）；orchestrator 提示取上游；画布对话测试依赖未引入的类型，已移除该测试块 |
| `78ff49c` work ID 归属 | 自动合并 | 119 文件，`novel_editor.dart`、`novel_workspace_panel.dart` 的自有改动保留 |

## 四、B3 设置与引导（2 条，跳过 1 条）

| 上游 | 结果 | 说明 |
|---|---|---|
| `e2fd235` 聚光灯引导 | 手工 | `home.dart` 仅 import 冲突，取 `dart:async` 全量导入；guide 组件三件套为新增文件，不动首页结构 |
| `a15be2c` 只保存选中 provider | 直摘 | 无冲突 |
| `3294489` 标题栏 + 移除首页重播按钮 | **跳过** | 依赖画布画廊 `canvas_gallery`（`6fb739f` 未同步），文件不存在，整条跳过 |

## 五、B4 数据层与渠道（5 条）

| 上游 | 结果 | 说明 |
|---|---|---|
| `4d594dc` 列迁移幂等 | 手工 | 保留本地 v2–v8 迁移链，**移除 `migrateToV9`**（v9 属匿名遥测，不跟） |
| `e945097` Gemini 思考签名 | 直摘 | 渠道稳定性 |
| `9d52d18` Seedance 2.5 Flash + 网关别名 | 直摘 | 渠道可用性 |
| `72c5441` SDK 0.1.2 | 直摘 | — |
| `f94372f` SDK 0.1.3 / `hasAudio` | 直摘 | 修插件上传 422 |

## 六、未同步项（后续巡检按此口径过滤）

- `ba6486d`、`e19795f`：匿名诊断与启动失败上报（隐私与合规，且绑定 schema v9）
- `6fb739f`、`3294489`（连带）、以及全部画布/剪辑/制作批次：`ccf62a4`、`fb2a2c0`、`895961c`、`8bd7a49`、`6d75fed`、`61b8a4e`、`a3e7132`、`1ae1229`、`156beaf`、`36ccc00`、`67aa03e`、`71e93c2`、`8f2405d`、`6bfe2f0`、`e48dbf9`
- `44969d9`、`c74076b`、`b4ec5e5`：CI / ONNX SDK 缓存
- `df927e7`、`b2b0650`、`4535cf8`：版本号；`a40875b`、`2e54e15`、`dba098c`：文档与官网

## 七、验证结果

| 项 | 结果 |
|---|---|
| `flutter analyze --no-pub` | 0 error / 0 warning（其余为 `third/` 供应商包 info） |
| 单测 | 导入 2 例为 `shared_preferences` 缺失的环境问题（同步前即存在）；工作区/工具/引导/迁移相关 100+ 例全过 |
| Release 构建 | 191s / 192s / 189s / 222s，均成功 |
| `reveric.exe` | 174,592 B，与基线一致 |
| 启动冒烟 | 进程标题「书童AI工作台」，Responding=True |
| 数据库 schema | 仍为 **v8**，未引入 v9 |

## 八、待办

- 未推送：本地领先自建仓库 `zhnn456/shutong-studio` 若干提交，待确认后再推（绝不推上游）
- C 线产品补完（手册收尾、导出 DOCX/EPUB、成本可视化、全书审校报告）尚未开始
- GUI 深检（授权码、客服反馈、世界观手册保存链路）待实机点验
