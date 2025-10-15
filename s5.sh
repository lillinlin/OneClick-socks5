#!/bin/bash

# =================================================================
# Sing-box Core SOCKS5 Server - Ultimate All-in-One Script (v3.2)
#
# v3.2 Changelog:
# - Changed install/update method to direct binary download from GitHub Releases.
#   This bypasses the install.sh script to increase success rate on flaky networks.
#
# Author: Gemini
# =================================================================

# --- Script Configuration ---
CMD_PATH="/usr/local/bin/s5"
SINGBOX_PATH="/usr/local/bin/sing-box"
CONFIG_DIR="/usr/local/etc/sing-box"
CONFIG_FILE="${CONFIG_DIR}/config.json"
SERVICE_NAME="sing-box"
CONFIG_CACHE="/etc/singbox_s5_config"
# This script is now only used for UNINSTALL to ensure clean removal of the service file.
UNINSTALLER_URL="https://raw.githubusercontent.com/SagerNet/sing-box/main/install.sh"

# --- Style Definitions ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# --- Core Functions ---
check_root() { if [[ "$(id -u)" -ne 0 ]]; then echo -e "${RED}错误：此脚本必须以 root 权限运行！${NC}"; exit 1; fi; }

# This new function performs a direct binary download and sets up the service.
install_singbox_binary() {
    local target_version="$1"
    if [[ -z "$target_version" ]]; then
        echo -e "${YELLOW}▶ 正在获取最新正式版版本号...${NC}"
        JSDELIVR_DATA=$(curl -s --connect-timeout 5 "https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box")
        target_version=$(echo "$JSDELIVR_DATA" | grep -Eo '"[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' | sort -V | tail -n 1)
        if [[ -z "$target_version" ]]; then echo -e "${RED}获取最新版本号失败！请检查网络。${NC}"; return 1; fi
    fi
    echo -e "${YELLOW}▶ 目标版本: v${target_version}${NC}"

    local cpu_arch; case $(uname -m) in
        armv7l) cpu_arch=armv7;; aarch64) cpu_arch=arm64;; x86_64) cpu_arch=amd64;;
        *) echo -e "${RED}不支持的CPU架构: $(uname -m)${NC}"; return 1 ;;
    esac
    
    local file_name="sing-box-${target_version}-linux-${cpu_arch}"
    local download_url="https://github.com/SagerNet/sing-box/releases/download/v${target_version}/${file_name}.tar.gz"
    
    echo "下载地址: $download_url"
    
    cd /tmp
    wget -q --show-progress -O "${file_name}.tar.gz" "$download_url"
    if [ $? -ne 0 ]; then echo -e "${RED}下载核心失败！请检查网络。${NC}"; rm -f "${file_name}.tar.gz"; return 1; fi
    
    tar xzf "${file_name}.tar.gz"; if [ $? -ne 0 ]; then echo -e "${RED}解压失败！${NC}"; rm -rf "$file_name" "${file_name}.tar.gz"; return 1; fi
    
    echo -e "${YELLOW}▶ 正在安装核心文件...${NC}"
    mv -f "${file_name}/sing-box" "$SINGBOX_PATH"; chmod +x "$SINGBOX_PATH"
    
    echo -e "${YELLOW}▶ 正在创建 systemd 服务...${NC}"
    cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box service
After=network.target
[Service]
ExecStart=${SINGBOX_PATH} run -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload

    echo -e "${YELLOW}▶ 清理临时文件...${NC}"; rm -rf "$file_name" "${file_name}.tar.gz"
    
    if ! command -v sing-box &>/dev/null; then echo -e "${RED}Sing-box 核心安装失败。${NC}"; return 1; fi
    return 0
}

