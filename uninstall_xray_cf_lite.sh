#!/usr/bin/env bash
set -Eeuo pipefail

readonly STATE_DIR="/etc/xray-cf-lite"
readonly STATE_FILE="${STATE_DIR}/state.json"

info() { printf '\033[36m-\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m! %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

remove_path() {
    local path="$1"
    [[ -e "$path" || -L "$path" ]] || return 0
    rm -rf -- "$path"
    info "已删除 $path"
}

[[ "$(id -u)" == "0" ]] || die "请使用 root 运行"

echo
echo "即将彻底删除本机上的 xray-cf-lite 和 xray："
echo "  - xray 服务、进程、二进制、配置、geodata 和日志"
echo "  - /usr/local/bin/x 快捷命令"
echo "  - /etc/xray-cf-lite 状态及 Cloudflare 凭据"
echo "  - /root 和当前目录中的订阅快照"
echo
warn "此脚本不修改 Cloudflare。DNS、SSL、Origin Rules 和安全设置需要在 Cloudflare 控制台检查。"

if [[ -s "$STATE_FILE" ]]; then
    warn "检测到 $STATE_FILE，其中可能包含 Cloudflare 回滚备份。"
    warn "如需自动恢复 Cloudflare，应先使用 x 菜单中的正常卸载，不要运行本脚本。"
fi

if [[ "${1:-}" != "--yes" ]]; then
    read -rp "确认清除以上本机内容？请输入 REMOVE: " answer
    [[ "$answer" == "REMOVE" ]] || die "已取消"
fi

info "停止 xray 服务和残留进程"
if command -v systemctl &>/dev/null; then
    systemctl stop xray.service &>/dev/null || true
    systemctl disable xray.service &>/dev/null || true
    systemctl stop 'xray@*.service' &>/dev/null || true
fi

if command -v rc-service &>/dev/null; then
    rc-service xray stop &>/dev/null || true
fi
if command -v rc-update &>/dev/null; then
    rc-update del xray default &>/dev/null || true
fi
if command -v pkill &>/dev/null; then
    pkill -x xray &>/dev/null || true
fi

remove_path "/etc/systemd/system/xray.service"
remove_path "/etc/systemd/system/xray@.service"
remove_path "/etc/systemd/system/xray.service.d"
remove_path "/etc/systemd/system/xray@.service.d"
remove_path "/etc/systemd/system/multi-user.target.wants/xray.service"
remove_path "/etc/init.d/xray"

if command -v systemctl &>/dev/null; then
    systemctl daemon-reload
    systemctl reset-failed xray.service &>/dev/null || true
fi

remove_path "/usr/local/bin/x"
remove_path "/usr/local/bin/xray"
remove_path "/usr/local/etc/xray"
remove_path "/usr/local/share/xray"
remove_path "$STATE_DIR"
remove_path "/var/log/xray"
remove_path "/var/log/xray.log"
remove_path "/run/xray.pid"
remove_path "/root/cf_lite_last_links.txt"

if [[ "$PWD" != "/root" ]]; then
    remove_path "${PWD}/cf_lite_last_links.txt"
fi

# 清理由本项目安装器创建但未正常退出的临时目录。
find /tmp -mindepth 1 -maxdepth 1 -type d -name 'xray-install-[0-9]*' -exec rm -rf -- {} + 2>/dev/null || true

echo
ok "本机 xray-cf-lite 与 xray 已彻底清理"
warn "重新安装前，请到 Cloudflare 控制台检查对应域名的 A 记录、SSL 模式和 Origin Rules。"
