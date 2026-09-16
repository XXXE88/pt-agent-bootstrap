# pt-agent-bootstrap

PT Agent 的**公开引导仓库**（只放安装脚本，主仓库私有）。

## 安装

```bash
curl -fsSL https://raw.githubusercontent.com/XXXE88/pt-agent-bootstrap/main/install.sh | bash
pt init      # 配置模型与密钥（BYO）
pt           # 进入交战容器
pt doctor    # 自检
```

要求：Linux / WSL2 / macOS + Docker（Linux/WSL2 完整体验；macOS 仅 bridge 网络，SYN 扫描与内网不可达）。

## 这是什么

PT Agent = Web/API 深挖型渗透测试智能体（Docker 沙箱 + 身份包 + 5 个子智能体 + L3 高危动作确认闸）。
镜像 `ghcr.io/xxxe88/pt-agent`（公开，可匿名拉取）。

## 授权声明

本工具**不含目标白名单或授权校验机制**。使用者须自行确保对测试目标拥有合法授权，未经授权的测试属违法行为。

## 文件

| 文件 | 说明 |
|---|---|
| `install.sh` | 安装器（幂等）：环境检查 → 拉镜像 → 装 `pt` → 引导 `pt init` |
| `pt` | 启动器：`init/doctor/update/down/clean/capture/install/snapshot/selftest/export-learnings` |

> 这两个文件由主仓库 `installer/` 同步生成（`bash installer/sync-bootstrap.sh --push`），请勿直接在此修改。
