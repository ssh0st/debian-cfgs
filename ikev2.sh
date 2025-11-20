#!/bin/bash
set -e

SERVER_IP="$1"
PUB_ID="$2"
IFACE="$3"

apt update
apt install -y strongswan strongswan-pki strongswan-starter ufw

/usr/sbin/ufw allow 500,4500/udp

echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
echo 'net.ipv4.conf.all.accept_redirects=0' >> /etc/sysctl.conf
echo 'net.ipv4.conf.all.send_redirects=0' >> /etc/sysctl.conf
/usr/sbin/sysctl -p

/usr/sbin/ufw allow in on $IFACE from 10.10.10.0/24
/usr/sbin/ufw route allow in on $IFACE out on $IFACE

/usr/sbin/iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o $IFACE -m policy --dir out --pol ipsec -j ACCEPT
/usr/sbin/iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o $IFACE -j MASQUERADE
/usr/sbin/iptables -I FORWARD 1 -j ACCEPT

mkdir -p /etc/ipsec.d/private
chmod 700 /etc/ipsec.d/private

/usr/sbin/ipsec pki --gen --type rsa --size 4096 --outform pem > /etc/ipsec.d/private/ca-key.pem
/usr/sbin/ipsec pki --self --ca --lifetime 3650 --in /etc/ipsec.d/private/ca-key.pem --type rsa --dn "CN=VPN Root CA" --outform pem > /etc/ipsec.d/cacerts/ca-cert.pem

/usr/sbin/ipsec pki --gen --type rsa --size 4096 --outform pem > /etc/ipsec.d/private/server-key.pem

/usr/sbin/ipsec pki --pub --in /etc/ipsec.d/private/server-key.pem --type rsa | \
/usr/sbin/ipsec pki --issue --lifetime 1825 --cacert /etc/ipsec.d/cacerts/ca-cert.pem \
--cakey /etc/ipsec.d/private/ca-key.pem --dn "CN=$PUB_ID" \
--san="$SERVER_IP" --san="$PUB_ID" --flag serverAuth --flag ikeIntermediate \
--outform pem > /etc/ipsec.d/certs/server-cert.pem

cat > /etc/ipsec.conf << EOF
config setup
    charondebug="ike 4 knl 4 cfg 4 net 4 enc 4"
    uniqueids=no

conn ikev2-vpn
    auto=add
    compress=no
    type=tunnel
    keyexchange=ikev2
    ikev2=insist
    fragmentation=yes
    forceencaps=yes
    dpdaction=clear
    dpddelay=30s
    dpdtimeout=800s
    dpdaction=restart
    mobike=yes
    rekey=no
    left=%any
    leftid=$PUB_ID
    leftcert=server-cert.pem
    leftsendcert=always
    leftsubnet=0.0.0.0/0
    leftfirewall=yes
    right=%any
    rightid=%any
    rightauth=eap-mschapv2
    rightsourceip=10.10.10.0/24
    rightdns=8.8.8.8,8.8.4.4
    rightsendcert=never
    eap_identity=%identity
EOF

cat > /etc/ipsec.secrets << EOF
: RSA server-key.pem
liteuser : EAP "super_passw0rd"
EOF

chmod 600 /etc/ipsec.secrets
chmod 600 /etc/ipsec.d/private/*

systemctl restart strongswan-starter
systemctl enable strongswan-starter

/usr/sbin/ufw --force enable

systemctl status strongswan-starter
/usr/sbin/ipsec status
