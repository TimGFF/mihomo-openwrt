# ============================================================
#  Mihomo VPN Deployer для Windows
#  Автоматическая установка Mihomo на роутер OpenWrt
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
    Write-Host "║     Mihomo VPN — Установка на роутер         ║" -ForegroundColor Cyan
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
    # Читаем файл и конвертируем в UNIX-формат (LF вместо CRLF)
    $text = [IO.File]::ReadAllText($localPath, [Text.Encoding]::UTF8)
    $text = $text -replace "`r`n", "`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $b64 = [Convert]::ToBase64String($bytes)

    # Отправляем через SSH (base64 -> decode -> file)
    $cmd = "printf '%s' '$b64' | base64 -d > '$remotePath'"
    $result = & ssh @script:SshOpts "root@$script:Router" $cmd 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Не удалось загрузить файл $localPath -> $remotePath`n$result"
    }
}

function Invoke-SSH($command) {
    $result = & ssh @script:SshOpts "root@$script:Router" $command 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Команда SSH завершилась с ошибкой:`n$command`n$result"
    }
    return $result
}

# ────────────────────────────────────────────────────────────
#  НАЧАЛО СКРИПТА
# ────────────────────────────────────────────────────────────

Write-Header

# Проверяем что ssh доступен
if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    Write-Fail "SSH не найден. Установи OpenSSH:`nSettings -> Apps -> Optional Features -> OpenSSH Client"
}

# ── Запрашиваем параметры ──────────────────────────────────

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

Write-Step "1/5" "Проверка подключения к роутеру $($script:Router)..."

Write-Host ""
Write-Host "  Подключаемся к роутеру. Введите пароль если попросит." -ForegroundColor White
Write-Host "  (у свежего OpenWrt пароль обычно пустой — просто нажми Enter)" -ForegroundColor Gray
Write-Host ""

$testResult = & ssh @script:SshOpts "root@$script:Router" "echo CONNECTED" 2>&1
if ($LASTEXITCODE -ne 0 -or $testResult -notmatch "CONNECTED") {
    Write-Host ""
    Write-Fail "Не удалось подключиться к $($script:Router).`n`nПроверь:`n  1. Компьютер подключён к роутеру (кабель или WiFi)`n  2. IP роутера правильный`n  3. SSH включён на роутере (OpenWrt -> System -> Administration)"
}

Write-OK "Подключение успешно"

# Узнаём архитектуру роутера для информации
$arch = & ssh @script:SshOpts "root@$script:Router" "uname -m" 2>&1
$openwrtVer = & ssh @script:SshOpts "root@$script:Router" "cat /etc/openwrt_release 2>/dev/null | grep DISTRIB_RELEASE | cut -d= -f2 | tr -d chr(39)" 2>&1
Write-OK "Роутер: архитектура $arch, OpenWrt $openwrtVer"

# ── Шаг 2: Проверка config.yaml ───────────────────────────

Write-Step "2/5" "Проверка конфигурации VPN..."

$configPath = Join-Path $Root "mihomo\config.yaml"
if (-not (Test-Path $configPath)) {
    Write-Fail "Файл mihomo\config.yaml не найден! Он должен быть рядом с deploy.ps1"
}

$configContent = Get-Content $configPath -Raw
if ($configContent -match "YOUR_SERVER|YOUR_UUID|YOUR_PUBLIC_KEY") {
    Write-Host ""
    Write-Host "  СТОП! В файле mihomo\config.yaml есть незаполненные поля:" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Открой файл mihomo\config.yaml в любом редакторе и замени:" -ForegroundColor Yellow
    Write-Host "    YOUR_SERVER      -> адрес VPN сервера (например: vpn.example.com)" -ForegroundColor White
    Write-Host "    YOUR_UUID        -> твой UUID (из vless:// ссылки)" -ForegroundColor White
    Write-Host "    YOUR_SNI         -> SNI (sni= из vless:// ссылки)" -ForegroundColor White
    Write-Host "    YOUR_PUBLIC_KEY  -> публичный ключ (pbk= из vless:// ссылки)" -ForegroundColor White
    Write-Host "    YOUR_SHORT_ID    -> short-id (sid= из vless:// ссылки)" -ForegroundColor White
    Write-Host ""
    Write-Host "  Пример vless:// ссылки:" -ForegroundColor Gray
    Write-Host "  vless://UUID@SERVER:443?pbk=PUBLIC_KEY&sid=SHORT_ID&sni=SNI&..." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Подробная инструкция: README.md" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Нажмите Enter для выхода..."
    Read-Host | Out-Null
    exit 1
}

