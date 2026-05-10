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
Зависит от **серверной** конфигурации. Если в твоей `vless://` ссылке есть `flow=xtls-rprx-vision` — добавляй в профиль. Если нет — НЕ добавляй: сервер не примет, прокси будет в `alive: false`. На разных серверах одного провайдера может быть по-разному (проверено на NL/DE — у нас NL без flow, DE с flow).

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
