# PT Agent

**授权渗透测试智能体** —— 一个 Docker 沙箱里的 Web/API 深挖型 agent：
自主侦察 → 深挖利用 → 链式打通 → 内部横向 → 中文报告，全程留痕可复核。

> 面向**已获得书面授权的**渗透测试与红队评估。工具本身不含目标白名单或授权校验，授权责任在使用者。

## 安装（一条命令）

```bash
curl -fsSL https://raw.githubusercontent.com/XXXE88/pt-agent-bootstrap/main/install.sh | bash
pt init      # 配置模型与密钥（BYO：用自己的 key，走自己的网关）
pt           # 进入交战容器（首次会引导你选/新建交战）
```

装完可以先用这几条熟悉一下：

```bash
pt doctor    # 环境与能力自检（宿主 + 镜像）
pt ls        # 列出交战：最近活动 · 目标 · 发现数 · 交付状态
pt tools     # 全量工具自检（镜像内 86 项，权威清单）
```

**宿主只需要 `docker` + POSIX 工具**（不需要 python3 / node / jq）。
PT Agent 只用 `~/.pentest-agent/`，**不会碰你自己的 `~/.pi` 或全局 npm**。

## 国内网络（推荐走阿里云 ACR）

GHCR 在国内直连常不稳定（大层拉取易断、凭据过期会 `denied`）。国内建议用 ACR（公开仓库，可匿名拉取）：

```bash
# 安装时直接指定
PT_IMAGE_REGISTRY=crpi-bp9jv9s9c4qx3e17.cn-hangzhou.personal.cr.aliyuncs.com/pentest_images \
  bash install.sh

# 装好后也可以随时切换
PT_IMAGE_REGISTRY=crpi-bp9jv9s9c4qx3e17.cn-hangzhou.personal.cr.aliyuncs.com/pentest_images pt update

# 或者直接给完整镜像
PT_IMAGE=crpi-bp9jv9s9c4qx3e17.cn-hangzhou.personal.cr.aliyuncs.com/pentest_images/pt-agent:v0.2.3 \
  bash install.sh
```

也可以走离线包（约 2.1 GB，比裸拉 8.2 GB 省 3/4 流量）：
从 Release 下载 `pt-agent-v<版本>.tar.zst` 后 `bash install.sh --offline pt-agent-v<版本>.tar.zst`。

## 平台

| 平台 | 状态 |
|---|---|
| Linux / WSL2 | 完整体验（host 网络：SYN 扫描、内网横向都可用） |
| macOS | 可用，但仅 bridge 网络（SYN 扫描与内网目标不可达） |
| Windows | 建议 ssh 到一台 Linux 使用；或 WSL2 + Docker Desktop |

## 文件

| 文件 | 说明 |
|---|---|
| `install.sh` | 安装器（幂等）：环境检查 → 拉镜像 → 装 `pt` → 引导 `pt init` |
| `pt` | 启动器：`init / doctor / update / ls / rename / rm / capture / tools / snapshot / selftest / export-learnings` |

> 这两个文件由主仓库 `installer/` 同步生成（`bash installer/sync-bootstrap.sh --push`），请勿直接在此修改。
