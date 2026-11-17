# 上游更新跟进评估（reveric 0.6.14 → 上游 0.10.0）

日期：2026-11-17。范围：本地 `unstable` 相对上游 `origin/unstable`（looplj/reveric）未合并的 38 个提交。结论先行：**不建议一次性全量合并；建议分批跟进，先吸收通用稳定性修复，插件/Provider 架构重构与视觉制作体系单独开专项评估。**

## 1. 基线现状

| 项 | 值 |
| --- | --- |
| 本地分支 | `unstable`，`ahead 21 / behind 38`（相对 `origin/unstable`） |
| 共同祖先 | `fcd73dbd` |
| 本地打包版本 | `0.6.14`（pubspec `version: 0.6.14`；上游 pubspec 已到 `0.10.0`） |
| 上游改动规模 | 470 个文件（含大量 test、plugins SDK、production 画布体系） |
| 本地改动规模 | 75 个文件 |
| 双方直接重叠文件 | 15 个（见第 3 节） |
| 本地 DB / drift / dao / migration 改动 | 无（数据库层可安全跟随上游迁移） |

### 1.1 本地受保护定制（上游未改动，合并不会被覆盖）

以下文件是 Keygate 授权、客服反馈、托盘退出、产品区分等自有改造，**均不在上游改动清单内**，合并时需确认保留：

- `lib/desktop/pages/license_page.dart`
- `lib/desktop/widgets/license/license_pricing_view.dart`
- `lib/shared/models/license.dart`
- `lib/shared/services/keygate/keygate_client.dart`
- `lib/shared/services/keygate/keygate_token.dart`
- `lib/shared/services/license_service.dart`
- `lib/shared/services/system_tray_service.dart`
- `lib/shared/widgets/support/customer_service_feedback_dialog.dart`
- 对应 smoke / 单元测试若干

唯一与上游重叠的定制文件是 `lib/shared/localization/locale_keys.dart`（本地追加反馈/产品文案 key，上游追加新功能 key，属机械去重合并）。

## 2. 上游提交分组与价值评估

### A. 插件 / Provider 架构重构（底座，改动最大）

| 提交 | 内容 |
| --- | --- |
| `f047d4a` | 插件 Provider 方案设计文档 |
| `ab8ccfb` | 插件实例化 + 声明式媒体能力（provider instances / capabilities） |
| `2eaff38` | 视频生成 provider 认证体系统一 |
| `9c74458` | 内置与插件图像生成统一 |
| `a436f51` | 新增云雀（Xiaoyunque）视频 provider |
| `ef6b906` | 插件市场、云雀外置、provider 错误信息透传 |
| `0c97cc1` | 新增 91Token 与 New API 媒体支持 |
| `44c0976` | combo 设置字段 + 字段组间距收紧 |
| `f3d4e29` | 探测到的媒体信息透传给 provider 上传 |

- **价值**：为插件市场和多图像/视频渠道建立统一底座；内置插件与第三方插件同一包格式（`plugin.json` + JS 单文件入口 + 注册表）。
- **对本产品**：图像/视频服务于封面、分镜、短剧视觉；当前主推小说文本，短期收益有限。
- **风险：高**。跨 provider model、plugin dao、settings、image/video service、registry 与大量测试；与本地 `ai_provider.dart`、`provider_brand.dart`、`locale_keys.dart`、设置页重叠；插件市场属独立 UI/概念，需先确认是否需要后端、是否与现有「本地技能离线、不连后台」的 ADR 冲突。

### B. Production 画布 / 视觉制作功能

| 提交 | 内容 |
| --- | --- |
| `db35a0d` | 制作画布导入 / 导出 |
| `4987ef2e` | 画布预览用于排版检查 |
| `a687089` | 视频首帧缩略图预览 |
| `2360ac0` | 文本与媒体拖入画布 |
| `6dbf2d4` | 节点图片复制到系统剪贴板 |
| `eeb1ce5` | 画布工具栏导出视频节点 |
| `5e2758d` | 创建时 production 风格留空 |
| `ab7e974` | 草稿保存失败给出恢复步骤说明 |
| `ea8c9c1` | 解除演员 / 场景对象数量限制 |
| `01d59b7` | 播放器 dispose 前等待原生暂停完成 |
| `6070f2e` | Midjourney 参考图走 Atlas 编辑模型 |
| `0df9986` | 扩充制作与模型提示词技能文档 |

