#!/bin/sh
# ============================================================
#  Автообновление ядра mihomo с апстрима MetaCubeX
#
#  Зачем отдельный скрипт: фид OpenWrt отстаёт от апстрима на недели,
#  а apk обновить нечем. Ставим бинарник напрямую с GitHub.
#
#  Три ловушки, на которых это ломается (все проверены на живом роутере):
#
#  1. Бинарник 44 МБ, а на flash свободно ~15 МБ. Положить новый рядом
#     со старым нельзя — сначала удаляем старый, потом пишем новый.
#
#  2. /tmp на OpenWrt — это RAM. Скачанный туда бинарник съедает 44 МБ
#     оперативной памяти, и ядру перестаёт её хватать. Симптом обманчивый:
#     не OOM, а "Timeout, TUN device is not online". Поэтому /tmp
#     освобождается ДО запуска nikki, а не после.
#
#  3. Откат нельзя строить на `apk fix`: пакет живёт в кастомном фиде,
#     который бывает недоступен, и apk тогда молча пропускает установку.
#     17.08.2026 из-за этого роутер остался вообще без ядра на 38 часов.
#     Откатываемся на gzip-копию работающего бинарника в /tmp.
#
#  Порядок с проверкой на каждом шаге и откатом на сохранённую копию:
#    скачать -> проверить -v и with_gvisor -> остановить -> сохранить копию ->
#    заменить -> освободить RAM -> тест конфига -> запустить -> проверить связь
#
#  Запуск: 20 5 * * * /usr/bin/mihomo-auto-update
# ============================================================

LOG=/root/router-updates.log
API=https://api.github.com/repos/MetaCubeX/mihomo/releases/latest
TARGET=/usr/libexec/mihomo
TMPBIN=/tmp/mihomo-new
PREVBIN=/tmp/mihomo-prev.gz    # копия работающего ядра на время замены
BADLIST=/etc/nikki/bad-core-versions   # версии, не заработавшие на этом роутере
# В КИЛОБАЙТАХ. busybox `free -m` игнорирует флаг и всё равно печатает КБ —
# сравнение с числом в мегабайтах всегда проходило, и проверка была мёртвой.
# Читаем MemAvailable напрямую. 60 МБ = 44 МБ нового бинарника в tmpfs
# (качается, пока ядро ещё работает) плюс 16 МБ резерва.
# gzip-копия старого ядра для отката сюда не входит: она создаётся уже ПОСЛЕ
# остановки nikki, а это освобождает ~67 МБ его RSS.
MIN_FREE_RAM_KB=61440
MIN_FREE_FLASH_KB=15360   # 15 МБ — запас на двойную запись ядра при откате

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

# Версия, детерминированно завернувшая конфиг, будет заворачивать его и завтра,
# и послезавтра. Без этого списка роутер ронял бы VPN на пару минут каждую ночь
# ради заведомо провальной попытки. Разблокировать: удалить строку из файла.
if [ -f "$BADLIST" ] && grep -qx "$NEW" "$BADLIST"; then
	say "  $NEW уже проваливала проверку на этом роутере — пропускаю"
	exit 0
fi

# ── Предусловия ───────────────────────────────────────────
/etc/init.d/nikki status 2>/dev/null | grep -q running \
	|| fail "nikki сейчас не работает — сначала разберись с этим"

free_ram() { awk '/MemAvailable/{print $2}' /proc/meminfo; }

# RSS ядра растёт за сутки с ~55 до ~75 МБ, и к 05:20 свободной памяти обычно
# уже меньше порога. Без этого сброса обновление молча отменялось бы каждую
# ночь — «безопасно», но ядро не обновлялось бы никогда.
# Перезапуск здесь ничего не стоит сверх: ниже nikki всё равно останавливается.
FREE_RAM=$(free_ram)
if [ "$FREE_RAM" -lt "$MIN_FREE_RAM_KB" ]; then
	say "  памяти $((FREE_RAM/1024))МБ — перезапускаю ядро, чтобы сбросить RSS"
	/etc/init.d/nikki restart >/dev/null 2>&1
	for i in $(seq 1 24); do
		sleep 5
		curl -s --max-time 4 http://127.0.0.1:9090/version >/dev/null 2>&1 && break
	done
	FREE_RAM=$(free_ram)
	say "  после перезапуска: $((FREE_RAM/1024))МБ"
fi
[ "$FREE_RAM" -lt "$MIN_FREE_RAM_KB" ] 	&& fail "мало свободной памяти ($((FREE_RAM/1024))МБ, нужно $((MIN_FREE_RAM_KB/1024))МБ)"

