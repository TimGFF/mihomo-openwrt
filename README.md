# Прозрачный VPN на роутере OpenWrt + Nikki (Mihomo)

**YouTube, Instagram, TikTok работают автоматически** на всех устройствах в сети. Российские сайты (VK, Яндекс, RuTube) открываются напрямую без VPN.

Настраивается через скрипт на Windows. Перезагружать роутер после этого не нужно.

---

## Как это работает

```
  Телефон / ТВ / ПК
         |
      [Роутер OpenWrt + Nikki]
         |                         |
    youtube.com  →→→  [VPN сервер]  →→→  YouTube
    vk.com       →→→  Напрямую (без VPN)
```

**Nikki** (luci-app-nikki) — LuCI-пакет для управления [Mihomo](https://github.com/MetaCubeX/mihomo) на роутере. Он настраивает nftables, routing, TUN-интерфейс и автозапуск. Mihomo перехватывает трафик, смотрит куда идёт соединение, и выбирает маршрут по правилам.

---

## Что нужно

### Роутер
- **OpenWrt 24.x** с установленным **luci-app-nikki**
- Протестировано: Xiaomi AX3000T (aarch64_cortex-a53)
- Минимум 128 МБ RAM, 32 МБ Flash

### Компьютер
- **Windows 10 или 11** (встроенный SSH)

### VPN
Один из двух вариантов:
- **VLESS Reality сервер** (ссылка вида `vless://UUID@HOST:PORT?pbk=...`)
- **Подписка** в mihomo/clash формате (URL с прокси-листом)

---

## Установка — 3 шага

### Шаг 0: Установи luci-app-nikki на роутере

Подключись к роутеру по SSH и выполни:

```sh
opkg update && opkg install luci-app-nikki
```

Или через LuCI: **System → Software → Search** → `luci-app-nikki` → Install.

> После установки nikki появится в LuCI: **Services → Nikki**

---

### Шаг 1: Скачай репозиторий

```powershell
git clone https://github.com/TimGFF/mihomo-openwrt.git
cd mihomo-openwrt
```

Или нажми **Code → Download ZIP** и распакуй.

---

### Шаг 2: Заполни данные VPN

Открой **`mihomo/config.yaml`** в любом редакторе.

#### Вариант Б: Ручная VLESS-ссылка (активен по умолчанию)

Найди раздел `proxies:` и заполни поля:

```yaml
proxies:
  - name: "Мой VPN"
    type: vless
    server: YOUR_SERVER          # ← адрес VPN сервера
    port: 443
    uuid: YOUR_UUID              # ← UUID
    servername: YOUR_SNI         # ← sni= из ссылки
    reality-opts:
      public-key: YOUR_PUBLIC_KEY  # ← pbk= из ссылки
      short-id: YOUR_SHORT_ID      # ← sid= из ссылки
```

**Как разобрать vless:// ссылку:**
```
vless://UUID@SERVER:PORT?pbk=PUBLIC_KEY&sid=SHORT_ID&sni=SNI&...
```

| Параметр | Откуда |
|----------|--------|
| `server` | адрес после `@` |
| `port` | порт после `:` |
| `uuid` | строка до `@` |
| `servername` | параметр `sni=` |
| `public-key` | параметр `pbk=` |
| `short-id` | параметр `sid=` |

**Также замени** `YOUR_SERVER` в двух других местах:
- В `fake-ip-filter` (~строка 88): `- "YOUR_SERVER"`
- В `rules` (~строка 165): `- DOMAIN,YOUR_SERVER,DIRECT`

#### Вариант А: Подписка

Раскомментируй секцию `proxy-providers` в конфиге и замени `YOUR_SUBSCRIPTION_URL` на твой URL. Закомментируй или удали секцию `proxies`.

---

### Шаг 3: Запусти установку

Нажми правой кнопкой на **`deploy.ps1`** → **"Запустить с помощью PowerShell"**

Или в PowerShell:
```powershell
.\deploy.ps1
```

Скрипт:
1. Подключается к роутеру по SSH
2. Загружает профиль в `/etc/nikki/profiles/main.yaml`
3. Настраивает UCI nikki, dnsmasq, MSS clamping
4. Запускает nikki и проверяет статус

```
[1/4] Проверка подключения...  OK
[2/4] Проверка профиля...      OK
[3/4] Загрузка профиля...      OK
[4/4] Настройка и запуск...    OK

  VPN alive: TRUE ✓
  Веб-панель: http://192.168.1.1:9090/ui
```

> **Если PowerShell блокирует скрипт:**
> ```powershell
> Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```

---

## Проверка

1. Подключись к WiFi роутера
2. Открой **YouTube** → должен работать
3. Открой **ВКонтакте** → должен работать
4. Зайди на **2ip.ru** → должен показать IP VPN сервера (не твой домашний)

---

## Веб-панель

**http://192.168.1.1:9090/ui** — MetaCubeXD

- Вкладка **Proxies**: статус VPN (alive: true = работает)
- Вкладка **Connections**: текущие соединения и их маршрут
- Вкладка **Logs**: логи в реальном времени

---

## Управление через SSH

```sh
ssh root@192.168.1.1

# Статус
service nikki status

# Перезапуск
service nikki restart

# Логи nikki (app)
cat /var/log/nikki/app.log

# Логи mihomo (core — соединения, правила)
cat /var/log/nikki/core.log

# Статус VPN через API
curl -s http://127.0.0.1:9090/providers/proxies | grep '"alive"'
```

---

## Обновление профиля

Если VPN перестал работать (`alive: false`) — возможно изменился `short-id` на сервере.

1. Обнови `short-id` в `mihomo/config.yaml`
2. Перезапусти deploy.ps1

Или вручную на роутере:
```sh
ssh root@192.168.1.1
# Отредактируй профиль
vi /etc/nikki/profiles/main.yaml
# Перезапусти nikki
service nikki restart
```

---

## Частые проблемы

### VPN alive: false
- `server`, `uuid`, `public-key`, `short-id` скопированы точно, без пробелов?
- `short-id` актуален? (сервер мог его сменить — скачай свежую подписку)
- Нет лишней строки `flow:` если её не было в ссылке?

### iPhone/Android пишет "Нет интернета" при подключении к WiFi
Профиль уже содержит правила для captive portal (`captive.apple.com`, `connectivitycheck.gstatic.com`). Это нормально при первом подключении. Если ошибка постоянная — `service nikki restart`.

### Не открываются некоторые сайты (HTTPS)
MSS clamping настраивается автоматически скриптом. Если проблема осталась:
```sh
nft list table inet mss_clamp
```
Должна быть таблица с правилом `tcp option maxseg size set 1452`.

### Российские сайты (.ru) идут через VPN
Проверь что GeoSite базы загружены:
```sh
ls -lh /etc/mihomo/geosite.dat
```
Если файла нет — скачай вручную:
```sh
wget -O /etc/mihomo/geosite.dat \
  https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat
service nikki restart
```

### Nikki не запускается / статус "stopped"
```sh
cat /var/log/nikki/app.log
cat /var/log/nikki/core.log
```

### SSH не подключается
- Убедись что в одной сети с роутером
- Проверь: `ping 192.168.1.1`
- На OpenWrt: **System → Administration → SSH Access** — должен быть включён

---

## Технические детали

### Архитектура

```
LAN устройство (телефон)
    │
    ↓ DNS запрос → порт 53
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
    ↓ UDP соединение (DNS, QUIC, и т.д.)
[nftables fwmark 0x81] → ip rule → table 81 → default via Meta (TUN)
    │
[Mihomo TUN :gvisor] → правила → PROXY / DIRECT
```

### Почему именно так

| Решение | Причина |
|---------|---------|
| `gvisor` стек | `mixed` ломает DNS hijack (баг #1258) |
| `auto-route: false` | nikki управляет routing через nftables |
| `ipv4_dns_hijack: 0` | Иначе `.lan` домены не резолвятся через dnsmasq |
| dnsmasq → 127.0.0.1#1053 | DNS через mihomo fake-ip, но .lan через dnsmasq |
| MSS clamping 1452 | Предотвращает PMTUD blackhole через VPN |
| cgroup изоляция | nikki помещает mihomo в cgroup, трафик mihomo не попадает в redirect |
| geox_auto_update | Еженедельное обновление GeoIP/GeoSite баз (встроено в nikki) |
| tcp keepalive 600/15 | Предотвращает разрыв idle-соединений у iOS |

### Файловая структура на роутере

```
/etc/nikki/
├── profiles/
│   └── main.yaml          ← наш профиль (загружается deploy.ps1)
├── run/
│   ├── config.yaml        ← сгенерированный никки конфиг
│   ├── geoip.metadb       ← symlink → /etc/mihomo/geoip.metadb
│   ├── geosite.dat        ← symlink → /etc/mihomo/geosite.dat
│   └── ui                 ← symlink → /etc/mihomo/ui
└── ...

/etc/mihomo/
├── geoip.metadb           ← GeoIP база (~9 MB)
├── geosite.dat            ← GeoSite база (~4 MB)
└── ui/                    ← MetaCubeXD веб-панель

/etc/firewall.user         ← MSS clamping (наш скрипт)
```

### Файлы репозитория

```
.
├── deploy.ps1              ← запускать на Windows (главный скрипт)
├── mihomo/
│   └── config.yaml         ← профиль (заполни VPN данные)
└── openwrt/
    └── configure_nikki.sh  ← настройка nikki на роутере
```

### Порты Mihomo

| Порт | Назначение |
|------|-----------|
| 7890 | Mixed proxy (SOCKS5/HTTP для ручного использования) |
| 7891 | Transparent redirect — сюда идёт TCP от LAN |
| 7892 | TProxy port |
| 1053 | DNS сервер (fake-ip, принимает от dnsmasq) |
| 9090 | API и веб-панель |

---

## Источники

- [Mihomo (ядро)](https://github.com/MetaCubeX/mihomo)
- [luci-app-nikki](https://github.com/nikki-kkk/nikki)
- [MetaCubeXD (веб-панель)](https://github.com/MetaCubeX/metacubexd)
- [GeoIP/GeoSite базы](https://github.com/MetaCubeX/meta-rules-dat)
- [OpenWrt](https://openwrt.org)

---

MIT License — используй свободно для личных нужд.
