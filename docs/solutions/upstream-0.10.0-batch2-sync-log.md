# 上游 0.10.0 第二批同步记录（插件 / provider / 图片视频底座 / 资源契约）

分支：`merge/batch2-upstream-0.10.0`（起点 `unstable` @ `e20d4a4`，未合入、未推送）
基线对照：`unstable` @ `e20d4a4`（第一批 + WIP 拆分后）
记录时间：2026-11-17

## 一、已合入的上游提交（按依赖顺序）

| 上游 | 本地 | 说明 | 冲突 |
| --- | --- | --- | --- |
| `ab8ccfb` | `0eb228e` | 插件 provider 实例 + 声明式媒体能力，schema 6→7、plugin SDK | `ai_provider.dart` 1 处：取上游字符串键，保留本地显示名“星辰AI” |
| `9c74458` | `99c6f46` | 统一内置与插件图片生成，新增 `plugins/files.dart`、`media_files.dart` | `production/support.dart` import 块 1 处 |
| `44c0976` | `c2a8aca` | combo 设置字段 + 字段组间距 | 无 |
| `f3d4e29` | `c84623c` | 向 provider 上传暴露媒体探测信息 | 无 |
| `2eaff38` | `3d4c2e4` | 统一 provider 认证与视频生成（`ef6b906` 的前置） | 无 |
| `ef6b906` | `2a93262` | 插件市场 + 外置小云雀 + provider 错误透传 | 无（先补 `2eaff38` 后） |
| `0c97cc1` | `1eb0e52` | 91Token + New API 媒体共享（video 测试的 reconciliation 回收分支） | 无 |
| `6070f2e` | `9da290a` | Midjourney 参考图走 Atlas 编辑模型 | 无 |
| `93f0c31` | `1787dde` | 插件与视频诊断日志 | 无 |
| `9e97c29` | `c98a4e9` | 紧凑资源契约 + 摘要视图，新增 `test/helpers/resource_contract.dart` | 3 处内容冲突，见下 |

自建修复提交：`57c9f04`、`fc525fc`、`e45b17d`、`cc60bf3`、`1487868`、`e9368f8`。

### 依赖顺序（踩过两次，务必先补前置）

- `9c74458` 需要 `ab8ccfb`（`plugins/files.dart`、`media_files.dart`）。
- `ef6b906` 需要 `2eaff38`，否则 3 个文件 modify/delete 冲突。
- `ef6b906` / `2eaff38` 的 video 测试还需要 `0c97cc1`：`TaskService.refreshDue()` 里
  「`invalid_response` 且未请求取消的 reconciliation 任务也要继续轮询」这一段。
  跳序只会得到 `reconciliation_required` 的假红。
- 遇到冲突先 `git cherry-pick --abort`，补前置后重摘，不要硬解 modify/delete。

## 二、`9e97c29` 三处冲突的取舍

1. `lib/shared/services/bundled_official_skills.dart`：本地对 `剧本制片` 有大改，
   contentHash 必须按**合并后的内容**重算 → `f34417281a138be2726bd9f189d34577a661dd4590fccece1df8b85d61ed72f8`，
   updatedAt 采上游 `2026-11-15T15:19:54+08:00`。
2. `assets/bundled_skills/canvas-work-tools/references/production-canvas.md`：
   采纳上游 `/_schema/production/canvas/nodes` 路径，保留本地“媒体配置保存在分镜与媒体节点对应片段”表述。
3. `assets/official_skills/screenplay-production/SKILL.md`：保留本地“按任务推进”段落，
   把上游“按上表路径直接 `reference-get`，未知路径再 `reference-list`”合并进 `<skill_resources>`。

### hash 坑

`core.autocrlf=true`，工作区是 CRLF、git blob 是 LF。技能 hash 必须用
`git cat-file blob HEAD:<path>` 的字节算（主文件 + 按路径排序的每个附件前插 `\u0000<assetPath>\u0000`），
直接读工作区文件会得到 CRLF 版本的错值。该测试在 `unstable` 基线上 12 条 hash 全部不匹配
（含未改动技能），属 Windows 环境性失败，本地不可作判据。

## 三、本轮验证结果

- `flutter analyze --no-pub`：**0 error / 0 warning**（info 1711，全部是 third/ 三方包 deprecated 提示）。
- 专项全绿：`test/shared/services/plugins` 189 条、`test/shared/models/plugin` + `test/shared/widgets/settings` + `host_test` 268 条、
  迁移与 provider 模型 65 条、`tools_relation_history_test` / `tools_schema_test` / `tools_output_schema_test` 37 条、
  video 取消与恢复 8 条。
- `flutter test test/shared` 全量：6112 通过 / 139 失败，失败全部可归入既有的环境性类别：
  - golden 图渲染（`components/*_golden_test`，Windows 字体/缩放）
  - 路径分隔符断言（`file_workspaces\\work` vs `/`：`ffmpeg/*`、`files/*`、`director_output_test`）
  - `Binding has not yet been initialized`、`MissingPluginException(shared_preferences)`、`PathAccessException` 残留临时目录
  - 基线同样红（已用 `unstable` 同文件对照）：`plugin_dao_test`、`prop_catalog_test`、`audio_generation_test`、
    `director_output_test`、`update_providers_test`、`official_skill_sync_providers_test`、`agent_skill_transfer_test`、
    `bundled_official_skills_test`、`canvas_service_test`（符号链接 errno 183）
- 本轮新修（`e9368f8`）：
  - `canvas_service_test` 的 `request` 断言原来把**静态契约树**当运行时数据取用
    （`resourceContractTreeForTesting` 只接受 `/_schema` 路径，实例路径返回 error map），
    改为断言 `/_schema/clips/generations` 里 `request` 的 `read_path=true` / `listing=false`。
  - `bundled_official_skills` 剧本制片 hash 按合并内容重算。
  - 删掉上游在 `tools_relation_history_test` 加的无用 import。

## 四、仍有风险 / 只能真机验的部分

- schema 6→7 的真实老库升级未在真机验证过，需用 0.6.14 的老数据启动一次。
- 大范围改动集中在 provider/插件/图片视频底座，需真机回归：图片生成、视频生成与取消、
  插件市场安装与 provider 配置、画布/短剧生产链路。

## 五、后续待摘（第三批候选）

`79faaad`（设置首页化，撞 UI 重构）、`3dd93c8`（temperature opt-in + v8 迁移）、`31b0d11`（12 位 ID）、
`5e2758d`（新建作品不预设 style）、`0df9986` / `f047d4a`（文档）、画布系列 `db35a0d`、`2360ac0`、`4987ef2`、
`a687089`、`eeb1ce5`、`6dbf2d4`。`bfda0da`（版本号 0.10.0）不跟。
`a436f51` 无需再摘：其产物已在 `ef6b906` 中被整批删除。
