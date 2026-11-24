# 上游接入记录与回滚说明

## 回滚锚点

| 项目 | 值 |
|---|---|
| 分支 | `feat/upstream-skeleton` |
| 基线 commit | `40e2594fecec4b0061fc5f11d443dca4d66c43dd` |
| 基线含义 | 接入上游前的完整工作区快照（含开书技能上一版重写、视频改动、`third/upstreams` 源码） |

## 怎么回滚

**整体回滚到接入前**（丢弃接入后的全部改动，代码与技能都回到基线）：

```powershell
cd "D:\shutong studio\reveric"
git reset --hard 40e2594f
```

**只回滚某一步**（接入改动按步骤单独提交，每步一个 commit）：

```powershell
git log --oneline 40e2594f..HEAD     # 看接入过程
git revert <该步的 commit>           # 撤掉某一步，保留其他
```

**想保留接入成果、只是换回原分支**：

```powershell
git checkout sync/f2-screenplay-canvas
```

## 接入步骤记录

> 每完成一步，在下方追加一行；commit 号由 git 记录。改动文件清单与"为什么改"必须写清楚，便于判断哪一步不合适。

### 第 1 步：开书技能接入窗口制（分级冻结）

- 状态：**已完成** → commit `e4476405`
- 改动文件：
  - `assets/bundled_skills/setup/SKILL.md`
  - `assets/bundled_skills/setup/references/original.md`
  - 新增 `assets/bundled_skills/setup/references/planning-windows.md`（上游《规划窗口与防抢跑》的本地适配版）
- 依据上游：`third/upstreams/chinese-longnovel-skill/references/规划窗口与防抢跑.md`（MIT）
- 改法：保留"每卷每章标题 + 梗概"的交付要求（用户明确要），叠加上游的分级冻结——全书只锁宏观阶段与禁区，每卷一个窗口，当前窗口内每 5 章锁细节预算。
- 回滚此步：`git revert <commit>` 或删掉新增 reference 并还原两个文件。

### 第 2 步：校验器移植（QianBi mustscan）

- 状态：**已完成** → commit `bc5170d7`
- 改动文件：
  - `lib/shared/services/story_skeleton_checker.dart`（整份重写）
  - `lib/desktop/widgets/workspace/novel_overview.dart`（接入新缺口）
  - `assets/translations/{zh-CN,en}/workspace.json` + `lib/shared/localization/locale_keys.dart`
- 依据上游：`third/upstreams/qianbi-novel/app/mustscan.py`、`app/core/scan.py`（MIT）
- 移植的是判定纪律，不是 Python 代码：只有可指认的确定性缺口才标 blocking，判不准的一律 advisory / note；规则条数从 11 加到 13。
- 新增两条规则：`chapterTitleMissing`（标题只有「第 X 章」）、`volumeContractMissing`（卷纲缺「禁止提前完成 / 卷末未解决」）。
- **行为变化**：概览页原先对全部章节查"缺章纲"，一本 120 章的书会报「90 章缺章纲」；现在只查当前卷（后续卷章纲为空是设计允许的）。
- 回滚此步：`git revert bc5170d7`。

### 第 3 步：按卷补章入口改造

- 状态：**已完成**（commit 见 `git log` 中 `feat(plan)` 一条）
- 改动文件：
  - `lib/desktop/widgets/workspace/novel_workspace_panel.dart`（`_planChapters` 整段替换）
  - `assets/translations/{zh-CN,en}/workspace.json`（新增 `flow.plan_volume_chapters_prompt`）
  - `lib/shared/localization/locale_keys.dart`
- 行为变化：有分卷时按当前卷补齐，一次最多 35 章，强制传 `volume_id`，并要求写 `brief` 与六字段 `outline`；未分卷时保留原来"全书一次 10 章"。
- 卷目标章数按全书目标均分，末卷吃掉余数。**这是可调参数**：若发现均分不合适，改 `_planChapters` 里 `targetVolumeChapters` 的算法即可，不需要回滚整步。

### 第 4 步：骨架看板

- 状态：未开始

## 不适用的处理原则

接入后若发现用起来不合适，优先**调参数而不是拆机制**：窗口大小（50 章）、每 5 章预算、角色数量下限、梗概字数这些都是常量，可单独调；只有机制本身判断错误时才整步回滚。
