#!/bin/bash

# 默认配置
DOWNLOAD_URL="https://raw.githubusercontent.com/bqlpfy/ssr/refs/heads/master/ssserver"
DEFAULT_PASSWORD="Z6dcK1YS0BXW"
DEFAULT_PORT="15370"
BINARY_NAME="ssserver"
INSTALL_DIR="/usr/local/bin"
SERVICE_NAME="ssserver"

echo "=== SSServer 安装脚本 ==="
echo "下载地址: $DOWNLOAD_URL"
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo "错误: 请使用 root 权限运行此脚本"
    echo "使用: sudo $0"
    exit 1
fi

# 检查和开启 TCP Fast Open
echo "检查 TCP Fast Open 状态..."
current_tfo=$(cat /proc/sys/net/ipv4/tcp_fastopen 2>/dev/null || echo "0")
echo "当前 TCP Fast Open 值: $current_tfo"

if [ "$current_tfo" -eq 0 ] || [ "$current_tfo" -eq 1 ]; then
    echo "TCP Fast Open 未完全开启，正在设置..."
    
    # 临时设置 (立即生效)
    echo 3 > /proc/sys/net/ipv4/tcp_fastopen
    
    # 永久设置 (重启后依然生效)
    if ! grep -q "net.ipv4.tcp_fastopen" /etc/sysctl.conf; then
        echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf
    else
        sed -i 's/^net.ipv4.tcp_fastopen.*/net.ipv4.tcp_fastopen = 3/' /etc/sysctl.conf
    fi
    
    echo "TCP Fast Open 已开启 (值设为 3: 客户端和服务端都支持)"
else
    echo "TCP Fast Open 已开启"
fi

echo ""

# 获取用户输入的密码
echo -n "请输入密码 (默认: $DEFAULT_PASSWORD): "
read -r PASSWORD
if [ -z "$PASSWORD" ]; then
    PASSWORD="$DEFAULT_PASSWORD"
fi

# 获取用户输入的端口
echo -n "请输入端口 (默认: $DEFAULT_PORT): "
read -r PORT
if [ -z "$PORT" ]; then
    PORT="$DEFAULT_PORT"
fi

echo ""
echo "配置信息:"
echo "  密码: $PASSWORD"
echo "  端口: $PORT"
echo ""

# 下载文件
echo "正在下载 ssserver..."
if ! curl -L -o "$BINARY_NAME" "$DOWNLOAD_URL"; then
    echo "错误: 下载失败"
    exit 1
fi

echo "下载完成！"

# 给执行权限并安装到系统目录
echo "设置执行权限并安装到系统目录..."
chmod +x "$BINARY_NAME"
cp "$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"

echo "安装完成！"

# 创建 systemd 服务文件
echo "创建系统服务..."
cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=SSServer Service
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
ExecStart=$INSTALL_DIR/$BINARY_NAME -s [::]:$PORT -k $PASSWORD -m chacha20-ietf-poly1305 -U --tcp-fast-open
Restart=always
RestartSec=3
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF

# 重载 systemd 配置
systemctl daemon-reload

# 启用开机自启
systemctl enable "$SERVICE_NAME"

echo "开机自启设置完成！"

# 启动服务
echo "启动 ssserver 服务..."
systemctl start "$SERVICE_NAME"

echo ""
echo "=== 安装完成！ ==="
echo "配置信息:"
echo "  服务名称: $SERVICE_NAME"
echo "  监听地址: 0.0.0.0:$PORT"
echo "  密码: $PASSWORD"
echo "  加密方式: chacha20-ietf-poly1305"
echo "  TCP Fast Open: 已开启"
echo ""
echo "服务管理命令:"
echo "  查看状态: sudo systemctl status $SERVICE_NAME"
echo "  停止服务: sudo systemctl stop $SERVICE_NAME"
echo "  重启服务: sudo systemctl restart $SERVICE_NAME"
echo "  查看日志: sudo journalctl -u $SERVICE_NAME -f"
echo "  禁用开机自启: sudo systemctl disable $SERVICE_NAME"

# 显示服务状态
echo ""
echo "当前服务状态:"
systemctl status "$SERVICE_NAME" --no-pager 