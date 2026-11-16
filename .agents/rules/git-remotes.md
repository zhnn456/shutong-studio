# Git 远程与推送策略

适用于本仓库的 clone、push、pull、fetch、merge、Pull Request 与远程（remote）配置调整。

## 核心约束（硬性）

- 本项目代码**永远只推送到自有仓库**：`https://github.com/zhnn456/shutong-studio.git`（remote 名 `shutong-studio`，分支 `unstable`）。
- **禁止任何形式的推送（push）到上游仓库** `https://github.com/looplj/reveric.git`（remote 名 `origin`）。
- 上游 `origin` 仅用于 `fetch` / `pull` 拉取上游更新，**绝不用于 push**。
- 禁止向上游发起 Pull Request（PR），禁止任何把本仓库改动回传、合并、同步回上游的操作。
- 未经用户明确同意，不得删除、改名或重写现有 remote 配置，不得把 `origin` 指向自有仓库，不得添加指向上游的其它写权限 remote。

## 操作约定

- 提交（commit）：按需在本机保存版本快照。
- 推送（push）：默认且唯一目标是 `shutong-studio`，即 `git push shutong-studio unstable`。
- 拉取上游更新：使用 `git fetch origin` / `git pull origin unstable`（只读）。
- 发现任何尝试 `git push origin` 或向 `looplj/reveric` 写远程的操作，必须立即停止并改用 `shutong-studio`。

## 技术保护

- 已将 `origin` 的 push URL 指向一个不可达占位地址，从配置层面保证 `git push origin` 必然失败；如需恢复或调整须先征得用户确认。