Write-OK "config.yaml заполнен"

# ── Шаг 3: Установка Mihomo ───────────────────────────────

Write-Step "3/5" "Установка Mihomo на роутер (2-5 минут)..."
Write-Host "  Скачивает: mihomo бинарник, GeoIP, GeoSite базы, веб-панель" -ForegroundColor Gray
Write-Host ""

$installScript = Join-Path $Root "openwrt\install_mihomo.sh"
if (-not (Test-Path $installScript)) {
    Write-Fail "Файл openwrt\install_mihomo.sh не найден!"
}

# Загружаем скрипт на роутер
Send-File $installScript "/tmp/install_mihomo.sh"

# Запускаем (вывод в реальном времени)
& ssh @script:SshOpts "root@$script:Router" "sh /tmp/install_mihomo.sh"
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Установка Mihomo завершилась с ошибкой. Смотри вывод выше."
}

Write-OK "Mihomo установлен"

# ── Шаг 4: Загрузка конфигурации ──────────────────────────

Write-Step "4/5" "Загрузка конфигурации VPN..."

Send-File $configPath "/etc/mihomo/config.yaml"
Write-OK "config.yaml загружен в /etc/mihomo/config.yaml"

# ── Шаг 5: Запуск Mihomo ──────────────────────────────────

Write-Step "5/5" "Запуск Mihomo..."

Invoke-SSH "service mihomo restart" | Out-Null
Write-Host "  Ждём запуска (15 секунд)..." -ForegroundColor Gray
Start-Sleep 15

# Проверяем статус
$status = & ssh @script:SshOpts "root@$script:Router" "service mihomo status 2>&1 | head -1" 2>&1
Write-OK "Сервис: $status"

# Проверяем proxy alive через API
$proxyName = [Uri]::EscapeDataString("Мой VPN")
$alive = & ssh @script:SshOpts "root@$script:Router" "wget -q -O - 'http://localhost:9090/proxies/$proxyName' 2>/dev/null | grep -o '\"alive\":[a-z]*' | head -1" 2>&1

if ($alive -match "alive.*true") {
    Write-Host ""
    Write-Host "  VPN alive: TRUE ✓" -ForegroundColor Green
} elseif ($alive -match "alive.*false") {
    Write-Host ""
    Write-Host "  VPN alive: FALSE" -ForegroundColor Red
    Write-Host "  Возможные причины:" -ForegroundColor Yellow
    Write-Host "    - Неверный server/uuid/public-key/short-id в config.yaml" -ForegroundColor White
    Write-Host "    - VPN сервер временно недоступен" -ForegroundColor White
    Write-Host "    - short-id мог измениться (скачай свежую подписку и обнови)" -ForegroundColor White
} else {
    Write-Host ""
    Write-Host "  Статус VPN: проверь вручную (возможно ещё запускается)" -ForegroundColor Yellow
}

# ── ИТОГ ──────────────────────────────────────────────────

Write-Host ""
Write-Host "══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  УСТАНОВКА ЗАВЕРШЕНА!" -ForegroundColor Green
Write-Host "══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Подключись к WiFi роутера и проверь:" -ForegroundColor White
Write-Host "    YouTube, Instagram -> должны открываться через VPN" -ForegroundColor White
Write-Host "    VK, Яндекс, RuTube -> открываются напрямую (без VPN)" -ForegroundColor White
Write-Host ""
Write-Host "  Веб-панель управления:" -ForegroundColor White
Write-Host "    http://$($script:Router):9090/ui" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Логи (если что-то не работает):" -ForegroundColor White
Write-Host "    ssh root@$($script:Router) 'logread | grep mihomo | tail -30'" -ForegroundColor Gray
Write-Host ""

Write-Host "Нажмите Enter для выхода..."
Read-Host | Out-Null
