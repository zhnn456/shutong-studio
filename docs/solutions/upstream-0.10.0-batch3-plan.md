# 上游 0.10.0 第三批候选：取舍与执行计划

> 生成时间：2026-11-17
> 前置状态：第一批 15 条 + CRC 加固、WIP 拆分 7 提交、第二批 11 条已全部快进合入 `unstable`（HEAD `02ade03`，304 files / +26332 −3244）。
> 本文只做评估，不代表已合并。

## 一、剩余上游提交概览

上游 `origin/unstable` 最新 `f3d4e29`，本地 `unstable` 相对上游 ahead 61 / behind 38。
真正未摘的上游提交共 **12 条**（`bfda0da` 仅为版本号 0.10.0，不跟）。

按上游时间顺序（这也是建议的摘取顺序，越靠后越依赖前面）：

| # | SHA | 日期 | 标题 | 规模 |
|---|---|---|---|---|
| 1 | `6dbf2d4` | 11-14 21:08 | feat(canvas): copy node images to the system clipboard | 8 files / +281 −47 |
| 2 | `eeb1ce5` | 11-14 20:27 | feat(editing): export video nodes from the canvas toolbar | 10 files / +405 −67 |
| 3 | `2360ac0` | 11-15 00:41 | feat(production): drop text and media onto the canvas | 4 files / +558 −1 |
| 4 | `a687089` | 11-15 02:58 | feat(production): preview first frame for video thumbnails | 10 files / +1108 −32 |
| 5 | `4987ef2` | 11-15 11:54 | feat(production): render a canvas preview for layout checks | 13 files / +2078 −15 |
| 6 | `5e2758d` | 11-15 12:36 | fix(production): leave production style unset on create | 8 files / +69 −299 |
| 7 | `0df9986` | 11-15 12:36 | docs(skills): expand production and model prompting guides | 44 files / +1341 −949 |
| 8 | `db35a0d` | 11-15 20:47 | feat: import/export production canvas | 14 files / +3092 −19 |
| 9 | `31b0d11` | 11-16 02:04 | chore: use twelve-character suffixes for generation tasks and assets | 12 files / +35 −17 |
| 10 | `3dd93c8` | 11-16 14:46 | feat(ai): make temperature opt-in with catalog capability checks | 35 files / +1192 −241 |
| 11 | `79faaad` | 11-12 — | feat(desktop): open settings as a home page instead of a dialog | 8 files / +135 −171 |
| 12 | `f047d4a` | 11-06 — | docs: plugin provider solution design | 5 files / +854 −50 |

依赖事实（已用文件级核对确认）：

- `4987ef2` 使用 `lib/shared/services/production/video_thumbnail_cache.dart`，该文件由 `a687089` 引入 → **必须 a687089 先摘**。
- `a687089` 与 `2360ac0` 共改 `lib/desktop/features/production/drop_region.dart` → 建议 2360ac0 先于 a687089。
- `db35a0d` 改 `lib/desktop/pages/home.dart`（我们的 UI 重构文件）→ 需手工解冲突。
- `79faaad` 同样改 `lib/desktop/pages/home.dart` → 与我们的首页重构直接冲突。

## 二、逐项对比表

| 上游更新 | 与自有改造冲突 | 可否合并 | 建议同步 | 理由 | 优先级 |
|---|---|---|---|---|---|
| `6dbf2d4` 复制节点图片到剪贴板 | 无（新增 `utils/image_clipboard.dart`，仅动 node_bar + 预览） | 可直接 cherry-pick | **是** | 用户可感知的小而实用能力，成本极低 | P0 |
| `eeb1ce5` 画布工具栏导出视频节点 | 无（动 editing 导出对话框 + node_bar） | 可直接 cherry-pick | **是** | 成片导出是高频诉求，纯增量 | P0 |
| `2360ac0` 拖拽文本/媒体到画布 | 无（4 个文件，全在 production 画布内） | 可直接 cherry-pick | **是** | 编辑器手感提升，改动小 | P0 |
| `a687089` 视频节点首帧缩略图 | 无（新增缩略图缓存服务 + ffmpeg_runner） | 可直接 cherry-pick | **是** | 画布里一眼看懂视频内容；也是 `4987ef2` 的前置 | P1 |
| `4987ef2` 画布预览（给 AI 做版式自查） | 依赖 a687089；触碰 `canvas-work-tools` / `screenplay-tools` 的 production-canvas 参考文档（我们改过表述） | 可摘，文档 1–2 处手工合并 | **是** | 让 AI 能"看"版式再改，直接关系出图/出片质量 | P1 |
| `5e2758d` 建片不预设风格 | 无强冲突（production 编排层，已在第二批整体跟齐） | 可直接 cherry-pick | 建议是（需先验证） | 去掉硬塞默认风格，避免 AI 被错风格带偏；但会改现有默认行为 | P1 |
| `db35a0d` 画布导入/导出（作品打包） | **是**：`lib/desktop/pages/home.dart`（我们重写过首页） | 需手工解冲突 | 建议是（分批最后做） | 作品可打包迁移/备份，属于商业软件必备能力，价值最高 | P1 |
| `3dd93c8` temperature 改为按模型能力可选 | 中：动 `ai_provider.dart`（我们保留"星辰AI"品牌）、DB 升 **v8**（我们现为 v7） | 需解冲突 + 真机迁移验证 | 建议是（排最后） | 修掉不支持 temperature 的渠道报错，属真实 bug；但要连带验证老库 v7→v8 | P2 |
| `31b0d11` 任务/资产 ID 后缀改 12 位 | 低 | 可直接 cherry-pick | 可不做 | 纯内部 ID 长度，用户无感；会动已存记录的兼容面 | P3 |
| `0df9986` 生产与提示词指南文档扩充 | 高：44 文件涉及 `assets/bundled_skills`（我们大改过，且 hash 需按 blob 重算） | 不建议整条摘 | 只手工吸收指南段落 | 内容是好的 prompt 指导，但整条 cherry-pick 会大面积覆盖我们的技能文案 | P2 |
| `79faaad` 设置从弹窗改为首页 | **是**：`lib/desktop/pages/home.dart`（我们的首页重构设计） | 不建议摘 | 否 | 与我们的 UI 重构直接对冲，收益只是导航形态 | — |
| `f047d4a` 插件 provider 设计文档 | 无 | 可摘 | 否 | 纯设计文档，已合入的插件 provider 实现就是它的落地版 | — |

