#!/bin/bash

set -e

export PATH=$PATH:/usr/sbin:/sbin:/usr/bin:/bin

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Требуются права root"
        exit 1
    fi
}

install_wireguard() {
    apt update
    apt install -y wireguard
}

enable_ip_forwarding() {
    echo 1 > /proc/sys/net/ipv4/ip_forward
}

generate_keys() {
    umask 077
    wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
    SERVER_PRIVATE=$(cat /etc/wireguard/private.key)
    SERVER_PUBLIC=$(cat /etc/wireguard/public.key)
}

create_server_config() {
    SERVER_IP="10.10.0.1"
    WG_PORT="51820"
    
    cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = $SERVER_IP/24
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIVATE
SaveConfig = true
EOF
}

start_wireguard() {
    systemctl enable wg-quick@wg0
    systemctl start wg-quick@wg0
}

main() {
    check_root
    install_wireguard
    enable_ip_forwarding
    generate_keys
    create_server_config
    start_wireguard
    echo "WireGuard запущен"
    echo "Публичный ключ: $(cat /etc/wireguard/public.key)"
}

main