- **价值**：偏短剧 / 分镜 / 视觉制作流程；与现有 screenplay、production、canvas、map 模块相邻。
- **对本产品**：纯小说文本链路用不到；短剧视觉方向排期后再评估。
- **风险：中**。production 模块本地未大改，跟随较顺；但体量大（470 文件中占大头），且依赖 A 批 provider 统一接口。

### C. AI / Agent 稳定性与渲染修复（通用，价值高、风险低）

| 提交 | 内容 |
| --- | --- |
| `0b434b4` | 保留 Gemini 工具响应，配置 Gemini 4 模型 |
| `15b3cbe` | Agent 取消独立于卡顿请求 |
| `82eb2d6` | 保存权限规则后释放排队中的审批 |
| `7187567` | 保留操作控制调用状态 |
| `4f3af85` | 工具活动行显示完成检查 |
| `009099d` | OpenAI 图片请求省略 `response_format` |
| `7c07b82` | markdown 标题 / 行内代码使用正文颜色 |
| `3dd93c8` | temperature 改为可选，按目录能力检查 |
| `9e97c29` | 紧凑资源契约与摘要视图 |
| `93f0c31` | 插件与视频诊断日志扩充 |

- **价值**：直接改善对话 / Agent 稳定性、工具调用与文本渲染，小说写作主链路受益。
- **风险：低–中**。改动集中在 agent client、tool、markdown、image request；本地这些文件未改，cherry-pick 较干净。

### D. 技能模块（与本地技能 / 广场相邻）

| 提交 | 内容 |
| --- | --- |
| `c252931` | 导入技能时替换已存在的同名技能 |
| `ea83014` | 处理导入时缺失的 GitHub revision |

- **价值**：技能导入体验改进。
- **风险：中**。本地改过技能导入编排、广场与 `setup_panel`，需逐条核对，避免影响现有导入流程与广场链接预填。

### E. 桌面导航 / 杂项

| 提交 | 内容 |
| --- | --- |
| `79faaad` | 设置作为首页打开，而非对话框（`settings_dialog.dart` +102 / -133 大改） |
| `31b0d11` | 生成任务与资源使用 12 位后缀 |
| `10f6e41` | CI 停止上传 Linux release 到 R2 |
| `bfda0da` | 版本号 0.10.0 |

- **风险**：`79faaad` 与本地导航、反馈入口、授权页入口存在交互，需确认现有反馈按钮 / 授权页是否依赖旧对话框形态；`10f6e41` CI 改动低风险。

### F. 备份修复

| 提交 | 内容 |
| --- | --- |
| `9e8f7af` | 备份 ZIP 限制内存占用，Android 导入改为流式 |

- **风险：中**。本地 `backup_service.dart` 也改过（+17 / -2），需手工合并双方改动。

## 3. 重叠文件冲突面（双方都改）