## 三、建议同步清单（按执行顺序）

**A 组：体验小改（风险低，先摘，一次构建即可验收）**
1. `6dbf2d4` → cherry-pick
2. `eeb1ce5` → cherry-pick
3. `2360ac0` → cherry-pick
4. `a687089` → cherry-pick

**B 组：画布与作品能力（中等，需手工解 1–2 处）**
5. `4987ef2` → cherry-pick，`production-canvas.md` 两处文档按本地表述保留
6. `5e2758d` → cherry-pick，验收"新建分镜不再自动带风格"
7. `db35a0d` → cherry-pick，`lib/desktop/pages/home.dart` 手工解冲突（保留我们的首页结构，只接导入/导出入口）

**C 组：底座与迁移（最后做，必须真机验证）**
8. `3dd93c8` → cherry-pick + 手工处理 `ai_provider.dart` 品牌键、`currentSchemaVersion` 7→8，老库启动验证

可选、不阻塞：
9. `31b0d11`（内部 ID 长度，用户无感）
10. `0df9986`（只把 prompting 指南段落手工并入本地技能文案）

## 四、建议不同步

| 提交 | 原因 |
|---|---|
| `79faaad` | 设置改首页与我们已完成的首页/侧栏重构正面冲突，改动成本大于收益 |
| `f047d4a` | 纯设计文档，实现部分（插件 provider）已在第二批到位 |
| `bfda0da` | 仅版本号 0.10.0，我们的对外版本另行管理（当前 pubspec 0.6.14） |

## 五、执行步骤

1. 建分支 `merge/batch3-upstream-0.10.0`，从 `unstable`（`02ade03`）切出。
2. 按 A → B → C 顺序逐条 cherry-pick；每摘 1–2 条跑一次 `flutter analyze --no-pub`，保持 0 error / 0 warning。
3. A 组摘完先构建一次 `flutter build windows --release`，实机点一遍剪贴板复制、视频节点导出、拖拽、缩略图。
4. B 组摘完，重点验证：画布预览、作品打包导出→再导入、新建分镜默认风格。
5. C 组摘完，用 0.6.14 老库副本启动一次，确认 v7→v8 迁移不丢数据，再跑 `test/shared` 全量对照基线。
6. 全部验证通过后 `git switch unstable && git merge --ff-only merge/batch3-upstream-0.10.0`，再写同步记录文档。
7. 全程不推送；推送 `zhnn456/shutong-studio` 需单独确认。

## 六、风险与注意事项

- **单实例锁**：机器上已有 0.6.14 实例在跑时，新构建无法启动演示；实机验收前需先退出旧实例。
- **DB 迁移**：`3dd93c8` 引入 v8；当前 v7 只在新版本上验证过编译与单测，未经真实老库升级。摘 C 组前建议先备份用户数据目录。
- **技能 hash**：任何碰 `assets/bundled_skills` / `assets/official_skills` 的合并（尤其 `0df9986`、`4987ef2`）都要用 `git cat-file blob HEAD:<path>` 重算，不能用工作区文件（`core.autocrlf=true` 会算出 CRLF 的错值）。
- **依赖顺序**：跳序会撞 modify/delete 冲突或测试假红（第二批已踩过 3 次）；遇到即 `git cherry-pick --abort` 后补前置。
- **协议合规**：上游为 AGPL-3.0，我们为 fork 二次开发。任何合并都属同一许可证下的衍生，需持续履行 AGPL 义务（提供对应源码、保留版权与许可声明、网络服务用户可获取源码）；同时自有品牌文案、Keygate 授权逻辑属我们自己的代码，不因合并而变成上游版权。