# Ядро занимает на flash ~19 МБ после сжатия UBIFS, и записывается оно дважды:
# новое при замене, старое при откате. UBIFS освобождает удалённые блоки не
# мгновенно, поэтому нужен запас. 18.08.2026 при 7.9 МБ свободных откат записал
# обрезанный бинарник — роутер остался без рабочего ядра.
FREE_FLASH=$(df -k /overlay | awk 'NR==2{print $4}')
[ "$FREE_FLASH" -lt "$MIN_FREE_FLASH_KB" ] \
	&& fail "мало места на flash ($((FREE_FLASH/1024))МБ, нужно $((MIN_FREE_FLASH_KB/1024))МБ) — откат не смог бы записать старое ядро"

# ── Скачивание в RAM, пока VPN ещё поднят ─────────────────
# Распаковываем на лету, а не через файл .gz: иначе архив (16 МБ) и
# распакованный бинарник (44 МБ) одновременно лежат в tmpfs, и пик выходит
# 60 МБ вместо 44 — при MemAvailable, который тут гуляет в районе 60–100 МБ,
# это разница между «обновилось» и «OOM убил ядро».
URL="https://github.com/MetaCubeX/mihomo/releases/download/${NEW}/mihomo-${ARCH}-${NEW}.gz"
rm -f "$TMPBIN" "$TMPBIN.gz"
curl -sL --max-time 300 "$URL" | gunzip -c > "$TMPBIN"
[ -s "$TMPBIN" ] || fail "скачивание или распаковка не удались"
chmod +x "$TMPBIN"

# ── Проверка бинарника ДО замены ──────────────────────────
VER_OUT=$("$TMPBIN" -v 2>&1)
echo "$VER_OUT" | grep -q "$NEW"      || fail "скачанный бинарник не сообщает версию $NEW"
echo "$VER_OUT" | grep -q with_gvisor || fail "бинарник без with_gvisor — TUN-режим не заработает"
say "  скачан и проверен: $(echo "$VER_OUT" | head -1)"

# Восстановить прежнее ядро из копии. Порядок попыток — от надёжного
# к отчаянному. Возвращает 0, только если на выходе есть рабочий бинарник.
restore_prev() {
	rm -f "$TARGET"
	# Освобождаем заведомо восстановимое: cache.db — это кэш соединений mihomo,
	# он пересоздаётся сам. 18.08.2026 откату не хватило места на flash, gunzip
	# записал обрезанный бинарник, и роутер остался с нерабочим ядром.
	rm -f /etc/nikki/run/cache.db
	sync
	if [ -s "$PREVBIN" ] && gunzip -c "$PREVBIN" > "$TARGET" 2>/dev/null; then
		chmod +x "$TARGET"
		sync
		"$TARGET" -v >/dev/null 2>&1 && { say "  ядро восстановлено из копии"; return 0; }
	fi
	say "  копия не сработала — пробую apk fix (шанс мал: кастомный фид)"
	apk fix mihomo-meta 2>&1 | tail -2 >> "$LOG"
	[ -x "$TARGET" ] && "$TARGET" -v >/dev/null 2>&1 && return 0
	return 1
}

# Если ядра нет, DNS роутера (dnsmasq -> 127.0.0.1:1053) мёртв, и роутер
# не может даже скачать себе замену. Переводим резолвер на аплинк,
# чтобы машина осталась чинибельной по сети.
dns_failsafe() {
	WANDNS=$(ubus call network.interface.wan status 2>/dev/null | jsonfilter -e '@["dns-server"][0]')
	[ -z "$WANDNS" ] && WANDNS=1.1.1.1
	echo "nameserver $WANDNS" > /tmp/resolv.conf
	say "  DNS переведён на $WANDNS — иначе роутер недостижим по именам"
}

# rollback bad  — провал воспроизводимый, версию заносим в чёрный список
# rollback keep — провал мог быть случайным (сеть моргнула), завтра пробуем снова
rollback() {
	MODE=$1; shift
	say "  ОТКАТ: $*"
	logger -t mihomo-update "откат: $*"
	if [ "$MODE" = bad ]; then
		echo "$NEW" >> "$BADLIST"
		say "  $NEW занесена в $BADLIST — повторных попыток не будет"
	fi
	if restore_prev; then
		/etc/init.d/nikki start >/dev/null 2>&1
		for i in $(seq 1 24); do
			sleep 5
			curl -s --max-time 4 http://127.0.0.1:9090/version >/dev/null 2>&1 && break
		done
	else
		say "  !!! ЯДРА НЕТ. VPN не работает, нужно вмешательство руками."
		logger -t mihomo-update "КРИТИЧНО: ядро не восстановлено"
		dns_failsafe
	fi
	rm -f "$PREVBIN"
	say "  после отката: nikki $(/etc/init.d/nikki status), $(/usr/bin/mihomo -v 2>/dev/null | head -1)"
	exit 1
}

# ── Замена ────────────────────────────────────────────────
/etc/init.d/nikki stop >/dev/null 2>&1
sleep 5

