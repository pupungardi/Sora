<#
.SYNOPSIS
    Builds Sora for Windows.

.DESCRIPTION
    Sora on Windows is a Win32 shell + libmpv (runtime-loaded mpv-2.dll) plus
    the nuvio-engine C API for magnet links.

    nuvio-engine cannot be compiled on a Windows host: its build scripts assume
    a Linux container toolchain. Build the package once with Docker, then this
    script wires it in:

        scripts\build-windows.ps1 -BuildEngine

    That calls vendor\nuvio-engine\scripts\build-windows-packages.sh through
    Docker (needs Docker Desktop with Linux containers) and unpacks
    nuvio-engine-windows-x86_64.zip into vendor\engine-windows.

.PARAMETER BuildEngine
    Build the engine Windows package first (requires Docker).

.PARAMETER MpvDll
    Path to mpv-2.dll; copied next to Sora.exe. Get it from
    https://sourceforge.net/projects/mpv-player-windows/files/64bit/

.PARAMETER Config
    CMake build type: Debug (default) or Release.

.EXAMPLE
    scripts\build-windows.ps1 -MpvDll C:\tools\mpv\mpv-2.dll -BuildEngine -Config Release
#>

[CmdletBinding()]
param(
    [switch]$BuildEngine,
    [string]$MpvDll = "",
    [ValidateSet("Debug", "Release")]
    [string]$Config = "Debug"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$vendor = Join-Path $repoRoot "vendor"
$enginePackage = Join-Path $vendor "engine-windows"
$buildDir = Join-Path $repoRoot "windows\build"
$mpvDllPath = ""

function Require-Command([string]$Name, [string]$Hint) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Missing '$Name'. $Hint"
    }
}

Write-Host "==> checking toolchain" -ForegroundColor Cyan
Require-Command cmake "Install CMake 3.22+ (winget install Kitware.CMake) or run this from a Visual Studio Developer PowerShell."

if (-not (Test-Path (Join-Path $vendor "nuvio-engine"))) {
    Write-Host "==> vendor\nuvio-engine missing, cloning it" -ForegroundColor Yellow
    Require-Command git "Install Git for Windows."
    $ref = if ($env:NUVIO_ENGINE_REF) { $env:NUVIO_ENGINE_REF } else { "main" }
    New-Item -ItemType Directory -Force -Path $vendor | Out-Null
    & git clone --depth 1 --branch $ref https://github.com/NuvioMedia/nuvio-engine.git (Join-Path $vendor "nuvio-engine")
    if ($LASTEXITCODE -ne 0) { throw "git clone failed" }
}

if ($BuildEngine) {
    Require-Command docker "Install Docker Desktop and switch it to Linux containers."
    $packagesScript = Join-Path $vendor "nuvio-engine\scripts\build-windows-packages.sh"
    if (-not (Test-Path $packagesScript)) {
        throw "Not found: $packagesScript"
    }
    $bash = Get-Command bash -ErrorAction SilentlyContinue
    if (-not $bash) {
        throw "The engine build script needs bash. Install Git for Windows and rerun."
    }
    $shellName = & bash -c "uname -s"
    if ($shellName -notmatch "MINGW|MSYS") {
        throw "bash resolved to '$shellName'. Use Git Bash, not WSL, so Docker paths translate correctly."
    }
    Write-Host "==> building nuvio-engine Windows packages in Docker (x86_64 + aarch64)" -ForegroundColor Cyan
    & bash ($packagesScript -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "engine package build failed" }

    $zip = Join-Path $vendor "nuvio-engine\platform\windows\dist\nuvio-engine-windows-x86_64.zip"
    if (-not (Test-Path $zip)) {
        throw "Docker build finished but $zip is missing."
    }
    if (Test-Path $enginePackage) { Remove-Item $enginePackage -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $enginePackage -Force
    Write-Host "    unpacked to vendor\engine-windows" -ForegroundColor Green
}

if ($MpvDll) {
    if (-not (Test-Path $MpvDll)) { throw "mpv-2.dll not found at $MpvDll" }
    $mpvDllPath = (Resolve-Path $MpvDll).Path
}

$configureArgs = @(
    "-S", (Join-Path $repoRoot "windows"),
    "-B", $buildDir,
    "-DCMAKE_BUILD_TYPE=$Config"
)
if (Test-Path (Join-Path $enginePackage "lib")) {
    $configureArgs += "-DNUVIO_ENGINE_DIR=$enginePackage"
} else {
    Write-Host "==> nuvio-engine package not found; building without magnet support" -ForegroundColor Yellow
}
if ($mpvDllPath) {
    $configureArgs += "-DMPV_DLL=$mpvDllPath"
}

Write-Host "==> configuring" -ForegroundColor Cyan
& cmake @configureArgs
if ($LASTEXITCODE -ne 0) { throw "cmake configure failed" }

Write-Host "==> building" -ForegroundColor Cyan
& cmake --build $buildDir --config $Config
if ($LASTEXITCODE -ne 0) { throw "cmake build failed" }

$exe = Get-ChildItem -Path $buildDir -Filter "Sora.exe" -Recurse | Select-Object -First 1
if (-not $exe) { throw "Sora.exe was not produced" }

Write-Host ""
Write-Host "==> done" -ForegroundColor Green
Write-Host "    exe: $($exe.FullName)"
Write-Host "    mpv-2.dll must sit next to Sora.exe (pass -MpvDll to copy it automatically)."
