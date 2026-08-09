#!/bin/sh
# ============================================================
#  Ежедневная проверка обновлений роутера
#
#  ТОЛЬКО ПРОВЕРЯЕТ — ничего не устанавливает. Причина: на OpenWrt
#  `apk upgrade` тянет пакеты, собранные под другую ревизию ядра,
#  что ломает драйверы Wi-Fi и может забить overlay (у нас 23 МБ
#  свободно). Прошивка обновляется только через sysupgrade вручную.
#
#  Отчёт: /root/router-updates.log + системный лог (LuCI -> Status -> System Log)
#  Запуск: 0 5 * * * /usr/bin/router-update-check
# ============================================================

LOG=/root/router-updates.log
TS=$(date '+%Y-%m-%d %H:%M:%S')

# лог не должен расти бесконечно
if [ -f "$LOG" ]; then
	tail -n 400 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
fi

{
	echo ""
	echo "===== $TS ====="
} >> "$LOG"

# ── 1. Пакеты ─────────────────────────────────────────────
if apk update >/dev/null 2>&1; then
	PKGS=$(apk list --upgradable 2>/dev/null | grep -c '')
	echo "Пакеты: доступно обновлений — $PKGS" >> "$LOG"
	if [ "$PKGS" -gt 0 ]; then
		apk list --upgradable 2>/dev/null | sed 's/ .*//; s/^/  /' >> "$LOG"
	fi
else
	PKGS="?"
	echo "Пакеты: ОШИБКА — не удалось обновить индексы (нет интернета?)" >> "$LOG"
fi

# ── 2. Прошивка ───────────────────────────────────────────
FW=$(owut check 2>&1)
FROM=$(echo "$FW" | awk '/^Version-from/ {print $2, $3}')
TO=$(echo "$FW"   | awk '/^Version-to/   {print $2, $3}')
echo "Прошивка: $FROM  ->  $TO" >> "$LOG"

if echo "$FW" | grep -q 'cannot upgrade'; then
	echo "  ОБНОВЛЕНИЕ ЗАБЛОКИРОВАНО — эти пакеты отсутствуют в целевой версии:" >> "$LOG"
	owut check --verbose 2>&1 | grep 'missing to-version' | sed 's/^/  /' >> "$LOG"
	echo "  (это пакеты nikki/mihomo из кастомного фида — ждём, пока фид" >> "$LOG"
	echo "   соберёт их под новую версию, иначе обновление снесёт VPN)" >> "$LOG"
	FWSTATE="заблокировано"
elif [ "$FROM" = "$TO" ]; then
	FWSTATE="актуальна"
else
	echo "  Можно обновляться: owut upgrade (или LuCI -> Attended Sysupgrade)" >> "$LOG"
	FWSTATE="доступно $TO"
fi

# ── 3. Geo-базы mihomo (обновляет само ядро, интервал в UCI) ──
GEO_INT=$(uci get nikki.mixin.geox_update_interval 2>/dev/null)
GEO_MTIME=$(date -r /etc/mihomo/geosite.dat +%s 2>/dev/null || echo 0)
GEO_AGE=$(( ($(date +%s) - GEO_MTIME) / 3600 ))
echo "Geo-базы: интервал ${GEO_INT}ч, возраст geosite.dat ${GEO_AGE}ч" >> "$LOG"

# ── 4. Состояние VPN ──────────────────────────────────────
NIKKI=$(/etc/init.d/nikki status 2>/dev/null)
NODE=$(curl -s --max-time 5 http://127.0.0.1:9090/proxies/AUTO 2>/dev/null \
	| sed -n 's/.*"now":"\([^"]*\)".*/\1/p')
echo "VPN: nikki=$NIKKI, активный узел=${NODE:-неизвестно}" >> "$LOG"

# ── Сводка в системный лог ────────────────────────────────
logger -t update-check "пакетов: $PKGS; прошивка: $FWSTATE; nikki: $NIKKI; узел: ${NODE:-?}"
