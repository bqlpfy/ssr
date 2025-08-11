#!/bin/bash

# 配置变量
DOWNLOAD_URL="https://raw.githubusercontent.com/bqlpfy/ssr/refs/heads/master/anytls"
DEFAULT_PASSWORD="Z6dcK1YS0BXW"
DEFAULT_PORT="15371"
BINARY_NAME="anytls"
INSTALL_DIR="/usr/local/bin"
SERVICE_NAME="anytls"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要root权限运行"
        print_message "请使用: sudo $0"
        exit 1
    fi
}

# 获取用户输入
get_user_input() {
    print_message "请输入anytls的配置信息（直接回车使用默认值）"
    
    # 获取密码
    read -p "请输入密码 (默认: $DEFAULT_PASSWORD): " PASSWORD
    PASSWORD=${PASSWORD:-$DEFAULT_PASSWORD}
    
    # 获取端口
    read -p "请输入端口 (默认: $DEFAULT_PORT): " PORT
    PORT=${PORT:-$DEFAULT_PORT}
    
    print_message "配置信息:"
    print_message "密码: $PASSWORD"
    print_message "端口: $PORT"
}

# 下载anytls二进制文件
download_anytls() {
    print_message "正在下载anytls..."
    
    if curl -L -o "/tmp/$BINARY_NAME" "$DOWNLOAD_URL"; then
        print_message "下载完成"
    else
        print_error "下载失败"
        exit 1
    fi
}

# 安装anytls
install_anytls() {
    print_message "正在安装anytls..."
    
    # 创建安装目录
    mkdir -p "$INSTALL_DIR"
    
    # 复制二进制文件
    cp "/tmp/$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
    
    # 设置执行权限
    chmod +x "$INSTALL_DIR/$BINARY_NAME"
    
    # 清理临时文件
    rm -f "/tmp/$BINARY_NAME"
    
    print_message "安装完成"
}

# 创建systemd服务文件
create_service() {
    print_message "正在创建systemd服务..."
    
    cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=AnyTLS Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=$INSTALL_DIR/$BINARY_NAME -l [::]:$PORT -p $PASSWORD
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载systemd配置
    systemctl daemon-reload
    
    # 启用服务开机自启
    systemctl enable "$SERVICE_NAME"
    
    print_message "服务创建完成并已启用开机自启"
}

# 启动服务
start_service() {
    print_message "正在启动anytls服务..."
    
    if systemctl start "$SERVICE_NAME"; then
        print_message "服务启动成功"
    else
        print_error "服务启动失败"
        exit 1
    fi
}

# 显示服务状态
show_status() {
    print_message "服务状态:"
    systemctl status "$SERVICE_NAME" --no-pager -l
    
    print_message ""
    print_message "配置信息:"
    print_message "端口: $PORT"
    print_message "密码: $PASSWORD"
    print_message "二进制文件位置: $INSTALL_DIR/$BINARY_NAME"
    print_message "服务名称: $SERVICE_NAME"
    
    print_message ""
    print_message "常用命令:"
    print_message "查看状态: systemctl status $SERVICE_NAME"
    print_message "停止服务: systemctl stop $SERVICE_NAME"
    print_message "重启服务: systemctl restart $SERVICE_NAME"
    print_message "查看日志: journalctl -u $SERVICE_NAME -f"
}

# 主函数
main() {
    print_message "开始安装anytls..."
    
    # 检查root权限
    check_root
    
    # 获取用户输入
    get_user_input
    
    # 下载并安装
    download_anytls
    install_anytls
    
    # 创建并启动服务
    create_service
    start_service
    
    # 显示状态
    show_status
    
    print_message "安装完成！"
}

# 运行主函数
main "$@"