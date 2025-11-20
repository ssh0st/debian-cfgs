#!/bin/bash

set -e

export PATH=$PATH:/usr/sbin:/sbin

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен запускаться с правами root"
        exit 1
    fi
}

update_system() {
    print_info "Обновление списка пакетов и системы..."
    apt update && apt upgrade -y
}

create_superh0st_user() {
    print_info "Создание пользователя superh0st..."

    if id "superh0st" &>/dev/null; then
        print_warning "Пользователь superh0st уже существует"
    else
        useradd -m -s /bin/bash -p $(openssl passwd -6 'Nevermind+=1') superh0st
        usermod -aG sudo superh0st
        print_info "Пользователь superh0st создан с паролем 'Nevermind+=1' и добавлен в группу sudo"
    fi
}

configure_ssh() {
    print_info "Настройка SSH..."

    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

    cat > /etc/ssh/sshd_config << 'EOF'
Port 7220
PermitRootLogin no
PubkeyAuthentication no
PasswordAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

    print_info "SSH сконфигурирован на порт 7220 с отключением root доступа"
}

setup_ufw() {
    print_info "Установка и настройка UFW..."

    if ! command -v ufw &> /dev/null; then
        apt install ufw -y
    fi

    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 7220/tcp
    ufw --force enable

    print_info "Статус UFW:"
    ufw status verbose
}

install_fail2ban() {
    print_info "Установка Fail2ban..."
    apt install fail2ban -y
}

configure_fail2ban() {
    print_info "Настройка Fail2ban..."

    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 4
action = %(action_mwl)s
ignoreip = 127.0.0.1/8 ::1
backend = systemd

[sshd]
enabled = true
port = 7220
filter = sshd
logpath = /var/log/auth.log
maxretry = 4
bantime = 86400

[sshd-ddos]
enabled = true
port = 7220
filter = sshd-ddos
logpath = /var/log/auth.log
maxretry = 2
bantime = 604800
EOF

    print_warning "/etc/fail2ban/jail.local настроен"
}

setup_fail2ban_ufw() {
    print_info "Настройка интеграции Fail2ban с UFW..."

    cat > /etc/fail2ban/filter.d/ufw.conf << 'EOF'
[Definition]
failregex = \[UFW BLOCK\].*SRC=<HOST>
ignoreregex =
EOF

    cat >> /etc/fail2ban/jail.local << 'EOF'

[ufw]
enabled = true
filter = ufw
action = ufw
logpath = /var/log/ufw.log
maxretry = 1
bantime = 2592000
EOF
}

enable_services() {
    print_info "Запуск и включение служб..."

    systemctl enable fail2ban
    systemctl restart ssh
    systemctl start fail2ban

    print_info "Проверка статуса Fail2ban..."
    systemctl status fail2ban --no-pager
}

verify_installation() {
    print_info "Проверка установки Fail2ban..."

    fail2ban-client --version

    print_info "Статус jails:"
    fail2ban-client status

    print_info "Статус SSH jail:"
    fail2ban-client status sshd

    print_info "Проверка SSH порта:"
    ss -tlnp | grep 7220
}

install_utils() {
    print_info "Установка дополнительных утилит..."
    apt install whois -y
}

main() {
    print_info "Начало установки и настройки безопасности на Debian 12"

    check_root
    update_system
    create_superh0st_user
    configure_ssh
    setup_ufw
    install_fail2ban
    configure_fail2ban
    setup_fail2ban_ufw
    install_utils
    enable_services
    verify_installation

    print_info "=================================================="
    print_info "Установка и настройка завершена!"
    print_info "=================================================="
    echo ""
    print_warning "ВАЖНО:"
    echo "1. SSH теперь работает на порту 7220"
    echo "2. Root доступ по SSH отключен"
    echo "3. Создан пользователь superh0st с sudo правами"
    echo "Конфиг fail2ban /etc/fail2ban/jail.local"
    echo ""
    print_info "Для подключения используйте:"
    echo "  ssh -p 7220 superh0st@server_ip"
    echo ""
    print_info "Полезные команды для мониторинга:"
    echo "  fail2ban-client status sshd"
    echo "  fail2ban-client status ufw"
    echo "  tail -f /var/log/fail2ban.log"
    echo "  journalctl -f"
    echo "  ufw status verbose"
}

main
