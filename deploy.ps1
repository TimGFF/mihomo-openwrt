# ============================================================
#  Nikki (Mihomo) Deployer для Windows
#  Настройка прозрачного VPN на роутере OpenWrt через nikki
#
#  Требования: luci-app-nikki должен быть установлен на роутере
#
#  Запуск: правой кнопкой -> "Запустить с помощью PowerShell"
#  Или в терминале: .\deploy.ps1
# ============================================================

#Requires -Version 5.0

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot

# ────────────────────────────────────────────────────────────
#  ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ────────────────────────────────────────────────────────────

function Write-Header {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║   Nikki (Mihomo) VPN — Настройка роутера    ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step($n, $text) {
    Write-Host ""
    Write-Host "[$n] $text" -ForegroundColor Yellow
}

function Write-OK($text)   { Write-Host "    OK: $text" -ForegroundColor Green }
function Write-Warn($text) { Write-Host "    ПРЕДУПРЕЖДЕНИЕ: $text" -ForegroundColor Yellow }
function Write-Fail($text) {
    Write-Host ""
    Write-Host "  ОШИБКА: $text" -ForegroundColor Red
    Write-Host ""
    Write-Host "Нажмите Enter для выхода..."
    Read-Host | Out-Null
    exit 1
}

# Отправить текстовый файл на роутер через SSH stdin
# (работает без scp — только стандартный ssh)
function Send-File($localPath, $remotePath) {
    $text = [IO.File]::ReadAllText($localPath, [Text.Encoding]::UTF8)
    $text = $text -replace "`r`n", "`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $b64 = [Convert]::ToBase64String($bytes)
    $cmd = "printf '%s' '$b64' | base64 -d > '$remotePath'"
    $result = & ssh @script:SshOpts "root@$script:Router" $cmd 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Не удалось загрузить файл $localPath -> $remotePath`n$result"
    }
}

function Invoke-SSH($command) {
    $result = & ssh @script:SshOpts "root@$script:Router" $command 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "SSH команда завершилась с ошибкой:`n$command`n$result"
    }
    return $result
}

# ────────────────────────────────────────────────────────────
#  НАЧАЛО
# ────────────────────────────────────────────────────────────

Write-Header

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    Write-Fail "SSH не найден. Установи OpenSSH:`nSettings -> Apps -> Optional Features -> OpenSSH Client"
}

# ── Параметры ──────────────────────────────────────────────

Write-Host "  Введите параметры подключения:" -ForegroundColor White
Write-Host ""

$script:Router = Read-Host "  IP роутера (Enter = 192.168.1.1)"
if ([string]::IsNullOrWhiteSpace($script:Router)) { $script:Router = "192.168.1.1" }

$script:SshOpts = @(
    "-o", "StrictHostKeyChecking=no",
    "-o", "ConnectTimeout=15",
    "-o", "LogLevel=ERROR"
)

# ── Шаг 1: Проверка подключения ───────────────────────────

Write-Step "1/4" "Проверка подключения к $($script:Router)..."

Write-Host ""
Write-Host "  Подключаемся. Введите пароль если попросит." -ForegroundColor White
Write-Host "  (пароль root на OpenWrt обычно задаётся при первой настройке)" -ForegroundColor Gray
Write-Host ""

$testResult = & ssh @script:SshOpts "root@$script:Router" "echo CONNECTED" 2>&1
if ($LASTEXITCODE -ne 0 -or $testResult -notmatch "CONNECTED") {
    Write-Fail "Не удалось подключиться к $($script:Router).`n`nПроверь:`n  1. Компьютер подключён к роутеру`n  2. IP роутера правильный`n  3. SSH включён: OpenWrt -> System -> Administration"
}
Write-OK "Подключение успешно"

# Проверяем что nikki установлен
$nikkiCheck = & ssh @script:SshOpts "root@$script:Router" "test -d /etc/nikki && echo YES || echo NO" 2>&1
if ($nikkiCheck -notmatch "YES") {
    Write-Host ""
    Write-Host "  СТОП! luci-app-nikki не установлен на роутере." -ForegroundColor Red
    Write-Host ""
    Write-Host "  Установи его по SSH:" -ForegroundColor Yellow
    Write-Host "    ssh root@$($script:Router)" -ForegroundColor White
    Write-Host "    opkg update && opkg install luci-app-nikki" -ForegroundColor White
    Write-Host ""
    Write-Host "  Или через LuCI: System -> Software -> luci-app-nikki -> Install" -ForegroundColor White
    Write-Host ""
    Write-Host "  После установки снова запусти deploy.ps1" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Нажмите Enter для выхода..."
    Read-Host | Out-Null
    exit 1
}

$arch = & ssh @script:SshOpts "root@$script:Router" "uname -m" 2>&1
Write-OK "Роутер: $arch, nikki установлен"

# ── Шаг 2: Проверка профиля ───────────────────────────────

Write-Step "2/4" "Проверка профиля VPN..."

$profilePath = Join-Path $Root "mihomo\config.yaml"
if (-not (Test-Path $profilePath)) {
    Write-Fail "Файл mihomo\config.yaml не найден! Он должен быть рядом с deploy.ps1"
}

$profileContent = Get-Content $profilePath -Raw

if ($profileContent -match "YOUR_SUBSCRIPTION_URL") {
    Write-Host ""
    Write-Host "  СТОП! В файле mihomo\config.yaml не заполнен URL подписки." -ForegroundColor Red
    Write-Host "  Замени YOUR_SUBSCRIPTION_URL на твой URL." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Нажмите Enter для выхода..."
    Read-Host | Out-Null
    exit 1
}

if ($profileContent -match "YOUR_SERVER|YOUR_UUID|YOUR_PUBLIC_KEY") {
    Write-Host ""
    Write-Host "  СТОП! В файле mihomo\config.yaml есть незаполненные поля:" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Открой mihomo\config.yaml и замени:" -ForegroundColor Yellow
    Write-Host "    YOUR_SERVER      -> адрес VPN сервера (из vless:// ссылки, часть после @)" -ForegroundColor White
    Write-Host "    YOUR_UUID        -> UUID (часть до @)" -ForegroundColor White
    Write-Host "    YOUR_SNI         -> sni= из ссылки" -ForegroundColor White
    Write-Host "    YOUR_PUBLIC_KEY  -> pbk= из ссылки" -ForegroundColor White
    Write-Host "    YOUR_SHORT_ID    -> sid= из ссылки" -ForegroundColor White
    Write-Host ""
    Write-Host "  Пример ссылки:" -ForegroundColor Gray
    Write-Host "  vless://UUID@SERVER:443?pbk=PUBLIC_KEY&sid=SHORT_ID&sni=SNI" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Подробнее: README.md" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Нажмите Enter для выхода..."
    Read-Host | Out-Null
    exit 1
}

Write-OK "Профиль заполнен"

# ── Шаг 3: Загрузка профиля ───────────────────────────────

Write-Step "3/4" "Загрузка профиля на роутер..."

Invoke-SSH "mkdir -p /etc/nikki/profiles" | Out-Null
Send-File $profilePath "/etc/nikki/profiles/main.yaml"
Write-OK "Профиль загружен в /etc/nikki/profiles/main.yaml"

# ── Шаг 4: Настройка и запуск ─────────────────────────────

Write-Step "4/4" "Настройка nikki и запуск..."

$configScript = Join-Path $Root "openwrt\configure_nikki.sh"
if (-not (Test-Path $configScript)) {
    Write-Fail "Файл openwrt\configure_nikki.sh не найден!"
}

Send-File $configScript "/tmp/configure_nikki.sh"
& ssh @script:SshOpts "root@$script:Router" "sh /tmp/configure_nikki.sh"
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Настройка завершилась с ошибкой. Смотри вывод выше."
}

