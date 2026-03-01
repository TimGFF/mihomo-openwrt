# Mihomo VPN на роутере OpenWrt

**Прозрачный VPN для всех устройств в сети** — YouTube, Instagram, TikTok работают автоматически на телефоне, ТВ, ноутбуке и всём остальном. Российские сайты (VK, Яндекс, RuTube) открываются напрямую без VPN.

Настраивается **один раз** через скрипт на Windows. Перезагружать роутер после этого не нужно.

---

## Как это работает

```
  Телефон / ТВ / ПК
         |
      [Роутер OpenWrt]
         |                  |
    youtube.com  →→→  [VPN сервер]  →→→  YouTube
    vk.com       →→→  Напрямую (без VPN)
```

Mihomo — это программа на роутере, которая:
1. Перехватывает весь трафик из твоей сети
2. Смотрит куда идёт соединение
3. Российские сайты пускает напрямую, остальные — через VPN
4. Устройства в сети даже не знают что есть VPN — он прозрачный

---

## Что нужно

### Оборудование
- **Роутер на OpenWrt** (прошивка должна быть уже установлена)
  - Протестировано: Xiaomi AX3000, Xiaomi AX6000, GL.iNet
  - Работает на: любой OpenWrt 22+ с архитектурой aarch64, armv7, x86_64, mips
- **Компьютер на Windows 10 или 11**

### VPN
- **VLESS Reality сервер** или подписка с vless:// ссылкой
  - Если у тебя нет сервера — его можно арендовать или поднять самому (3x-ui, XKeen, Marzban)
  - Подписки продаются у многих провайдеров VPN

### Программы
- **Git** — для скачивания этого репозитория
  Скачать: https://git-scm.com/download/win
- **OpenSSH** — уже встроен в Windows 10/11
  Проверить: открой PowerShell и введи `ssh -V`

---

## Установка — 3 шага

### Шаг 1: Скачай репозиторий

Открой **PowerShell** или **cmd** и выполни:

```powershell
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git
cd YOUR_REPO
```

Или нажми кнопку **"Code → Download ZIP"** на этой странице и распакуй.

---

### Шаг 2: Заполни данные VPN

Открой файл **`mihomo/config.yaml`** в любом текстовом редакторе (Блокнот, VS Code, Notepad++).

Найди раздел с прокси (строки ~95-110) и заполни поля:

```yaml
proxies:
  - name: "Мой VPN"
    type: vless
    server: YOUR_SERVER          # ← адрес VPN сервера
    port: 443
    uuid: YOUR_UUID              # ← UUID
    network: tcp
    tls: true
    udp: true
    servername: YOUR_SNI         # ← SNI
    reality-opts:
      public-key: YOUR_PUBLIC_KEY  # ← публичный ключ
      short-id: YOUR_SHORT_ID      # ← short-id
    client-fingerprint: random
```

#### Как получить параметры из vless:// ссылки

Если у тебя есть ссылка вида:
```
vless://66dc8983-dcb6-42a8-9ab0-410ecd5d378e@vpn.example.com:443?pbk=XXGfXLEizI0s&sid=42aafa32&sni=sni.example.com&...
```

Разбираем её:

| Что куда | Пример |
|----------|--------|
| `server:` | адрес после `@` → `vpn.example.com` |
| `port:` | порт после `:` → `443` |
| `uuid:` | строка до `@` → `66dc8983-dcb6-42a8-9ab0-410ecd5d378e` |
| `servername:` | параметр `sni=` → `sni.example.com` |
| `public-key:` | параметр `pbk=` → `XXGfXLEizI0s...` |
| `short-id:` | параметр `sid=` → `42aafa32` |

> **Важно:** НЕ добавляй `flow: xtls-rprx-vision` если его нет в твоей ссылке.
> Если ссылка содержит `flow=xtls-rprx-vision` — тогда добавь эту строку в конфиг.