# --- Management Functions ---
do_install() {
    # ... (Rest of the script remains mostly the same, just calling install_singbox_binary instead of the old function)
    check_root
    if [ -f "$SINGBOX_PATH" ] && [ -f "$CMD_PATH" ]; then echo -e "${YELLOW}服务已安装...${NC}"; exit 0; fi
    clear
    echo -e "${BLUE}--- 欢迎使用 Sing-box SOCKS5 终极安装向导 (v3.2) ---${NC}"
    
    read -rp "请输入代理端口 [默认: 65000]: " PORT; PORT=${PORT:-"65000"}
    read -rp "请输入代理用户名 [默认: 123123]: " USERNAME; USERNAME=${USERNAME:-"123123"}
    read -rp "请输入代理密码 [留空则自动生成12位强密码]: " PASSWORD
    if [ -z "$PASSWORD" ]; then
        PASSWORD=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 12 | head -n 1)
        echo -e "${YELLOW}已为您生成随机密码，请务必记好！${NC}"
    fi
    
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<EOF
{
  "log": { "level": "warn", "timestamp": true },
  "inbounds": [ { "type": "socks", "tag": "socks-in", "listen": "::", "listen_port": ${PORT}, "users": [ { "username": "${USERNAME}", "password": "${PASSWORD}" } ] } ],
  "outbounds": [ { "type": "direct", "tag": "direct" } ]
}
EOF
    echo -e "${GREEN}✔ 配置文件创建成功。${NC}"

    if ! install_singbox_binary; then
        echo -e "${RED}安装失败，正在回滚...${NC}"
        rm -rf "$CONFIG_DIR" "$CONFIG_CACHE"
        exit 1
    fi
    
    echo "PORT=${PORT}" > $CONFIG_CACHE; echo "USERNAME=${USERNAME}" >> $CONFIG_CACHE; echo "PASSWORD=${PASSWORD}" >> $CONFIG_CACHE
    do_start
    
    echo -e "${YELLOW}▶ 正在将此脚本安装为 's5' 命令...${NC}"
    cat > "$CMD_PATH" < "$0"; chmod +x "$CMD_PATH"
    [ -f "/usr/local/bin/sb-s5" ] && rm -f "/usr/local/bin/sb-s5"
    echo -e "${GREEN}✔ 's5' 命令已安装成功！${NC}"

    clear
    # ... (Success message)
    echo -e "${GREEN}🎉 Sing-box SOCKS5 代理已成功安装并启动！${NC}"
    echo "=============================================="
    echo -e "  服务器 IP:   ${YELLOW}$(hostname -I | awk '{print $1}')${NC}"
    echo -e "  端口:        ${YELLOW}${PORT}${NC}"
    echo -e "  用户名:      ${YELLOW}${USERNAME}${NC}"
    echo -e "  密码:        ${YELLOW}${PASSWORD}${NC}"
    echo "=============================================="
    echo -e "现在您可以随时通过输入 '${GREEN}s5${NC}' 命令来管理服务。"
}

do_uninstall() {
    check_root
    read -rp "$(echo -e ${RED}警告：这将卸载 Sing-box 核心并删除所有相关文件！${NC}) 您确定吗？ [y/N]: " confirmation
    if [[ ! "$confirmation" =~ ^[yY]$ ]]; then echo "操作已取消。"; exit 0; fi
    
    systemctl stop ${SERVICE_NAME} &>/dev/null
    systemctl disable ${SERVICE_NAME} &>/dev/null
    rm -f /etc/systemd/system/sing-box.service
    rm -f "$SINGBOX_PATH"
    rm -rf "$CONFIG_DIR" "$CONFIG_CACHE" "$CMD_PATH" "/usr/local/bin/sb-s5"
    echo -e "${GREEN}✅ Sing-box 及相关组件卸载完成。${NC}"
}

do_update() {
    get_status_info quiet
    if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then echo -e "\n${GREEN}已经是最新版！${NC}"; sleep 2; return; fi
    read -rp "发现新版本 ${LATEST_VERSION}，是否更新? (y/n): " choice
    if [[ ! "$choice" =~ ^[yY]$ ]]; then echo "操作已取消。"; return; fi
    if install_singbox_binary "$LATEST_VERSION"; then
        echo -e "${GREEN}✔ 核心更新完成！正在重启服务...${NC}"; do_restart
        read -rp "按回车键返回..."
    else
        echo -e "${RED}更新失败！${NC}"; read -rp "按回车键返回..."
    fi
}

# --- (Other functions like do_start, get_status_info, show_menu remain largely the same, but adapted for the new structure) ---
do_start() { systemctl restart ${SERVICE_NAME}; systemctl enable ${SERVICE_NAME} &>/dev/null; }
do_stop() { systemctl stop ${SERVICE_NAME}; }
do_restart() { systemctl restart ${SERVICE_NAME}; }
view_logs() { journalctl -u ${SERVICE_NAME} -f --no-pager; }

