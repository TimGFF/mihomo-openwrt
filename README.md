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
opkg update && opkg install luci-app-nikki
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

#### Вариант Б: Ручная VLESS-ссылка (по умолчанию)

Найди раздел `proxies:` (~строка 140) и замени плейсхолдеры:

```yaml
proxies:
  - name: "Мой VPN"
    server: YOUR_SERVER          # ← адрес сервера
    uuid: YOUR_UUID              # ← UUID
    servername: YOUR_SNI         # ← SNI
    reality-opts:
      public-key: YOUR_PUBLIC_KEY
      short-id: YOUR_SHORT_ID
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
- `short-id` актуален? (сервер мог сменить — скачай свежую подписку)
- Нет лишней строки `flow:` если её не было в ссылке?

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
│   └── configure_nikki.sh          ← настройка nikki на роутере
└── docs/
    └── install-openwrt-ax3000t.md  ← установка OpenWrt (новый роутер)
```

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
- [luci-app-nikki](https://github.com/nikki-kkk/nikki)
- [MetaCubeXD (веб-панель)](https://github.com/MetaCubeX/metacubexd)
- [GeoIP/GeoSite базы](https://github.com/MetaCubeX/meta-rules-dat)
- [OpenWrt](https://openwrt.org)
- [Firmware Selector для AX3000T](https://firmware-selector.openwrt.org/?target=mediatek%2Ffilogic&id=xiaomi_mi-router-ax3000t)

---

MIT License — используй свободно для личных нужд.
