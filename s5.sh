#!/bin/bash
# 文件名: /usr/local/bin/s5
# 运行: s5
# 功能: Xray SOCKS5 管理面板

SERVICE="xray-socks5"
SERVICE_FILE="/etc/systemd/system/xray-socks5.service"
CONFIG_FILE="/etc/xray-socks5.json"
XRAY_BIN="/usr/local/bin/xray"

# 获取用户名密码
get_credentials(){
    if [[ -f $CONFIG_FILE ]]; then
        USERNAME=$(jq -r '.inbounds[0].settings.accounts[0].user' $CONFIG_FILE)
        PASSWORD=$(jq -r '.inbounds[0].settings.accounts[0].pass' $CONFIG_FILE)
    else
        USERNAME="未生成"
        PASSWORD="未生成"
    fi
}

# 获取 Xray 版本
get_xray_version(){
    if [[ -f $XRAY_BIN ]]; then
        XRAY_VERSION=$($XRAY_BIN version 2>/dev/null | head -n1)
    else
        XRAY_VERSION="未安装"
    fi
}

# 面板
panel(){
    while true; do
        clear
        echo "================ Xray SOCKS5 管理面板 ================"
        get_credentials
        get_xray_version
        STATUS=$(systemctl is-active $SERVICE)
        echo "服务状态 : $STATUS"
        echo "核心版本 : $XRAY_VERSION"
        echo "用户名   : $USERNAME"
        echo "密码     : $PASSWORD"
        echo "-------------------------------------------------------"
        echo "1. 启动服务"
        echo "2. 停止服务"
        echo "3. 卸载服务"
        echo "4. 更新核心"
        echo "5. 退出面板"
        read -rp "请选择操作: " choice
        case $choice in
            1) systemctl start $SERVICE ;;
            2) systemctl stop $SERVICE ;;
            3) 
                systemctl stop $SERVICE
                systemctl disable $SERVICE
                rm -f $SERVICE_FILE $CONFIG_FILE
                echo "已卸载 Xray SOCKS5"
                exit
                ;;
            4)
                echo "正在更新 Xray 核心..."
                bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
                echo "更新完成，重启服务"
                systemctl restart $SERVICE
                sleep 2
                ;;
            5) exit ;;
            *) echo "无效选择" ;;
        esac
        read -rp "按回车继续..." 
    done
}

# 初始化
if [[ ! -f $XRAY_BIN ]]; then
    echo "Xray 未安装，正在安装..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
fi

if [[ ! -f $CONFIG_FILE ]]; then
    echo "未检测到 SOCKS5 配置，正在生成..."
    USERNAME="user$(date +%s%N | sha256sum | head -c 6)"
    PASSWORD=$(date +%s%N | sha256sum | head -c 12)
    cat > $CONFIG_FILE <<EOF
{
  "inbounds": [{
    "port": 1080,
    "protocol": "socks",
    "settings": {
      "auth": "password",
      "accounts": [
        {
          "user": "$USERNAME",
          "pass": "$PASSWORD"
        }
      ]
    }
  }],
  "outbounds": [{
    "protocol": "freedom"
  }]
}
EOF
fi

# 创建 systemd 服务
if [[ ! -f $SERVICE_FILE ]]; then
    cat > $SERVICE_FILE <<EOF
[Unit]
Description=Xray SOCKS5 Service
After=network.target

[Service]
ExecStart=$XRAY_BIN -config $CONFIG_FILE
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now $SERVICE
fi

panel
# 管理面板
management_panel(){
while true; do
    echo "================ Xray SOCKS5 管理面板 ================"
    echo "1. 查看状态"
    echo "2. 查看用户名密码"
    echo "3. 停止服务"
    echo "4. 启动服务"
    echo "5. 卸载服务"
    echo "6. 退出"
    read -rp "请选择操作: " choice
    case $choice in
        1) systemctl status xray-socks5 ;;
        2) echo "用户名: $USERNAME"; echo "密码: $PASSWORD" ;;
        3) systemctl stop xray-socks5 ;;
        4) systemctl start xray-socks5 ;;
        5) 
            systemctl stop xray-socks5
            systemctl disable xray-socks5
            rm -f $SERVICE_FILE /etc/xray-socks5.json
            echo "已卸载 Xray SOCKS5"
            exit
            ;;
        6) exit ;;
        *) echo "无效选择" ;;
    esac
done
}

# 执行安装
install_xray
create_config
create_service
echo "Xray SOCKS5 已安装完成"
management_panel