get_status_info() {
    if ! command -v sing-box &>/dev/null; then STATUS_MSG="${RED}未安装${NC}"; return; fi
    CURRENT_VERSION=$($SINGBOX_PATH version 2>/dev/null | head -n 1 | awk '{print $2}')
    if [[ "$1" != "quiet" ]]; then
        JSDELIVR_DATA=$(curl -s --connect-timeout 3 "https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box")
        LATEST_VERSION=$(echo "$JSDELIVR_DATA" | grep -Eo '"[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' | sort -V | tail -n 1)
        UPDATE_INFO=""
        if [[ -n "$LATEST_VERSION" && "$CURRENT_VERSION" != "$LATEST_VERSION" ]]; then
            UPDATE_INFO="${GREEN}(可更新至: ${LATEST_VERSION})${NC}"
        fi
        if systemctl is-active --quiet ${SERVICE_NAME}; then
            STATUS_MSG="${GREEN}运行中${NC}"; PID=$(systemctl show ${SERVICE_NAME} --property=MainPID --value); STATUS_MSG+=" (PID: ${YELLOW}${PID}${NC})"
        else STATUS_MSG="${RED}已停止${NC}"; fi
        if [ -f $CONFIG_CACHE ]; then
            source $CONFIG_CACHE
            IP=$(hostname -I | awk '{print $1}')
            CONFIG_INFO="  ${BLUE}IP:${YELLOW} ${IP}  ${BLUE}端口:${YELLOW} ${PORT}  ${BLUE}用户:${YELLOW} ${USERNAME}${NC}"
        fi
    fi
}

show_menu() {
    check_root
    while true; do
        clear; echo -e "${BLUE}    ╔════════════════════════════════════════════════╗\n    ║     Sing-box SOCKS5 Server Management Panel      ║\n    ╚════════════════════════════════════════════════╝${NC}"; get_status_info
        echo -e "\n  当前状态: ${STATUS_MSG}"
        echo -e "  核心版本: ${YELLOW}${CURRENT_VERSION}${NC} ${UPDATE_INFO}"
        echo -e "${CONFIG_INFO}"
        echo -e "--------------------------------------------------"
        echo -e "  1. 启动服务         2. 停止服务         3. 重启服务"
        echo -e "  4. 查看日志         ${YELLOW}6. 更新核心${NC}"
        echo -e "  ${RED}5. 卸载服务${NC}"
        echo -e "  0. 退出脚本"
        echo -e "--------------------------------------------------"
        read -rp "请输入数字 [0-6]: " choice
        case $choice in
            1) do_start; echo -e "${GREEN}✔ 服务已启动${NC}"; sleep 1 ;;
            2) do_stop; echo -e "${GREEN}✔ 服务已停止${NC}"; sleep 1 ;;
            3) do_restart; echo -e "${GREEN}✔ 服务已重启${NC}"; sleep 1 ;;
            4) view_logs ;;
            5) do_uninstall; break ;;
            6) do_update ;;
            0) break ;;
            *) echo -e "${RED}无效输入...${NC}"; sleep 1 ;;
        esac
    done
}

# --- Script Entry Point ---
if [[ "$(readlink -f "$0")" == "$CMD_PATH" ]]; then
    show_menu
else
    do_install
fi    fi
    
    install_singbox
    
    echo -e "${YELLOW}▶ 正在生成 Sing-box 配置文件...${NC}"
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<EOF
{
  "log": { "level": "warn", "timestamp": true },
  "inbounds": [ { "type": "socks", "tag": "socks-in", "listen": "::", "listen_port": ${PORT}, "users": [ { "username": "${USERNAME}", "password": "${PASSWORD}" } ] } ],
  "outbounds": [ { "type": "direct", "tag": "direct" } ]
}
EOF
    echo -e "${GREEN}✔ 配置文件创建成功。${NC}"

    echo "PORT=${PORT}" > $CONFIG_CACHE; echo "USERNAME=${USERNAME}" >> $CONFIG_CACHE; echo "PASSWORD=${PASSWORD}" >> $CONFIG_CACHE
    
    do_start
    
    echo -e "${YELLOW}▶ 正在将此脚本安装为 's5' 命令...${NC}"
    cat > "$CMD_PATH" < "$0"; chmod +x "$CMD_PATH"
    [ -f "$OLD_CMD_PATH" ] && rm -f "$OLD_CMD_PATH"
    echo -e "${GREEN}✔ 's5' 命令已安装成功！${NC}"

    clear
    echo -e "${GREEN}🎉 Sing-box SOCKS5 代理已成功安装并启动！${NC}"
    echo "=============================================="
    echo -e "  服务器 IP:   ${YELLOW}$(hostname -I | awk '{print $1}')${NC}"
    echo -e "  端口:        ${YELLOW}${PORT}${NC}"
    echo -e "  用户名:      ${YELLOW}${USERNAME}${NC}"
    echo -e "  密码:        ${YELLOW}${PASSWORD}${NC}"
    echo "=============================================="
    echo -e "现在您可以随时通过输入 '${GREEN}s5${NC}' 命令来管理服务。"
}

