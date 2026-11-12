# Подменяет ggml-cpu.dll во всех местах, откуда её берут llamadart и сборка.
#
# Зачем: пакет llamadart тянет предсобранный llama.cpp с AVX2, который не
# работает на CPU без AVX2 (Sandy Bridge/i5-2500K и старше). Собранную под
# такой CPU DLL (см. tool\build_ggml_cpu.ps1) нужно положить:
#   - в распакованный бандл в pub-кэше (источник для build-hook),
#   - в кэш hooks_runner проекта,
#   - в .dart_tool\lib (оттуда библиотека грузится при `dart run`),
#   - в готовые сборки build\windows\...\runner\{Debug,Release}.
#
# Запускать после `flutter pub get`, обновления llamadart и после
# `flutter build windows` (сборка копирует DLL заново).
#
# Запуск: powershell -ExecutionPolicy Bypass -File tool\patch_ggml_cpu.ps1

param(
    [string]$Source = "native\win-x64\ggml-cpu.dll",
    [switch]$Restore
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

$sourcePath = Join-Path $projectRoot $Source
if (-not (Test-Path $sourcePath)) {
    throw "Нет файла $Source. Сначала соберите его: tool\build_ggml_cpu.ps1"
}
if (-not $Restore -and (Get-Item $sourcePath).Length -lt 500KB) {
    throw "Подозрительно маленький файл $Source - это точно ggml-cpu.dll?"
}

$replaced = 0
$skipped = 0

function Update-Plugin {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }

    $backup = "$Path.orig"
    if ($Restore) {
        if (Test-Path $backup) {
            Copy-Item $backup $Path -Force
            Write-Host "  восстановлен: $Path"
            $script:replaced++
        }
        return
    }

    if (-not (Test-Path $backup)) { Copy-Item $Path $backup }
    if ((Get-FileHash $Path).Hash -eq (Get-FileHash $sourcePath).Hash) {
        $script:skipped++
        return
    }
    Copy-Item $sourcePath $Path -Force
    Write-Host "  заменён: $Path"
    $script:replaced++
}

# 1. Распакованный бандл llamadart в pub-кэше
$pubCache = Join-Path $env:LOCALAPPDATA "Pub\Cache\hosted\pub.dev"
if (Test-Path $pubCache) {
    Get-ChildItem $pubCache -Directory -Filter "llamadart-*" | ForEach-Object {
        $bundleRoot = Join-Path $_.FullName ".dart_tool\llamadart\native_bundles"
        if (Test-Path $bundleRoot) {
            Get-ChildItem $bundleRoot -Recurse -Filter "ggml-cpu.dll" -File |
                ForEach-Object { Update-Plugin $_.FullName }
        }
    }
}

# 2. Кэш build-hook'а в проекте
$hooksRoot = ".dart_tool\hooks_runner\shared\llamadart\build"
if (Test-Path $hooksRoot) {
    Get-ChildItem $hooksRoot -Recurse -Filter "ggml-cpu.dll" -File |
        ForEach-Object { Update-Plugin $_.FullName }
}

# 3. Каталог нативных библиотек для `dart run`
Update-Plugin ".dart_tool\lib\ggml-cpu.dll"

# 4. Готовые сборки приложения
foreach ($config in @("Debug", "Release", "Profile")) {
    Update-Plugin "build\windows\x64\runner\$config\ggml-cpu.dll"
}

Write-Host ""
if ($Restore) {
    Write-Host "Восстановлено файлов: $replaced"
} else {
    Write-Host "Заменено: $replaced, уже актуальных: $skipped"
}
Write-Host "Проверка: выполните tool\llm_check.dart или запустите приложение."
