#!/usr/bin/env bash
# wsl-docker-fix.sh —— 在 WSL2 里把 Docker 修到可用（幂等，可反复跑）
#
#   sudo bash installer/wsl-docker-fix.sh
#
# 做四件事：
#   ① 判断是否该走 Docker Desktop（装了的话给出建议，不擅自改 Windows 配置）
#   ② 确保 docker CLI + dockerd 存在
#   ③ 把 daemon 拉起来（依次尝试 service / systemd / 手动 dockerd / iptables-legacy / vfs 兜底）
#   ④ 配国内镜像加速（含 ghcr 代理），最后自检
set -uo pipefail

if [ "$(id -u)" != "0" ]; then
  echo "[x] 请用 root 运行：sudo bash $0" >&2
  exit 1
fi

C_G="\033[32m"; C_Y="\033[33m"; C_R="\033[31m"; C_B="\033[36m"; C_0="\033[0m"
ok(){ printf "${C_G}[ok]${C_0} %s\n" "$*"; }
info(){ printf "${C_B}[..]${C_0} %s\n" "$*"; }
warn(){ printf "${C_Y}[!]${C_0} %s\n" "$*"; }
bad(){ printf "${C_R}[x]${C_0} %s\n" "$*"; }

is_wsl=0; grep -qi microsoft /proc/version 2>/dev/null && is_wsl=1
[ "$is_wsl" = 1 ] && ok "检测到 WSL" || warn "这不是 WSL（脚本仍可运行，但针对 WSL 的兜底步骤可能不适用）"

daemon_up() { docker info 2>/dev/null | grep -q "Server Version"; }

# ── ① Docker Desktop 提示 ───────────────────────────────
DD="/mnt/c/Program Files/Docker/Docker/Docker Desktop.exe"
if [ -f "$DD" ]; then
  ok "检测到 Windows 侧 Docker Desktop 已安装"
  info "更推荐的做法（省去 WSL 内跑 daemon 的麻烦）："
  info "  打开 Docker Desktop → Settings → Resources → WSL Integration → 打开本发行版 → Apply & Restart"
  info "  然后回到 WSL 执行：docker info | grep 'Server Version'"
  info "若你不想用 Desktop，下面的步骤会继续在 WSL 内自建 daemon。"
else
  info "未检测到 Docker Desktop（将使用 WSL 内自建 daemon）"
fi

# ── ② CLI / dockerd ────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
  info "安装 docker.io（走系统镜像源）"
  apt-get update -qq && apt-get install -y -qq docker.io || { bad "docker.io 安装失败"; exit 1; }
fi
ok "docker CLI: $(docker --version)"
if ! command -v dockerd >/dev/null 2>&1; then
  warn "缺少 dockerd，尝试补装 docker.io"
  apt-get install -y -qq docker.io || true
fi
command -v dockerd >/dev/null 2>&1 && ok "dockerd: $(command -v dockerd)" || bad "仍无 dockerd"

# ── ③ 拉起 daemon ─────────────────────────────────────
if daemon_up; then
  ok "daemon 已在运行：$(docker info 2>/dev/null | awk -F': ' '/Server Version/{print $2}')"
else
  info "尝试 service docker start"
  service docker start >/dev/null 2>&1 || true; sleep 4
  daemon_up || { info "尝试 systemctl start docker"; systemctl start docker >/dev/null 2>&1 || true; sleep 4; }

  if ! daemon_up; then
    info "手动启动 dockerd（日志 /tmp/dockerd.log）"
    nohup dockerd >/tmp/dockerd.log 2>&1 & sleep 10
  fi

  if ! daemon_up; then
    if grep -qi "iptables" /tmp/dockerd.log 2>/dev/null; then
      warn "日志提示 iptables 问题 → 切 legacy 后重启"
      update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true
      update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true
      pkill -f dockerd 2>/dev/null || true; sleep 3
      nohup dockerd >/tmp/dockerd.log 2>&1 & sleep 10
    fi
  fi

  if ! daemon_up; then
    if grep -qiE "overlay|mount" /tmp/dockerd.log 2>/dev/null; then
      warn "日志提示 overlay 挂载问题 → 用 vfs 存储驱动兜底（较慢）"
      pkill -f dockerd 2>/dev/null || true; sleep 3
      nohup dockerd --storage-driver=vfs >/tmp/dockerd.log 2>&1 & sleep 10
    fi
  fi
fi

# ── ③.5 Compose v2（靶场与多容器需要）──────────────────
if ! docker compose version >/dev/null 2>&1; then
  info "安装 docker compose v2"
  apt-get install -y -qq docker-compose-v2 2>/dev/null \
    || { mkdir -p /usr/local/lib/docker/cli-plugins
         curl -fL --retry 2 -o /usr/local/lib/docker/cli-plugins/docker-compose \
           "https://ghfast.top/https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(dpkg --print-architecture | sed 's/amd64/x86_64/;s/arm64/aarch64/')" \
           && chmod +x /usr/local/lib/docker/cli-plugins/docker-compose; }
fi
docker compose version >/dev/null 2>&1 && ok "compose: $(docker compose version --short)" || warn "compose 仍不可用（靶场无法启动）"

# ── ④ 镜像加速（国内）────────────────────────────────────
DAEMON_JSON=/etc/docker/daemon.json
if [ ! -f "$DAEMON_JSON" ]; then
  info "写入 $DAEMON_JSON（Docker Hub 加速）"
  mkdir -p /etc/docker
  cat > "$DAEMON_JSON" <<'EOF'
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://docker.1ms.run",
    "https://hub.rat.dev"
  ],
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
  pkill -f dockerd 2>/dev/null || true; sleep 2
  service docker restart >/dev/null 2>&1 || (nohup dockerd >/tmp/dockerd.log 2>&1 & sleep 8)
else
  ok "已存在 $DAEMON_JSON（保留原配置）"
fi

# ── 自检 ───────────────────────────────────────────────
echo
info "自检"
if daemon_up; then
  ok "daemon 可用：$(docker info 2>/dev/null | awk -F': ' '/Server Version/{print "Server "$2}')"
  docker images >/dev/null 2>&1 && ok "docker images 正常"
  echo
  info "ghcr.io 拉取（本产品镜像仓库）如需加速，可在 /etc/docker/daemon.json 里改用："
  info '  "registry-mirrors" 之外，ghcr 代理可用：docker pull ghcr.m.daocloud.io/xxxe88/pt-agent:dev 再 docker tag 回 ghcr.io/xxxe88/pt-agent:dev'
  echo
  ok "现在可以构建：bash image/build.sh --tag pt-agent:dev --proxy https://ghfast.top/"
  info "（若构建期 apt/pip 拉不动：加 --network-host）"
else
  bad "daemon 仍未起来，请把下面日志后 30 行贴回："
  tail -30 /tmp/dockerd.log 2>/dev/null || echo "（无日志，可能 dockerd 未启动）"
  exit 1
fi
