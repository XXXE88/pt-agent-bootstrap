# pt-agent-bootstrap

PT Agent 的**公开引导仓库**（只放安装脚本，主仓库私有）。

## 安装

```bash
curl -fsSL https://raw.githubusercontent.com/XXXE88/pt-agent-bootstrap/main/install.sh | bash
pt init      # 配置模型与密钥（BYO）
pt           # 进入交战容器（首次会让你选/新建交战）
pt doctor    # 环境与能力自检
pt ls        # 列出交战：最近活动 · 目标 · 发现数 · 交付状态
```

**宿主只需要 `docker` + POSIX 工具**（不需要 python3 / node / jq）。
PT Agent 只用 `~/.pentest-agent/`，**不会碰你自己的 `~/.pi` 或全局 npm**。

平台：Linux / WSL2 完整体验；macOS 仅 bridge 网络（SYN 扫描与内网不可达）；
Windows 建议 ssh 到一台 Linux 用（本机无需虚拟化），或走 WSL2 + Docker Desktop。

## 这是什么

PT Agent = Web/API 深挖型渗透测试智能体（Docker 沙箱 + 身份包 + 5 个子智能体 + L3 高危动作确认闸）。
镜像 `ghcr.io/xxxe88/pt-agent`（当前 v0.2.2；默认 private，安装时用 `PT_GHCR_TOKEN=<PAT>` 拉取）。
另有离线包：Release 里的 `pt-agent-v<版本>.tar.zst`（`install.sh --offline` 可直接加载）。

## 授权声明

本工具**不含目标白名单或授权校验机制**。使用者须自行确保对测试目标拥有合法授权，未经授权的测试属违法行为。

## 文件

| 文件 | 说明 |
|---|---|
| `install.sh` | 安装器（幂等）：环境检查 → 拉镜像 → 装 `pt` → 引导 `pt init` |
| `pt` | 启动器：`init/doctor/update/down/clean/capture/install/snapshot/selftest/export-learnings` |

> 这两个文件由主仓库 `installer/` 同步生成（`bash installer/sync-bootstrap.sh --push`），请勿直接在此修改。