| 文件 | 本地改动 | 上游改动 | 合并要点 |
| --- | --- | --- | --- |
| `.github/workflows/build.yaml` | +38 / -40 | +0 / -30 | 本地打包 CI 为主；补上游「停传 Linux R2」 |
| `assets/translations/en/settings.json` | +127 / -1 | +3 / -1 | 以本地反馈文案为主，补上游 3 条 |
| `assets/translations/zh-CN/settings.json` | +135 / -9 | +3 / -1 | 同上 |
| `lib/desktop/pages/home.dart` | +56 / -11 | +17 / -9 | 本地反馈入口 / 导航 / 品牌为主，核对上游导航改动 |
| `lib/desktop/widgets/settings/settings_dialog.dart` | +1 / 0 | +102 / -133 | 上游重构为首页式设置；本地仅 1 行，跟随上游并确认入口 |
| `lib/desktop/widgets/workspace/novel_workspace_panel.dart` | +47 / 0 | +1 / -4 | 以本地为主，吸收上游 1 处小改 |
| `lib/main.dart` | +10 / 0 | +4 / -8 | 核对初始化顺序与本地注入 |
| `lib/shared/app_config.dart` | +5 / -5 | +5 / -1 | 保留本地 product 常量与 catalog URL，合并上游新增常量 |
| `lib/shared/localization/locale_keys.dart` | +100 / 0 | +142 / -1 | 追加式去重合并 |
| `lib/shared/models/ai_provider.dart` | +2 / -2 | +127 / -54 | 跟随上游 provider 重构，保留本地 2 处定制 |
| `lib/shared/models/provider_brand.dart` | +1 / -1 | +2 / 0 | 小改合并 |
| `lib/shared/services/backup_service.dart` | +17 / -2 | +83 / -27 | 双方都改备份，需手工合并内存上限 / 流式导入 |
| `lib/shared/services/novel_actions.dart` | +6 / 0 | +4 / -18 | 核对上游删减是否触及本地创作入口 |
| `lib/shared/widgets/settings/backup_settings_section.dart` | +3 / 0 | +53 / -28 | 跟随上游设置面板重构，保留本地 3 行 |
| `pubspec.yaml` | +6 / -2 | +3 / -1 | 仅新增 asset 条目与版本号；依赖未做大版本升级 |

## 4. 跟进策略（建议）

### 第一批：现在可吸收（低风险、主链路受益）

- C 批全部 AI / Agent 稳定性与渲染修复（`0b434b4`、`15b3cbe`、`82eb2d6`、`7187567`、`4f3af85`、`009099d`、`7c07b82`、`3dd93c8`、`9e97c29`、`93f0c31`）。
- D 批技能小修（`c252931`、`ea83014`），逐条核对现有导入与广场流程。
- E 批 CI（`10f6e41`）；`31b0d11` 任务后缀可一并评估。

方式：在当前 `unstable` 上按提交逐个 cherry-pick，每个提交后跑 `flutter analyze` 与相关 smoke 测试；不做整分支 merge。

### 第二批：单独开专项分支评估（架构 / 视觉体系）

- A 批插件 / Provider 架构重构：先回答三个问题——插件市场是否需要后端与审核；是否与本地技能离线优先 ADR 冲突；本地 Keygate 授权层如何挂到新 provider 注册表。确认后再迁移。
- B 批 production 画布与视觉制作：等短剧 / 分镜视觉功能排期时再跟；其接口依赖 A 批 provider 统一，不宜抢先。
- `79faaad` 设置首页化：与本地导航 / 反馈 / 授权入口一起在专项里评估，避免破坏现有入口。

### 暂缓 / 不跟进

- 上游版本号 `0.10.0` 本身；本地打包版本号体系（`0.6.14`）独立维护，不随上游 pubspec 版本号走。
- 与小说文本创作无关的 Android 端适配细节（本产品交付 Windows 桌面便携版）。

## 5. 合并前置校验清单（任何一批合并后必做）

1. 跑 drift 代码生成与本地数据库迁移校验；确认既有作品、人物、大纲、伏笔、地图、世界观数据不丢。
2. 核对 `home.dart` 反馈入口、授权页、托盘菜单在新导航 / 设置形态下仍可达。
3. `locale_keys.dart` 与中英翻译去重，无缺失 key、无悬空引用。
4. 保留第 1.1 节受保护定制文件不被上游覆盖。
5. Windows release 打包回归（便携版冒烟：启动稳定、无崩溃、授权与反馈弹窗正常）。
6. 本仓库约束：只推自有 `zhnn456/shutong-studio`，禁止推上游 `looplj/reveric`；打包等用户通知。

## 6. 待决策项

- 是否现在启动第一批 cherry-pick，还是等当前小说生成压测与问题清单收口后再动代码。
- A 批插件市场是否纳入产品规划（决定是否值得跟进 provider 重构）。
- B 批视觉制作体系的排期（短剧 / 分镜功能是否在近期路线图内）。
