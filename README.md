# Прозрачный VPN на роутере OpenWrt + Nikki (Mihomo)

**YouTube, Instagram, TikTok работают автоматически** на всех устройствах в сети — телефоне, ТВ, ноутбуке. Российские сайты (VK, Яндекс, RuTube) открываются напрямую без VPN.

---

## С чего начать?

### Вариант 1: У тебя уже стоит OpenWrt

→ Перейди к **[Быстрый старт](#быстрый-старт)** ниже.

### Вариант 2: Роутер новый (стоит прошивка Xiaomi)

Сначала нужно установить OpenWrt:

→ **[Инструкция по установке OpenWrt на Xiaomi AX3000T](docs/install-openwrt-ax3000t.md)**

После установки OpenWrt и `luci-app-nikki` возвращайся сюда.

### Вариант 3: У тебя другой роутер

Установи OpenWrt с [официального сайта](https://firmware-selector.openwrt.org/), затем через SSH:
```sh
# OpenWrt 24.10:
opkg update && opkg install luci-app-nikki curl

# OpenWrt 25.12+:
apk update && apk add luci-app-nikki curl
```
И возвращайся к **[Быстрый старт](#быстрый-старт)**.

---

## Как это работает

```
  Телефон / ТВ / ПК
         │
      [Роутер OpenWrt + Nikki]
         │                         │
    youtube.com  →→→  [VPN сервер]  →→→  YouTube
    vk.com       →→→  Напрямую (без VPN)
```

**Nikki** (luci-app-nikki) управляет [Mihomo](https://github.com/MetaCubeX/mihomo) на роутере. Mihomo перехватывает весь трафик, смотрит куда идёт соединение и выбирает маршрут по правилам — через VPN или напрямую. Устройства в сети ничего не знают о VPN.

---

## Что нужно

| Что | Детали |
|-----|--------|
| **Роутер** | OpenWrt 24.x + luci-app-nikki |
| **Компьютер** | Windows 10/11 (SSH встроен) |
| **VPN** | VLESS Reality сервер **или** подписка в mihomo/clash формате |

> Протестировано: Xiaomi AX3000T (OpenWrt 24.10.0, aarch64_cortex-a53)

---

## Быстрый старт

### Шаг 1: Скачай репозиторий

```powershell
git clone https://github.com/TimGFF/mihomo-openwrt.git
cd mihomo-openwrt
```

Или нажми **Code → Download ZIP** и распакуй.

---

### Шаг 2: Заполни данные VPN

Открой **`mihomo/config.yaml`** в любом текстовом редакторе (Блокнот, VS Code, Notepad++).

#### Вариант Б: Ручная VLESS-ссылка (по умолчанию, активный)

В профиле уже есть пример с **двумя серверами в fallback-группе** (NL основной, DE резервный — при отказе одного автоматически переключается на другой). Найди секцию `proxies:` и замени данные на свои:

```yaml
proxies:
  - name: "NL"
    server: YOUR_SERVER          # ← адрес сервера (основной)
    uuid: YOUR_UUID
    servername: YOUR_SNI
    reality-opts:
      public-key: YOUR_PUBLIC_KEY
      short-id: YOUR_SHORT_ID

  - name: "DE"
    # … второй сервер для резерва. Можно удалить эту запись
    # и убрать "DE" из proxy-groups.PROXY если он не нужен.
```

**Как разобрать vless:// ссылку:**

```
vless://UUID@SERVER:PORT?pbk=PUBLIC_KEY&sid=SHORT_ID&sni=SNI&...
         ↑↑↑   ↑↑↑↑↑↑       ↑↑↑↑↑↑↑↑↑     ↑↑↑↑↑↑↑↑   ↑↑↑
        uuid  server        public-key     short-id    sni
```

| В ссылке | → В конфиг |
|----------|-----------|
| строка до `@` | `uuid:` |
| адрес после `@` | `server:` |
| `sni=...` | `servername:` |
| `pbk=...` | `public-key:` |
| `sid=...` | `short-id:` |

**Также замени** `YOUR_SERVER` ещё в двух местах:
- `fake-ip-filter` (~строка 88): `- "YOUR_SERVER"`
- `rules` (~строка 165): `- DOMAIN,YOUR_SERVER,DIRECT`

#### Вариант А: Подписка

Раскомментируй секцию `proxy-providers` (~строка 115), замени `YOUR_SUBSCRIPTION_URL` на свой URL. Закомментируй или удали секцию `proxies`.

---

### Шаг 3: Запусти установку

Нажми правой кнопкой на **`deploy.ps1`** → **"Запустить с помощью PowerShell"**

Или в PowerShell:
```powershell
.\deploy.ps1
```

Скрипт подключится к роутеру, загрузит профиль, настроит nikki и запустит VPN:

```
[1/4] Проверка подключения...  OK: aarch64, nikki установлен
[2/4] Проверка профиля...      OK: профиль заполнен
[3/4] Загрузка профиля...      OK
[4/4] Настройка и запуск...

  VPN alive: TRUE ✓

  Веб-панель: http://192.168.1.1:9090/ui
```

> **Если PowerShell не запускает скрипт:**
> ```powershell
> Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```

---

## Проверка

1. Подключись к WiFi роутера
2. Открой **YouTube** → должен работать
3. Открой **ВКонтакте** → должен работать без VPN
4. Зайди на **2ip.ru** → должен показать IP VPN сервера (не твой домашний)

---

## Веб-панель

**http://192.168.1.1:9090/ui** (MetaCubeXD)

- **Proxies** — статус VPN (alive: true = работает)
- **Connections** — текущие соединения и их маршрут
- **Logs** — логи mihomo в реальном времени

---

## Управление через SSH

```sh
ssh root@192.168.1.1

# Статус nikki
service nikki status

# Перезапуск
service nikki restart

# Логи (что происходит при запуске)
cat /var/log/nikki/app.log

# Логи mihomo (соединения, правила)
cat /var/log/nikki/core.log

# Статус VPN через API
curl -s http://127.0.0.1:9090/providers/proxies | grep '"alive"'
```

---

## Обновление профиля

Если VPN перестал работать (`alive: false`) — скорее всего изменился `short-id` на сервере.

1. Обнови `short-id` (и другие параметры если нужно) в `mihomo/config.yaml`
2. Запусти `deploy.ps1` снова

Или вручную на роутере:
```sh
vi /etc/nikki/profiles/main.yaml
service nikki restart
```

---

## Ежедневная проверка обновлений

`openwrt/router-update-check.sh` → `/usr/bin/router-update-check`, крон `0 5 * * *`.

Скрипт **только проверяет и пишет отчёт, ничего не ставит**. Причина: на OpenWrt
`apk upgrade` тянет пакеты, собранные под другую ревизию ядра — это ломает драйверы
Wi-Fi, а overlay на AX3000T всего ~60 МБ. Прошивка обновляется только через sysupgrade.

Что проверяет:
- пакеты (`apk update` + `apk list --upgradable`)
- прошивку (`owut check`) — и **почему обновление заблокировано**, если это так
- возраст geo-баз mihomo (их обновляет само ядро, интервал `nikki.mixin.geox_update_interval`)
- жив ли nikki и какой узел выбран

Отчёт: `/root/router-updates.log` + сводка в системный лог (LuCI → Status → System Log).

```sh
router-update-check          # запустить вручную
cat /root/router-updates.log # посмотреть отчёт
```

## Автоматическое обновление

`openwrt/router-auto-update.sh` → `/usr/bin/router-auto-update`, крон `10 5 * * *`.

Что обновляется само:

| Что | Как | Риск |
|---|---|---|
| geo-базы mihomo | ядром, раз в 24ч | нет |
| выбор VPN-узла | `url-test`, раз в 3 мин | нет |
| LuCI, `ca-bundle`, `owut` | `router-auto-update`, ежедневно | сломается веб-интерфейс, не сеть |
| ядро mihomo | `mihomo-auto-update`, ежедневно | откат на пакетную версию |
| драйверы, сеть, nikki | **вручную** | сломает Wi-Fi/сеть/VPN |
| прошивка | **вручную**, sysupgrade | кирпич при сбое питания |

Автоматически ставится **только тот набор, поломка которого не роняет
маршрутизацию, Wi-Fi и VPN** — LuCI это веб-интерфейс, `ca-bundle` корневые
сертификаты, `owut` утилита проверки. Всё остальное (`wpad`, `netifd`, `dnsmasq`,
`libubox`, `ubus`, `nftables`, `kmod-*`, стек nikki) собрано под конкретную
ревизию ядра, и обновлять его вслепую нельзя: у `apk` нет транзакционного отката.

Четыре предохранителя, любой отменяет установку:

1. **Место на flash** — отказ, если на overlay меньше 10 МБ.
2. **Симуляция** (`apk upgrade -s`) — разбираем, что реально изменится. Если
   транзакция потянула хоть один пакет вне безопасного набора (бывает, когда
   новый LuCI требует нового `libubox`) — **отмена целиком**, запись в лог.
3. **Резервная копия** конфигурации (`sysupgrade -b`) до установки.
4. **Проверка здоровья** после: маршрут, nikki, интернет, VPN, веб-интерфейс.
   При сбое — автовосстановление по возрастающей: `rpcd`+`uhttpd` → `network`
   → `nikki`. Если не помогло, в лог пишется команда отката.

> Проверки смотрят **код ответа**, а не «curl не упал»: `curl -o /dev/null` на
> 404 или 403 завершается успешно и молча пропустил бы поломку. Отдельная
> тонкость — LuCI на `/cgi-bin/luci/` штатно отдаёт **403** без сессии, поэтому
> проверять надо корень `http://127.0.0.1/`, где 200.

```sh
router-auto-update              # запустить вручную
logread -e auto-update          # что делал
sysupgrade -r /root/backup-pre-update.tar.gz && reboot   # аварийный откат
```

> **Важно про прошивку.** `owut` может показывать «cannot upgrade»: пакеты
> `nikki`, `mihomo-meta`, `luci-app-nikki`, `luci-i18n-nikki-ru` живут в кастомном
> фиде и появляются для новой версии OpenWrt с задержкой. Обновляться до того, как
> фид их соберёт, нельзя — sysupgrade вынесет VPN.

---

## Частые проблемы

### VPN alive: false
- `server`, `uuid`, `public-key`, `short-id` скопированы точно без пробелов?
- `short-id` актуален? (сервер мог сменить — попроси у провайдера новую vless-ссылку)
- Нет лишней строки `flow:` если её не было в ссылке?

### "Работало, через месяц перестало"
Самые частые причины (в порядке вероятности):
1. **Подписка отдаёт 404** (провайдер удалил/ротировал URL). Проверь:
   ```sh
   tail /var/log/nikki/core.log | grep -i 'pull error\|404'
   ```
   Решение — попроси у провайдера актуальную ссылку или vless://.
2. **Сервер сменил short-id/public-key** — обнови в `mihomo/config.yaml` и передеплой.
3. **Watchdog не стоит** — без него один краш mihomo уводит VPN в "тихий мёртвый" режим. Скрипт `configure_nikki.sh` ставит cron-watchdog (`/usr/bin/nikki-watchdog`) — проверь:
   ```sh
   crontab -l | grep nikki-watchdog
   tail /var/log/nikki/watchdog.log
   ```

### "Health-check OK но реальный трафик timeout-ит"
Симптом: в веб-панели прокси `alive: true`, ping/handshake к серверу проходят, а сайты грузятся 5-10 секунд и падают по таймауту. Через 30 минут — само работает.

Это **["16-килобайтная штора"](https://github.com/net4people/bbs/issues/490)** — российский метод DPI-блокировки, который пропускает мелкие пакеты (<1KB) и замораживает соединение когда суммарно прокачано >16KB. Расширяется на datacenter-CIDR с июня 2025, эскалирован 15 апреля 2026.

**Никаким mihomo-конфигом это не лечится** — блокировка работает на уровне ISP до VPS. Лечится только сменой транспорта:
- **WebSocket+TLS через Cloudflare CDN** — CF CIDR частично whitelisted у TSPU
- **NaiveProxy** (HTTP/2 CONNECT) — другая DPI-сигнатура
- **Shadowsocks-2022** на uncommon порту
- **Cloudflare WARP / Argo Tunnel** как фронт перед VPS

Запроси у провайдера VLESS+WebSocket+TLS на CF-проксированном домене или возьми второго провайдера с другим транспортом.

### `flow: xtls-rprx-vision` — добавлять или нет?
Зависит от **серверной** конфигурации. Если в твоей `vless://` ссылке есть `flow=xtls-rprx-vision` — добавляй в профиль. Если нет — НЕ добавляй: сервер не примет, прокси будет в `alive: false`. На разных серверах одного провайдера может быть по-разному — сверяйся с конкретной ссылкой, а не с соседним сервером.

### Российские сайты не открываются, а YouTube работает
Значит сломан DNS для DIRECT. Проверь:
```sh
curl -s 'http://127.0.0.1:9090/dns/query?name=vk.com&type=A'
```
Если в ответе `dns resolve failed: couldn't find ip` — mihomo не может отрезолвить имена своих же DoH-серверов, потому что бутстрап идёт по UDP/53 на 8.8.8.8, а он в РФ режется. Лечится заданием DoH **по IP** (`https://8.8.8.8/dns-query` вместо `https://dns.google/dns-query`) — см. секцию `dns` в профиле. Проксируемые сайты при этом работают, потому что домен резолвится на стороне VPN-сервера.

### iPhone/Android пишет "Нет интернета"
Это captive portal detection. Профиль уже содержит правила для `captive.apple.com` и `connectivitycheck.gstatic.com` — должно работать. Если ошибка постоянная: `service nikki restart`.

### Не открываются некоторые HTTPS-сайты
MSS clamping настраивается автоматически скриптом. Проверь:
```sh
nft list table inet mss_clamp
```
Должно быть правило `tcp option maxseg size set 1452`.

### Российские сайты (.ru) идут через VPN
GeoSite базы не загружены. Проверь:
```sh
ls -lh /etc/mihomo/geosite.dat
```
Если файла нет:
```sh
wget -O /etc/mihomo/geosite.dat \
  https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat
service nikki restart
```

### "luci-app-nikki не установлен" при запуске deploy.ps1
```sh
ssh root@192.168.1.1
# OpenWrt 25.12+:
apk update && apk add luci-app-nikki
# OpenWrt 24.10:
opkg update && opkg install luci-app-nikki
```

### Nikki не запускается
```sh
cat /var/log/nikki/app.log
cat /var/log/nikki/core.log
```

### SSH не подключается к роутеру
- Проверь подключение: `ping 192.168.1.1`
- На OpenWrt: **System → Administration → SSH Access** должен быть включён

---

## Технические детали

### Wi-Fi-уплинк: не вешай AP и STA на одно радио

Если роутер получает интернет по Wi-Fi (режим клиента, `mode='sta'`), а не по кабелю,
критично, **на каком радио** висит этот клиентский интерфейс. Радио не умеет
передавать и принимать одновременно: когда одно и то же радио и раздаёт точку
доступа, и тянет интернет, каждый пакет идёт по эфиру дважды — пропускная
способность падает больше чем вдвое.

Замеры на этой конфигурации (сигнал уплинка был отличный, −9 dBm — дело не в нём):

| Уплинк | Линк | Скорость DIRECT | Скорость через VPN |
|---|---|---|---|
| radio0, 2.4 ГГц, вместе с точкой доступа | 258 Мбит/с | 8–10 Мбит/с | 8.8 Мбит/с |
| radio1, 5 ГГц | 2401 Мбит/с | ~65 Мбит/с | **~90 Мбит/с** |

```sh
uci set wireless.wifinet0.device='radio1'   # перенести STA на 5 ГГц
uci commit wireless && wifi reload
```

Два следствия, о которых легко забыть:
- 2.4 ГГц освобождается и сама уходит на свободный канал — точка доступа становится чистой;
- STA-интерфейс на другом радио имеет **другой MAC**, поэтому роутер получит
  **новый IP** от вышестоящего DHCP. Не потеряй его: ищи по `arp -a` или скану порта 22.

Идеальный вариант — кабель: тогда оба радио целиком уходят клиентам.

### Ловушка: кабель в LAN-порт вместо WAN отключает VPN

Кабель от вышестоящего роутера, воткнутый в **LAN**-порт, не даёт WAN-подключения —
он объединяет обе сети на канальном уровне, потому что LAN-порты входят в мост `br-lan`.
Последствие тихое и опасное: чужой DHCP оказывается в одном сегменте с нашим, часть
устройств получает адрес от вышестоящего роутера и **идёт мимо mihomo — без VPN**.

Как распознать (адрес вышестоящего роутера виден на мосту — значит попался):
```sh
ip neigh show dev br-lan | grep 192.168.31.1
```

Чинится либо перестановкой кабеля в WAN-порт, либо переназначением порта без беготни:
```sh
uci del_list network.@device[0].ports='lan2'   # вывести порт из моста
uci set network.wan.device='lan2'              # и сделать его WAN
uci commit network && /etc/init.d/network reload
ip neigh flush dev br-lan                      # сбросить кэш, иначе висит старая запись
```

Когда кабель заработал, Wi-Fi-уплинк лучше выключить — иначе два интерфейса живут
в одной подсети (ARP flux), а радио остаётся занятым:
```sh
uci set wireless.wifinet0.disabled='1' && uci commit wireless && wifi reload
```

### Канал 5 ГГц: не наследуй его у соседа

Пока уплинк был на 5 ГГц, канал точки доступа был жёстко привязан к каналу
вышестоящего роутера — а тот стоял рядом и светил в −5 dBm, то есть был самой
сильной помехой в эфире. После отключения STA канал освобождается — выбирай по скану:

```sh
iwinfo phy1-ap0 scan | grep -oE 'Channel: [0-9]+' | sort -t' ' -k2 -n | uniq -c
```

На этой точке все 16 соседних сетей оказались на каналах 36–48, а весь верхний
блок (132–165) пуст. Соблазн очевиден — но **проверять надо не сканом роутера,
а тем, видят ли канал клиенты**.

Проверено на живом железе: при `channel='149'` роутер поднимал точку штатно
(`AP-ENABLED`), а ноутбук (Realtek 8822CE, 802.11ac) не видел её ни разу за
5 сканов подряд, хотя 2.4 ГГц находил каждый раз. То же с DFS-каналом 52.
На канале 36 точка появляется в скане мгновенно. Итог — оставлен **36**.

Клиентские адаптеры в RU-регдомене, как правило, не сканируют верхний блок
(5745–5825) и пассивно относятся к DFS. Роутеру диапазон разрешён, устройствам
пользователя — нет, и «улучшение» оборачивается отключением 5 ГГц вообще.

Про соседа на том же канале: **со-канальность лучше частичного перекрытия**.
Устройства на одном канале делят эфир по CSMA (слышат друг друга и ждут),
а сдвиг на 4–8 каналов даёт именно разрушительные помехи.

Как проверять правильно (иначе получишь ложный результат):
- сканировать **с другой сети**, а не с самой GG WP — для текущей сети Windows
  показывает в основном ассоциированный BSSID;
- принудительно освежать скан переподключением: кэш `netsh wlan show networks`
  живёт достаточно долго, чтобы соврать. На этом легко сделать неверный вывод —
  «точка не видна», хотя к ней в тот же момент успешно подключаются.

### Доступ к роутеру снаружи его LAN

Если ПК не в сети роутера, а в вышестоящей — SSH туда по умолчанию закрыт
(fw4 режет вход из зоны `wan`). Без этого правила можно остаться без доступа,
если что-то сломается в конфиге:

```sh
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-SSH-Upstream'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].src_ip='192.168.31.0/24'   # только своя вышестоящая сеть
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].dest_port='22'
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall && /etc/init.d/firewall reload
```

### Рискованные изменения по сети — только с автооткатом

`wifi reload` рвёт связь с роутером, поэтому команду нельзя запускать так, чтобы
она умерла вместе с SSH-сессией. В busybox **нет `nohup`** — используй
`start-stop-daemon -S -b`. Скрипт должен сам проверить связь и откатиться:

```sh
start-stop-daemon -S -b -x /bin/sh -- /tmp/change.sh
```

### `test_profile` роняет перезапуск на роутерах с малой памятью

nikki по умолчанию тестирует профиль перед стартом: `mihomo -d "$RUN_DIR" -t`
внутри `start_service()`. При `restart` procd останавливает старый mihomo
**асинхронно**, поэтому тестовый экземпляр поднимается, пока прежний ещё держит
память. На AX3000T (240 МБ ОЗУ) это стабильно приводит к OOM — тест «падает»,
nikki выходит, сеть остаётся без интернета до срабатывания watchdog (~15 мин).

Измерено на живом роутере:

| `test_profile` | Провалов перезапуска |
|---|---|
| `1` (по умолчанию) | **1 из 2** |
| `0` | **0 из 4** |

```sh
uci set nikki.config.test_profile='0' && uci commit nikki
```

Безопасно: отката тест не даёт — старый процесс к этому моменту уже остановлен,
и негодный конфиг положит сеть в любом случае, просто на шаг позже. Проверка
синтаксиса (`[Profile] Checking...`, через `yq`) при этом остаётся.

Симптом в `/var/log/nikki/app.log`, если поймал именно это:
```
[Profile] Testing...
[Profile] Test failed.
[App] Exit.
```
При этом `mihomo -t` на том же файле проходит успешно, если запустить его
с остановленным nikki — верный признак, что дело в памяти, а не в конфиге.

### Ручное обновление mihomo мимо фида

Фид OpenWrt отстаёт от апстрима MetaCubeX (у нас был 1.19.27 против 1.19.29).
Заменить бинарник можно, но есть две ловушки — обе пойманы на живом роутере.

**Ловушка 1: места на flash меньше, чем весит бинарник.** mihomo — **44 МБ**,
свободно было 15 МБ. Положить новый рядом со старым нельзя: сначала удаляем
старый (освобождается 44 МБ), потом пишем новый.

**Ловушка 2: `/tmp` — это RAM.** Скачанный туда бинарник занимает 44 МБ
оперативной памяти, и её перестаёт хватать ядру. Симптом характерный —
не OOM при старте, а:
```
[Proxy] Waiting for tun device online within 30 seconds...
[Proxy] Timeout, TUN device is not online.
[App] Exit.
```
Поэтому **освобождать `/tmp` надо до запуска** nikki, а не после.

Рабочий порядок:
```sh
# 1. скачать и проверить, пока VPN ещё работает
cd /tmp && curl -sL -o m.gz https://github.com/MetaCubeX/mihomo/releases/download/v1.19.29/mihomo-linux-arm64-v1.19.29.gz
gunzip m.gz && chmod +x m && ./m -v      # должно быть "with_gvisor" — иначе TUN не поднимется
# 2. заменить и СРАЗУ освободить /tmp
/etc/init.d/nikki stop
rm -f /usr/libexec/mihomo && cp /tmp/m /usr/libexec/mihomo && chmod +x /usr/libexec/mihomo && sync
rm -f /tmp/m
/etc/init.d/nikki start
# откат, если что: rm -f /usr/libexec/mihomo && apk fix mihomo-meta
```

> **Последствие:** `apk` продолжает считать установленной версию из пакета.
> `apk fix mihomo-meta` или обновление фида молча вернут старый бинарник.
> Скрипт `router-auto-update` это не затронет — mihomo не входит в его
> безопасный набор (`^(luci|ca-bundle|owut)`).

Всё это автоматизировано в `openwrt/mihomo-auto-update.sh` →
`/usr/bin/mihomo-auto-update`, крон `20 5 * * *`. Скрипт сверяет запущенную
версию с последним релизом MetaCubeX и обновляет только при расхождении.

Предохранители: отказ, если nikki сейчас не работает или свободно меньше 60 МБ
RAM; проверка, что скачанный бинарник сообщает нужную версию **и** собран
`with_gvisor`; тест конфига уже новым бинарником; проверка API, активного узла
и реального выхода в интернет после запуска. Любой сбой → `apk fix mihomo-meta`
и возврат к пакетной версии.

Проверено обходом в обе стороны: принудительное понижение до 1.19.28 и
автоматический подъём обратно до 1.19.29 — оба раза с рабочим VPN на выходе.

> **Осторожно с `free -m` в busybox:** флаг игнорируется, вывод всегда в
> килобайтах. Проверка вида `[ $(free -m | awk '/Mem:/{print $7}') -lt 90 ]`
> сравнивает ~88000 с 90 и не срабатывает никогда. Читай `MemAvailable`
> из `/proc/meminfo` и сравнивай в КБ.

### Мощность передатчика поднять нельзя

`iw reg get` для страны RU даёт лимит **20 dBm (100 мВт)** на все диапазоны, и
радио уже работает на этом максимуме. «Усилить сигнал» настройками невозможно —
только размещение роутера, вторая точка доступа или переход дальних клиентов
на 2.4 ГГц (лучше проходит сквозь стены).

### Архитектура

```
LAN устройство (телефон)
    │
    ↓ DNS запрос на порт 53
[dnsmasq] → форвард → [Mihomo DNS :1053]
    ← fake-IP (198.18.x.x)
    │
    ↓ TCP соединение к fake-IP
[nftables PREROUTING] → redirect → [Mihomo redir-port :7891]
    │
[Mihomo правила]
    ├─ GEOSITE tld-ru / category-ru → DIRECT (Яндекс, VK, RuTube)
    ├─ GEOIP RU → DIRECT (российские IP)
    └─ MATCH → PROXY → [VLESS Reality туннель] → интернет
    │
    ↓ UDP трафик
[nftables fwmark 0x81] → table 81 → default via Meta (TUN)
    │
[Mihomo TUN gvisor] → PROXY / DIRECT
```

### Почему именно так

| Решение | Причина |
|---------|---------|
| `gvisor` стек TUN | `mixed` ломает DNS hijack (баг #1258) |
| `auto-route: false` | nikki управляет routing через nftables сам |
| `ipv4_dns_hijack: 0` | Иначе `.lan` домены не резолвятся через dnsmasq |
| dnsmasq → 127.0.0.1#1053 | DNS через mihomo fake-ip, но .lan через dnsmasq |
| MSS clamping 1452 | Предотвращает PMTUD blackhole через VPN |
| cgroup изоляция | Трафик самого mihomo не попадает в nftables redirect |
| geox_auto_update | Еженедельное обновление GeoIP/GeoSite (встроено в nikki) |
| tcp keepalive 600/15 | Предотвращает разрыв idle-соединений у iOS |

### Файлы на роутере

```
/etc/nikki/profiles/main.yaml   ← наш профиль
/etc/mihomo/geoip.metadb        ← GeoIP база (~9 MB)
/etc/mihomo/geosite.dat         ← GeoSite база (~4 MB)
/etc/mihomo/ui/                 ← MetaCubeXD веб-панель
/etc/firewall.user              ← MSS clamping
```

### Файлы репозитория

```
.
├── deploy.ps1                      ← запускать на Windows
├── mihomo/
│   └── config.yaml                 ← профиль (заполни VPN данные)
├── openwrt/
│   └── configure_nikki.sh          ← настройка nikki + watchdog на роутере
└── docs/
    └── install-openwrt-ax3000t.md  ← установка OpenWrt (новый роутер)
```

### Watchdog

`configure_nikki.sh` ставит на роутер `/usr/bin/nikki-watchdog` и cron `*/5 * * * *`. Каждые 5 минут проверяется:
1. `service nikki status` = running
2. процесс `mihomo` живой
3. PROXY-группа `alive: true` через API mihomo

При **3 подряд** провалах — `service nikki restart` + запись в `/var/log/nikki/watchdog.log`. Это защищает от ситуации "VPN тихо умер на месяц".

### Порты Mihomo

| Порт | Назначение |
|------|-----------|
| 7890 | Mixed proxy (SOCKS5/HTTP) |
| 7891 | Transparent redirect — сюда идёт TCP от LAN |
| 7892 | TProxy port |
| 1053 | DNS сервер (fake-ip) |
| 9090 | API и веб-панель |

---

## Источники

- [Mihomo (ядро)](https://github.com/MetaCubeX/mihomo)
- [luci-app-nikki (OpenWrt)](https://github.com/nikkinikki-org/OpenWrt-nikki)
- [MetaCubeXD (веб-панель)](https://github.com/MetaCubeX/metacubexd)
- [GeoIP/GeoSite базы](https://github.com/MetaCubeX/meta-rules-dat)
- [OpenWrt](https://openwrt.org)
- [Firmware Selector для AX3000T](https://firmware-selector.openwrt.org/?target=mediatek%2Ffilogic&id=xiaomi_mi-router-ax3000t)

---

MIT License — используй свободно для личных нужд.
