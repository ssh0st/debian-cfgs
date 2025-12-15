#!/bin/bash

set -e

export PATH=$PATH:/usr/sbin:/sbin:/usr/bin:/bin

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

get_user_input() {
    echo ""
    print_info "=== НАСТРОЙКА ПАРАМЕТРОВ СКРИПТА ==="
    echo ""
    
    while true; do
        read -p "Введите SSH порт (по умолчанию: 7220): " ssh_port
        ssh_port=${ssh_port:-7220}
        
        if [[ "$ssh_port" =~ ^[0-9]+$ ]] && [ "$ssh_port" -ge 1 ] && [ "$ssh_port" -le 65535 ]; then
            break
        else
            print_error "Неверный порт. Введите число от 1 до 65535"
        fi
    done
    
    read -p "Введите имя пользователя (по умолчанию: superh0st): " username
    username=${username:-superh0st}
    
    while [[ ! "$username" =~ ^[a-z][-a-z0-9_]*$ ]]; do
        print_error "Имя пользователя должно начинаться с буквы и содержать только строчные буквы, цифры, дефисы и подчеркивания"
        read -p "Введите имя пользователя: " username
    done
    
    read -sp "Введите пароль для пользователя (по умолчанию: Pa\$\$word): " user_password
    user_password=${user_password:-Pa$$word}
    echo ""
    while true; do
        read -p "Установить и настроить UFW? (y/n, по умолчанию: y): " install_ufw
        install_ufw=${install_ufw:-y}
        
        case "$install_ufw" in
            [Yy]* ) install_ufw=true; break;;
            [Nn]* ) install_ufw=false; break;;
            * ) print_error "Пожалуйста, ответьте y (да) или n (нет)";;
        esac
    done
    
    while true; do
        read -p "Установить и настроить Fail2ban? (y/n, по умолчанию: y): " install_fail2ban
        install_fail2ban=${install_fail2ban:-y}
        
        case "$install_fail2ban" in
            [Yy]* ) install_fail2ban=true; break;;
            [Nn]* ) install_fail2ban=false; break;;
            * ) print_error "Пожалуйста, ответьте y (да) или n (нет)";;
        esac
    done
    
    echo ""
    print_info "=== ПОДТВЕРЖДЕНИЕ НАСТРОЕК ==="
    echo "SSH порт: $ssh_port"
    echo "Имя пользователя: $username"
    echo "Установка UFW: $install_ufw"
    echo "Установка Fail2ban: $install_fail2ban"
    echo ""
    
    while true; do
        read -p "Продолжить с этими настройками? (y/n): " confirm
        case "$confirm" in
            [Yy]* ) break;;
            [Nn]* ) 
                print_info "Перезапустите скрипт для ввода новых параметров"
                exit 0;;
            * ) print_error "Пожалуйста, ответьте y (да) или n (нет)";;
        esac
    done
    
    echo ""
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

create_user() {
    print_info "Создание пользователя $username..."
    
    if id "$username" &>/dev/null; then
        print_warning "Пользователь $username уже существует"
    else
        useradd -m -s /bin/bash -p $(openssl passwd -6 "$user_password") "$username"
        usermod -aG sudo "$username"
        print_info "Пользователь $username создан и добавлен в группу sudo"
    fi
}

