# Установка OpenWrt на Xiaomi AX3000T

Это подробная пошаговая инструкция для тех, кто впервые устанавливает OpenWrt.

> **Протестировано на:** Xiaomi AX3000T (китайская версия RD03)
> **OpenWrt:** 24.10.0

---

## ⚠️ Прочитай это перед началом

### Проверь версию своего роутера

На коробке или наклейке снизу роутера найди **Model**:

| Model | Статус |
|-------|--------|
| **RD03** | ✅ Поддерживается — используй эту инструкцию |
| **RD23** (Global/EU) | ✅ Поддерживается — используй эту инструкцию |
| **RD03V2** | ❌ **НЕ поддерживается** — другой процессор (Qualcomm), OpenWrt не работает |

> Если у тебя **RD03V2** — OpenWrt не установить. Инструкция не подходит.

### Проверь версию прошивки Xiaomi

**Важно:** В роутерах с прошивкой **1.0.84 и новее** — другой чип сетевого коммутатора. Если понизить прошивку на таких устройствах — роутер станет кирпичом.

Узнай версию: открой `192.168.31.1` → в настройках найди версию прошивки.

| Версия прошивки | Что делать |
|----------------|-----------|
| Ниже 1.0.84 | ✅ Следуй инструкции ниже (понизь до 1.0.47) |
| 1.0.84 и выше | ⚠️ Обратись на [форум OpenWrt](https://forum.openwrt.org/t/openwrt-support-for-xiaomi-ax3000t/180490) — нужен другой метод |

---

## Что тебе понадобится

- **Роутер** Xiaomi AX3000T (RD03 или RD23)
- **Компьютер на Windows** (macOS/Linux для некоторых шагов тоже подойдёт)
- **Патч-корд** (сетевой кабель) для подключения ПК к роутеру
- **Python 3.8+** — [скачать](https://www.python.org/downloads/)
- **Git** — [скачать](https://git-scm.com/download/win)
- ~30 минут времени

---

## Шаг 1: Понизь прошивку до 1.0.47

> **Зачем:** Эксплойт для получения SSH работает только на прошивке 1.0.47.

### Скачай файлы

1. **Прошивка Xiaomi 1.0.47:**
   Скачай с [4PDA](https://4pda.to/forum/index.php?showtopic=1048199) или поищи `miwifi_rd03_firmware_5cda9_1.0.47.bin`

2. **Утилита прошивки MIWIFIRepairTool:**
   [Скачать с сайта Xiaomi](https://miwifi.com/miwifi_download.html) — раздел "Repair Tool"

### Процедура прошивки

1. Отключи брандмауэр Windows и антивирус **на время прошивки**
2. Установи на ПК статический IP: `192.168.31.100`, маска `255.255.255.0`, шлюз `192.168.31.1`
3. Подключи кабель: **ПК → LAN-порт роутера** (не WAN!)
4. Переведи роутер в режим восстановления:
   - Выключи роутер
   - Зажми кнопку **Reset** на дне
   - Удерживая Reset, включи питание
   - Жди пока индикатор не станет **оранжевым/жёлтым** (~8 секунд)
   - Отпусти Reset
5. Запусти **MIWIFIRepairTool.exe**
6. Выбери файл прошивки `miwifi_rd03_firmware_5cda9_1.0.47.bin`
7. Нажми **Flash** и жди ~3-5 минут
8. Роутер перезагрузится — индикатор станет **синим**

---

## Шаг 2: Первичная настройка Xiaomi

1. Открой браузер и перейди на `http://192.168.31.1`
2. Пройди мастер настройки:
   - Выбери **"Подключение через DHCP"** (или любой тип — не важно)
   - Придумай **пароль WiFi** — он же станет паролем администратора
   - Запомни этот пароль — он нужен в следующем шаге
3. Дождись завершения настройки

---

## Шаг 3: Получи SSH через xmir-patcher

xmir-patcher — утилита, которая использует уязвимость в прошивке Xiaomi для получения доступа по SSH.

### Установка

Открой **PowerShell** или **командную строку** и выполни:

```powershell
git clone https://github.com/openwrt-xiaomi/xmir-patcher.git
cd xmir-patcher
pip install -r requirements.txt
```

### Скачай прошивку OpenWrt

Скачай в папку `xmir-patcher/firmware/`:

```powershell
# Создай папку firmware если её нет
mkdir firmware

# Скачай initramfs образ
curl -L -o firmware/openwrt-initramfs-factory.ubi `
  "https://downloads.openwrt.org/releases/24.10.0/targets/mediatek/filogic/openwrt-24.10.0-mediatek-filogic-xiaomi_mi-router-ax3000t-initramfs-factory.ubi"
```

Или скачай вручную через браузер:
**https://downloads.openwrt.org/releases/24.10.0/targets/mediatek/filogic/**

Найди файл: `openwrt-24.10.0-mediatek-filogic-xiaomi_mi-router-ax3000t-initramfs-factory.ubi`

Положи его в папку `xmir-patcher/firmware/`

### Запуск

```powershell
# В папке xmir-patcher:
python run.py
```

В меню выбирай по порядку:

```
> 1  # Set router IP address
  → Введи: 192.168.31.1

> 2  # Connect to device (install exploit)
  → Введи пароль WiFi из Шага 2
  → Дождись "OK" или "SSH enabled"

> 7  # Install firmware (from directory firmware/)
  → Подтверди установку
  → Дождись "Done" — роутер начнёт перезагружаться
```

> ⏳ Роутер перезагружается **40-70 секунд**. Индикатор станет **белым** — это OpenWrt initramfs.

---

## Шаг 4: Установи постоянную прошивку

Initramfs — это временная прошивка в RAM. После выключения роутер вернётся к Xiaomi. Нужно записать OpenWrt постоянно.

### Подключись по SSH

```powershell
ssh root@192.168.1.1
# Пароль не нужен — просто нажми Enter
```

### Скачай и запиши sysupgrade

```sh
cd /tmp

wget https://downloads.openwrt.org/releases/24.10.0/targets/mediatek/filogic/openwrt-24.10.0-mediatek-filogic-xiaomi_mi-router-ax3000t-squashfs-sysupgrade.bin

sysupgrade /tmp/openwrt-24.10.0-mediatek-filogic-xiaomi_mi-router-ax3000t-squashfs-sysupgrade.bin
```

> ⏳ Роутер прошивается ~2 минуты и перезагружается. **Не выключай и не трогай** в это время.

---

## Шаг 5: Первоначальная настройка OpenWrt

После перезагрузки:

```powershell
ssh root@192.168.1.1
# Пароль пустой — нажми Enter
```

### Установи пароль root

```sh
passwd
# Придумай и введи пароль дважды
```

### Проверь что интернет работает

Подключи кабель провайдера к **WAN-порту** (синий или с иконкой глобуса).

```sh
ping -c 3 8.8.8.8
```

Если интернет есть — ты готов к установке nikki и настройке VPN.

---

## Шаг 6: Установи luci-app-nikki

```sh
opkg update && opkg install luci-app-nikki
```

> Если пакет не нашёлся — проверь подключение к интернету и повтори.

После установки nikki появится в веб-интерфейсе: **http://192.168.1.1 → Services → Nikki**

---

## Что дальше?

Возвращайся к основной инструкции в [README.md](../README.md) — **Шаг 1: Скачай репозиторий**.

OpenWrt установлен, nikki установлен — остаётся только настроить VPN.

---

## Частые проблемы

### xmir-patcher не подключается к роутеру
- Убедись что IP роутера `192.168.31.1` (не .1.1)
- Проверь что ПК в той же сети: `ping 192.168.31.1`
- Попробуй выключить VPN на ПК если есть

### "Python not found" при запуске xmir-patcher
```powershell
# Установи Python
winget install Python.Python.3.12
# Или скачай с python.org
```

### После sysupgrade роутер не отвечает на 192.168.1.1
- Подожди 3-5 минут — прошивка может записываться дольше обычного
- Попробуй переподключиться к WiFi (`OpenWrt` или без имени)
- Если не помогает — жди ещё, не выключай

### В initramfs нет интернета (wget не скачивает)
Можно скачать sysupgrade заранее на ПК и передать на роутер:

```powershell
# На ПК — скачай файл
# Потом передай через SSH:
ssh root@192.168.1.1 "cat > /tmp/sysupgrade.bin" < openwrt-24.10.0-mediatek-filogic-xiaomi_mi-router-ax3000t-squashfs-sysupgrade.bin
ssh root@192.168.1.1 "sysupgrade /tmp/sysupgrade.bin"
```

### Роутер стал кирпичом
Попробуй аппаратное восстановление:
- Повтори Шаг 1 (MIWIFIRepairTool в режиме восстановления)
- Обратись на [форум OpenWrt](https://forum.openwrt.org/t/openwrt-support-for-xiaomi-ax3000t/180490)

---

## Ссылки

- [Firmware Selector для AX3000T](https://firmware-selector.openwrt.org/?target=mediatek%2Ffilogic&id=xiaomi_mi-router-ax3000t)
- [Все файлы OpenWrt 24.10.0 для AX3000T](https://downloads.openwrt.org/releases/24.10.0/targets/mediatek/filogic/)
- [xmir-patcher](https://github.com/openwrt-xiaomi/xmir-patcher)
- [Тема на форуме OpenWrt](https://forum.openwrt.org/t/openwrt-support-for-xiaomi-ax3000t/180490)
