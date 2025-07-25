#!/bin/bash

# === 脚本标识，用于区分规则来源 ===
SCRIPT_TAG="FORWARD-SCRIPT"

# === 显示菜单 ===
show_menu() {
    echo ""
    echo "========================================="
    echo "        iptables 端口转发管理工具"
    echo "========================================="
    echo "1. 安装端口转发规则"
    echo "2. 清除端口转发规则" 
    echo "3. 查看当前规则"
    echo "4. 退出"
    echo "========================================="
}

# === 检测系统类型 ===
detect_system() {
    if [[ -f /etc/debian_version ]]; then
        echo "debian"
    elif [[ -f /etc/redhat-release ]] || [[ -f /etc/centos-release ]]; then
        echo "redhat"
    else
        echo "unknown"
    fi
}

# === 设置 IP 转发持久化 ===
setup_ip_forward_persistent() {
    echo "[+] 设置 IP 转发持久化..."
    
    # 当前启用 IP 转发
    sysctl -w net.ipv4.ip_forward=1
    
    # 持久化 IP 转发设置
    if ! grep -q "^net.ipv4.ip_forward = 1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
        echo "[✓] IP 转发已持久化到 /etc/sysctl.conf"
    else
        echo "[✓] IP 转发持久化已存在"
    fi
}

# === 安装持久化工具 ===
install_persistence_tools() {
    local system_type=$(detect_system)
    
    echo "[+] 检测系统类型: $system_type"
    echo "[+] 安装 iptables 持久化工具..."
    
    case $system_type in
        "debian")
            # Debian/Ubuntu 系统
            if ! dpkg -l | grep -q iptables-persistent; then
                echo "[+] 安装 iptables-persistent..."
                apt-get update > /dev/null 2>&1
                DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent > /dev/null 2>&1
                if [[ $? -eq 0 ]]; then
                    echo "[✓] iptables-persistent 安装成功"
                else
                    echo "[!] iptables-persistent 安装失败，将使用手动方式"
                    return 1
                fi
            else
                echo "[✓] iptables-persistent 已安装"
            fi
            ;;
        "redhat")
            # CentOS/RHEL 系统
            if ! rpm -q iptables-services > /dev/null 2>&1; then
                echo "[+] 安装 iptables-services..."
                yum install -y iptables-services > /dev/null 2>&1 || dnf install -y iptables-services > /dev/null 2>&1
                if [[ $? -eq 0 ]]; then
                    echo "[✓] iptables-services 安装成功"
                    systemctl enable iptables > /dev/null 2>&1
                else
                    echo "[!] iptables-services 安装失败，将使用手动方式"
                    return 1
                fi
            else
                echo "[✓] iptables-services 已安装"
            fi
            ;;
        *)
            echo "[!] 未识别的系统类型，将使用手动持久化方式"
            return 1
            ;;
    esac
    return 0
}

# === 保存 iptables 规则 ===
save_iptables_rules() {
    local system_type=$(detect_system)
    
    echo "[+] 保存 iptables 规则..."
    
    case $system_type in
        "debian")
            # Debian/Ubuntu 使用 iptables-persistent
            if command -v netfilter-persistent > /dev/null; then
                netfilter-persistent save
                echo "[✓] 规则已通过 netfilter-persistent 保存"
            elif [[ -d /etc/iptables ]]; then
                iptables-save > /etc/iptables/rules.v4
                echo "[✓] 规则已保存到 /etc/iptables/rules.v4"
            else
                manual_save
            fi
            ;;
        "redhat")
            # CentOS/RHEL 使用 iptables-services
            if command -v iptables-save > /dev/null && [[ -d /etc/sysconfig ]]; then
                iptables-save > /etc/sysconfig/iptables
                echo "[✓] 规则已保存到 /etc/sysconfig/iptables"
            else
                manual_save
            fi
            ;;
        *)
            manual_save
            ;;
    esac
}

# === 手动保存规则 ===
manual_save() {
    local backup_dir="/etc/iptables-backup"
    local rules_file="$backup_dir/iptables-rules.sh"
    
    echo "[+] 使用手动方式保存规则..."
    
    # 创建备份目录
    mkdir -p "$backup_dir"
    
    # 生成规则恢复脚本
    cat > "$rules_file" << 'EOF'
#!/bin/bash
# iptables 规则恢复脚本
# 由 iptables.sh 自动生成

# 开启 IP 转发
sysctl -w net.ipv4.ip_forward=1

# 恢复 iptables 规则
EOF
    
    # 添加当前规则到脚本
    iptables-save >> "$rules_file"
    
    # 设置执行权限
    chmod +x "$rules_file"
    
    # 创建 systemd 服务（如果系统支持）
    if command -v systemctl > /dev/null; then
        cat > /etc/systemd/system/iptables-restore-custom.service << EOF
[Unit]
Description=Restore iptables rules
After=network.target

[Service]
Type=oneshot
ExecStart=$rules_file
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        systemctl enable iptables-restore-custom.service > /dev/null 2>&1
        echo "[✓] 规则已保存，并创建了 systemd 服务"
    else
        # 添加到 rc.local（传统方式）
        if [[ -f /etc/rc.local ]]; then
            if ! grep -q "$rules_file" /etc/rc.local; then
                sed -i '/^exit 0/i '$rules_file /etc/rc.local
                echo "[✓] 规则已添加到 /etc/rc.local"
            fi
        else
            echo "[!] 无法自动设置开机启动，请手动运行: $rules_file"
        fi
    fi
    
    echo "[✓] 备份文件保存在: $rules_file"
}

