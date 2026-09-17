#!/usr/bin/env bash
# PT Agent 安装器（幂等，可重复执行）
#   curl -fsSL https://raw.githubusercontent.com/XXXE88/pt-agent/main/installer/install.sh | bash
#   bash install.sh --help
#
# 规格见 docs/SPEC.md §13

set -euo pipefail

PT_VERSION_DEFAULT="0.1.0"
PT_DIR="${PT_DIR:-$HOME/.pentest-agent}"
PT_IMAGE_REGISTRY="${PT_IMAGE_REGISTRY:-ghcr.io/xxxe88}"
PT_OFFLINE_TAR=""
PT_SKIP_PULL=0
PT_LOCAL_IMAGE=""

C_R="\033[31m"; C_G="\033[32m"; C_Y="\033[33m"; C_B="\033[36m"; C_0="\033[0m"
log()  { printf "${C_B}[pt]${C_0} %s\n" "$*"; }
ok()   { printf "${C_G}[ok]${C_0} %s\n" "$*"; }
warn() { printf "${C_Y}[!]${C_0} %s\n" "$*"; }
die()  { printf "${C_R}[x]${C_0} %s\n" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
用法: install.sh [选项]

  --dir <path>        运行时目录（默认 ~/.pentest-agent）
  --version <ver>     镜像版本（默认 0.1.0）
  --registry <host>   镜像仓库前缀（默认 ghcr.io/xxxe88）
  --local-image <tag> 使用本地已有的镜像 tag，不拉取
  --offline <tar>     从离线镜像包安装（docker load）
  --skip-pull         跳过镜像拉取（仅装启动器与目录）
  -h, --help          显示帮助
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) PT_DIR="$2"; shift 2 ;;
    --version) PT_VERSION_DEFAULT="$2"; shift 2 ;;
    --registry) PT_IMAGE_REGISTRY="$2"; shift 2 ;;
    --local-image) PT_LOCAL_IMAGE="$2"; PT_SKIP_PULL=1; shift 2 ;;
    --offline) PT_OFFLINE_TAR="$2"; PT_SKIP_PULL=1; shift 2 ;;
    --skip-pull) PT_SKIP_PULL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数: $1（--help 查看用法）" ;;
  esac
done

PT_IMAGE="${PT_IMAGE_REGISTRY}/pt-agent:${PT_VERSION_DEFAULT}"
mkdir -p "$PT_DIR"
LOG="$PT_DIR/install.log"
exec > >(tee -a "$LOG") 2>&1

log "PT Agent 安装器 · $(date -Iseconds)"
log "运行时目录: $PT_DIR"

# ── 1. 前置检查 ─────────────────────────────────────────
log "1/6 前置检查"

case "$(uname -s)" in
  Linux) OS=linux ;;
  Darwin) OS=darwin ;;
  *) die "不支持的系统: $(uname -s)（需要 Linux / WSL2 / macOS）" ;;
esac
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) die "不支持的架构: $ARCH" ;;
esac
log "  系统: $OS/$ARCH"

if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; then
  IS_WSL=1; log "  环境: WSL2 ($WSL_DISTRO_NAME)"
else
  IS_WSL=0
  if [ "$OS" = "darwin" ]; then
    warn "macOS：Docker Desktop 只能使用 bridge 网络，SYN 扫描与内网目标不可达（见 README 平台说明）"
  fi
fi

command -v curl >/dev/null || die "缺少 curl"
if ! command -v docker >/dev/null; then
  die "未检测到 docker。
  → 请先安装 Docker（Linux: apt install docker.io 或官方脚本；Windows: Docker Desktop + WSL2）
  → 或改用裸机方案: pi install <identity>（工具不全，仅方法论可用）"
fi
docker info >/dev/null 2>&1 || die "docker 已安装但 daemon 不可用（检查服务是否启动 / 当前用户是否在 docker 组）"

AVAIL_KB=$(df -Pk "$PT_DIR" | awk 'NR==2{print $4}')
if [ "${AVAIL_KB:-0}" -lt 8388608 ]; then
  warn "可用磁盘 $((AVAIL_KB/1024)) MB < 8 GB，镜像与工作区可能不够"
fi
ok "docker $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo '?') · 磁盘 $((AVAIL_KB/1024/1024)) GB 可用"

# ── 2. 目录与资源探测 ───────────────────────────────────
log "2/6 创建目录与资源探测"
mkdir -p "$PT_DIR"/{workspaces,pi-home} "$PT_DIR/pi-home/"{skills,agents}

detect_mem_mb() {
  if [ -r /proc/meminfo ]; then awk '/MemTotal/{printf "%d\n", $2/1024}' /proc/meminfo; else echo 8192; fi
}
detect_cpu() {
  if command -v nproc >/dev/null; then nproc; elif [ "$OS" = darwin ]; then sysctl -n hw.ncpu; else echo 4; fi
}
TOTAL_MEM_MB=$(detect_mem_mb); CPUS=$(detect_cpu)
# 60% 分配（SPEC §4/§29）；下限保护
MEM_MB=$(( TOTAL_MEM_MB * 60 / 100 )); [ "$MEM_MB" -lt 2048 ] && MEM_MB=2048
CPUS_60=$(( CPUS * 60 / 100 )); [ "$CPUS_60" -lt 1 ] && CPUS_60=1

CONFIG="$PT_DIR/config.env"
if [ -f "$CONFIG" ]; then
  log "  已有 config.env，保留用户配置（仅补充缺失项）"