do_uninstall() {
    check_root
    read -rp "$(echo -e ${RED}警告：这将卸载 Sing-box 核心并删除所有相关文件！${NC}) 您确定吗？ [y/N]: " confirmation
    if [[ ! "$confirmation" =~ ^[yY]$ ]]; then echo "操作已取消。"; exit 0; fi
    
    bash -c "$(wget -qO- $INSTALLER_URL || curl -fsSL $INSTALLER_URL)" uninstall
    rm -rf "$CONFIG_DIR" "$CONFIG_CACHE" "$CMD_PATH" "$OLD_CMD_PATH"
    echo -e "${GREEN}✅ Sing-box 及相关组件卸载完成。${NC}"
}

do_update() {
    echo -e "${YELLOW}▶ 正在检查并更新 Sing-box 核心，请稍候...${NC}"
    install_singbox
    echo -e "${GREEN}✔ 核心更新完成！正在重启服务...${NC}"
    do_restart
}

do_start() { systemctl restart ${SERVICE_NAME}; systemctl enable ${SERVICE_NAME} &>/dev/null; }
do_stop() { systemctl stop ${SERVICE_NAME}; }
do_restart() { systemctl restart ${SERVICE_NAME}; }
view_logs() { journalctl -u ${SERVICE_NAME} -f --no-pager; }

get_status_info() {
    if ! command -v sing-box &>/dev/null; then STATUS_MSG="${RED}未安装${NC}"; return; fi
    CURRENT_VERSION=$($SINGBOX_PATH version | head -n 1 | awk '{print $2}')
    LATEST_VERSION_JSON=$(curl -s --connect-timeout 2 "https://api.github.com/repos/SagerNet/sing-box/releases/latest")
    LATEST_VERSION=$(echo "$LATEST_VERSION_JSON" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    UPDATE_INFO=""
    if [[ -n "$LATEST_VERSION" && "$CURRENT_VERSION" != "$LATEST_VERSION" ]]; then
        UPDATE_INFO="${GREEN}(可更新至: ${LATEST_VERSION})${NC}"
    fi
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        STATUS_MSG="${GREEN}运行中${NC}"; PID=$(systemctl show ${SERVICE_NAME} --property=MainPID --value); STATUS_MSG+=" (PID: ${YELLOW}${PID}${NC})"
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
        clear; echo -e "${BLUE}    ╔════════════════════════════════════════════════╗\n    ║     Sing-box SOCKS5 Server Management Panel      ║\n    ╚════════════════════════════════════════════════╝${NC}"; get_status_info
        echo -e "\n  当前状态: ${STATUS_MSG}"
        echo -e "  核心版本: ${YELLOW}${CURRENT_VERSION}${NC} ${UPDATE_INFO}"
        echo -e "${CONFIG_INFO}"
        echo "--------------------------------------------------"
        echo "  1. 启动服务         2. 停止服务         3. 重启服务"
        echo "  4. 查看日志         ${YELLOW}6. 更新核心${NC}"
        echo -e "  ${RED}5. 卸载服务${NC}"
        echo "  0. 退出脚本"
        echo "--------------------------------------------------"
        read -rp "请输入数字 [0-6]: " choice
        case $choice in
            1) do_start; echo -e "${GREEN}✔ 服务已启动${NC}"; sleep 1 ;;
            2) do_stop; echo -e "${GREEN}✔ 服务已停止${NC}"; sleep 1 ;;
            3) do_restart; echo -e "${GREEN}✔ 服务已重启${NC}"; sleep 1 ;;
            4) view_logs ;;
            5) do_uninstall; break ;;
            6) do_update; read -rp "按回车键返回..." ;;
            0) break ;;
            *) echo -e "${RED}无效输入...${NC}"; sleep 1 ;;
        esac
    done
}

# --- Script Entry Point ---
if [[ "$(readlink -f "$0")" == "$CMD_PATH" || ( -f "$OLD_CMD_PATH" && "$(readlink -f "$0")" == "$OLD_CMD_PATH" ) ]]; then
    show_menu
else
    do_install
