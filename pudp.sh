#!/bin/bash

set -ex

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

setup_udp_tunnel() {
    print_info "Настройка Plain UDP Tunnel ..."
    
    apt install socat -y
    
    TUN_IF="tunudp"
    TUN_IP="10.0.100.1"
    TUN_PORT="1194"
    
    ip tuntap add mode tun dev $TUN_IF
    ip addr add $TUN_IP/24 dev $TUN_IF
    ip link set $TUN_IF up
    
    echo 1 > /proc/sys/net/ipv4/ip_forward
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p
    
    iptables -t nat -A POSTROUTING -s 10.0.100.0/24 -j MASQUERADE
    iptables -A FORWARD -i $TUN_IF -j ACCEPT
    iptables -A FORWARD -o $TUN_IF -m state --state RELATED,ESTABLISHED -j ACCEPT
    
    ufw allow $TUN_PORT/udp
    
    cat > /etc/systemd/system/udp-tunnel.service << EOF
[Unit]
Description=Plain UDP Tunnel
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/socat UDP4-LISTEN:$TUN_PORT,fork TUN:10.0.100.1/24,tun-name=$TUN_IF,iff-up
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable udp-tunnel
    systemctl start udp-tunnel
    
    print_info "Plain UDP Tunnel запущен на порту $TUN_PORT"
    print_info "Клиентский IP: 10.0.100.2-254"
    print_info "На Windows используйте:"
    echo "netsh interface portproxy add v4tov4 listenport=ЛЮБОЙ_ПОРТ connectport=$TUN_PORT connectaddress=$(hostname -I | awk '{print \$1}')"
}

main() {
    setup_udp_tunnel  
}

main
