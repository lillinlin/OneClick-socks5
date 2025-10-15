#!/bin/bash
set -e

# ============================================
# Xray SOCKS5 一体化安装与管理脚本 by lillinlin
# ============================================

XRAY_DIR="/usr/local/xray"
CONF_FILE="/etc/xray/config.json"
SERVICE_FILE="/etc/systemd/system/xray-socks5.service"

# 自动检测 root 权限
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        exec sudo "$0" "$@"
    else
        echo "错误: 当前用户不是 root 且系统未安装 sudo，请使用 root 用户执行。"
        exit 1
    fi
fi

# ================= 安装函数 =================
function install_s5() {
    echo "================ Xray SOCKS5 安装程序 ================"

    # 检测包管理器
    if command -v apt >/dev/null 2>&1; then
        PKG="apt"
    elif command -v yum >/dev/null 2>&1; then
        PKG="yum"
    elif command -v dnf >/dev/null 2>&1; then
        PKG="dnf"
    else
        echo "不支持的系统，请使用 Debian/Ubuntu/CentOS 等常见发行版。"
        exit 1
    fi

    echo "正在安装依赖..."
    $PKG update -y >/dev/null 2>&1 || true
    $PKG install -y curl wget jq unzip >/dev/null 2>&1 || true

    # 用户输入配置
    read -p "请输入监听端口（默认随机）: " PORT
    read -p "请输入用户名（默认123）: " USER
    read -p "请输入密码（默认123）: " PASS

    [ -z "$PORT" ] && PORT=$((RANDOM % 20000 + 10000))
    [ -z "$USER" ] && USER="123"
    [ -z "$PASS" ] && PASS="123"

    echo "-------------------------------------------------------"
    echo "端口: $PORT"
    echo "用户名: $USER"
    echo "密码: $PASS"
    echo "-------------------------------------------------------"

    mkdir -p /etc/xray /usr/local/xray

    # 下载 Xray 核心
    echo "正在下载最新 Xray 核心..."
    LATEST_URL=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r '.assets[] | select(.name | test("linux-64.zip$")) | .browser_download_url')
    if [ -z "$LATEST_URL" ]; then
        echo "无法获取最新版本，可能是 GitHub API 访问受限。"
        exit 1
    fi
    wget -qO /usr/local/xray/xray.zip "$LATEST_URL"
    unzip -o /usr/local/xray/xray.zip -d /usr/local/xray >/dev/null
    chmod +x /usr/local/xray/xray
    rm -f /usr/local/xray/xray.zip

    # 写入配置
    cat >"$CONF_FILE" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": $PORT,
    "protocol": "socks",
    "settings": {
      "auth": "password",
      "accounts": [{ "user": "$USER", "pass": "$PASS" }],
      "udp": true,
      "ip": "127.0.0.1"
    }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF

    # 创建 systemd 服务
    cat >"$SERVICE_FILE" <<EOF
[Unit]
Description=Xray SOCKS5 Service
After=network.target

[Service]
ExecStart=$XRAY_DIR/xray -config $CONF_FILE
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now xray-socks5 >/dev/null 2>&1

    ln -sf "$(realpath "$0")" /usr/local/bin/s5
    chmod +x /usr/local/bin/s5

    echo "================ 安装完成 ================"
    echo "SOCKS5 服务已启动"
    echo "端口: $PORT"
    echo "用户名: $USER"
    echo "密码: $PASS"
    echo "使用命令 's5' 可打开管理面板"
    echo "=========================================="
}

# ================= 卸载函数 =================
function uninstall_s5() {
    echo "正在卸载..."
    systemctl disable --now xray-socks5 >/dev/null 2>&1 || true
    rm -f "$SERVICE_FILE"
    rm -rf "$XRAY_DIR" /etc/xray
    rm -f /usr/local/bin/s5
    systemctl daemon-reload
    echo "卸载完成。"
}

# ================= 更新核心 =================
function update_core() {
    echo "正在更新 Xray 核心..."
    LATEST_URL=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r '.assets[] | select(.name | test("linux-64.zip$")) | .browser_download_url')
    wget -qO /usr/local/xray/xray.zip "$LATEST_URL"
    unzip -o /usr/local/xray/xray.zip -d /usr/local/xray >/dev/null
    chmod +x /usr/local/xray/xray
    rm -f /usr/local/xray/xray.zip
    systemctl restart xray-socks5
    echo "核心已更新。"
}

# ================= 管理面板 =================
function check_status() {
    local SYS_STATUS=$(systemctl is-active xray-socks5 || echo "inactive")
    local STATUS="关闭"
    [ "$SYS_STATUS" = "active" ] && STATUS="运行"

    local VERSION=$($XRAY_DIR/xray version 2>/dev/null | head -n 1 || echo "未知")
    local USERNAME=$(jq -r '.inbounds[0].settings.accounts[0].user' $CONF_FILE 2>/dev/null || echo "-")
    local PASSWORD=$(jq -r '.inbounds[0].settings.accounts[0].pass' $CONF_FILE 2>/dev/null || echo "-")
    local PORT=$(jq -r '.inbounds[0].port' $CONF_FILE 2>/dev/null || echo "-")

    # 检查最新 Xray 核心版本
    LATEST=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r '.tag_name')
    LOCAL_VER=$(echo $VERSION | awk '{print $2}')
    if [[ -n "$LATEST" && "$LATEST" != "$LOCAL_VER" ]]; then
        UPDATE_STATUS="有 ($LATEST)"
    else
        UPDATE_STATUS="无"
    fi

    echo "================ Xray SOCKS5 管理面板 ================"
    echo "服务状态      : $STATUS"
    echo "核心版本      : $VERSION"
    echo "是否有新版本  : $UPDATE_STATUS"
    echo "监听端口      : $PORT"
    echo "用户名        : $USERNAME"
    echo "密码          : $PASSWORD"
    echo "-------------------------------------------------------"
    echo "1. 启动服务"
    echo "2. 停止服务"
    echo "3. 卸载服务"
    echo "4. 更新核心"
    echo "5. 退出面板"
    echo "-------------------------------------------------------"
    read -p "请选择操作: " CHOICE

    case "$CHOICE" in
        1) systemctl start xray-socks5 && echo "已启动";;
        2) systemctl stop xray-socks5 && echo "已停止";;
        3) uninstall_s5;;
        4) update_core;;
        *) echo "已退出。"; exit 0;;
    esac
}

# ================= 主逻辑 =================
if [ ! -f "$SERVICE_FILE" ]; then
    install_s5
else
    check_status
fi