fi        echo -e "${YELLOW}已为您生成随机密码，请务必记好！${NC}"
    fi
    
    install_singbox_service
    
    echo -e "${YELLOW}▶ 正在生成 Sing-box 配置文件...${NC}"
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<EOF
{
  "log": { "level": "warn", "timestamp": true },
  "inbounds": [ { "type": "socks", "tag": "socks-in", "listen": "::", "listen_port": ${PORT}, "users": [ { "username": "${USERNAME}", "password": "${PASSWORD}" } ] } ],
  "outbounds": [ { "type": "direct", "tag": "direct" } ]
}
EOF
    echo -e "${GREEN}✔ 配置文件创建成功。${NC}"

    echo "PORT=${PORT}" > $CONFIG_CACHE; echo "USERNAME=${USERNAME}" >> $CONFIG_CACHE; echo "PASSWORD=${PASSWORD}" >> $CONFIG_CACHE
    
    do_start
    
    echo -e "${YELLOW}▶ 正在将此脚本安装为 's5' 命令...${NC}"
    cat > "$CMD_PATH" < "$0"; chmod +x "$CMD_PATH"
    [ -f "$OLD_CMD_PATH" ] && rm -f "$OLD_CMD_PATH"
    echo -e "${GREEN}✔ 's5' 命令已安装成功！${NC}"

    clear
    echo -e "${GREEN}🎉 Sing-box SOCKS5 代理已成功安装并启动！${NC}"
    echo "=============================================="
    echo -e "  服务器 IP:   ${YELLOW}$(hostname -I | awk '{print $1}')${NC}"
    echo -e "  端口:        ${YELLOW}${PORT}${NC}"
    echo -e "  用户名:      ${YELLOW}${USERNAME}${NC}"
    echo -e "  密码:        ${YELLOW}${PASSWORD}${NC}"
    echo "=============================================="
    echo -e "现在您可以随时通过输入 '${GREEN}s5${NC}' 命令来管理服务。"
}

do_uninstall() {
    check_root
    read -rp "$(echo -e ${RED}警告：这将卸载 Sing-box 核心并删除所有相关文件！${NC}) 您确定吗？ [y/N]: " confirmation
    if [[ ! "$confirmation" =~ ^[yY]$ ]]; then echo "操作已取消。"; exit 0; fi
    
    bash -c "$(wget -qO- $INSTALLER_URL || curl -fsSL $INSTALLER_URL)" uninstall
    rm -rf "$CONFIG_DIR" "$CONFIG_CACHE" "$CMD_PATH" "$OLD_CMD_PATH"
    echo -e "${GREEN}✅ Sing-box 及相关组件卸载完成。${NC}"
}

do_update() {
    get_status_info quiet # Refresh version info without printing
    
    if [[ -z "$LATEST_VERSION" ]]; then
        echo -e "${RED}无法获取最新版本信息，请检查网络！${NC}"; sleep 2; return;
    fi
    
    if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
        echo -e "\n${GREEN}您当前的版本已经是最新正式版 (${CURRENT_VERSION})！无需更新。${NC}"; sleep 2; return;
    fi

    echo -e "\n当前版本: ${YELLOW}${CURRENT_VERSION}${NC}"
    echo -e "最新正式版: ${GREEN}${LATEST_VERSION}${NC}"
    read -rp "是否要更新到最新正式版？ (y/n): " choice
    if [[ ! "$choice" =~ ^[yY]$ ]]; then echo "操作已取消。"; return; fi

    echo -e "${YELLOW}▶ 准备更新核心至版本: v${LATEST_VERSION}${NC}"
    
    local cpu_arch; case $(uname -m) in
        armv7l) cpu_arch=armv7;; aarch64) cpu_arch=arm64;; x86_64) cpu_arch=amd64;;
        *) echo -e "${RED}不支持的CPU架构: $(uname -m)${NC}"; return ;;
    esac
    
    local file_name="sing-box-${LATEST_VERSION}-linux-${cpu_arch}"
    local download_url="https://github.com/SagerNet/sing-box/releases/download/v${LATEST_VERSION}/${file_name}.tar.gz"
    
    echo "下载地址: $download_url"
    
    cd /tmp
    wget -q --show-progress -O "${file_name}.tar.gz" "$download_url"
    if [ $? -ne 0 ]; then echo -e "${RED}下载失败！${NC}"; rm -f "${file_name}.tar.gz"; return; fi
    
    tar xzf "${file_name}.tar.gz"; if [ $? -ne 0 ]; then echo -e "${RED}解压失败！${NC}"; rm -rf "$file_name" "${file_name}.tar.gz"; return; fi
    
    echo -e "${YELLOW}▶ 正在替换核心文件...${NC}"
    mv -f "${file_name}/sing-box" "$SINGBOX_PATH"; chmod +x "$SINGBOX_PATH"
    
    echo -e "${YELLOW}▶ 清理临时文件...${NC}"; rm -rf "$file_name" "${file_name}.tar.gz"
    
    echo -e "${GREEN}✔ 核心更新完成！正在重启服务...${NC}"; do_restart
    
    CURRENT_VERSION=$($SINGBOX_PATH version | head -n 1 | awk '{print $2}')
    echo -e "${GREEN}当前新版本为: ${CURRENT_VERSION}${NC}"
}