# ── Ждём запуска и проверяем ──────────────────────────────

Write-Host ""
Write-Host "  Ждём запуска nikki (30 секунд)..." -ForegroundColor Gray
Start-Sleep 32

$nikkiStatus = & ssh @script:SshOpts "root@$script:Router" "service nikki status 2>/dev/null | head -1" 2>&1
Write-OK "Nikki: $nikkiStatus"

# Проверяем VPN через API
$alive = & ssh @script:SshOpts "root@$script:Router" `
    "curl -s http://127.0.0.1:9090/providers/proxies 2>/dev/null | grep -o '""alive"":true' | head -1" 2>&1

if ($alive -match "alive.*true") {
    Write-Host ""
    Write-Host "  VPN alive: TRUE ✓" -ForegroundColor Green
} else {
    # Пробуем через прокси (для ручной VLESS)
    $proxyName = [Uri]::EscapeDataString("Мой VPN")
    $aliveProxy = & ssh @script:SshOpts "root@$script:Router" `
        "curl -s 'http://127.0.0.1:9090/proxies/$proxyName' 2>/dev/null | grep -o '""alive"":true' | head -1" 2>&1
    if ($aliveProxy -match "alive.*true") {
        Write-Host ""
        Write-Host "  VPN alive: TRUE ✓" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "  VPN alive: не удалось проверить автоматически" -ForegroundColor Yellow
        Write-Host "  Проверь вручную: http://$($script:Router):9090/ui" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Если alive: false — проверь server/uuid/public-key/short-id в профиле" -ForegroundColor Yellow
    }
}

# ── ИТОГ ──────────────────────────────────────────────────

Write-Host ""
Write-Host "══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  ГОТОВО!" -ForegroundColor Green
Write-Host "══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Подключись к WiFi роутера и проверь:" -ForegroundColor White
Write-Host "    YouTube, Instagram  →  через VPN" -ForegroundColor White
Write-Host "    VK, Яндекс, RuTube →  напрямую (без VPN)" -ForegroundColor White
Write-Host ""
Write-Host "  Веб-панель nikki:" -ForegroundColor White
Write-Host "    http://$($script:Router):9090/ui" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Логи (если что-то не работает):" -ForegroundColor White
Write-Host "    ssh root@$($script:Router) 'cat /var/log/nikki/app.log'" -ForegroundColor Gray
Write-Host "    ssh root@$($script:Router) 'cat /var/log/nikki/core.log'" -ForegroundColor Gray
Write-Host ""

Write-Host "Нажмите Enter для выхода..."
Read-Host | Out-Null
