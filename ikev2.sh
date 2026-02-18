#!/bin/bash
set -e

SERVER_IP="$1"
PUB_ID="$2"
IFACE="$3"

if [[ -z "$SERVER_IP" || -z "$PUB_ID" || -z "$IFACE" ]]; then
    echo "Usage: $0 <SERVER_PUBLIC_IP> <VPN_ID> <INTERFACE>"
    exit 1
fi

echo "[INFO] Updating system..."
apt update
apt install -y strongswan strongswan-pki strongswan-starter ufw iptables-persistent curl

echo "[INFO] Configuring UFW..."
ufw allow 500/udp
ufw allow 4500/udp
ufw --force enable

echo "[INFO] Enabling IPv4 forwarding..."
sysctl -w net.ipv4.ip_forward=1
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
echo 'net.ipv4.conf.all.accept_redirects=0' >> /etc/sysctl.conf
echo 'net.ipv4.conf.all.send_redirects=0' >> /etc/sysctl.conf

echo "[INFO] Configuring iptables for NAT..."
iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o "$IFACE" -m policy --dir out --pol ipsec -j ACCEPT
iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o "$IFACE" -j MASQUERADE
iptables -I FORWARD 1 -j ACCEPT

echo "[INFO] Creating certificate directories..."
mkdir -p /etc/ipsec.d/private /etc/ipsec.d/cacerts /etc/ipsec.d/certs
chmod 700 /etc/ipsec.d/private

echo "[INFO] Generating CA key and certificate..."
ipsec pki --gen --type rsa --size 4096 --outform pem > /etc/ipsec.d/private/ca-key.pem
ipsec pki --self --ca --lifetime 3650 \
  --in /etc/ipsec.d/private/ca-key.pem \
  --type rsa \
  --dn "CN=VPN Root CA" \
  --outform pem > /etc/ipsec.d/cacerts/ca-cert.pem

echo "[INFO] Generating server key and certificate..."
ipsec pki --gen --type rsa --size 4096 --outform pem > /etc/ipsec.d/private/server-key.pem
ipsec pki --pub --in /etc/ipsec.d/private/server-key.pem --type rsa | \
ipsec pki --issue --lifetime 1825 \
  --cacert /etc/ipsec.d/cacerts/ca-cert.pem \
  --cakey /etc/ipsec.d/private/ca-key.pem \
  --dn "CN=$PUB_ID" \
  --san="$SERVER_IP" --san="$PUB_ID" \
  --flag serverAuth --flag ikeIntermediate \
  --outform pem > /etc/ipsec.d/certs/server-cert.pem

echo "[INFO] Writing ipsec.conf..."
cat > /etc/ipsec.conf << EOF
config setup
    charondebug="ike 2 knl 2 cfg 2 net 2 enc 2"
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
    leftcert=/etc/ipsec.d/certs/server-cert.pem
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

echo "[INFO] Writing ipsec.secrets..."
cat > /etc/ipsec.secrets << EOF
: RSA /etc/ipsec.d/private/server-key.pem
liteuser : EAP "super_passw0rd"
EOF

chmod 600 /etc/ipsec.secrets
chmod 600 /etc/ipsec.d/private/*

echo "[INFO] Restarting strongSwan..."
systemctl restart strongswan-starter
systemctl enable strongswan-starter

echo "[INFO] VPN setup completed!"
echo "Connect using IKEv2 with username: liteuser and password: super_passw0rd"
echo "Server IP: $SERVER_IP"
echo "You can check VPN status with: ipsec statusall"
