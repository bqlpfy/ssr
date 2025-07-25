#!/bin/bash

# === 交互式配置 ===
# 脚本标识，用于区分规则来源
SCRIPT_TAG="FORWARD-SCRIPT"

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

echo "[+] 清除本脚本之前添加的转发规则..."
# 只删除带有我们标识的规则
iptables-save | grep -v "$SCRIPT_TAG" | iptables-restore

echo "[+] 添加新的 NAT 转发规则（带标识）..."
iptables -t nat -A PREROUTING -p tcp --dport $PORT_START:$PORT_END -j DNAT --to-destination $B_IP -m comment --comment "$SCRIPT_TAG"
iptables -t nat -A POSTROUTING -p tcp -d $B_IP --dport $PORT_START:$PORT_END -j MASQUERADE -m comment --comment "$SCRIPT_TAG"
iptables -t nat -A PREROUTING -p udp --dport $PORT_START:$PORT_END -j DNAT --to-destination $B_IP -m comment --comment "$SCRIPT_TAG"
iptables -t nat -A POSTROUTING -p udp -d $B_IP --dport $PORT_START:$PORT_END -j MASQUERADE -m comment --comment "$SCRIPT_TAG"

echo "[+] 添加新的 FORWARD 放行规则（带标识）..."
iptables -I FORWARD -p tcp -d $B_IP --dport $PORT_START:$PORT_END -j ACCEPT -m comment --comment "$SCRIPT_TAG"
iptables -I FORWARD -p udp -d $B_IP --dport $PORT_START:$PORT_END -j ACCEPT -m comment --comment "$SCRIPT_TAG"
iptables -I FORWARD -p tcp -s $B_IP --sport $PORT_START:$PORT_END -j ACCEPT -m comment --comment "$SCRIPT_TAG"
iptables -I FORWARD -p udp -s $B_IP --sport $PORT_START:$PORT_END -j ACCEPT -m comment --comment "$SCRIPT_TAG"

echo "[✓] 已清除本脚本的旧规则，端口 $PORT_START 到 $PORT_END 的 TCP + UDP 已成功转发到 $B_IP"
echo "[✓] 其他程序或手动添加的规则不受影响"
echo ""
echo "[信息] 本脚本添加的规则都带有标识: $SCRIPT_TAG"
echo "[信息] 可以通过以下命令查看本脚本的规则:"
echo "        iptables-save | grep '$SCRIPT_TAG'"