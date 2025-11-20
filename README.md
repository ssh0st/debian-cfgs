# 🚀 Debian Security + IKEv2 VPN Installer

Автоматическая настройка безопасности сервера Debian 12 и установка IKEv2 VPN с сертификатами, NAT, DNS и Fail2Ban.  
Подходит для чистых VPS и продакшен-систем.

---

## 🔐 1. Настройка безопасности

Скрипт `secure.sh` выполняет:

- Отключение SSH root-доступа
- Создание пользователя **superh0st** с sudo
- Изменение SSH порта на **7220**
- Установку и настройку **UFW**
- Установку и настройку **Fail2Ban**

### ▶️ Запуск

```bash
curl -s "https://raw.githubusercontent.com/ssh0st/debian-cfgs/refs/heads/master/secure.sh" | bash
```

```bash
curl -s "https://raw.githubusercontent.com/ssh0st/debian-cfgs/refs/heads/master/ikev2.sh" | bash -s 199.99.99.99 domain.ru eth0
```