# === 安装端口转发规则 ===
install_rules() {
    echo ""
    echo "[+] 配置端口转发规则"
    echo "==============================="
    
    read -p "目标 IP: " B_IP
    read -p "起始端口: " PORT_START
    read -p "结束端口: " PORT_END

    # 验证输入
    if [[ ! $B_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "错误: IP 地址格式不正确"
        return 1
    fi

    if [[ ! $PORT_START =~ ^[0-9]+$ ]] || [[ ! $PORT_END =~ ^[0-9]+$ ]]; then
        echo "错误: 端口必须是数字"
        return 1
    fi

    if [[ $PORT_START -gt $PORT_END ]]; then
        echo "错误: 起始端口不能大于结束端口"
        return 1
    fi

    echo ""
    echo "配置信息:"
    echo "目标 IP: $B_IP"
    echo "端口范围: $PORT_START-$PORT_END"
    echo ""

    # 设置 IP 转发持久化
    setup_ip_forward_persistent

    echo "[+] 清除之前的规则..."
    iptables-save | grep -v "$SCRIPT_TAG" | iptables-restore

    echo "[+] 添加 NAT 规则..."
    iptables -t nat -A PREROUTING -p tcp --dport $PORT_START:$PORT_END -j DNAT --to-destination $B_IP -m comment --comment "$SCRIPT_TAG"
    iptables -t nat -A POSTROUTING -p tcp -d $B_IP --dport $PORT_START:$PORT_END -j MASQUERADE -m comment --comment "$SCRIPT_TAG"
    iptables -t nat -A PREROUTING -p udp --dport $PORT_START:$PORT_END -j DNAT --to-destination $B_IP -m comment --comment "$SCRIPT_TAG"
    iptables -t nat -A POSTROUTING -p udp -d $B_IP --dport $PORT_START:$PORT_END -j MASQUERADE -m comment --comment "$SCRIPT_TAG"

    echo "[+] 添加 FORWARD 规则..."
    iptables -I FORWARD -p tcp -d $B_IP --dport $PORT_START:$PORT_END -j ACCEPT -m comment --comment "$SCRIPT_TAG"
    iptables -I FORWARD -p udp -d $B_IP --dport $PORT_START:$PORT_END -j ACCEPT -m comment --comment "$SCRIPT_TAG"
    iptables -I FORWARD -p tcp -s $B_IP --sport $PORT_START:$PORT_END -j ACCEPT -m comment --comment "$SCRIPT_TAG"
    iptables -I FORWARD -p udp -s $B_IP --sport $PORT_START:$PORT_END -j ACCEPT -m comment --comment "$SCRIPT_TAG"

    echo ""
    echo "[+] 配置规则持久化..."
    echo "==============================="
    
    # 尝试安装持久化工具
    if install_persistence_tools; then
        # 使用系统的持久化工具保存规则
        save_iptables_rules
    else
        # 使用手动方式保存规则
        manual_save
    fi

    echo ""
    echo "[✓] 端口 $PORT_START 到 $PORT_END 的 TCP + UDP 已成功转发到 $B_IP"
    echo "[✓] 规则安装完成！"
    echo "[✓] 规则已持久化，重启后不会丢失！"
}

# === 清除端口转发规则 ===
clear_rules() {
    echo ""
    echo "[+] 清除端口转发规则"
    echo "==============================="
    
    # 检查是否存在规则
    rule_count=$(iptables-save | grep -c "$SCRIPT_TAG")
    
    if [[ $rule_count -eq 0 ]]; then
        echo "[!] 没有找到由本脚本创建的规则"
        return 0
    fi
    
    echo "[+] 找到 $rule_count 条规则，正在清除..."
    
    # 清除所有带有脚本标识的规则
    iptables-save | grep -v "$SCRIPT_TAG" | iptables-restore
    
    echo "[✓] 已清除所有端口转发规则"
    echo "[✓] 规则清除完成！"
}

# === 查看当前规则 ===
view_rules() {
    echo ""
    echo "[+] 查看当前规则"
    echo "==============================="
    
    echo "当前 NAT 表规则:"
    iptables -t nat -L -n --line-numbers | grep -E "(Chain|$SCRIPT_TAG|^[0-9]+)"
    
    echo ""
    echo "当前 FORWARD 规则:"
    iptables -L FORWARD -n --line-numbers | grep -E "(Chain|$SCRIPT_TAG|^[0-9]+)"
    
    echo ""
    echo "本脚本创建的所有规则:"
    rule_count=$(iptables-save | grep -c "$SCRIPT_TAG")
    if [[ $rule_count -eq 0 ]]; then
        echo "[!] 没有找到由本脚本创建的规则"
    else
        echo "找到 $rule_count 条规则:"
        iptables-save | grep "$SCRIPT_TAG"
    fi
}

# === 主程序 ===
main() {
    # 检查是否为 root 用户
    if [[ $EUID -ne 0 ]]; then
        echo "错误: 此脚本需要 root 权限运行"
        echo "请使用: sudo $0"
        exit 1
    fi
    
    while true; do
        show_menu
        read -p "请选择操作 [1-4]: " choice
        
        case $choice in
            1)
                install_rules
                ;;
            2)
                clear_rules
                ;;
            3)
                view_rules
                ;;
            4)
                echo ""
                echo "[+] 退出程序"
                exit 0
                ;;
            *)
                echo ""
                echo "[!] 无效选择，请输入 1-4"
                ;;
        esac
        
        echo ""
        read -p "按 Enter 键继续..." -r
    done
}

# 运行主程序
main