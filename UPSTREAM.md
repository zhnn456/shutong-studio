# 上游基线与合并记录

本项目基于 `looplj/reveric`（AGPL-3.0）二次开发。本文件只记录「我们基于上游哪个版本」以及怎么把上游更新合进来，不记录业务改动。

## 当前状态

| 项 | 值 |
| --- | --- |
| 上游仓库 | https://github.com/looplj/reveric |
| 我们的基线 | **v0.9.0**（上游 commit `fcd73db`，= 上游 unstable HEAD；本地 tag `upstream-0.9.0`） |
| 历史基线 | v0.6.0（commit `dbdad3fc`，本地 tag `base-upstream-0.6.0`，2026-11 之前长期使用） |
| 上游最新（2026-11-16 核对） | **v0.9.0**（已合并，差距归零） |
| 本项目版本序列 | 自有序列，与上游版本号解耦（规划从 1.0.0 起） |

## 版本号约定

**两套号，永不混用：**

- **对外版本号**（用户看得到、安装包文件名、关于页）：用我们自己的序列。当前 0.6.12，下一个对外发布版规划为 `1.0.0`，之后 1.0.x 递增。理由：上游已经到 0.9.0，我们继续用 0.6.x 会永久错位。
- **上游基线号**：只存在于本文件与 git tag（`base-upstream-0.6.0`、`upstream-0.9.0`）。用户界面不显示。

## 已完成：一次合并 v0.9.0（2026-11-16）

从 v0.6.0 直接合到 v0.9.0，一次跨完 9 个上游版本（124 个提交），没有分段。

- 分支：`merge-up-0.9.0`（从 `unstable` 拉出，`unstable` 全程未动，可随时 `git checkout unstable` 回退）。
- 冲突：20 个文件 / 约 47 个冲突块，全部手工解决；`flutter pub get` 重跑；`flutter analyze` 的 error 与 warning 清零（`third/` 第三方包的 info 不计）。
- 测试：托盘退出、Hero 写作入口、`test/smoke` 三组共 52 个用例全部通过。
- 打包：`dist/0.6.12/reveric-0.6.12-windows-setup.exe`。

### 这次合并踩到的坑（下次直接照着处理）

1. **托盘 API 换代**：上游 v0.9.0 的 `tray_manager` 换成 nativeapi 版（`TrayIcon.create()` / `MenuItem.createWithLabelAndType` + listener），旧的 `onTrayMenuItemClick` / 全局 `trayManager.destroy()` 全部不存在。退出流程改为「隐藏图标 + `_disposeTray()`，不 await 原生回包」，`_disposeTray` 内每个 dispose 单独 try，避免清理异常把退出流程打断。
2. **上游改了 `ContinueWritingHero` 签名**（新增 `required hasAnyFoundation`），但上游自己的测试没跟着改。补参数时取 `true`，才能保持「无章节 → 开始第 1 章」的原语义。
3. **原生资产构建**：`native_toolchain_rust 1.0.7` 在 Windows 上会崩（`Illegal character in path: xxx.lib`），升到 `1.1.1` 后正常；`sqlite3` 的 hook 需要下载预编译 DLL，构建脚本已内置「临时禁用 sqlite3 hooks + 清 hook cache」的处理。
4. **上游 CI 新增 R2 上传步骤**，需要 `CLOUDFLARE_R2_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID`，我们没配 → 该步骤丢弃，保留自己的 `dist/**/*.exe` 上传。
5. **上游重构了「新建作品」入口**（`lib/desktop/widgets/novel_create_submitter.dart`），首页旧的 `createNovel` 已删；免费版额度提示（`NovelFreeLimitException`）要挂到 submitter 里，否则超限用户只看到通用「创建失败」。
6. **上游新增「插件」入口和「回收站」设置分区**，与本地的「客服反馈」「授权」入口并存，两者都保留。

## 下次合并流程

```
git fetch origin --tags
git checkout -b merge-up-<ver> unstable
git merge v<ver>            # 解决冲突
flutter pub get
flutter analyze | Select-String "error -|warning -"
flutter test test/shared/services/system_tray_service_test.dart test/desktop/widgets/workspace/continue_writing_hero_test.dart test/smoke
.\build-windows.ps1 -SkipInstallTools
git checkout unstable && git branch -f unstable merge-up-<ver>
```

合并完成后更新本文件的「当前状态」表并打 `upstream-<ver>` tag。

## 冲突热区（合并时优先看这些）

我们改过、上游大概率也改过的文件：

- `lib/desktop/pages/home.dart`、`lib/main.dart`
- `lib/shared/services/novel_actions.dart`、`demo_novel.dart`、`backup_service.dart`、`device_id_service.dart`
- `lib/desktop/widgets/sidebar/*`、`workspace/*`
- `assets/translations/{zh-CN,en}/*.json`、`lib/shared/localization/locale_keys.dart`
- `windows/runner/*`、`windows/CMakeLists.txt`、`windows/packaging/exe/inno_setup.iss`、`.github/workflows/build.yaml`
- `pubspec.yaml` / `pubspec.lock`

几乎不会冲突的（我们纯新增）：

- `lib/shared/services/keygate/*`、`lib/shared/services/license_service.dart`、`lib/shared/models/license.dart`、`lib/shared/services/novel_quota_gate.dart`、`lib/desktop/pages/license_page.dart`、`test/smoke/*`

## 降低未来冲突成本的三条措施

1. **品牌替换脚本化**：README、translations、InfoPlist、Runner.rc、inno_setup.iss 里的品牌与文案改动，抽成一个可重复执行的脚本，每次合并后一键重跑，不手工重做。
2. **改上游文件时保持最小侵入**：只在必要处挂一个调用，不整段重写，避免上游改了同一区域时冲突扩大。
3. **新功能优先新增文件**：授权、额度、客服反馈都已经是独立文件，这个习惯保持。

## 安全护栏

- `origin` 的 push 地址已被改写为占位远端（`__PUSH-TO-UPSTREAM-BLOCKED__`），**不可能误推到上游**。fetch 仍指向上游，可正常拉更新。
- 自有仓库：`shutong-studio` → `https://github.com/zhnn456/shutong-studio.git`。
