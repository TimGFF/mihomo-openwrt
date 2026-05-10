#!/bin/sh
# ============================================================
#  Настройка nikki (luci-app-nikki) на OpenWrt
#
#  Что делает:
#  1. Проверяет зависимости
#  2. Настраивает UCI nikki (TUN gvisor, redirect, fake-ip-через-dnsmasq)
#  3. Настраивает dnsmasq на форвард в mihomo (127.0.0.1#1053)
#  4. Создаёт /etc/firewall.user (MSS clamping)
#  5. Подключает include в UCI firewall
#  6. Ставит watchdog + cron (автоперезапуск при сбое прокси)
#  7. Запускает nikki
#
#  Требования: luci-app-nikki установлен (opkg install luci-app-nikki)
# ============================================================

set -e

PROFILE_PATH="/etc/nikki/profiles/main.yaml"
FIREWALL_USER="/etc/firewall.user"
WATCHDOG_BIN="/usr/bin/nikki-watchdog"

echo ""
echo "========================================"
echo "  Настройка Nikki (Mihomo) на OpenWrt"
echo "========================================"
echo ""

# ------------------------------------------------------------
#  1. Проверка зависимостей
# ------------------------------------------------------------
echo "[1/6] Проверка зависимостей..."

if [ ! -d /etc/nikki ]; then
    echo "ОШИБКА: /etc/nikki не найдена. Установи luci-app-nikki:"
    echo "  opkg update && opkg install luci-app-nikki"
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "ОШИБКА: curl не установлен. Поставь: opkg install curl"
    exit 1
fi

echo "  OK: nikki установлен, curl доступен"

# ------------------------------------------------------------
#  2. Профиль
# ------------------------------------------------------------
echo ""
echo "[2/6] Проверка профиля..."

mkdir -p /etc/nikki/profiles /etc/nikki/run/proxies

if [ ! -f "$PROFILE_PATH" ]; then
    echo "ОШИБКА: профиль $PROFILE_PATH не найден."
    echo "deploy.ps1 должен был его загрузить раньше."
    exit 1
fi

echo "  OK: $PROFILE_PATH"

# ------------------------------------------------------------
#  3. UCI nikki
# ------------------------------------------------------------
echo ""
echo "[3/6] Настройка UCI nikki..."

# Основное
uci set nikki.config.enabled='1'
uci set nikki.config.profile='file:main.yaml'
uci set nikki.config.test_profile='1'

# TUN: gvisor (mixed ломает DNS hijack — баг mihomo #1258)
uci set nikki.mixin.tun_stack='gvisor'
# tun_dns_hijack отключаем: dnsmasq сам форвардит на 127.0.0.1#1053 — для .lan
uci set nikki.mixin.tun_dns_hijack='0'

# TCP через redirect, UDP через TUN
uci set nikki.proxy.tcp_mode='redirect'
uci set nikki.proxy.udp_mode='tun'
uci set nikki.proxy.ipv4_dns_hijack='0'
uci set nikki.proxy.ipv6_dns_hijack='0'
uci set nikki.proxy.tun_timeout='30'

# IPv6 выкл
uci set nikki.mixin.ipv6='0'

uci commit nikki
echo "  OK"

# ------------------------------------------------------------
#  4. dnsmasq → mihomo DNS
# ------------------------------------------------------------
echo ""
echo "[4/6] Настройка dnsmasq..."

uci set dhcp.@dnsmasq[0].noresolv='1'
uci set dhcp.@dnsmasq[0].cachesize='0'
uci -q del dhcp.@dnsmasq[0].server 2>/dev/null || true
uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#1053'
uci commit dhcp
/etc/init.d/dnsmasq restart 2>/dev/null || true
echo "  OK: dnsmasq -> 127.0.0.1#1053"

# ------------------------------------------------------------
#  5. Firewall: MSS clamping
# ------------------------------------------------------------
echo ""
echo "[5/6] Настройка firewall (MSS clamping)..."

cat > "$FIREWALL_USER" << 'EOF'
# MSS clamping для VPN (предотвращает PMTUD blackhole через TUN)
nft add table inet mss_clamp 2>/dev/null || true
nft add chain inet mss_clamp postrouting "{ type filter hook postrouting priority mangle; }" 2>/dev/null || true
nft flush chain inet mss_clamp postrouting 2>/dev/null || true
nft add rule inet mss_clamp postrouting "tcp flags syn tcp option maxseg size > 1452 tcp option maxseg size set 1452" 2>/dev/null || true
EOF

if ! uci show firewall 2>/dev/null | grep -q "path='/etc/firewall.user'"; then
    uci add firewall include > /dev/null
    uci set firewall.@include[-1].path="$FIREWALL_USER"
    uci set firewall.@include[-1].type='script'
    uci commit firewall
fi
/etc/init.d/firewall reload 2>/dev/null || true
echo "  OK"

# ------------------------------------------------------------
#  6. Watchdog + cron
# ------------------------------------------------------------
echo ""
echo "[6/6] Установка watchdog (автоперезапуск при сбое)..."

cat > "$WATCHDOG_BIN" << 'WD'
#!/bin/sh
# Nikki watchdog: проверяет работоспособность mihomo, рестартит при сбое.
# Запускается раз в 5 минут через cron. Рестарт после 3 подряд провалов.

STATE=/tmp/nikki-watchdog.state
LOG=/var/log/nikki/watchdog.log
THRESHOLD=3

mkdir -p "$(dirname "$LOG")"

check_alive() {
    service nikki status 2>/dev/null | grep -q running || return 1
    pgrep mihomo >/dev/null || return 2
    curl -s -m 5 "http://127.0.0.1:9090/proxies/PROXY" 2>/dev/null \
        | grep -q '"alive":true' || return 3
    return 0
}

if check_alive; then
    rm -f "$STATE"
    exit 0
fi

REASON=$?
FAILS=$(cat "$STATE" 2>/dev/null || echo 0)
FAILS=$((FAILS + 1))
echo "$FAILS" > "$STATE"

NOW=$(date '+%Y-%m-%d %H:%M:%S')
echo "$NOW [WARN] check failed (reason=$REASON, consecutive=$FAILS)" >> "$LOG"

if [ "$FAILS" -ge "$THRESHOLD" ]; then
    echo "$NOW [ACTION] threshold reached, restarting nikki" >> "$LOG"
    service nikki restart >> "$LOG" 2>&1
    rm -f "$STATE"
fi
WD
chmod +x "$WATCHDOG_BIN"

# Cron: чистим старую запись, добавляем новую
( crontab -l 2>/dev/null | grep -v 'nikki-watchdog'; echo "*/5 * * * * $WATCHDOG_BIN" ) | crontab -
/etc/init.d/cron enable 2>/dev/null || true
/etc/init.d/cron restart 2>/dev/null || true
echo "  OK: $WATCHDOG_BIN, cron */5 минут"

# ------------------------------------------------------------
#  Запуск nikki
# ------------------------------------------------------------
echo ""
echo "  Запускаем nikki..."
/etc/init.d/nikki enable 2>/dev/null || true
/etc/init.d/nikki restart

echo ""
echo "========================================"
echo "  Готово!"
echo "========================================"
echo ""
echo "  Веб-панель:  http://192.168.1.1:9090/ui"
echo "  Статус:      service nikki status"
echo "  Логи:        cat /var/log/nikki/app.log"
echo "  Watchdog:    cat /var/log/nikki/watchdog.log"
echo ""
