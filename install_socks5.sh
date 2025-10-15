#!/bin/bash

# =================================================================
# SOCKS5 Proxy (Dante) & Interactive Management Panel
#
# A simple, robust SOCKS5 server installer and manager.
#
# Author: Gemini
# =================================================================

# --- Script Configuration ---
INSTALL_PATH="/usr/local/bin/s5"
CONFIG_FILE="/etc/danted.conf"
LOG_FILE="/var/log/danted.log"
SERVICE_NAME="danted"

# --- Style Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Global Variables ---
DEFAULT_PORT="65000"
DEFAULT_USER="123123"

# --- Core Functions ---

# Function to display the logo
show_logo() {
    echo -e "${BLUE}"
    echo "    ╔════════════════════════════════════════════════╗"
    echo "    ║                                                ║"
    echo "    ║    SOCKS5 (Dante) Server Management Panel      ║"
    echo "    ║                                                ║"
    echo "    ╚════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Check for root privileges
check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        echo -e "${RED}错误：此脚本必须以 root 权限运行！${NC}"
        exit 1
    fi
}

# Install necessary packages
install_packages() {
    echo -e "${YELLOW}正在更新软件包列表...${NC}"
    if command -v apt-get &>/dev/null; then
        apt-get update -y
        echo -e "${YELLOW}正在安装 Dante Server...${NC}"
        apt-get install -y dante-server
    elif command -v dnf &>/dev/null || command -v yum &>/dev/null; then
        if ! rpm -q epel-release &>/dev/null; then
            echo -e "${YELLOW}正在安装 EPEL repository...${NC}"
            yum install -y epel-release || dnf install -y epel-release
        fi
        echo -e "${YELLOW}正在安装 Dante Server...${NC}"
        yum install -y dante-server || dnf install -y dante-server
    else
        echo -e "${RED}错误：未检测到支持的包管理器 (apt, dnf, yum)。${NC}"
        exit 1
    fi

    if ! command -v danted &>/dev/null; then
        echo -e "${RED}错误：Dante Server 安装失败，请检查您的系统软件源。${NC}"
        exit 1
    fi
    echo -e "${GREEN}Dante Server 安装成功。${NC}"
}

# --- Management Functions ---

# Installation process
do_install() {
    check_root
    
    if command -v danted &>/dev/null; then
        echo -e "${YELLOW}Dante Server 似乎已经安装。如果您想重新安装，请先卸载。${NC}"
        return
    fi

    echo "--- 开始安装 SOCKS5 代理 ---"
    
    # Get user input for configuration
    read -rp "请输入代理端口 [默认: ${DEFAULT_PORT}]: " PORT
    PORT=${PORT:-$DEFAULT_PORT}
    
    read -rp "请输入代理用户名 [默认: ${DEFAULT_USER}]: " USERNAME
    USERNAME=${USERNAME:-$DEFAULT_USER}

    # Generate a random password if user leaves it empty
    read -rp "请输入代理密码 [留空则自动生成]: " PASSWORD
    if [ -z "$PASSWORD" ]; then
        PASSWORD=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 12 | head -n 1)
        echo -e "${YELLOW}已为您生成随机密码。${NC}"
    fi

    install_packages

    echo -e "${YELLOW}正在创建用户: ${USERNAME}...${NC}"
    useradd --shell /usr/sbin/nologin "$USERNAME" || true
    echo "$USERNAME:$PASSWORD" | chpasswd
    echo -e "${GREEN}用户创建成功。${NC}"

    echo -e "${YELLOW}正在配置 Dante...${NC}"
    INTERFACE=$(ip -o -4 route show to default | awk '{print $5}')
    if [ -z "$INTERFACE" ]; then
        echo -e "${RED}错误：无法检测到主网络接口。${NC}"
        exit 1
    fi

    [ -f "$CONFIG_FILE" ] && mv "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%s)"

    cat > "$CONFIG_FILE" <<EOF
logoutput: $LOG_FILE
internal: 0.0.0.0 port = $PORT
external: $INTERFACE
socksmethod: username
user.privileged: root
user.unprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error connect disconnect
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    log: error connect disconnect
}
EOF
    echo -e "${GREEN}Dante 配置完成。${NC}"
    
    # Save config for the panel
    echo "PORT=${PORT}" > /etc/s5_config
    echo "USERNAME=${USERNAME}" >> /etc/s5_config
    echo "PASSWORD=${PASSWORD}" >> /etc/s5_config

    do_start

    # Make the script a global command
    cp "$0" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"

    clear
    show_logo
    echo -e "${GREEN}🎉 SOCKS5 代理已成功安装并启动！${NC}"
    echo "=============================================="
    echo -e "  服务器 IP:   ${YELLOW}$(hostname -I | awk '{print $1}')${NC}"
    echo -e "  端口:        ${YELLOW}${PORT}${NC}"
    echo -e "  用户名:      ${YELLOW}${USERNAME}${NC}"
    echo -e "  密码:        ${YELLOW}${PASSWORD}${NC}"
    echo "=============================================="
    echo -e "现在您可以随时通过输入 '${GREEN}s5${NC}' 命令来管理服务。"
    echo ""
}

