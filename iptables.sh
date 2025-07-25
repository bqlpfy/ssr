#!/bin/bash

# === 交互式配置 ===
echo "请输入目标 IP 地址:"
read -p "目标 IP: " B_IP

echo "请输入端口范围:"
read -p "起始端口: " PORT_START
read -p "结束端口: " PORT_END

# 验证输入
if [[ ! $B_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo "错误: IP 地址格式不正确"
    exit 1
fi

if [[ ! $PORT_START =~ ^[0-9]+$ ]] || [[ ! $PORT_END =~ ^[0-9]+$ ]]; then
    echo "错误: 端口必须是数字"
    exit 1
fi

if [[ $PORT_START -gt $PORT_END ]]; then
    echo "错误: 起始端口不能大于结束端口"
    exit 1
fi

echo "配置信息:"
echo "目标 IP: $B_IP"
echo "端口范围: $PORT_START-$PORT_END"
echo ""

echo "[+] 开启 IP 转发..."
sysctl -w net.ipv4.ip_forward=1

echo "[+] 清除旧的 nat 规则（可选）"
iptables -t nat -D PREROUTING -p tcp --dport $PORT_START:$PORT_END -j DNAT --to-destination $B_IP 2>/dev/null
iptables -t nat -D PREROUTING -p udp --dport $PORT_START:$PORT_END -j DNAT --to-destination $B_IP 2>/dev/null
iptables -t nat -D POSTROUTING -p tcp -d $B_IP --dport $PORT_START:$PORT_END -j MASQUERADE 2>/dev/null
iptables -t nat -D POSTROUTING -p udp -d $B_IP --dport $PORT_START:$PORT_END -j MASQUERADE 2>/dev/null

echo "[+] 添加 NAT 转发规则..."
iptables -t nat -A PREROUTING -p tcp --dport $PORT_START:$PORT_END -j DNAT --to-destination $B_IP
iptables -t nat -A POSTROUTING -p tcp -d $B_IP --dport $PORT_START:$PORT_END -j MASQUERADE
iptables -t nat -A PREROUTING -p udp --dport $PORT_START:$PORT_END -j DNAT --to-destination $B_IP
iptables -t nat -A POSTROUTING -p udp -d $B_IP --dport $PORT_START:$PORT_END -j MASQUERADE

echo "[+] 清除旧的 FORWARD 规则（可选）"
iptables -D FORWARD -p tcp -d $B_IP --dport $PORT_START:$PORT_END -j ACCEPT 2>/dev/null
iptables -D FORWARD -p udp -d $B_IP --dport $PORT_START:$PORT_END -j ACCEPT 2>/dev/null
iptables -D FORWARD -p tcp -s $B_IP --sport $PORT_START:$PORT_END -j ACCEPT 2>/dev/null
iptables -D FORWARD -p udp -s $B_IP --sport $PORT_START:$PORT_END -j ACCEPT 2>/dev/null

echo "[+] 添加 FORWARD 放行规则..."
iptables -I FORWARD -p tcp -d $B_IP --dport $PORT_START:$PORT_END -j ACCEPT
iptables -I FORWARD -p udp -d $B_IP --dport $PORT_START:$PORT_END -j ACCEPT
iptables -I FORWARD -p tcp -s $B_IP --sport $PORT_START:$PORT_END -j ACCEPT
iptables -I FORWARD -p udp -s $B_IP --sport $PORT_START:$PORT_END -j ACCEPT

echo "[✓] 端口 $PORT_START 到 $PORT_END 的 TCP + UDP 已成功转发到 $B_IP"