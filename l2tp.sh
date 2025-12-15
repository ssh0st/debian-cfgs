#!/bin/bash

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Run as root: sudo bash $0"
    exit 1
fi

PUBLIC_IP=$(/usr/bin/curl -s ifconfig.me || hostname -I | /usr/bin/awk '{print $1}')
PSK_KEY="$(date +%s | /usr/bin/md5sum | /usr/bin/head -c 16)"
VPN_USER="usr_00"
VPN_PASS="pa\$\$w0rd"
EXTERNAL_IF=$(ip route | grep default | /usr/bin/awk '{print $5}' | /usr/bin/head -1)

apt update
apt install -y strongswan xl2tpd

cat > /etc/ipsec.conf << EOF
config setup
    charondebug="ike 1, knl 1, cfg 1"
    uniqueids=no

conn %default
    ikelifetime=24h
    lifetime=8h
    keyingtries=1
    keyexchange=ikev1
    authby=secret
    ike=aes256-sha1-modp1024
    esp=aes256-sha1
    forceencaps=yes

conn l2tp-psk
    auto=add
    left=%any
    leftid=@$PUBLIC_IP
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any
    type=transport
EOF

cat > /etc/ipsec.secrets << EOF
%any %any : PSK "$PSK_KEY"
EOF

chmod 600 /etc/ipsec.secrets

cat > /etc/xl2tpd/xl2tpd.conf << EOF
[global]
port = 1701
auth file = /etc/ppp/chap-secrets

[lns default]
ip range = 10.10.10.100-10.10.10.200
local ip = 10.10.10.1
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
pppoptfile = /etc/ppp/options.xl2tpd
EOF

mkdir -p /etc/ppp

cat > /etc/ppp/options.xl2tpd << EOF
require-mschap-v2
ms-dns 8.8.8.8
ms-dns 8.8.4.4
auth
mtu 1200
mru 1000
proxyarp
lcp-echo-interval 30
lcp-echo-failure 4
nodefaultroute
EOF

cat > /etc/ppp/chap-secrets << EOF
"$VPN_USER" l2tpd "$VPN_PASS" *
EOF

chmod 600 /etc/ppp/chap-secrets

/sbin/sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-vpn.conf
/sbin/sysctl -p /etc/sysctl.d/99-vpn.conf

/usr/bin/ufw allow 500/udp
/usr/bin/ufw allow 4500/udp
/usr/bin/ufw allow 1701/udp
/usr/bin/ufw allow proto esp from any to any

cat > /etc/ufw/before.rules << EOF
*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 10.10.10.0/24 -o $EXTERNAL_IF -j MASQUERADE
COMMIT
EOF

/usr/bin/sed -i '/^DEFAULT_FORWARD_POLICY=/s/DROP/ACCEPT/' /etc/default/ufw
/usr/bin/ufw --force disable
/usr/bin/ufw --force enable

/sbin/iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o $EXTERNAL_IF -j MASQUERADE

systemctl restart strongswan-starter
systemctl enable strongswan-starter
systemctl restart xl2tpd
systemctl enable xl2tpd

echo "L2TP/IPsec VPN configured"
echo "Server IP: $PUBLIC_IP"
echo "PSK: $PSK_KEY"
echo "User: $VPN_USER"
echo "Pass: $VPN_PASS"
