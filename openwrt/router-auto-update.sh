#!/bin/sh
# ============================================================
#  Автоматическое обновление — только безопасный набор пакетов
#
#  Почему не «обновлять всё»: на OpenWrt пакеты собираются под конкретную
#  ревизию ядра. Обновление wpad/hostapd, netifd, dnsmasq, libubox, ubus,
#  nftables или kmod-* вслепую ломает Wi-Fi, сеть или загрузку — и откатить
#  это нечем, у apk нет транзакционного отката. Прошивка ставится только
#  через sysupgrade вручную.
#
#  Поэтому обновляем лишь то, поломка чего не роняет маршрутизацию и VPN:
#  LuCI (веб-интерфейс), ca-bundle (корневые сертификаты), owut.
#  Худший исход — перестал открываться веб-интерфейс, интернет при этом жив.
#
#  Защита на каждом шаге:
#    1. проверка свободного места на overlay
#    2. симуляция (apk -s) и отказ, если транзакция вышла за безопасный набор
#    3. резервная копия конфигурации перед установкой
#    4. проверка здоровья после и автовосстановление
#
#  Запуск: 10 5 * * * /usr/bin/router-auto-update
# ============================================================

LOG=/root/router-updates.log
BACKUP=/tmp/backup-pre-update.tar.gz   # /tmp = RAM: бэкап нужен только
                                       # на время этого запуска, а на flash
                                       # его 7 МБ стоили роутеру места, из-за
                                       # которого 18.08.2026 сорвался откат ядра.
                                       # Долгоживущие копии снимай снаружи:
                                       # ssh root@router 'sysupgrade -b /tmp/b.tar.gz
                                       # >/dev/null && cat /tmp/b.tar.gz; rm -f /tmp/b.tar.gz'
MIN_FREE_KB=10240          # не обновляться, если на overlay меньше 10 МБ
ALLOW='^(luci|ca-bundle|owut)'

say() { echo "$*" >> "$LOG"; }

say ""
say "===== $(date '+%Y-%m-%d %H:%M:%S') автообновление ====="

apk update >/dev/null 2>&1 || {
	say "  ОТМЕНА: не удалось обновить индексы (нет интернета?)"
	logger -t auto-update "отмена: нет доступа к репозиториям"
	exit 1
}

# ── 1. Кандидаты из безопасного набора ────────────────────
CAND=$(apk list --upgradable 2>/dev/null | sed 's/-[0-9].*//' | grep -E "$ALLOW" | sort -u | tr '\n' ' ')
if [ -z "$(echo "$CAND" | tr -d ' ')" ]; then
	say "  нечего обновлять в безопасном наборе"
	exit 0
fi
say "  кандидаты: $(echo "$CAND" | wc -w) шт"

# ── 2. Место на flash ─────────────────────────────────────
FREE_KB=$(df /overlay | awk 'NR==2 {print $4}')
if [ "$FREE_KB" -lt "$MIN_FREE_KB" ]; then
	say "  ОТМЕНА: на overlay свободно ${FREE_KB}КБ, нужно минимум ${MIN_FREE_KB}КБ"
	logger -t auto-update "отмена: мало места на flash (${FREE_KB}КБ)"
	exit 1
fi

# ── 3. Симуляция: не вылезает ли транзакция за безопасный набор ──
SIM=$(apk upgrade -s $CAND 2>&1)
ESCAPED=$(echo "$SIM" | sed -n 's/^([ 0-9]*\/[ 0-9]*) *\(Upgrading\|Installing\|Replacing\) \([^ ]*\).*/\2/p' \
	| grep -vE "$ALLOW" | sort -u)
if [ -n "$ESCAPED" ]; then
	say "  ОТМЕНА: обновление затронуло бы пакеты вне безопасного набора:"
	echo "$ESCAPED" | sed 's/^/    /' >> "$LOG"
	say "  (это ядро/сеть/драйверы — ставить их автоматически нельзя, обнови вручную)"
	logger -t auto-update "отмена: транзакция вышла за безопасный набор"
	exit 1
fi

# ── 4. Резервная копия конфигурации ───────────────────────
if sysupgrade -b "$BACKUP" >/dev/null 2>&1; then
	say "  бэкап конфигурации: $BACKUP ($(du -h "$BACKUP" | cut -f1))"
else
	say "  ОТМЕНА: не удалось сделать бэкап конфигурации"
	logger -t auto-update "отмена: бэкап не создан"
	exit 1
fi

# ── 5. Установка ──────────────────────────────────────────
say "  устанавливаю..."
if apk upgrade $CAND >/tmp/auto-update.out 2>&1; then
	sed -n 's/^([ 0-9]*\/[ 0-9]*) *//p' /tmp/auto-update.out | sed 's/^/    /' >> "$LOG"
	say "  установлено успешно"
	RESULT=ok
else
	say "  ОШИБКА установки:"
	tail -10 /tmp/auto-update.out | sed 's/^/    /' >> "$LOG"
	RESULT=fail
fi

# ── 6. Проверка здоровья и восстановление ─────────────────
# Проверки именно на код ответа, а не на «curl не упал»: 404 или 403 тоже
# завершаются успешно, и такая проверка молча пропустила бы поломку.
# LuCI на /cgi-bin/luci/ штатно отдаёт 403 без сессии — берём корень, там 200.
health() {
	PROBLEMS=""
	ip route | grep -q '^default' || PROBLEMS="$PROBLEMS маршрут"
	/etc/init.d/nikki status 2>/dev/null | grep -q running || PROBLEMS="$PROBLEMS nikki"
	[ "$(curl -sI -o /dev/null -w '%{http_code}' --max-time 10 http://speedtest.selectel.ru/10MB)" = "200" ] \
		|| PROBLEMS="$PROBLEMS интернет"
	curl -s --max-time 15 "http://127.0.0.1:9090/proxies/AUTO/delay?timeout=8000&url=http%3A%2F%2Fwww.gstatic.com%2Fgenerate_204" \
		2>/dev/null | grep -q '"delay"' || PROBLEMS="$PROBLEMS VPN"
	[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 http://127.0.0.1/)" = "200" ] \
		|| PROBLEMS="$PROBLEMS веб-интерфейс"
}

health

if [ -z "$PROBLEMS" ]; then
	say "  проверка здоровья: всё в порядке"
else
	say "  ПРОБЛЕМЫ после обновления:$PROBLEMS — восстанавливаю"
	logger -t auto-update "проблемы после обновления:$PROBLEMS"

	case "$PROBLEMS" in *веб-интерфейс*) /etc/init.d/rpcd restart >/dev/null 2>&1
	                                     /etc/init.d/uhttpd restart >/dev/null 2>&1 ;; esac
	case "$PROBLEMS" in *маршрут*|*интернет*) /etc/init.d/network restart >/dev/null 2>&1; sleep 20 ;; esac
	case "$PROBLEMS" in *nikki*|*интернет*|*VPN*) /etc/init.d/nikki restart >/dev/null 2>&1; sleep 25 ;; esac

	health
	STILL="$PROBLEMS"
	if [ -z "$STILL" ]; then
		say "  восстановление удалось"
		logger -t auto-update "восстановление удалось"
	else
		say "  !!! НЕ ВОССТАНОВЛЕНО:$STILL"
		say "  !!! откат конфигурации: sysupgrade -r $BACKUP && reboot"
		logger -t auto-update "КРИТИЧНО: не восстановлено:$STILL"
	fi
fi

logger -t auto-update "обновление $RESULT, пакетов: $(echo "$CAND" | wc -w)"
