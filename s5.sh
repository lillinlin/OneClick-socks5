#!/bin/bash

# =================================================================
# SOCKS5 (Dante) - All-in-One Self-Installing Script (v2 - with Source Fix)
#
# Changelog v2:
# - Added intelligent source list checker and fixer for Debian systems.
#
# Author: Gemini
# =================================================================

# --- Script Configuration ---
INSTALL_PATH="/usr/local/bin/s5"
CONFIG_FILE="/etc/danted.conf"
LOG_FILE="/var/log/danted.log"
SERVICE_NAME="danted"
CONFIG_CACHE="/etc/s5_config"

# --- Style Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0;m'

# ================================================================
#                       CORE FUNCTIONS
# ================================================================
show_logo() {
    echo -e "${BLUE}"
    echo "    ╔════════════════════════════════════════════════╗"
    echo "    ║                                                ║"
    echo "    ║    SOCKS5 (Dante) Server Management Panel      ║"
    echo "    ║                                                ║"
    echo "    ╚════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        echo -e "${RED}错误：此脚本必须以 root 权限运行！请使用 sudo 或切换到 root 用户。${NC}"
        exit 1
    fi
}

# NEW: Function to check and fix Debian sources.list
check_and_fix_sources() {
    if [ -f /etc/debian_version ]; then
        # Check if dante-server is available
        apt-get update >/dev/null
        if ! apt-cache pkgnames | grep -q "^dante-server$"; then
            echo -e "${YELLOW}警告：在您的 Debian 系统中找不到 'dante-server' 软件包。${NC}"
            echo "这很可能是因为软件源配置不完整。"
            read -rp "您想让脚本自动尝试修复 '/etc/apt/sources.list' 吗？ (y/n): " choice
            if [[ "$choice" =~ ^[yY]$ ]]; then
                echo -e "${YELLOW}▶ 正在备份并更新软件源...${NC}"
                
                DEBIAN_VERSION_CODENAME=$(cat /etc/os-release | grep "VERSION_CODENAME" | cut -d'=' -f2)
                
                cp /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%s)
                tee /etc/apt/sources.list > /dev/null <<EOF
deb http://deb.debian.org/debian/ ${DEBIAN_VERSION_CODENAME} main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ ${DEBIAN_VERSION_CODENAME} main contrib non-free non-free-firmware

deb http://security.debian.org/debian-security ${DEBIAN_VERSION_CODENAME}-security main contrib non-free non-free-firmware
deb-src http://security.debian.org/debian-security ${DEBIAN_VERSION_CODENAME}-security main contrib non-free non-free-firmware

deb http://deb.debian.org/debian/ ${DEBIAN_VERSION_CODENAME}-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ ${DEBIAN_VERSION_CODENAME}-updates main contrib non-free non-free-firmware
EOF
                echo -e "${GREEN}✔ 软件源已更新为官方源。${NC}"
                echo -e "${YELLOW}▶ 正在刷新软件包列表...${NC}"
                apt-get update
            else
                echo -e "${RED}操作已取消。安装无法继续。${NC}"
                exit 1
            fi
        fi
    fi
}


install_packages() {
    echo -e "${YELLOW}▶ 正在更新软件包列表...${NC}"
    if command -v apt-get &>/dev/null; then
        apt-get update -y
        echo -e "${YELLOW}▶ 正在安装 Dante Server...${NC}"
        apt-get install -y dante-server
    elif command -v dnf &>/dev/null || command -v yum &>/dev/null; then
        if ! rpm -q epel-release &>/dev/null; then
            echo -e "${YELLOW}▶ 正在安装 EPEL repository...${NC}"
            yum install -y epel-release || dnf install -y epel-release
        fi
        echo -e "${YELLOW}▶ 正在安装 Dante Server...${NC}"
        yum install -y dante-server || dnf install -y dante-server
    else
        echo -e "${RED}错误：未检测到支持的包管理器 (apt, dnf, yum)。${NC}"
        exit 1
    fi

    if ! command -v danted &>/dev/null; then
        echo -e "${RED}错误：Dante Server 安装失败，请再次检查您的系统软件源。${NC}"
        exit 1
    fi
    echo -e "${GREEN}✔ Dante Server 安装成功。${NC}"
}


# ================================================================
#                     MANAGEMENT FUNCTIONS
# ================================================================