do_start() { systemctl restart ${SERVICE_NAME}; systemctl enable ${SERVICE_NAME} &>/dev/null; }
do_stop() { systemctl stop ${SERVICE_NAME}; }
do_restart() { systemctl restart ${SERVICE_NAME}; }
view_logs() { journalctl -u ${SERVICE_NAME} -f --no-pager; }

get_status_info() {
    if ! command -v sing-box &>/dev/null; then STATUS_MSG="${RED}未安装${NC}"; return; fi
    
    CURRENT_VERSION=$($SINGBOX_PATH version 2>/dev/null | head -n 1 | awk '{print $2}')
    
    JSDELIVR_DATA=$(curl -s --connect-timeout 3 "https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box")
    # Robustly find the latest stable version by sorting
    LATEST_VERSION=$(echo "$JSDELIVR_DATA" | grep -Eo '"[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' | sort -V | tail -n 1)

    if [[ "$1" != "quiet" ]]; then
        UPDATE_INFO=""
        if [[ -n "$LATEST_VERSION" && "$CURRENT_VERSION" != "$LATEST_VERSION" ]]; then
            UPDATE_INFO="${GREEN}(可更新至: ${LATEST_VERSION})${NC}"
        fi
        if systemctl is-active --quiet ${SERVICE_NAME}; then
            STATUS_MSG="${GREEN}运行中${NC}"; PID=$(systemctl show ${SERVICE_NAME} --property=MainPID --value); STATUS_MSG+=" (PID: ${YELLOW}${PID}${NC})"
        else STATUS_MSG="${RED}已停止${NC}"; fi
        if [ -f $CONFIG_CACHE ]; then
            source $CONFIG_CACHE
            IP=$(hostname -I | awk '{print $1}')
            CONFIG_INFO="  ${BLUE}IP:${YELLOW} ${IP}  ${BLUE}端口:${YELLOW} ${PORT}  ${BLUE}用户:${YELLOW} ${USERNAME}${NC}"
        fi
    fi
}

show_menu() {
    check_root
    while true; do
        clear; echo -e "${BLUE}    ╔════════════════════════════════════════════════╗\n    ║     Sing-box SOCKS5 Server Management Panel      ║\n    ╚════════════════════════════════════════════════╝${NC}"; get_status_info
        echo -e "\n  当前状态: ${STATUS_MSG}"
        echo -e "  核心版本: ${YELLOW}${CURRENT_VERSION}${NC} ${UPDATE_INFO}"
        echo -e "  最新正式版: ${GREEN}${LATEST_VERSION}${NC}"
        echo -e "${CONFIG_INFO}"
        echo -e "--------------------------------------------------"
        echo -e "  1. 启动服务         2. 停止服务         3. 重启服务"
        echo -e "  4. 查看日志         ${YELLOW}6. 更新核心${NC}"
        echo -e "  ${RED}5. 卸载服务${NC}"
        echo -e "  0. 退出脚本"
        echo -e "--------------------------------------------------"
        read -rp "请输入数字 [0-6]: " choice
        case $choice in
            1) do_start; echo -e "${GREEN}✔ 服务已启动${NC}"; sleep 1 ;;
            2) do_stop; echo -e "${GREEN}✔ 服务已停止${NC}"; sleep 1 ;;
            3) do_restart; echo -e "${GREEN}✔ 服务已重启${NC}"; sleep 1 ;;
            4) view_logs ;;
            5) do_uninstall; break ;;
            6) do_update; read -rp "按回车键返回..." ;;
            0) break ;;
            *) echo -e "${RED}无效输入...${NC}"; sleep 1 ;;
        esac
    done
}

# --- Script Entry Point ---
if [[ "$(readlink -f "$0")" == "$CMD_PATH" || ( -f "$OLD_CMD_PATH" && "$(readlink -f "$0")" == "$OLD_CMD_PATH" ) ]]; then
    show_menu
else
    do_install
fi