# Uninstall process
do_uninstall() {
    check_root
    read -rp "$(echo -e ${RED}警告：这将彻底卸载 Dante Server！${NC}) 您确定吗？ [y/N]: " confirmation
    if [[ ! "$confirmation" =~ ^[yY]([eE][sS])?$ ]]; then
        echo "操作已取消。"
        exit 0
    fi
    
    do_stop
    systemctl disable ${SERVICE_NAME} &>/dev/null || true

    echo -e "${YELLOW}正在卸载 Dante Server 软件包...${NC}"
    if command -v apt-get &>/dev/null; then
        apt-get purge -y dante-server
    elif command -v dnf &>/dev/null || command -v yum &>/dev/null; then
        yum remove -y dante-server || dnf remove -y dante-server
    fi

    echo -e "${YELLOW}正在清理配置文件和用户...${NC}"
    rm -f "$CONFIG_FILE" "$LOG_FILE" /etc/s5_config
    USERNAME=$(grep USERNAME /etc/s5_config | cut -d'=' -f2)
    [ -n "$USERNAME" ] && userdel "$USERNAME" &>/dev/null

    # Remove the command itself
    rm -f "$INSTALL_PATH"
    
    echo -e "${GREEN}✅ 卸载完成。${NC}"
}

# Service actions
do_start() {
    echo -e "${YELLOW}正在启动 Dante 服务...${NC}"
    systemctl start ${SERVICE_NAME}
    systemctl enable ${SERVICE_NAME}
    echo -e "${GREEN}服务已启动并设为开机自启。${NC}"
}

do_stop() {
    echo -e "${YELLOW}正在停止 Dante 服务...${NC}"
    systemctl stop ${SERVICE_NAME}
    echo -e "${GREEN}服务已停止。${NC}"
}

do_restart() {
    echo -e "${YELLOW}正在重启 Dante 服务...${NC}"
    systemctl restart ${SERVICE_NAME}
    echo -e "${GREEN}服务已重启。${NC}"
}

view_logs() {
    echo -e "${YELLOW}--- 显示最新的 20 条日志 (按 Ctrl+C 退出) ---${NC}"
    tail -n 20 -f ${LOG_FILE}
}


# --- Interactive Panel ---

# Get current status information for the panel
get_status_info() {
    if ! command -v danted &>/dev/null; then
        STATUS_MSG="${RED}未安装${NC}"
        return
    fi
    
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        STATUS_MSG="${GREEN}运行中${NC}"
        PID=$(systemctl show ${SERVICE_NAME} --property=MainPID --value)
        STATUS_MSG+=" (PID: ${YELLOW}${PID}${NC})"
    else
        STATUS_MSG="${RED}已停止${NC}"
    fi

    # Load config for display
    if [ -f /etc/s5_config ]; then
        source /etc/s5_config
        IP=$(hostname -I | awk '{print $1}')
        CONFIG_INFO="  ${BLUE}IP:${YELLOW} ${IP}  ${BLUE}端口:${YELLOW} ${PORT}  ${BLUE}用户:${YELLOW} ${USERNAME}${NC}"
    else
        CONFIG_INFO="${YELLOW}配置信息丢失，请考虑重装。${NC}"
    fi
}

# Main menu loop
show_menu() {
    while true; do
        clear
        show_logo
        get_status_info
        
        echo "  当前状态: ${STATUS_MSG}"
        echo -e "${CONFIG_INFO}"
        echo "--------------------------------------------------"

        echo "  1. 启动服务"
        echo "  2. 停止服务"
        echo "  3. 重启服务"
        echo "  4. 查看日志"
        echo -e "  ${RED}5. 卸载服务${NC}"
        echo ""
        echo "  0. 退出脚本"
        echo "--------------------------------------------------"

        read -rp "请输入数字 [0-5]: " choice

        case $choice in
            1) do_start; read -rp "按回车键返回..." ;;
            2) do_stop; read -rp "按回车键返回..." ;;
            3) do_restart; read -rp "按回车键返回..." ;;
            4) view_logs ;;
            5) do_uninstall; break ;;
            0) break ;;
            *) echo -e "${RED}无效输入，请重试。${NC}"; sleep 1 ;;
        esac
    done
}


# --- Main Entry Point ---
# This determines what action to take based on the command-line argument
case "$1" in
    install)
        do_install
        ;;
    *)
        if [ "$0" == "$INSTALL_PATH" ] || [ -f "$INSTALL_PATH" ]; then
            check_root
            show_menu
        else
            # If the script is run without arguments and not installed, show help.
            echo "用法: "
            echo "  $0 install  - 首次安装"
            echo "要使用管理面板, 请先完成安装。"
        fi
        ;;
esac