configure_ssh() {
    print_info "Настройка SSH на порт $ssh_port..."
    
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    
    cat > /etc/ssh/sshd_config << EOF
Include /etc/ssh/sshd_config.d/*.conf
KbdInteractiveAuthentication no
UsePAM yes
X11Forwarding yes
PrintMotd no
UseDNS no
AcceptEnv LANG LC_*
Subsystem       sftp    /usr/lib/openssh/sftp-server

Port $ssh_port
PermitRootLogin no
PubkeyAuthentication no
PasswordAuthentication yes
ChallengeResponseAuthentication no
EOF
    
    print_info "SSH сконфигурирован на порт $ssh_port с отключением root доступа"
}

setup_ufw() {
    if [ "$install_ufw" = false ]; then
        print_warning "Пропуск установки UFW по выбору пользователя"
        return
    fi
    
    print_info "Установка и настройка UFW..."
    
    if ! command -v ufw &> /dev/null; then
        apt install ufw -y
    fi
    
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow "$ssh_port/tcp"
    ufw allow OpenSSH
    ufw --force enable
    
    print_info "Статус UFW:"
    ufw status verbose
}

install_fail2ban_package() {
    if [ "$install_fail2ban" = false ]; then
        print_warning "Пропуск установки Fail2ban по выбору пользователя"
        return
    fi
    
    print_info "Установка Fail2ban..."
    apt install fail2ban -y
}

configure_fail2ban() {
    if [ "$install_fail2ban" = false ]; then
        return
    fi
    
    print_info "Настройка Fail2ban..."
    
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 4
action = %(action_mwl)s
ignoreip = 127.0.0.1/8 ::1
backend = systemd

[sshd]
enabled = true
port = $ssh_port
filter = sshd
logpath = /var/log/auth.log
maxretry = 4
bantime = 86400

[sshd-ddos]
enabled = true
port = $ssh_port
filter = sshd-ddos
logpath = /var/log/auth.log
maxretry = 2
bantime = 604800
EOF
    
    print_warning "/etc/fail2ban/jail.local настроен"
}

setup_fail2ban_ufw() {
    if [ "$install_fail2ban" = false ] || [ "$install_ufw" = false ]; then
        return
    fi
    
    print_info "Настройка интеграции Fail2ban с UFW..."
    
    cat > /etc/fail2ban/filter.d/ufw.conf << 'EOF'
[Definition]
failregex = \[UFW BLOCK\].*SRC=<HOST>
ignoreregex =
EOF
    
    cat >> /etc/fail2ban/jail.local << EOF

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
    
    if [ "$install_fail2ban" = true ]; then
        systemctl enable fail2ban
        systemctl start fail2ban
    fi
    
    systemctl restart ssh
    
    if [ "$install_fail2ban" = true ]; then
        print_info "Проверка статуса Fail2ban..."
        systemctl status fail2ban --no-pager
    fi
}

verify_installation() {
    print_info "Проверка установки..."
    
    if [ "$install_fail2ban" = true ]; then
        fail2ban-client --version
        
        print_info "Статус jails:"
        fail2ban-client status
    fi
    
    print_info "Проверка SSH порта:"
    ss -tlnp | grep "$ssh_port" || print_warning "SSH порт $ssh_port не слушается"
}

install_utils() {
    print_info "Установка дополнительных утилит..."
    apt install whois -y
}

print_summary() {
    print_info "=================================================="
    print_info "Установка и настройка завершена!"
    print_info "=================================================="
    echo ""
    print_warning "ВАЖНО:"
    echo "1. SSH теперь работает на порту $ssh_port"
    echo "2. Root доступ по SSH отключен"
    echo "3. Создан пользователь $username с sudo правами"
    
    if [ "$install_ufw" = true ]; then
        echo "4. UFW установлен и настроен"
    fi
    
    if [ "$install_fail2ban" = true ]; then
        echo "5. Fail2ban установлен и настроен"
        echo "Конфиг fail2ban: /etc/fail2ban/jail.local"
    fi
    
    echo ""
    print_info "Для подключения используйте:"
    echo "  ssh -p $ssh_port $username@server_ip"
    echo ""
    
    if [ "$install_fail2ban" = true ]; then
        print_info "Полезные команды для мониторинга:"
        echo "  fail2ban-client status sshd"
        if [ "$install_ufw" = true ]; then
            echo "  fail2ban-client status ufw"
        fi
        echo "  tail -f /var/log/fail2ban.log"
        echo "  journalctl -f"
    fi
    
    if [ "$install_ufw" = true ]; then
        echo "  ufw status verbose"
    fi
}

main() {
    clear
    echo -e "${GREEN}"
    echo "⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄"
    echo "⠄⠄⠄⠄⠄⠄⠄⣀⡤⠶⠒⠒⠒⠒⠶⢤⣀⠄⠄⠄⠄⠄⠄⠄"
    echo "⠄⠄⠄⠄⢀⡴⠋⠁⠄⠄⠄⠄⠄⠄⠄⠄⠈⠙⢦⡀⠄⠄⠄⠄"
    echo "⠄⠄⠄⢠⠏⠄⢀⣠⣤⣀⠄⠄⠄⣠⠖⠲⣄⠄⠄⠹⡄⠄⠄⠄"
    echo "⠄⠄⢠⡏⠄⠄⠸⠁⠄⠙⠄⠄⠄⠃⠄⠄⠉⠄⠄⠄⢹⡄⠄⠄"
    echo "⠄⠄⢸⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⣀⠄⠄⠄⠄⠄⡇⠄⠄"
    echo "⠄⠄⢸⠄⣀⣀⡀⠄⠳⢦⣄⣀⣠⡤⠞⠁⠄⢀⣀⣀⠄⡇⠄⠄"
    echo "⠄⡴⠚⣉⠉⠉⠉⠳⣄⠄⠄⠄⠄⠄⠄⣠⠞⠉⠉⠉⣉⠓⢦⠄"
    echo "⣤⠗⠚⣉⠳⠶⠆⠄⢸⠄⠄⠄⠄⠄⠄⡇⠄⠰⠶⠞⣉⠓⠺⣤"
    echo "⢹⠚⢋⣥⠖⣀⠄⢀⡞⠄⠄⠄⠄⠄⠄⢳⡀⠄⣀⠲⣌⡙⠓⡏"
    echo "⠈⠻⣍⣴⣞⣡⡴⠋⠓⠶⠤⠤⠤⠤⠶⠚⠙⢦⣌⣳⣦⣩⠟⠁"
    echo "⠄⠄⠄⠄⠉⠁⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠈⠉⠄⠄⠄⠄"
    echo -e "${NC}"
    
    get_user_input
    
    check_root
    update_system
    create_user
    configure_ssh
    setup_ufw
    install_fail2ban_package
    configure_fail2ban
    setup_fail2ban_ufw
    install_utils
    enable_services
    verify_installation
    print_summary
}

main
