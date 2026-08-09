#!/bin/sh
# ============================================================
#  Автообновление ядра mihomo с апстрима MetaCubeX
#
#  Зачем отдельный скрипт: фид OpenWrt отстаёт от апстрима на недели,
#  а apk обновить нечем. Ставим бинарник напрямую с GitHub.
#
#  Две ловушки, на которых это ломается (обе проверены на живом роутере):
#
#  1. Бинарник 44 МБ, а на flash свободно ~15 МБ. Положить новый рядом
#     со старым нельзя — сначала удаляем старый, потом пишем новый.
#
#  2. /tmp на OpenWrt — это RAM. Скачанный туда бинарник съедает 44 МБ
#     оперативной памяти, и ядру перестаёт её хватать. Симптом обманчивый:
#     не OOM, а "Timeout, TUN device is not online". Поэтому /tmp
#     освобождается ДО запуска nikki, а не после.
#
#  Порядок с проверкой на каждом шаге и откатом на пакетную версию:
#    скачать -> проверить -v и with_gvisor -> остановить -> заменить ->
#    освободить RAM -> тест конфига -> запустить -> проверить связь
#
#  Запуск: 20 5 * * * /usr/bin/mihomo-auto-update
# ============================================================

LOG=/root/router-updates.log
API=https://api.github.com/repos/MetaCubeX/mihomo/releases/latest
TARGET=/usr/libexec/mihomo
TMPBIN=/tmp/mihomo-new
# В КИЛОБАЙТАХ. busybox `free -m` игнорирует флаг и всё равно печатает КБ —
# сравнение с числом в мегабайтах всегда проходило, и проверка была мёртвой.
# Читаем MemAvailable напрямую. 60 МБ = запас на 44 МБ бинарника в tmpfs
# (он качается, пока ядро ещё работает) плюс небольшой резерв.
MIN_FREE_RAM_KB=61440

say() { echo "$*" >> "$LOG"; }
fail() { say "  ОТМЕНА: $*"; logger -t mihomo-update "отмена: $*"; rm -f "$TMPBIN" "$TMPBIN.gz"; exit 1; }

say ""
say "===== $(date '+%Y-%m-%d %H:%M:%S') обновление ядра mihomo ====="

# ── Архитектура ───────────────────────────────────────────
case "$(uname -m)" in
	aarch64) ARCH=linux-arm64 ;;
	armv7l)  ARCH=linux-armv7 ;;
	x86_64)  ARCH=linux-amd64 ;;
	*) fail "неизвестная архитектура $(uname -m)" ;;
esac

# ── Что стоит и что доступно ──────────────────────────────
CUR=$(/usr/bin/mihomo -v 2>/dev/null | head -1 | awk '{print $3}')
[ -z "$CUR" ] && fail "не удалось определить текущую версию"

NEW=$(curl -s --max-time 30 "$API" | sed -n 's/.*"tag_name" *: *"\([^"]*\)".*/\1/p' | head -1)
[ -z "$NEW" ] && fail "не удалось получить версию с GitHub (нет сети?)"

say "  установлено: $CUR, в апстриме: $NEW"
if [ "$CUR" = "$NEW" ]; then
	say "  уже актуальная версия"
	exit 0
fi

# ── Предусловия ───────────────────────────────────────────
/etc/init.d/nikki status 2>/dev/null | grep -q running \
	|| fail "nikki сейчас не работает — сначала разберись с этим"

FREE_RAM=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
[ "$FREE_RAM" -lt "$MIN_FREE_RAM_KB" ] 	&& fail "мало свободной памяти ($((FREE_RAM/1024))МБ, нужно $((MIN_FREE_RAM_KB/1024))МБ)"

# ── Скачивание в RAM, пока VPN ещё поднят ─────────────────
URL="https://github.com/MetaCubeX/mihomo/releases/download/${NEW}/mihomo-${ARCH}-${NEW}.gz"
rm -f "$TMPBIN" "$TMPBIN.gz"
curl -sL --max-time 300 -o "$TMPBIN.gz" "$URL" || fail "скачивание не удалось"
[ -s "$TMPBIN.gz" ] || fail "скачан пустой файл"
gunzip -f "$TMPBIN.gz" || fail "не удалось распаковать"
chmod +x "$TMPBIN"

# ── Проверка бинарника ДО замены ──────────────────────────
VER_OUT=$("$TMPBIN" -v 2>&1)
echo "$VER_OUT" | grep -q "$NEW"      || fail "скачанный бинарник не сообщает версию $NEW"
echo "$VER_OUT" | grep -q with_gvisor || fail "бинарник без with_gvisor — TUN-режим не заработает"
say "  скачан и проверен: $(echo "$VER_OUT" | head -1)"

# ── Замена ────────────────────────────────────────────────
/etc/init.d/nikki stop >/dev/null 2>&1
sleep 5

rm -f "$TARGET"
cp "$TMPBIN" "$TARGET" || {
	say "  копирование не удалось — восстанавливаю пакетную версию"
	apk fix mihomo-meta >/dev/null 2>&1
	/etc/init.d/nikki start >/dev/null 2>&1
	fail "не удалось записать новый бинарник"
}
chmod +x "$TARGET"
sync
rm -f "$TMPBIN"          # КРИТИЧНО: освободить RAM до запуска ядра
say "  заменён, свободно RAM: $(($(awk '/MemAvailable/{print $2}' /proc/meminfo)/1024))МБ, flash: $(df -h /overlay | awk 'NR==2{print $4}')"

rollback() {
	say "  ОТКАТ на пакетную версию: $*"
	logger -t mihomo-update "откат: $*"
	rm -f "$TARGET"
	apk fix mihomo-meta >/dev/null 2>&1
	/etc/init.d/nikki start >/dev/null 2>&1
	for i in $(seq 1 24); do
		sleep 5
		curl -s --max-time 4 http://127.0.0.1:9090/version >/dev/null 2>&1 && break
	done
	say "  после отката: nikki $(/etc/init.d/nikki status), $(/usr/bin/mihomo -v 2>/dev/null | head -1)"
	exit 1
}

# ── Тест конфига: теперь RAM свободна ─────────────────────
"$TARGET" -t -d /etc/nikki/run -f /etc/nikki/run/config.yaml >/dev/null 2>&1 \
	|| rollback "новая версия не приняла конфиг"

# ── Запуск и проверка ─────────────────────────────────────
/etc/init.d/nikki start >/dev/null 2>&1
UP=0
for i in $(seq 1 24); do
	sleep 5
	curl -s --max-time 4 http://127.0.0.1:9090/version >/dev/null 2>&1 && { UP=1; break; }
done
[ "$UP" = "1" ] || rollback "nikki не поднялся с новой версией"

NODE=$(curl -s --max-time 8 http://127.0.0.1:9090/proxies/AUTO 2>/dev/null | sed -n 's/.*"now":"\([^"]*\)".*/\1/p')
[ -n "$NODE" ] || rollback "нет активного VPN-узла"

[ "$(curl -sI -o /dev/null -w '%{http_code}' --max-time 15 http://speedtest.selectel.ru/10MB)" = "200" ] \
	|| rollback "нет интернета после обновления"

say "  ГОТОВО: $CUR -> $NEW, узел $NODE"
say "  (apk по-прежнему считает установленной пакетную версию — это ожидаемо)"
logger -t mihomo-update "обновлено $CUR -> $NEW, узел $NODE"