do_install() {
    check_root
    
    if command -v danted &>/dev/null; then
        echo -e "${YELLOW}Dante Server 似乎已经安装。如果您想重新安装，请先运行 's5' 并选择卸载。${NC}"
        exit 0
    fi

    clear
    show_logo
    echo "--- 欢迎使用 SOCKS5 全自动安装向导 (智能修复版) ---"
    
    # Run the new check function first
    check_and_fix_sources
    
    read -rp "请输入代理端口 [默认: 65000]: " PORT
    PORT=${PORT:-"65000"}
    read -rp "请输入代理用户名 [默认: 123123]: " USERNAME
    USERNAME=${USERNAME:-"123123"}
    read -rp "请输入代理密码 [留空则自动生成12位强密码]: " PASSWORD
    if [ -z "$PASSWORD" ]; then
        PASSWORD=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 12 | head -n 1)
        echo -e "${YELLOW}已为您生成随机密码，请务必记好！${NC}"
    fi

    install_packages

    echo -e "${YELLOW}▶ 正在创建用户: ${USERNAME}...${NC}"
    useradd --shell /usr/sbin/nologin "$USERNAME" 2>/dev/null || echo -e "${YELLOW}用户已存在，仅更新密码。${NC}"
    echo "$USERNAME:$PASSWORD" | chpasswd
    echo -e "${GREEN}✔ 用户配置成功。${NC}"

    echo -e "${YELLOW}▶ 正在配置 Dante...${NC}"
    INTERFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -n 1)
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
client pass { from: 0.0.0.0/0 to: 0.0.0.0/0 log: error connect disconnect }
socks pass { from: 0.0.0.0/0 to: 0.0.0.0/0 command: bind connect udpassociate log: error connect disconnect }
EOF
    echo -e "${GREEN}✔ Dante 配置完成。${NC}"
    
    echo "PORT=${PORT}" > $CONFIG_CACHE
    echo "USERNAME=${USERNAME}" >> $CONFIG_CACHE
    echo "PASSWORD=${PASSWORD}" >> $CONFIG_CACHE

    do_start

    echo -e "${YELLOW}▶ 正在将此脚本安装为 's5' 命令...${NC}"
    cat > "$INSTALL_PATH" < "$0"
    chmod +x "$INSTALL_PATH"
    echo -e "${GREEN}✔ 's5' 命令已安装成功！${NC}"

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

do_uninstall() {
    check_root
    read -rp "$(echo -e ${RED}警告：这将彻底卸载 Dante Server 并删除 's5' 命令！${NC}) 您确定吗？ [y/N]: " confirmation
    if [[ ! "$confirmation" =~ ^[yY]([eE][sS])?$ ]]; then echo "操作已取消。"; exit 0; fi
    do_stop
    systemctl disable ${SERVICE_NAME} &>/dev/null || true
    echo -e "${YELLOW}▶ 正在卸载 Dante Server 软件包...${NC}"
    if command -v apt-get &>/dev/null; then apt-get purge -y dante-server &>/dev/null;
    elif command -v dnf &>/dev/null || command -v yum &>/dev/null; then yum remove -y dante-server &>/dev/null || dnf remove -y dante-server &>/dev/null; fi
    echo -e "${YELLOW}▶ 正在清理配置文件和用户...${NC}"
    USERNAME_TO_DEL=$(grep USERNAME $CONFIG_CACHE 2>/dev/null | cut -d'=' -f2)
    rm -f "$CONFIG_FILE" "$LOG_FILE" "$CONFIG_CACHE"
    [ -n "$USERNAME_TO_DEL" ] && userdel "$USERNAME_TO_DEL" &>/dev/null
    echo -e "${YELLOW}▶ 正在删除 's5' 命令...${NC}"
    rm -f "$INSTALL_PATH"
    echo -e "${GREEN}✅ 卸载完成。${NC}"
}

do_start() { systemctl restart ${SERVICE_NAME}; systemctl enable ${SERVICE_NAME} &>/dev/null; }
do_stop() { systemctl stop ${SERVICE_NAME}; }
do_restart() { systemctl restart ${SERVICE_NAME}; }
view_logs() { echo -e "${YELLOW}--- 按 Ctrl+C 退出日志查看 ---${NC}"; sleep 1; tail -n 50 -f ${LOG_FILE}; }

get_status_info() {
    if ! command -v danted &>/dev/null; then STATUS_MSG="${RED}未安装${NC}"; return; fi
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        STATUS_MSG="${GREEN}运行中${NC}"
        PID=$(systemctl show ${SERVICE_NAME} --property=MainPID --value)
        STATUS_MSG+=" (PID: ${YELLOW}${PID}${NC})"
    else STATUS_MSG="${RED}已停止${NC}"; fi
    if [ -f $CONFIG_CACHE ]; then
        source $CONFIG_CACHE
        IP=$(hostname -I | awk '{print $1}')
        CONFIG_INFO="  ${BLUE}IP:${YELLOW} ${IP}  ${BLUE}端口:${YELLOW} ${PORT}  ${BLUE}用户:${YELLOW} ${USERNAME}${NC}"
    fi
}

show_menu() {
    check_root
    while true; do
        clear; show_logo; get_status_info
        echo "  当前状态: ${STATUS_MSG}"; echo -e "${CONFIG_INFO}"
        echo "--------------------------------------------------"
        echo "  1. 启动服务         2. 停止服务         3. 重启服务"
        echo "  4. 查看日志"; echo -e "  ${RED}5. 卸载服务${NC}"; echo "  0. 退出脚本"
        echo "--------------------------------------------------"
        read -rp "请输入数字 [0-5]: " choice
        case $choice in
            1) do_start; echo -e "${GREEN}✔ 服务已启动${NC}"; sleep 1 ;;
            2) do_stop; echo -e "${GREEN}✔ 服务已停止${NC}"; sleep 1 ;;
            3) do_restart; echo -e "${GREEN}✔ 服务已重启${NC}"; sleep 1 ;;
            4) view_logs ;;
            5) do_uninstall; break ;;
            0) break ;;
            *) echo -e "${RED}无效输入...${NC}"; sleep 1 ;;
        esac
    done
}


# ================================================================
#                       SCRIPT ENTRY POINT
# ================================================================
if [ ! -f "$INSTALL_PATH" ]; then
    do_install
else
    show_menu
fi

