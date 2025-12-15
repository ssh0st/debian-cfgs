#!/bin/bash

set -e

export PATH=$PATH:/usr/sbin:/sbin:/usr/bin:/bin

setup_wg() {
    apt update
    apt install -y wireguard

    wg genkey | tee /etc/wireguard/server_privatekey | wg pubkey | tee /etc/wireguard/server_publickey

    SERVER_PRIVATE=$(cat /etc/wireguard/private.key)
    SERVER_PUBLIC=$(cat /etc/wireguard/public.key)
    SERVER_IP="10.10.0.1/24" # "$(ip -4 addr show ens3 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || curl -s ifconfig.me)"
    WG_PORT="51820"
    
    cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = $SERVER_IP
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIVATE
SaveConfig = true
PostUp = /usr/sbin/iptables -A FORWARD -i ens3 -j ACCEPT; iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE 
PostDown = /usr/sbin/iptables -D FORWARD -i ens3 -j ACCEPT; iptables -t nat -D POSTROUTING -o ens3 -j MASQUERADE
EOF

    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p

    systemctl enable wg-quick@wg0
    systemctl start wg-quick@wg0
}

add_client() {
    read -p "Имя клиента: " CLIENT_NAME
    
    CLIENT_PRIVATE=$(wg genkey)
    CLIENT_PUBLIC=$(echo $CLIENT_PRIVATE | wg pubkey)
    
    if [ -f /etc/wireguard/wg0.conf ]; then
        CLIENT_COUNT=$(grep -c "^\[Peer\]" /etc/wireguard/wg0.conf || echo 0)
    else
        CLIENT_COUNT=0
    fi
    
    CLIENT_IP="10.10.0.$((CLIENT_COUNT + 2))"
    
    cat >> /etc/wireguard/wg0.conf << EOF

[Peer]
PublicKey = $CLIENT_PUBLIC
AllowedIPs = $CLIENT_IP/32
EOF

    wg syncconf wg0 <(wg-quick strip wg0)
    
    EXTERNAL_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || echo "ВНЕШНИЙ_IP_НЕ_НАЙДЕН")
    
    cat > /root/$CLIENT_NAME.conf << EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE
Address = $CLIENT_IP/24
DNS = 8.8.8.8

[Peer]
PublicKey = $SERVER_PUBLIC
Endpoint = $EXTERNAL_IP:$WG_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
    
    echo "Клиент $CLIENT_NAME добавлен"
    echo "IP клиента: $CLIENT_IP"
    echo "Конфиг сохранен: /root/$CLIENT_NAME.conf"
    echo ""
    echo "Содержимое конфига клиента:"
    cat /root/$CLIENT_NAME.conf
}



main() {
    setup_wg
    add_client
    
    echo "WireGuard запущен"
    echo "Публичный ключ: $(cat /etc/wireguard/public.key)"
}

main
