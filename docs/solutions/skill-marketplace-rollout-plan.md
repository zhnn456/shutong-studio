# 技能广场落地规划（现状诊断 + 分阶段方案）

日期：2026-11-16。状态：规划文档，未改客户端代码。配套既有方案 `docs/solutions/github-skills-marketplace.md` 与 ADR 0003 / 0007 / 0012 / 0015。

## 1. 结论先行

代码里**已经有完整的技能广场 v1 规划，且客户端基本实现完毕**。截图里「技能广场」报错「无法加载技能目录，请检查网络后重试」，不是客户端缺陷，而是远端目录仓库尚未创建、目录 URL 仍指向上游 `looplj/reveric-skills`（本项目约束禁止推上游），且无本地缓存可兜底。

需要补的是：目录内容托管 + 把 URL 换到自有可达地址 + 首发样本条目。客户端的列表、搜索、分类、缓存、外链打开、预填导入链路均已就绪，无需另起一套安装流程。

## 2. 代码现状（已实现部分）

### 2.1 三个标签页的分工

父面板 `lib/desktop/features/agent_skills/setup_panel.dart`，枚举 `_SkTab { installed, official, market }`：

| 标签 | 枚举 | 数据来源 | 是否联网 | 职责 |
| --- | --- | --- | --- | --- |
| 技能 | `installed` | 本地已安装技能快照（设备本地 DB） | 否 | 启停、编辑、删除、导入、导出；本地技能与广场发布完全解耦 |
| 平台技能 | `official` | 打包在 App 的官方目录（`assets/official_skills/`、`assets/bundled_skills/`） | 否（离线） | 版本化本地快照，无需登录；安装后存本地快照，保留用户编辑 |
| 技能广场 | `market` | 远端 `catalog.json` 链接目录 | 是 | 只读浏览 + 浏览器打开原站 + 可导入链接预填现有导入流程 |

移动端对应 `lib/mobile/features/agent_skills/global_skill_setup_page.dart` 与 `marketplace_tab.dart`，两端共用同一套数据与交互。

### 2.2 广场数据流（已实现）

```text
app_config.revericSkillsCatalogUrl
  → AgentSkillCatalogService.listMarketplace()   流式下载 / 2 MiB 上限 / 10s 连接 · 30s 接收超时
  → 校验并原子写缓存 supportDir/skill_marketplace/catalog.json
  → MarketplaceAgentSkillsNotifier               先读缓存展示，后台刷新；失败保留旧值并记 error
  → useMarketplaceCatalog()                      防抖搜索、分类去重、内存过滤、url_launcher 打开外链
  → MarketplaceCatalogTab（桌面）/ marketplace_tab（移动）
```

关键文件：

| 文件 | 作用 |
| --- | --- |
| `lib/shared/models/marketplace_agent_skill.dart` | 六字段条目模型 + 严格 JSON 校验 + 关键词匹配 + `canImport`（链接能否被现有导入器解析） |
| `lib/shared/services/agent_skill_catalog_service.dart` | 目录下载、大小/超时限制、缓存读写与校验；官方本地目录读取相互独立 |
| `lib/shared/providers/agent_skill_catalog_providers.dart` | 广场目录加载 / 刷新 / 状态；与官方目录 provider 分开 |
| `lib/shared/widgets/agent_skill/marketplace_browser.dart` | 共享 Hook：搜索、分类、过滤、外链打开、刷新按钮与缓存提示 |
| `lib/desktop/features/agent_skills/marketplace_catalog_tab.dart` | 桌面广场：过滤栏 + 卡片网格 + 加载 / 空 / 错误三态 |
| `lib/shared/app_config.dart` | `revericSkillsCatalogUrl` 目录地址常量 |

### 2.3 目录条目格式（已由模型固化）

顶层 JSON 数组，顺序即默认展示顺序：

| 字段 | 必填 | 含义 |
| --- | --- | --- |
| `name` | 是 | 展示名称 |
| `description` | 是 | 能做什么（简短用途） |
| `url` | 是 | 来源页绝对 HTTPS 链接，不含用户名密码 |
| `when_to_use` | 否 | 什么时候用（适用场景），缺失则隐藏 |
| `category` | 否 | 分类，未填不分类 |
| `tags` | 否 | 字符串数组 |

重复 URL、非法类型、非 HTTPS、带 userInfo 的链接都会让整份目录校验失败；空数组合法。

### 2.4 当前报错根因

- `revericSkillsCatalogUrl = https://raw.githubusercontent.com/looplj/reveric-skills/main/catalog.json`。
- 该上游仓库不存在；本项目只推自有仓库 `zhnn456/shutong-studio`，禁止推上游。
- `raw.githubusercontent.com` 在国内网络常需代理；首次进入无缓存，于是落到错误态「无法加载技能目录」。

## 3. 既有架构边界（后续规划必须遵守）

摘自 ADR 与 v1 方案，不得在规划中突破：

- **本地技能不依赖广场发布**（ADR 0003）：本地编辑 / 导入 / 安装 / 执行不需要账号或审核；广场入口保持断开。未来若做投稿，需先立独立服务契约，并保证本地已存技能不受影响。
- **技能内容 = 指令文本 + 校验过的参考文件**（ADR 0007）：`references/` 可嵌套；安装与加载阶段不执行脚本。
- **官方目录离线打包**（ADR 0015）：浏览与安装读本地 asset，无需账号；广场是独立入口，不替代官方目录。
- **版本化靠本地快照 + 打包目录**（ADR 0012）：启动同步与显式升级用打包目录，尊重本地编辑与用户安装选择。
- v1 明确**不做**：应用内技能详情页、远端版本管理、自动升级、评论、评分、排行榜、专用后台、条目 ID / 作者资料 / 更新时间 / 审核人字段。

