# 上游 0.10.0 第一批同步记录

日期：2026-11-17。分支：`merge/batch1-upstream-0.10.0`（从本地 `unstable` 拉出，未改动 `unstable`）。
方式：按提交逐个 `cherry-pick`，不做整分支 merge。上游 `origin/unstable` 为 `f3d4e29`，本地基线共同祖先 `fcd73db`，同步前 `ahead 21 / behind 38`。

## 1. 已合入（15 个）

| 上游提交 | 内容 | 结果 |
| --- | --- | --- |
| `009099d` | OpenAI 图片请求省略 response_format | 干净 |
| `7c07b82` | markdown 标题 / 行内代码使用正文颜色 | 干净 |
| `7187567` | 保留操作控制调用状态 | 干净 |
| `4f3af85` | 工具活动行显示完成检查 | 干净 |
| `82eb2d6` | 保存权限规则后释放排队审批 | 干净 |
| `0b434b4` | 保留 Gemini 工具响应并配置 Gemini 4 模型 | `ai_provider.dart` 自动合并 |
| `15b3cbe` | Agent 取消不再依赖卡顿请求 | 干净 |
| `ea83014` | 技能导入处理缺失 GitHub revision | 干净 |
| `c252931` | 技能导入可覆盖同名技能 | 干净 |
| `10f6e41` | CI 停止上传 Linux release 到 R2 | `build.yaml` 自动合并，本地打包步骤保留 |
| `9e8f7af` | 备份 ZIP 限制内存 + Android 流式导入 | `backup_service.dart` / `backup_settings_section.dart` 自动合并，`NovelQuotaGate` 备份恢复门禁确认保留 |
| `ea8c9c1` | 解除演员 / 场景对象数量限制 | 干净 |
| `01d59b7` | 播放器 dispose 前等待原生暂停 | 干净（上游只验 macOS，Windows 需人工回归） |
| `ab7e974` | 草稿保存失败给出恢复步骤 | `production/support.dart` 头部 import 冲突，手工保留上游新增 import |
| `9e8f7af` 附带 | 备份损坏条目日志 | 见第 3 节 |

## 2. 暂未合入及原因

- `3dd93c8`（temperature 改为可选 + provider options 存 JSON 列）：该提交的迁移编号是 v8，前置依赖 `ab8ccfb` 引入的 schema v7；本地库仍是 v6，单独 cherry-pick 会写出「v6 → v8」跳版迁移，破坏既有用户库。**必须与插件 / provider 底座批次一起合。**
- `93f0c31`（插件与视频诊断日志）：依赖本地尚不存在的新文件 `lib/shared/services/plugins/files.dart`、`media.dart`（由插件批次引入），冲突为 `DU/UU`，随插件批次一起合。
- `6070f2e`（Midjourney 参考图走 Atlas 编辑模型）：补丁上下文与本地 image 代码代差过大（上游历史重写所致），且属图像链路，留给图像批次。
- `5e2758d`（新建剧本不再默认带风格）：改动 `novel_actions.dart`（本地改过），且价值偏低，留待剧本批次。
- 插件市场 / provider 重构（`ab8ccfb`、`9c74458`、`2eaff38`、`a436f51`、`ef6b906`、`f3d4e29`、`44c0976`）、production 画布系列、`79faaad` 设置首页化、`31b0d11` 12 位 ID：均属第二批专项，见 `upstream-0.10.0-followup-assessment.md`。
- `bfda0da` 上游版本号 0.10.0：本地版本序列独立，不跟随。

## 3. 本次发现并修复的问题

**archive 版本漂移导致损坏备份包可被静默解压。** 本地锁定的 `archive` 为 4.7.1，上游锁 4.3.0。上游 `9e8f7af` 新增的用例依赖 archive 在遇到损坏 DEFLATE 块时抛出 `Filter error, bad data`；在 4.7.1 下该异常不再抛出，解压会成功写出脏数据，只靠 manifest 校验兜底。

处理：在 `_extractZipSafely` 中解压每个条目后按条目 CRC 复核落盘内容（64KB 分块读取，内存有界），不匹配即抛出并以 `invalidBackup` 拒绝；用例断言改为校验本地 CRC 复核日志（`stage=decompress`、`entry=`、`expectedCrc32=` 均保留）。代价是恢复路径多一次读盘，换取坏包不再可能被恢复。

## 4. 验证结果

- `flutter pub get`：通过。
- `flutter analyze --no-pub`：**0 error / 0 warning**；1703 条 info 与同步前完全一致（绝大多数来自 `third/`）。
- 新增用例通过：`backup_zip_test`、`backup_settings_section_test`、`production/error_test`、`director/document_test`、`director/commands_test`、`agent_skill_import_orchestrator_test`、`gemini_client_test`、`agent_test`、`tool_permissions_test`、`markdown_text_test`、`tool_activity_group_test`（合计 94 条全绿）。
- `backup_service_test`：`+26 / -35`，失败项与同步前基线 `+25 / -35` 完全同源，均为 `MissingPluginException(shared_preferences)` 与真实网络请求类环境问题；唯一新增的上游用例已通过。
- `image_url_response_test`：`+2 / -5`，与基线一致（需真实 Agnes 接口、Windows 路径分隔符断言差异），非本次引入。

## 5. 后续

1. 本分支尚未并入 `unstable`；用户侧还有一批未提交改动（客服反馈 / Keygate / 托盘等）已用 stash 暂存，标签为「WIP 客服反馈/Keygate/托盘 改动 (2026-11-17 同步前暂存)」。合并分支后再 `git stash pop` 回工作区，避免在脏树上解冲突。
2. Windows 手工回归项：`01d59b7` 播放器 / 关闭视频导致卡死、备份恢复（大包 + 损坏包）、技能导入覆盖同名、Gemini 渠道对话。
3. 第二批开工前置：先合 `ab8ccfb`（插件实例 + schema v7），再考虑 `3dd93c8`（v8）与 `ef6b906` 插件市场；`3dd93c8` 合入后需重跑 `provider_config_migration_test`、`provider_state_migration_test`、`app_database_schema_test`。
4. 推送目标只允许 `zhnn456/shutong-studio`，`origin` push 地址仍被占位护栏阻断。
