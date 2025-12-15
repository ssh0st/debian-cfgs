#!/bin/bash

set -e

export PATH=$PATH:/usr/sbin:/sbin:/usr/bin:/bin

setup_wg() {
    apt update
    apt install -y wireguard

    echo 1 > /proc/sys/net/ipv4/ip_forward

    wg genkey | tee /etc/wireguard/server_privatekey | wg pubkey | tee /etc/wireguard/server_publickey

    SERVER_PRIVATE=$(cat /etc/wireguard/private.key)
    SERVER_PUBLIC=$(cat /etc/wireguard/public.key)
    SERVER_IP="$(ip -4 addr show ens3 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || curl -s ifconfig.me)"
    WG_PORT="51820"
    
    cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = $SERVER_IP
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIVATE
SaveConfig = true
PostUp = /usr/sbin/iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE 
PostDown = /usr/sbin/iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ens3 -j MASQUERADE
EOF

    systemctl enable wg-quick@wg0
    systemctl start wg-quick@wg0
}

main() {
    setup_wg
    
    echo "WireGuard запущен"
    echo "Публичный ключ: $(cat /etc/wireguard/public.key)"
}

main
