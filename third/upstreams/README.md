# 上游复用源码（third/upstreams）

本目录存放从开源项目直接取用的源码与文档，**不是自研实现**。所有条目均为宽松许可证，可商用，须保留原始 LICENSE 与版权声明。

## 1. chinese-longnovel-skill（MyNovel）

- 来源：https://github.com/xiaofeng-928/chinese-longnovel-skill
- 版本：v2.2.0（master，depth=1 克隆）
- 许可证：MIT（见 `chinese-longnovel-skill/LICENSE`）
- 形态：Codex / Claude Code Skill（SKILL.md + references + prompts + scripts）
- 复用方式：**文档与提示词直接作为规范来源**；Python 脚本作为规则参考，不随包分发。

可直接对接本项目的能力：

| 上游文件 | 对应本项目能力 |
|---|---|
| `references/开书流程.md` | 一键开书主链（扫榜→方案→建壳） |
| `references/规划窗口与防抢跑.md` | 分级冻结：宏观阶段 / 50 章窗口 / 5 章预算 |
| `references/长篇上下文与一致性.md` | 分层上下文组装、事实锁 |
| `references/状态与总结.md` | 篇幅状态回证（计划态 vs 事实态） |
| `prompts/大纲生成提示词.md` | 总大纲 + 分卷 |
| `prompts/分阶段大纲细化提示词.md` | 逐章细纲（每章标题与梗概） |
| `scripts/validate_project.py` | 骨架校验规则源（窗口合同/细纲节点/提交链） |
| `scripts/validate_chapter_candidate.py` | 章级候选校验规则源 |

**改造边界**：原技能假定 Agent 有本地文件读写与 `py -3` 执行权限。本项目的 Agent 使用 `Run` / `Create` / `AskUser` 等结构化工具，数据库为 SQLite 而非 Markdown 文件。因此只搬运「方法论、规则、schema、判定条件」，工具调用段必须改写为本项目 schema；这一层属于适配，不是重写方法论。

## 2. QianBi-Novel（千笔一文）

- 来源：https://github.com/GLFzr/QianBi-Novel
- 许可证：MIT（见 `qianbi-novel/LICENSE`）
- 形态：PySide6 + QML 桌面应用
- 已取文件：`app/mustscan.py`、`app/wb.py`、`app/core/scan.py`

可直接对接本项目的能力：

| 上游文件 | 对应本项目能力 |
|---|---|
| `app/mustscan.py` | 正则 must 契约的**确定性复检**（零 LLM，~100 行，纯正则+极性判定） |
| `app/core/scan.py` | L0 本地预检：专名错乱 / 长重复串 / 数字矛盾 / 钩子缺失 / 术语漂移 |
| `app/wb.py` | 条目化世界书引擎：`parse` / `trigger` / `assemble`，条目带 `content_hash`，按「常驻 > 本章命中 > 近章登记 > 节权重」入预算，返回 `activated` / `dropped` 留痕 |

**改造边界**：Python 实现不嵌入 Flutter 包。移植到 Dart 的是**判定逻辑与规则表**（正则表、极性、窗口、阻断/建议分级），数据结构映射到本项目 `Document` / `lore` / `Foreshadowings`。世界书条目优先级模型可直接复用，存储层改为按 `documentId` 关联。

## 注意

- 上游 README 与文档中的产品名、价格、功能承诺均不属于本项目承诺。
- 升级上游时按 commit 记录版本，不要无痕覆盖。
