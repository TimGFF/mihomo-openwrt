#!/bin/sh
# ============================================================
#  Настройка nikki (luci-app-nikki) на OpenWrt
#
#  Что делает этот скрипт:
#  1. Настраивает UCI опции nikki
#  2. Настраивает dnsmasq для DNS через mihomo
#  3. Создаёт /etc/firewall.user (MSS clamping)
#  4. Включает UCI firewall include для /etc/firewall.user
#  5. Копирует профиль и запускает nikki
#
#  Требования: luci-app-nikki должен быть установлен
#  Запуск: sh /tmp/configure_nikki.sh
# ============================================================

set -e

PROFILE_PATH="/etc/nikki/profiles/main.yaml"
FIREWALL_USER="/etc/firewall.user"

echo ""
echo "========================================"
echo "  Настройка Nikki (Mihomo) на OpenWrt"
echo "========================================"
echo ""

# ============================================================
#  1. ПРОВЕРКА ЗАВИСИМОСТЕЙ
# ============================================================
echo "[1/5] Проверка зависимостей..."

if [ ! -x /usr/bin/mihomo ] && [ ! -x /usr/libexec/nikki ]; then
    echo ""
    echo "ОШИБКА: nikki не установлен."
    echo ""
    echo "Установи luci-app-nikki:"
    echo "  1. Через LuCI: System -> Software -> Search 'luci-app-nikki'"
    echo "  2. Через SSH:  opkg update && opkg install luci-app-nikki"
    echo ""
    echo "После установки снова запусти этот скрипт."
    exit 1
fi

if [ ! -d /etc/nikki ]; then
    echo "ОШИБКА: директория /etc/nikki не найдена."
    echo "Убедись что luci-app-nikki установлен корректно."
    exit 1
fi

echo "  OK: nikki установлен"

# ============================================================
#  2. ПРОФИЛЬ
# ============================================================
echo ""
echo "[2/5] Проверка профиля..."

mkdir -p /etc/nikki/profiles /etc/nikki/run/proxies

if [ ! -f "$PROFILE_PATH" ]; then
    echo "ОШИБКА: профиль не найден: $PROFILE_PATH"
    echo "Скрипт deploy.ps1 должен загрузить профиль перед запуском этого скрипта."
    exit 1
fi

echo "  OK: $PROFILE_PATH"

# ============================================================
#  3. UCI NIKKI — ключевые настройки
# ============================================================
echo ""
echo "[3/5] Настройка UCI nikki..."

# Основное
uci set nikki.config.enabled='1'
uci set nikki.config.profile='file:main.yaml'
uci set nikki.config.test_profile='1'

# TUN: gvisor обязательно (mixed ломает DNS hijack — баг #1258)
uci set nikki.mixin.tun_stack='gvisor'
# DNS-hijack управляется из профиля (any:53), не через UCI nftables
uci set nikki.mixin.tun_dns_hijack='0'

# TCP через redirect, UDP через TUN
uci set nikki.proxy.tcp_mode='redirect'
uci set nikki.proxy.udp_mode='tun'
# DNS-hijack через nftables выключен: dnsmasq сам форвардит на 127.0.0.1#1053
# Это нужно чтобы .lan домены продолжали работать через dnsmasq
uci set nikki.proxy.ipv4_dns_hijack='0'
uci set nikki.proxy.ipv6_dns_hijack='0'

# 30 секунд достаточно — geodata грузится за 4-5 секунд
uci set nikki.proxy.tun_timeout='30'

# Geodata: автообновление раз в неделю (заменяет ручной cron)
uci set nikki.mixin.geox_auto_update='1'
uci set nikki.mixin.geox_update_interval='168'

# Keepalive для iPhone (предотвращает разрыв соединений)
uci set nikki.mixin.tcp_keep_alive_idle='600'
uci set nikki.mixin.tcp_keep_alive_interval='15'

# IPv6 выключен
uci set nikki.mixin.ipv6='0'

uci commit nikki
echo "  OK: UCI nikki настроен"

# ============================================================
#  4. DNSMASQ → MIHOMO DNS
# ============================================================
echo ""
echo "[4/5] Настройка dnsmasq..."

# Форвардим весь DNS на mihomo (порт 1053, fake-ip)
# Выключаем кеш — mihomo сам кеширует
# Выключаем resolv.conf — nikki cgroup защищает mihomo от петли
uci set dhcp.@dnsmasq[0].noresolv='1'
uci set dhcp.@dnsmasq[0].cachesize='0'
uci -q del dhcp.@dnsmasq[0].server 2>/dev/null || true
uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#1053'
uci commit dhcp
/etc/init.d/dnsmasq restart 2>/dev/null || true
echo "  OK: dnsmasq -> 127.0.0.1#1053 (fake-ip)"

# ============================================================
#  5. FIREWALL: MSS CLAMPING
# ============================================================
echo ""
echo "[5/5] Настройка firewall (MSS clamping)..."

# MSS clamping — предотвращает проблемы с большими пакетами через VPN
# Без этого могут не открываться некоторые сайты (PMTUD blackhole)
cat > "$FIREWALL_USER" << 'EOF'
# MSS clamping для VPN (предотвращает проблемы с большими пакетами)
# Выполняется fw4 при каждом старте/перезагрузке firewall
nft add table inet mss_clamp 2>/dev/null || true
nft add chain inet mss_clamp postrouting "{ type filter hook postrouting priority mangle; }" 2>/dev/null || true
nft flush chain inet mss_clamp postrouting 2>/dev/null || true
nft add rule inet mss_clamp postrouting "tcp flags syn tcp option maxseg size > 1452 tcp option maxseg size set 1452" 2>/dev/null || true
EOF

# UCI include: fw4 не выполняет /etc/firewall.user автоматически без него
if ! uci show firewall 2>/dev/null | grep -q "path='/etc/firewall.user'"; then
    uci add firewall include > /dev/null
    uci set firewall.@include[-1].path="$FIREWALL_USER"
    uci set firewall.@include[-1].type='script'
    uci commit firewall
    /etc/init.d/firewall reload 2>/dev/null || true
    echo "  OK: /etc/firewall.user создан и добавлен в UCI firewall"
else
    /etc/init.d/firewall reload 2>/dev/null || true
    echo "  OK: /etc/firewall.user (UCI include уже есть)"
fi

# ============================================================
#  ЗАПУСК NIKKI
# ============================================================
echo ""
echo "  Запускаем nikki..."
/etc/init.d/nikki enable 2>/dev/null || true
/etc/init.d/nikki restart

echo ""
echo "========================================"
echo "  Nikki настроен и запущен!"
echo "========================================"
echo ""
echo "  Веб-панель: http://192.168.1.1:9090/ui"
echo "  Проверить статус: service nikki status"
echo "  Логи:  cat /var/log/nikki/app.log"
echo "         cat /var/log/nikki/core.log"
echo ""
