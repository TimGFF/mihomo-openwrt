#!/bin/sh
# ============================================================
#  Установка Mihomo на OpenWrt (прозрачный VPN-прокси)
#
#  Поддержка: aarch64, armv7, x86_64, mips/mipsel
#  Запуск: sh /tmp/install_mihomo.sh
# ============================================================

set -e

MIHOMO_VERSION="v1.19.20"
MIHOMO_BASE="https://github.com/MetaCubeX/mihomo/releases/download/${MIHOMO_VERSION}"
GEODATA_BASE="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest"
WORKDIR="/etc/mihomo"

echo ""
echo "========================================"
echo "  Mihomo Install для OpenWrt"
echo "  Версия: ${MIHOMO_VERSION}"
echo "========================================"
echo ""

# ============================================================
#  1. ЗАВИСИМОСТИ
# ============================================================
echo "[1/6] Установка зависимостей..."
opkg update 2>/dev/null | tail -1 || true
for pkg in kmod-tun kmod-inet-diag ca-bundle ca-certificates; do
    opkg install "$pkg" 2>/dev/null && echo "  + $pkg" || echo "  ~ $pkg (уже установлен)"
done

# ============================================================
#  2. ОПРЕДЕЛЕНИЕ АРХИТЕКТУРЫ
# ============================================================
echo ""
echo "[2/6] Определение архитектуры..."
ARCH=$(uname -m)
echo "  Архитектура: $ARCH"

case "$ARCH" in
    x86_64)   MIHOMO_FILE="mihomo-linux-amd64-${MIHOMO_VERSION}.gz" ;;
    aarch64)  MIHOMO_FILE="mihomo-linux-arm64-${MIHOMO_VERSION}.gz" ;;
    armv7l|armv7) MIHOMO_FILE="mihomo-linux-armv7-${MIHOMO_VERSION}.gz" ;;
    armv6l|armv6) MIHOMO_FILE="mihomo-linux-armv6-${MIHOMO_VERSION}.gz" ;;
    mips)     MIHOMO_FILE="mihomo-linux-mips-hardfloat-${MIHOMO_VERSION}.gz" ;;
    mipsel)   MIHOMO_FILE="mihomo-linux-mipsle-hardfloat-${MIHOMO_VERSION}.gz" ;;
    mips64)   MIHOMO_FILE="mihomo-linux-mips64-${MIHOMO_VERSION}.gz" ;;
    *)
        echo "ОШИБКА: Архитектура '$ARCH' не поддерживается."
        echo "Скачай бинарник вручную: ${MIHOMO_BASE}/"
        exit 1
        ;;
esac
echo "  Файл: $MIHOMO_FILE"

# ============================================================
#  3. СКАЧИВАНИЕ MIHOMO
# ============================================================
echo ""
echo "[3/6] Скачивание Mihomo ${MIHOMO_VERSION}..."
cd /tmp
rm -f /tmp/mihomo.gz /tmp/mihomo 2>/dev/null || true

if wget -q -O /tmp/mihomo.gz "${MIHOMO_BASE}/${MIHOMO_FILE}"; then
    gunzip -f /tmp/mihomo.gz
    mv /tmp/mihomo /usr/bin/mihomo
    chmod +x /usr/bin/mihomo
    echo "  OK: $(/usr/bin/mihomo -v 2>/dev/null | head -1)"
else
    # Для MIPS: пробуем без hardfloat
    if echo "$ARCH" | grep -q "^mips"; then
        ALT_FILE=$(echo "$MIHOMO_FILE" | sed 's/-hardfloat//')
        echo "  Пробуем без hardfloat: $ALT_FILE"
        wget -q -O /tmp/mihomo.gz "${MIHOMO_BASE}/${ALT_FILE}"
        gunzip -f /tmp/mihomo.gz
        mv /tmp/mihomo /usr/bin/mihomo
        chmod +x /usr/bin/mihomo
        echo "  OK: $(/usr/bin/mihomo -v 2>/dev/null | head -1)"
    else
        echo "ОШИБКА: Не удалось скачать Mihomo. Проверь интернет на роутере."
        exit 1
    fi
fi

# ============================================================
#  4. ДИРЕКТОРИИ И БАЗЫ ДАННЫХ
# ============================================================
echo ""
echo "[4/6] Скачивание баз данных GeoIP/GeoSite..."
mkdir -p ${WORKDIR}/proxies ${WORKDIR}/ui

# GeoIP (нужна для правила GEOIP,RU,DIRECT)
if [ ! -f "${WORKDIR}/geoip.metadb" ]; then
    echo "  Скачивание geoip.metadb (~9 MB)..."
    wget -q -O "${WORKDIR}/geoip.metadb" "${GEODATA_BASE}/geoip.metadb" \
        && echo "  OK: geoip.metadb" \
        || echo "  ПРЕДУПРЕЖДЕНИЕ: не удалось скачать geoip.metadb"
else
    echo "  OK: geoip.metadb (уже есть)"
fi

# GeoSite (нужна для GEOSITE,tld-ru и category-ru)
if [ ! -f "${WORKDIR}/geosite.dat" ]; then
    echo "  Скачивание geosite.dat (~4 MB)..."
    wget -q -O "${WORKDIR}/geosite.dat" "${GEODATA_BASE}/geosite.dat" \
        && echo "  OK: geosite.dat" \
        || echo "  ПРЕДУПРЕЖДЕНИЕ: не удалось скачать geosite.dat"
