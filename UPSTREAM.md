# 上游基线与合并记录

本项目基于 `looplj/reveric`（AGPL-3.0）二次开发。本文件只记录「我们基于上游哪个版本」以及怎么把上游更新合进来，不记录业务改动。

## 当前状态

| 项 | 值 |
| --- | --- |
| 上游仓库 | https://github.com/looplj/reveric |
| 我们的基线 | **v0.6.0**（上游 commit `dbdad3fc`，本地 tag `base-upstream-0.6.0`） |
| 上游最新（2026-11-16 核对） | **v0.9.0**（commit `fcd73db`，即上游 unstable 分支 HEAD） |
| 待合并 | 124 个上游提交，跨越 v0.6.1 / 0.6.2 / 0.7.0 / 0.7.1 / 0.8.0 / 0.8.1 / 0.8.2 / 0.8.3 / 0.9.0 |
| 我们领先上游 | 16 个自有提交，改动 72 个文件（51 个改上游已有文件，21 个新增文件） |
| 本项目版本序列 | 自有序列，与上游版本号解耦（规划从 1.0.0 起） |

## 版本号约定

**两套号，永不混用：**

- **对外版本号**（用户看得到、安装包文件名、关于页）：用我们自己的序列。当前 0.6.11，下一个发布版规划为 `1.0.0`，之后 1.0.x 递增。理由：上游已经到 0.9.0，我们继续用 0.6.x 会撞车且永久错位。
- **上游基线号**：只存在于本文件与 git tag（`base-upstream-0.6.0`、合并后再打 `upstream-0.7.0` 之类）。用户界面不显示。

pubspec 里的 `version: x.y.z+build`，`+build` 用我们自己的递增构建号，与上游无关。

## 合并流程（建议按 tag 分段，不要一次跳到 0.9.0）

```
git fetch origin --tags
git checkout -b merge-up-0.6.1 unstable
git merge v0.6.1          # 解决冲突
flutter analyze && flutter test test/smoke
（打包验证）
git checkout unstable && git merge merge-up-0.6.1
```

每一段做完就跑一次 analyze + 38 个冒烟用例 + 打一次包。**一次只推进一个上游版本**，冲突面小、出问题好定位。全部追平后再打 `upstream-0.9.0` tag 记录新基线。

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