## 4. 竞品做法对照（仅作形态参考，不照搬）

| 产品 | 市场形态 | 可借鉴点 | 与本项目边界的冲突 |
| --- | --- | --- | --- |
| 扣子 Coze 技能商店 | 分类筛选 + 搜索 + 卡片 + 详情页；免费直装 / 付费订阅；安装后配置环境变量或授权；按 Agent 分配 | 分类 + 搜索 + 卡片的信息层级；安装后配置入口 | 付费、授权连接、按 Agent 分配属后端能力，超出 v1 |
| Claude Agent Skills | `SKILL.md` + YAML frontmatter + `references/`；渐进式披露：会话初只暴露名称与一句话简介 | 与本项目 SKILL.md / references 结构一致；卡片只露名称 + 一句话简介即可 | 无冲突，本项目已是该结构 |
| aiskillstore 等 GitHub 技能市场 | 仓库目录 + 安装命令 / 下载 ZIP 解压到作用域目录 | 「链接目录 + 复用现有导入」思路与本项目 v1 完全一致 | 无冲突 |
| 虾评类社区 | 评分、评测、种草、用户反馈 | 未来社区化时的参考形态 | 评分 / 评论需后端与审核，突破 ADR 0003，须另立 ADR |

## 5. 分阶段落地规划

### P0 —— 让广场在离线与国内网络下都可用（最小改动，不连后端）

1. **选定目录托管**（按可达性优先）：
   - 首选：放到自有后端 `keygate.de5.net` 静态托管一份 `catalog.json`（与反馈后台同域，国内可达，不依赖 GitHub）。
   - 次选：自有仓库 `zhnn456/shutong-studio` 子目录 + GitHub raw（国内可能仍需代理，作为备选）。
2. **内置兜底目录**：在 `assets/` 放一份首发精选 `catalog.json`（广场专用，与官方目录 asset 分开放置，遵守 ADR 0015）。启动先用内置目录展示；远端拉取成功后覆盖，失败时用「内置目录 + 磁盘缓存」兜底，避免首屏空白错误态。
3. **切换 URL 常量**：`app_config.dart` 的 `revericSkillsCatalogUrl` 指向自有地址；内置兜底由 service 在远端失败时回退读取（需在 service 增加一个 asset 目录读取方法，与 `listOfficial` 保持独立）。
4. **首发样本条目**：3–6 条自有写作技能链接（剧情连续性、章节流水线、剧本工具等，与现有 bundled 技能呼应），外加 1–2 个可被现有导入器解析的第三方公开仓库链接；普通 HTTPS 页面只展示外链、不显示导入按钮。
5. **验收**：断网可看到内置目录；有网刷新后列表替换；坏响应不覆盖好缓存；链接可在浏览器打开；受支持链接进入现有导入弹窗且预填 URL，确认前不下载。

### P1 —— 体验补齐（仍不连后端，全部本地计算）

- 条目**只读详情弹窗**：展示本地 `description` / `when_to_use` / `category` / `tags` / 来源主机名；不抓取原站正文，不做远端渲染。
- **已安装标记**：按 `url` 与本地已装技能来源比对，卡片标记「已安装」（只读标记，不提供广场专属升级 / 覆盖）。
- **失效链接提示**：目录条目链接打不开时标记待复核，不影响其它条目展示。
- 分类图标与空分类「全部」视图；搜索高亮命中字段。
- 目录增加可选 `updated_at` 展示（仅目录元数据，不做远端版本比对）。

### P2 —— 社区化 / 商业化（须先立新 ADR，突破当前边界）

以下都需要后端与审核服务，**不在 v1 范围**；立项前必须先写独立 ADR，并验证不影响本地已存技能：

- 投稿与后台审核、条目上下架。
- 评分、评论、收藏、排行榜。
- 远端版本管理、技能自动升级、更新提醒。
- 付费技能订阅与授权连接（参考扣子）。
- 多产品区分：广场条目与客服留言一样带 `product` / `product_name` 字段，后台按书童AI写作、鲸喜AI等分组展示。

## 6. 与现有安装流程的关系（不重复造轮子）

广场只把链接交给现有导入器：`AgentSkillImportSource.parse(url)` 接受 GitHub / GitLab / Gitee / GitCode 公开仓库链接；扫描候选、同名冲突、附件限制、下载取消与结果反馈全部沿用现有 `agent_skill_import_orchestrator.dart`。导入后来源保持 `novelLocal`，不写 `marketplace` 来源，不新增追溯字段。广场刷新、打开来源都不触发下载或数据库写入。

## 7. 待确认事项

- 目录托管最终选 keygate 静态托管还是自有仓库 raw（影响 `revericSkillsCatalogUrl` 取值与是否需要内置兜底）。
- P0 首发条目的清单与各自来源链接（自有技能先从现有 bundled 技能里挑选可公开的）。
- 是否在本次客户端版本就内置兜底 asset，还是先只换远端地址。