**Также замени** в конфиге:
```yaml
    - "YOUR_SERVER"   # ← в разделе fake-ip-filter (строка ~78)
```
```yaml
  - DOMAIN,YOUR_SERVER,DIRECT   # ← в разделе rules (строка ~117)
```
На реальный адрес своего VPN сервера.

---

### Шаг 3: Запусти установку

**Убедись:**
- Компьютер подключён к роутеру (по кабелю или WiFi)
- Роутер имеет выход в интернет (нужен для скачивания компонентов)

**Запусти скрипт:**

Нажми правой кнопкой мыши на файл **`deploy.ps1`** → **"Запустить с помощью PowerShell"**

Или в PowerShell:
```powershell
.\deploy.ps1
```

Скрипт спросит IP роутера (по умолчанию `192.168.1.1`) и сделает всё сам:

```
[1/5] Проверка подключения к роутеру...
[2/5] Проверка конфигурации VPN...
[3/5] Установка Mihomo (2-5 минут)...
      Скачивает: mihomo бинарник, GeoIP, GeoSite, веб-панель
[4/5] Загрузка конфигурации VPN...
[5/5] Запуск Mihomo...
      VPN alive: TRUE ✓
УСТАНОВКА ЗАВЕРШЕНА!
```

> **Если PowerShell не запускает скрипт:** открой PowerShell от имени администратора и выполни:
> ```powershell
> Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```

---

## Проверка

После установки:

1. Подключись к WiFi роутера
2. Открой **YouTube** → должен работать
3. Открой **ВКонтакте** → должен работать
4. Зайди на **2ip.ru** → должен показать IP VPN сервера (не твой домашний)

---

## Веб-панель управления

Открой в браузере: **http://192.168.1.1:9090/ui**

Здесь можно видеть:
- Какие сайты открываются через VPN, какие напрямую
- Скорость соединений
- Статус VPN (alive: true = работает)

> **Важно:** Не меняй режим в веб-панели. Должен стоять **"Правила"** (Rules).
> Любые изменения в веб-панели не сохраняются — при перезапуске сбросятся.

---

## Обновление конфигурации VPN

Если VPN перестал работать (статус `alive: false`) — скорее всего изменился `short-id` на сервере.

**Быстрое обновление:**

1. Скачай свежую подписку и декодируй:
   ```powershell
   # В PowerShell:
   $b64 = (Invoke-WebRequest "https://ТВОЯ_ССЫЛКА_ПОДПИСКИ").Content
   [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
   ```

   Или на роутере:
   ```sh
   wget -q -O - "https://ТВОЯ_ССЫЛКА_ПОДПИСКИ" | base64 -d
   ```

2. Найди параметр `sid=` в выводе — это новый `short-id`

3. Обнови `mihomo/config.yaml`:
   ```yaml
   short-id: НОВЫЙ_SHORT_ID
   ```

4. Загрузи новый конфиг:
   ```powershell
   .\deploy.ps1
   ```
   Или только загрузи конфиг (без переустановки):
   ```powershell
   # В PowerShell:
   Get-Content .\mihomo\config.yaml | ssh root@192.168.1.1 "cat > /etc/mihomo/config.yaml && service mihomo restart"
   ```

---

## Управление через SSH

Подключись к роутеру:
```sh
ssh root@192.168.1.1
```

Полезные команды:

```sh
# Статус сервиса
service mihomo status

# Перезапуск
service mihomo restart

# Логи в реальном времени
logread -f | grep mihomo

# Проверить статус VPN (alive: true = работает)
wget -q -O - http://localhost:9090/proxies/ 2>/dev/null

# Посмотреть активные соединения
wget -q -O - http://localhost:9090/connections 2>/dev/null | head -500
```

---

## Частые проблемы

### VPN alive: false
Сервер отклоняет подключение. Проверь:
- `server`, `uuid`, `public-key`, `short-id` скопированы правильно без пробелов
- `short-id` не устарел (сервер мог его сменить — скачай свежую подписку)
- Не добавил лишнюю строку `flow:` если её нет в ссылке