else
    echo "  OK: geosite.dat (уже есть)"
fi

# MetaCubeXD — веб-панель управления (опционально)
if [ ! -f "${WORKDIR}/ui/index.html" ]; then
    echo "  Скачивание MetaCubeXD (веб-панель)..."
    if wget -q -O /tmp/metacubexd.tgz \
        "https://github.com/MetaCubeX/metacubexd/releases/latest/download/compressed-dist.tgz" 2>/dev/null; then
        tar -xzf /tmp/metacubexd.tgz -C "${WORKDIR}/ui/" 2>/dev/null || true
        rm -f /tmp/metacubexd.tgz
        echo "  OK: MetaCubeXD -> http://192.168.1.1:9090/ui"
    else
        echo "  (MetaCubeXD пропущен - можно установить позже)"
    fi
else
    echo "  OK: MetaCubeXD (уже есть)"
fi

# ============================================================
#  5. СЕРВИС /etc/init.d/mihomo
# ============================================================
echo ""
echo "[5/6] Создание сервиса /etc/init.d/mihomo..."

cat > /etc/init.d/mihomo << 'INITEOF'
#!/bin/sh /etc/rc.common
START=99
STOP=10
USE_PROCD=1

PROG=/usr/bin/mihomo
WORKDIR=/etc/mihomo

cleanup() {
    ip link delete Meta 2>/dev/null || true
    nft delete table inet mihomo 2>/dev/null || true
    while ip rule show | grep -q 'lookup 2022'; do
        ip rule del table 2022 2>/dev/null || break
    done
    ip route flush table 2022 2>/dev/null || true
    ip route del 198.18.0.0/16 2>/dev/null || true
    sleep 1
}

setup_redirect() {
    local i=0
    while [ $i -lt 30 ]; do
        ip link show Meta >/dev/null 2>&1 && break
        sleep 1
        i=$((i+1))
    done
    sleep 1
    ip route add 198.18.0.0/16 dev Meta 2>/dev/null || true
    logger -t mihomo "fake-ip route 198.18.0.0/16 -> Meta"
    nft add table inet mihomo
    nft add chain inet mihomo prerouting '{ type nat hook prerouting priority dstnat + 1; policy accept; }'
    nft add rule inet mihomo prerouting 'iifname "Meta" return'
    nft add rule inet mihomo prerouting 'ip daddr { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10 } return'
    nft add rule inet mihomo prerouting 'meta nfproto ipv4 meta l4proto tcp redirect to :7891'
    logger -t mihomo "nftables: LAN TCP -> :7891 OK"
}

start_service() {
    cleanup

    # Авто-определение WAN интерфейса (ждём до 60 сек после загрузки)
    local i=0
    local wan_if=""
    while [ $i -lt 60 ]; do
        wan_if=$(ip route show default 2>/dev/null | awk 'NR==1{print $5}')
        [ -n "$wan_if" ] && [ "$wan_if" != "lo" ] && [ "$wan_if" != "Meta" ] && break
        wan_if=""
        sleep 1
        i=$((i+1))
    done

    # Обновляем interface-name в конфиге (привязывает VLESS к WAN, предотвращает routing loop)
    if [ -n "$wan_if" ]; then
        sed -i "s/interface-name: .*/interface-name: $wan_if/" /etc/mihomo/config.yaml
        logger -t mihomo "WAN interface: $wan_if"
    else
        logger -t mihomo "WARN: WAN не найден за 60 сек, interface-name не обновлён"
    fi

    mkdir -p /etc/mihomo/proxies
    procd_open_instance
    procd_set_param command $PROG -d $WORKDIR
    procd_set_param respawn 3600 5 5
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

stop_service() {
    killall mihomo 2>/dev/null || true
    sleep 2
    cleanup
}

service_started() {
    setup_redirect
}

reload_service() {
    stop
    sleep 2
    start
}
INITEOF

chmod +x /etc/init.d/mihomo
/etc/init.d/mihomo enable
echo "  OK: сервис создан и включён в автозапуск"

# ============================================================
#  6. НАСТРОЙКА DNSMASQ И FIREWALL
# ============================================================
echo ""
echo "[6/6] Настройка dnsmasq и firewall..."

# dnsmasq -> mihomo DNS (127.0.0.1:1053)
uci set dhcp.@dnsmasq[0].noresolv='1'
uci set dhcp.@dnsmasq[0].cachesize='0'
uci -q del dhcp.@dnsmasq[0].server 2>/dev/null || true
uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#1053'
uci commit dhcp
/etc/init.d/dnsmasq restart 2>/dev/null || true
echo "  OK: dnsmasq -> 127.0.0.1#1053"

# Firewall: порт 9090 для веб-панели
if ! uci show firewall 2>/dev/null | grep -q "Allow-Mihomo-Dashboard"; then
    uci add firewall rule >/dev/null
    uci set firewall.@rule[-1].name='Allow-Mihomo-Dashboard'
    uci set firewall.@rule[-1].src='lan'
    uci set firewall.@rule[-1].dest_port='9090'
    uci set firewall.@rule[-1].proto='tcp'
    uci set firewall.@rule[-1].target='ACCEPT'
    uci commit firewall
    /etc/init.d/firewall reload 2>/dev/null || true
    echo "  OK: firewall -> порт 9090 открыт"
else
    echo "  OK: firewall rule (уже есть)"
fi

echo ""
echo "========================================"
echo "  Mihomo установлен!"
echo "========================================"
echo ""
