# 上游 0.10.0 第三批同步记录

日期：2026-11-17
分支：`merge/batch3-upstream-0.10.0` → 已快进合入 `unstable`（HEAD `f42f38f`）
基线：`2551906`（官方 `unstable`，含第三批计划文档 `docs/solutions/upstream-0.10.0-batch3-plan.md`）
上游基线：`origin/unstable` = `f3d4e29`（2026-11-16 21:42）

## 一、本次摘入的 9 条

| 上游 SHA | 本地 SHA | 内容 | 优先级 |
| --- | --- | --- | --- |
| `79faaad` | `29fd0e9` | 设置改为首页内容页，弹窗拆成单分区小窗 | P2 |
| `6dbf2d4` | `8ac96b8` | 复制节点图片到系统剪贴板 | P0 |
| `eeb1ce5` | `98d83e9` | 画布工具栏导出视频/图片节点 | P0 |
| `2360ac0` | `c41bb7a` | 拖拽文本/媒体到画布 | P0 |
| `a687089` | `16d0342` | 视频节点首帧缩略图与缓存 | P0 |
| `4987ef2` | `df95a92` | 画布预览渲染（布局检查） | P1 |
| `5e2758d` | `cb4bf41` | 新建作品不预设风格，删除 `default_style.dart` | P1 |
| `db35a0d` | `d4af8e2` | 作品打包导入导出（`.rvcanvas`） | P1 |
| `3dd93c8` | `29a70d0` | temperature 改为可选 + schema v8（`aiProviders.config`） | P2 |

补充提交：

- `f42f38f` 测试夹具适配（`importFile` 新增 `onProgress`；Windows 临时目录清理加容错）

未摘（用户本轮明确不做）：`31b0d11`（12 位 ID）、`0df9986`（技能文档整条）、`f047d4a`（设计文档）、`bfda0da`（版本号）。
`a436f51` 无需摘：其产物已在 `ef6b906` 删除。

## 二、冲突与合并过程

9 条全部 `git cherry-pick` 零冲突落地，`home.dart`、`settings_dialog.dart`、`ai_provider.dart`、
`assets/translations/{zh-CN,en}/settings.json`、`locale_keys.dart` 均为 auto-merge 通过，
自有改造（Keygate 授权码、客服反馈、UI 重构、托盘/许可）未受影响。

品牌核对：`lib/shared/models/ai_provider.dart:176`、`:437` 的「星辰AI」保留。

## 三、schema 变更（v7 → v8）

- `lib/shared/database/app_database.dart:1289` `currentSchemaVersion = 8`
- `migrateToV7`：`generationTasks.providerState`（第二批引入，仍在）
- `migrateToV8`：`aiProviders.config`（`AiProviderConfigConverter`，旧行留空，读取时默认不发送温度）
- `app_database.dart:1300/1312/1324/1336/1348/1360/1372` 依次调用 V2–V8，链条连续无空洞

## 四、功能接线核对（源码级）

| 功能 | 入口 |
| --- | --- |
| 设置首页化 | `home.dart:1453` 侧栏选中 `_HomeSettingsSelection()`，`:1018` 渲染 `DesktopSettingsPage` |
| 复制图片 | `node_bar.dart:231/257` → `image_clipboard.dart` |
| 导出节点 | `node_bar.dart:172` 导出态 + `editing_output_orchestrator.dart` |
| 拖拽到画布 | `board.dart:1274` `ProductionDropRegion` |
| 视频首帧 | `node_card.dart:1032` `ProductionVideoThumb` |
| 画布预览 | `shared/services/ai/media/production.dart:749` `renderProductionCanvasPreview` |
| 打包导入 | `home.dart:955` 画布作品库「导入」→ `importCanvasFromShelf` |
| 打包导出 | `novel_list.dart:249` 作品菜单 → `exportCanvasFromShelf` |
| 温度可选 | `AiProviderConfig.enableTemperature`（默认 false）、`agent_config.dart:86` |

## 五、验证结果

| 项 | 结果 |
| --- | --- |
| `flutter analyze --no-pub` | 0 error / 0 warning / 1714 info（info 全在 `third/` 三方包） |
| 第三批自带用例（7 个文件） | 45 条全绿 |
| 关联用例（8 个文件） | 68 条全绿 |
| `flutter test test/shared` 全量 | 6144 通过 / 47 skipped / 139 失败 |
| 失败对比第二批基线 | 数量与类别一致（6112+32 新通过，139 失败为既有环境性问题） |
| `flutter build windows --release` | 成功，188.8s，`reveric.exe` 174592 B（11:07:42） |
| 启动烟测 | 进程启动正常，窗口标题「书童AI工作台」 |

139 条失败仍是已知环境性类别，非本次合并引入：

- 插件未注册：`MissingPluginException`（`shared_preferences`、`path_provider`）——`novel_import_test`、`novel_actions_test`、`backup_service_test`、`roleplay_family_test` 等
- Windows 路径分隔符：`image_library_service_test`、`file_workspace_orchestrator_test`、`command_paths_test`、`session_files_test`、`director_output_test` 等
- 符号链接 errno 183：`storage_paths_test`、`canvas_service_test`
- 技能哈希 CRLF：`bundled_official_skills_test`、`bundled_control_skills_test`
- golden 图：`presentation_components_*`、`reveric_button_*`、`standard_controls_*`、`confirm_dialog_*`、`markdown_context_menu_*`、`next_action_states_*`、`spawn_agent_row_*`
- 上游自身问题：`plugin_dao_test`（`generation_tasks` 无 `output_headers` 列）
- 超时/环境：`ask_user_notification_test`、`agent_council_providers_test`（Binding 未初始化）

## 六、测试代码改动（`f42f38f`）

- `test/shared/production/grid_split_test.dart`：`_Library.importFile` 补 `onProgress` 形参与透传
- `test/desktop/features/production/node_card_test.dart`、`inline_media_test.dart`：新增 `removeTempRoot()`，
  删除临时目录遇 Windows 文件占用（errno 32）时重试 5 次后放弃，避免测试框架把清理失败记成用例失败

## 七、待人工验收（本次未做）

1. 老库 v7→v8 真实升级：用 0.6.14 老数据启动一次，确认供应商列表与温度开关正常
2. 画布：拖拽文本/图片到画布、复制图片、导出视频节点、首帧缩略图
3. 作品库：导入 `.rvcanvas`、导出打包、画布预览
4. 设置：侧栏「设置」进内容页；首页外入口仍弹单分区小窗
5. Windows 真机回归四项（播放器/关闭视频卡死、备份恢复、技能导入覆盖同名、Gemini 渠道对话）

## 八、协议与推送

- 上游 AGPL-3.0，本项目为 fork 二次开发；新增文件均来自上游，遵循同一许可，对外分发仍需履行 AGPL 义务
- 全程未推送任何远端；`origin`（looplj/reveric）推送地址已被护栏改写，禁止推送
- 自有仓库 `zhnn456/shutong-studio` 的推送需用户单独确认
