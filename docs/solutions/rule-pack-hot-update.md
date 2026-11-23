# 规则库混合热更

规则库（小说题材包 + 竖屏短剧流派包）支持三种更新路径：安装包内置、远端热更缓存、缓存失效自动回退内置。

## 加载顺序

1. 读内置清单 `assets/rule_packs/manifest.json`，得到内置版本号；
2. 读本地缓存 `<应用数据>/rule_packs_cache/manifest.json`；
3. **缓存版本 严格大于 内置版本** 且逐文件校验通过 → 用缓存（UI 显示「已热更」）；
4. 否则用内置（UI 显示「内置」）。

缓存校验包含：文件名合法（仅 `*.json`，无路径分隔符）、字节数与清单一致、sha256 一致、内容能解析出至少一个可用包。任一条失败即整体回退内置，不中断使用。

## 发布一次热更

```bash
# 1. 改 assets/rule_packs/*.json（新增包直接追加到对应文件）
# 2. 递增版本号并重算清单（同时写 assets 内置清单与 rule_packs 发布目录）
python tools/build_rule_pack_manifest.py --version 3
# 3. 推送仓库；GitHub raw 即成为热更源
git add assets/rule_packs rule_packs tools/build_rule_pack_manifest.py
git commit -m "feat(rule-pack): 规则库热更 v3"
git push
```

清单地址在 `lib/shared/app_config.dart` 的 `revericRulePackManifestUrl`；为空表示不发任何网络请求，只用内置。

## 版本与回滚

- 清单 `version` 必须严格递增才生效，同版本重复检查直接返回「已是最新」。
- 下载先落 `<缓存>/staging_<时间戳>/`，全部校验通过后才原子改名进缓存目录，清单最后写盘；中途失败旧缓存不受影响。
- 回滚到内置：删除 `rule_packs_cache/` 目录，或调用 `resetAgentRulePacksToBundled()`。
- 安装包自带更新的规则库时（内置版本 ≥ 缓存版本），内置自动优先，无需清理用户机器。

## 结构兼容

- 清单 `schema` 固定为 1；结构真要变，才需要随安装包升级并提高 `schema`。
- 规则包 JSON 新增字段对老版本应「可忽略」；只有新增 UI 才能展示的字段（如分组、正例、自检项）应先发数据、再发客户端。

## 代码位置

- `lib/shared/models/agent_rule_pack_manifest.dart` — 清单模型与合法性校验
- `lib/shared/services/agent_rule_pack_service.dart` — `loadAgentRulePacks` / `describeAgentRulePackLibrary` / `refreshAgentRulePacks` / `resetAgentRulePacksToBundled`
- `lib/desktop/widgets/agent_management/agent_rule_pack_dialog.dart` — 规则库弹窗底部的版本行与「检查更新」入口
- `tools/build_rule_pack_manifest.py` — 生成内置清单与发布目录
- `test/shared/agent_rule_pack_hot_update_test.dart` — 清单校验、缓存优先、篡改回退、下载落地、失败不污染缓存

## 已验证

真机（Windows，2026-11-23）：

- 内置态：底栏显示「规则库 v2 · 25 包 272 条 · 内置」；
- 远端未发布时点「检查更新」→ 提示「更新失败，继续使用当前规则库」，包数不变；
- 手工写入 v3 缓存（含一个测试包）后重启 → 显示「v3 · 26 包 282 条 · 已热更」，左侧分类出现该包；
- 缓存文件字节与清单不符时 → 自动回退内置，日志记录 `体积异常`，界面仍是 25 包。