### iPhone/iPad пишет "Нет подключения к интернету" при подключении к WiFi
Это нормально — iOS проверяет интернет через `captive.apple.com`.
Эта ошибка уже исправлена в конфиге (captive.apple.com идёт напрямую).
Если ошибка всё равно есть — перезапусти mihomo: `service mihomo restart`

### YouTube не работает, хотя VPN alive: true
Иногда нужно подождать 30-60 секунд после запуска mihomo.
Принудительно сбрось DNS кэш на телефоне: выключи и включи WiFi.

### PowerShell говорит "cannot be loaded because running scripts is disabled"
```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Скрипт не может подключиться к роутеру
- Убедись что ты в одной сети с роутером
- Проверь IP: `ping 192.168.1.1`
- На OpenWrt: **System → Administration → SSH Access** — должен быть включён

### Mihomo не запускается после перезагрузки роутера
Зайди по SSH и запусти вручную:
```sh
service mihomo start
logread | grep mihomo | tail -20
```

---

## Технические детали

### Архитектура работы

```
LAN устройство (телефон)
    ↓ TCP/UDP пакет
[dnsmasq] → запрос DNS → [Mihomo DNS :1053]
    ← fake IP (198.18.x.x)
    ↓ TCP к 198.18.x.x
[nftables PREROUTING] → redirect → [Mihomo redir-port :7891]
    ↓ SO_ORIGINAL_DST → знает реальный домен
[Правила Mihomo]
    ├─ GEOSITE tld-ru / category-ru → DIRECT (Яндекс, VK, RuTube)
    ├─ GEOIP RU → DIRECT (российские IP)
    └─ MATCH → PROXY → [VLESS Reality туннель] → интернет
```

### Почему такая схема

- **fake-ip режим** — роутер возвращает фиктивные IP для всех доменов. Реальное разрешение DNS происходит внутри mihomo. Это позволяет перехватить весь трафик на уровне сокета.
- **nftables PREROUTING redirect** — перенаправляет TCP пакеты от LAN устройств на mihomo redir-port. Это нужно потому что Firewall на OpenWrt не пропускает трафик через Meta TUN из FORWARD цепочки.
- **gVisor stack** — надёжный перехват DNS. Альтернативный `mixed` стек ломает DNS hijack на OpenWrt.
- **VLESS Reality** — маскирует VPN трафик под обычный HTTPS, обходя DPI блокировки.

### Файловая структура

```
.
├── deploy.ps1              ← запускать на Windows (главный скрипт)
├── mihomo/
│   └── config.yaml         ← конфигурация (заполни свои VPN данные)
└── openwrt/
    └── install_mihomo.sh   ← скрипт установки (запускается на роутере)
```

### Порты Mihomo

| Порт | Назначение |
|------|-----------|
| 7890 | Mixed proxy (SOCKS5/HTTP) |
| 7891 | Transparent redirect (redir-port) |
| 7892 | TProxy (tproxy-port) |
| 1053 | DNS сервер (fake-ip) |
| 9090 | API и веб-панель |

---

## Поддерживаемые роутеры

Протестировано:
- **Xiaomi AX3000** (OpenWrt 24.10.0, aarch64_cortex-a53)

Должно работать:
- Любой роутер на OpenWrt 22+ с архитектурой aarch64, armv7, x86_64, mips/mipsel
- Минимум 64 МБ RAM, 16 МБ Flash (для хранения баз данных)

---

## Источники

- [Mihomo (ядро)](https://github.com/MetaCubeX/mihomo)
- [MetaCubeXD (веб-панель)](https://github.com/MetaCubeX/metacubexd)
- [GeoIP/GeoSite базы](https://github.com/MetaCubeX/meta-rules-dat)
- [OpenWrt](https://openwrt.org)

---

## Лицензия

MIT — используй свободно для личных нужд.