# Копия работающего ядра — ЕДИНСТВЕННЫЙ надёжный путь отката.
# `apk fix` бесполезен: mihomo-meta живёт в кастомном фиде, который бывает
# недоступен, и тогда apk молча пишет "[APK unavailable, skipped]".
# 17.08.2026 это оставило роутер вообще без ядра на 38 часов.
# Копия в /tmp (RAM): на flash её положить некуда, там ~9 МБ свободно.
rm -f "$PREVBIN"
gzip -c "$TARGET" > "$PREVBIN" || {
	/etc/init.d/nikki start >/dev/null 2>&1
	fail "не удалось сохранить копию текущего ядра — обновление отменено"
}

rm -f "$TARGET"
cp "$TMPBIN" "$TARGET" || {
	say "  копирование не удалось"
	restore_prev
	/etc/init.d/nikki start >/dev/null 2>&1
	fail "не удалось записать новый бинарник"
}
chmod +x "$TARGET"
sync
rm -f "$TMPBIN"          # КРИТИЧНО: освободить RAM до запуска ядра
say "  заменён, свободно RAM: $(($(awk '/MemAvailable/{print $2}' /proc/meminfo)/1024))МБ, flash: $(df -h /overlay | awk 'NR==2{print $4}')"

# ── Тест конфига: теперь RAM свободна ─────────────────────
# Загрузка geosite — самый прожорливый момент за весь цикл. Отдаём ядру
# страничный кэш: он всё равно перечитается, а разница между 99 и 115 МБ
# здесь решает, переживёт тест или его снимет OOM.
sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
say "  перед тестом конфига свободно: $(($(free_ram)/1024))МБ"

# Вывод НЕ выбрасываем: 17.08.2026 причина ушла в /dev/null, и разбираться
# было не с чем — версию списали как «не приняла конфиг», хотя её убил OOM.
# GOMEMLIMIT — мягкий потолок кучи для Go. Без него сборщик мусора растит кучу,
# пока хватает памяти, и на загрузке geosite `cn` (её mihomo тянет всегда, это
# зашито в ядро) роутер ловит OOM: 125 МБ свободных не хватало, 129 хватало.
# С потолком GC работает агрессивнее и пик держится ниже границы.
if ! GOGC=30 GOMEMLIMIT=90MiB "$TARGET" -t -d /etc/nikki/run -f /etc/nikki/run/config.yaml > /tmp/cfgtest.log 2>&1; then
	# Код возврата конвейера — это код ПОСЛЕДНЕЙ команды, поэтому
	# `grep ... | tail ... || запасной_вариант` никогда не срабатывает:
	# tail всегда возвращает 0. Проверено 18.08.2026 — причина потерялась.
	CFGERR=$(grep -iE "level=(error|fatal)|invalid|unsupported|unmarshal" /tmp/cfgtest.log)
	[ -z "$CFGERR" ] && CFGERR=$(tail -8 /tmp/cfgtest.log)
	say "  причина отказа конфига:"
	echo "$CFGERR" | tail -8 | sed 's/^/    /' >> "$LOG"
	cp /tmp/cfgtest.log "/tmp/cfgtest-$NEW.log"   # полный вывод до перезагрузки

	# "Killed" в выводе — это OOM, а не претензия к конфигу. Версия не виновата,
	# виновата нехватка памяти здесь и сейчас. В чёрный список НЕ заносим,
	# иначе навсегда отказываемся от, возможно, полностью рабочей версии.
	if grep -q "Killed" /tmp/cfgtest.log; then
		rm -f /tmp/cfgtest.log
		rollback keep "тест конфига убит OOM — это нехватка памяти, не вина версии"
	fi
	rm -f /tmp/cfgtest.log
	rollback bad "новая версия не приняла конфиг"
fi
rm -f /tmp/cfgtest.log

# ── Запуск и проверка ─────────────────────────────────────
/etc/init.d/nikki start >/dev/null 2>&1
UP=0
for i in $(seq 1 24); do
	sleep 5
	curl -s --max-time 4 http://127.0.0.1:9090/version >/dev/null 2>&1 && { UP=1; break; }
done
[ "$UP" = "1" ] || rollback bad "nikki не поднялся с новой версией"

NODE=$(curl -s --max-time 8 http://127.0.0.1:9090/proxies/AUTO 2>/dev/null | sed -n 's/.*"now":"\([^"]*\)".*/\1/p')
[ -n "$NODE" ] || rollback keep "нет активного VPN-узла"

[ "$(curl -sI -o /dev/null -w '%{http_code}' --max-time 15 http://speedtest.selectel.ru/10MB)" = "200" ] \
	|| rollback keep "нет интернета после обновления"

rm -f "$PREVBIN"
say "  ГОТОВО: $CUR -> $NEW, узел $NODE"
say "  (apk по-прежнему считает установленной пакетную версию — это ожидаемо)"
logger -t mihomo-update "обновлено $CUR -> $NEW, узел $NODE"