else
  cat > "$CONFIG" <<EOF
# PT Agent 配置（chmod 600；密钥只存这里，永不进镜像）
# 生成于 $(date -Iseconds)

# ── 运行资源（安装时探测：宿主内存/CPU 的 60%）──
PT_MEM=${MEM_MB}m
PT_CPUS=${CPUS_60}
PT_PIDS_LIMIT=2048
PT_NETWORK=host
PT_CAPS=NET_RAW,NET_ADMIN

# ── 镜像 ──
PT_IMAGE=${PT_IMAGE}

# ── 模型（BYO：默认 DeepSeek V4.1 Flash；可换任意 OpenAI 兼容）──
PT_MODEL=deepseek-v4-flash
PT_THINKING_RECON=medium
PT_THINKING_PROBER=max
PT_THINKING_EXPLOITER=max
PT_THINKING_REVIEWER=max
PT_THINKING_REPORTER=medium

# ── 凭据（按需填其一）──
# 方式一：OpenAI 兼容网关
# PT_PROVIDER=gateway
# PT_BASE_URL=https://your-gateway.example.com/v1
# PT_API_KEY=sk-...
# 方式二：原生 provider（Anthropic / OpenAI / DeepSeek …）
# PT_PROVIDER=deepseek
# DEEPSEEK_API_KEY=sk-...
EOF
  ok "已生成 $CONFIG（内存 ${MEM_MB}m / CPU ${CPUS_60}，宿主共 ${TOTAL_MEM_MB}m / ${CPUS} 核）"
fi
chmod 600 "$CONFIG"

# ── 3. 镜像 ─────────────────────────────────────────────
log "3/6 镜像"
if [ -n "$PT_OFFLINE_TAR" ]; then
  [ -f "$PT_OFFLINE_TAR" ] || die "离线包不存在: $PT_OFFLINE_TAR"
  log "  从离线包导入: $PT_OFFLINE_TAR（可能需要几分钟）"
  docker load -i "$PT_OFFLINE_TAR" || die "docker load 失败"
  ok "离线镜像已导入"
elif [ -n "$PT_LOCAL_IMAGE" ]; then
  docker image inspect "$PT_LOCAL_IMAGE" >/dev/null 2>&1 || die "本地镜像不存在: $PT_LOCAL_IMAGE"
  ok "使用本地镜像 $PT_LOCAL_IMAGE"
elif [ "$PT_SKIP_PULL" = "1" ]; then
  warn "跳过镜像拉取"
else
  if docker image inspect "$PT_IMAGE" >/dev/null 2>&1; then
    ok "镜像已存在: $PT_IMAGE"
  else
    log "  拉取 $PT_IMAGE（约 3 GB，国内可用镜像加速）"
# 私有镜像仓库：给出 GHCR 凭据时不弹窗登录（GHCR 的 pt-agent 包默认 private）
if [ -n "${PT_GHCR_TOKEN:-}" ]; then
  echo "${PT_GHCR_TOKEN}" | docker login ghcr.io -u "${PT_GHCR_USER:-$(git config user.name || echo user)}" --password-stdin \
    && echo "[ok] 已登录 ghcr.io" || echo "[!] ghcr.io 登录失败（镜像若为 public 可忽略）"
fi
    if ! docker pull "$PT_IMAGE"; then
      die "镜像拉取失败。可选：
  → 配置 docker 镜像加速后重试（见 README）
  → 使用离线包: bash install.sh --offline pt-agent-v0.1.0.tar.zst
  → 如果镜像已在本机: bash install.sh --local-image <tag>"
    fi
    ok "镜像已就绪"
  fi
fi

# ── 4. 启动器 ───────────────────────────────────────────
log "4/6 安装 pt 启动器"
BIN_DIR="$HOME/.local/bin"; mkdir -p "$BIN_DIR"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo '.')"
if [ -f "$SCRIPT_DIR/pt" ]; then
  install -m 0755 "$SCRIPT_DIR/pt" "$BIN_DIR/pt"
else
  log "  从仓库下载 pt 启动器"
  curl -fsSL "https://raw.githubusercontent.com/XXXE88/pt-agent-bootstrap/main/pt" -o "$BIN_DIR/pt"
  chmod 0755 "$BIN_DIR/pt"
fi
ok "已安装 $BIN_DIR/pt"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) warn "请把 $BIN_DIR 加进 PATH: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;; esac

# ── 5. 身份包清单（供容器内 pi 更新）─────────────────────
log "5/6 身份包与扩展目录"
mkdir -p "$PT_DIR/pi-home/extensions"
ok "pi-home 就绪（身份在镜像内；容器内可 pi update --extensions 更新）"

# ── 6. 收尾 ─────────────────────────────────────────────
log "6/6 完成"
cat <<EOF

下一步：
  1) $BIN_DIR/pt init      # 选模型、填 key、连通性自检
  2) $BIN_DIR/pt           # 进入交战容器（首次会让你给交战起名）
  3) $BIN_DIR/pt doctor    # 六项自检

说明：
  · 装卸载：$BIN_DIR/pt clean --purge 可删工作区；卸载 = 删 $PT_DIR 与 $BIN_DIR/pt，再 docker rmi $PT_IMAGE
  · 授权：本产品不含目标白名单机制，测试授权由你自负（见 docs/SPEC.md §9）
EOF
