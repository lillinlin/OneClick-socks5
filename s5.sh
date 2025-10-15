#!/bin/bash

# --------------------------
# 一键生成 Xray SOCKS5 脚本
# --------------------------

XRAY_DIR="/usr/local/bin"
SERVICE_FILE="/etc/systemd/system/xray-socks5.service"

# 生成随机用户名密码
USERNAME="user$(date +%s%N | sha256sum | head -c 6)"
PASSWORD=$(date +%s%N | sha256sum | head -c 12)

# 下载 Xray 核心
install_xray(){
    echo "正在下载并安装 Xray..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
}

# 创建 Xray 配置
create_config(){
cat > /etc/xray-socks5.json <<EOF
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
}

# 创建 systemd 服务
create_service(){
cat > $SERVICE_FILE <<EOF
[Unit]
Description=Xray SOCKS5 Service
After=network.target

[Service]
ExecStart=$XRAY_DIR/xray -config /etc/xray-socks5.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now xray-socks5
}

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
