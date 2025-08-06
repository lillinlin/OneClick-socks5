#!/bin/bash

# =========================================================
# SOCKS5 Proxy (Dante) 一键安装脚本
# 支持: Debian, Ubuntu, CentOS, RHEL
# 作者: Gemini
# =========================================================

# --- 配置信息 ---
PORT="65001"
USERNAME="proxyuser"
PASSWORD="123123"

# --- 脚本函数 ---

# 检查是否为 root 用户
check_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "错误：此脚本必须以 root 权限运行！"
    exit 1
  fi
}

# 检测 Linux 发行版并安装 Dante
install_dante() {
  echo "正在检测包管理器并安装 Dante Server..."
  if command -v apt-get &>/dev/null; then
    apt-get update -y
    apt-get install -y dante-server
  elif command -v dnf &>/dev/null; then
    dnf install -y dante-server
  elif command -v yum &>/dev/null; then
    yum install -y dante-server
  else
    echo "错误：未检测到支持的包管理器 (apt, dnf, yum)。"
    exit 1
  fi
  echo "Dante Server 安装完成。"
}

# 创建代理用户并设置密码
create_user() {
  echo "正在创建用于认证的用户: $USERNAME"
  if ! id "$USERNAME" &>/dev/null; then
    # 创建一个不允许登录的系统用户
    useradd --shell /usr/sbin/nologin "$USERNAME"
  fi
  echo "$USERNAME:$PASSWORD" | chpasswd
  echo "用户创建并设置密码完成。"
}

# 配置 Dante
configure_dante() {
  echo "正在配置 Dante..."
  # 获取服务器的主网卡和 IP 地址
  INTERFACE=$(ip -o -4 route show to default | awk '{print $5}')
  SERVER_IP=$(ip -o -4 addr show dev "$INTERFACE" | awk '{print $4}' | cut -d'/' -f1)

  # 备份旧的配置文件
  [ -f /etc/danted.conf ] && mv /etc/danted.conf /etc/danted.conf.bak

  # 写入新的配置文件
  cat > /etc/danted.conf <<EOF
# 日志记录
logoutput: /var/log/danted.log

# 内部网络接口和端口
internal: $INTERFACE port = $PORT

# 外部网络接口
external: $INTERFACE

# 认证方式：使用系统用户进行用户名和密码验证
socksmethod: username

# 运行代理的用户
user.privileged: root
user.unprivileged: nobody

# 客户端访问规则
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error connect disconnect
}

# SOCKS 代理规则
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error connect disconnect
}
EOF
  echo "Dante 配置完成。"
}

# 设置防火墙
configure_firewall() {
  echo "正在配置防火墙..."
  if command -v firewall-cmd &>/dev/null; then
    echo "使用 firewalld 开放端口 $PORT"
    firewall-cmd --permanent --zone=public --add-port=${PORT}/tcp
    firewall-cmd --reload
  elif command -v ufw &>/dev/null; then
    echo "使用 ufw 开放端口 $PORT"
    ufw allow ${PORT}/tcp
    ufw status | grep -q "inactive" && ufw enable # 如果ufw未启用，则启用它
  else
    echo "警告：未检测到 firewalld 或 ufw。请手动开放 TCP 端口 $PORT。"
  fi
}

# 启动并启用服务
start_service() {
  echo "正在启动并设置 Dante 服务开机自启..."
  systemctl restart danted
  systemctl enable danted
  echo "Dante 服务已启动。"
}

# --- 主程序 ---
main() {
  check_root
  install_dante
  create_user
  configure_dante
  configure_firewall
  start_service

  # 获取最终的 IP
  FINAL_IP=$(hostname -I | awk '{print $1}')

  echo ""
  echo "🎉 SOCKS5 代理已成功安装并启动！"
  echo "=============================================="
  echo "  服务器 IP:   $FINAL_IP"
  echo "  端口:        $PORT"
  echo "  用户名:      $USERNAME"
  echo "  密码:        $PASSWORD"
  echo "=============================================="
  echo "🚨 安全警告: 密码 '$PASSWORD' 非常不安全, 强烈建议你立即修改！"
  echo "   你可以通过执行 'passwd $USERNAME' 命令来修改密码。"
  echo ""
}

main
