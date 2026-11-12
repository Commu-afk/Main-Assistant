# Собирает ggml-cpu.dll из исходников llama.cpp без AVX2.
#
# Зачем: приложение получает предсобранный llama.cpp от пакета llamadart,
# а он скомпилирован с AVX2. На старых CPU (Sandy Bridge и раньше, например
# i5-2500K) такой плагин не грузится: "backend ggml-cpu.dll is not supported
# on this system". Этот скрипт собирает тот же коммит llama.cpp, что и
# llamadart, но только с AVX/SSE4.2 - и кладёт DLL в native/win-x64/.
#
# Требуется: Visual Studio с C++ (MSVC) и CMake/Ninja из его поставки.
# Запуск: powershell -ExecutionPolicy Bypass -File tool\build_ggml_cpu.ps1

param(
    # Коммит llama.cpp, на котором собран llamadart 0.16.2 (submodule
    # в leehack/llamadart-native, тег v0.7.0-2). Менять только при обновлении
    # пакета llamadart - иначе ABI не совпадёт.
    [string]$Commit = "620d2225cc436ab0b001e3200e590e3b286ef9ab",
    [string]$OutDir = "native\win-x64"
)

$ErrorActionPreference = "Stop"

$vsRoot = "C:\Program Files\Microsoft Visual Studio\18\Community"
$cmake = Join-Path $vsRoot "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
$ninja = Join-Path $vsRoot "Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe"
$vcvars = Join-Path $vsRoot "VC\Auxiliary\Build\vcvars64.bat"

foreach ($tool in @($cmake, $ninja, $vcvars)) {
    if (-not (Test-Path $tool)) {
        throw "Не найдено: $tool. Установите Visual Studio с компонентом 'Desktop development with C++'."
    }
}

$srcRoot = Join-Path $env:TEMP "llamacpp-src"
$srcDir = Join-Path $srcRoot "llama.cpp-$Commit"
$buildDir = Join-Path $env:TEMP "llamacpp-build-sandybridge"

if (-not (Test-Path $srcDir)) {
    New-Item -ItemType Directory -Force -Path $srcRoot | Out-Null
    $zip = Join-Path $srcRoot "$Commit.zip"
    if (-not (Test-Path $zip)) {
        Write-Host "Скачиваю исходники llama.cpp $Commit ..."
        py -3 -c "import urllib.request,sys; urllib.request.urlretrieve(sys.argv[1], sys.argv[2])" `
            "https://codeload.github.com/ggml-org/llama.cpp/zip/$Commit" $zip
    }
    Write-Host "Распаковываю ..."
    py -3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" $zip $srcRoot
}

$configure = @(
    "`"$vcvars`" >nul && `"$cmake`" -G Ninja",
    "-S `"$srcDir`" -B `"$buildDir`"",
    "-DCMAKE_MAKE_PROGRAM=`"$ninja`"",
    "-DCMAKE_BUILD_TYPE=Release",
    # Главное отличие от сборки llamadart: без AVX2/BMI2, с AVX и SSE4.2.
    "-DGGML_NATIVE=OFF",
    "-DGGML_BACKEND_DL=ON",
    "-DBUILD_SHARED_LIBS=ON",
    "-DGGML_AVX=ON",
    "-DGGML_SSE42=ON",
    "-DGGML_AVX2=OFF",
    "-DGGML_BMI2=OFF",
    "-DGGML_AVX512=OFF",
    "-DGGML_BLAS=OFF",
    "-DGGML_VULKAN=OFF",
    "-DGGML_CUDA=OFF",
    "-DLLAMA_BUILD_TESTS=OFF",
    "-DLLAMA_BUILD_EXAMPLES=OFF",
    "-DLLAMA_BUILD_TOOLS=OFF",
    "-DLLAMA_BUILD_SERVER=OFF"
) -join " "

Write-Host "Конфигурирую CMake ..."
cmd /c $configure | Select-Object -Last 5

Write-Host "Собираю ggml-cpu ..."
cmd /c "`"$vcvars`" >nul && `"$cmake`" --build `"$buildDir`" --target ggml-cpu -j 4" |
    Select-Object -Last 5

$built = Join-Path $buildDir "bin\ggml-cpu.dll"
if (-not (Test-Path $built)) { throw "Сборка не дала ggml-cpu.dll" }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$target = Join-Path $OutDir "ggml-cpu.dll"
Copy-Item $built $target -Force

Write-Host ""
Write-Host "Готово: $target"
Write-Host "Теперь примените его к приложению: tool\patch_ggml_cpu.ps1"
