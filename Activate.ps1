# Activate.ps1 - Procreate Thumbnail Shell Extension
# ====================================================
# Usage: Right-click -> "Run with PowerShell" (as Administrator)
# This script will: compile DLL, register COM, clear cache, restart Explorer

$ErrorActionPreference = "Continue"

# ---- Check Admin ----
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process -Verb RunAs -FilePath powershell.exe -ArgumentList "-NoProfile -NoExit -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`""
    exit
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$csFile    = Join-Path $scriptDir "ProcreateThumbnailProvider.cs"
$dllFile   = Join-Path $scriptDir "ProcreateThumbnailProvider.dll"
$cscExe    = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$regasmExe = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\RegAsm.exe"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Procreate Thumbnail Provider - Activate" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# STEP 1: Kill any process holding the old DLL
# ============================================================
Write-Host "[1/4] Freeing locked files..." -ForegroundColor Yellow
taskkill /f /im dllhost.exe 2>$null | Out-Null
taskkill /f /im explorer.exe 2>$null | Out-Null
Start-Sleep -Seconds 2

# Try to delete old DLL
Remove-Item $dllFile -Force -ErrorAction SilentlyContinue
if (Test-Path $dllFile) {
    Write-Host "  WARNING: DLL still locked. Trying handle release..." -ForegroundColor Yellow
    Start-Sleep -Seconds 3
    Remove-Item $dllFile -Force -ErrorAction SilentlyContinue
}
Write-Host "  [OK] Old files released" -ForegroundColor Green

# ============================================================
# STEP 2: Compile DLL from source
# ============================================================
Write-Host "[2/4] Compiling DLL from source..." -ForegroundColor Yellow
$compileArgs = @(
    "/target:library",
    "/out:`"$dllFile`"",
    "/reference:System.Drawing.dll",
    "/reference:System.IO.Compression.dll",
    "/reference:System.IO.Compression.FileSystem.dll",
    "/platform:anycpu",
    "`"$csFile`""
)
$result = & $cscExe $compileArgs 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "  [ERROR] Compilation failed:" -ForegroundColor Red
    Write-Host $result
    pause
    exit 1
}
Write-Host "  [OK] DLL compiled: $dllFile" -ForegroundColor Green

# ============================================================
# STEP 3: Register COM with RegAsm
# ============================================================
Write-Host "[3/4] Registering COM component..." -ForegroundColor Yellow
& $regasmExe "$dllFile" /codebase /tlb 2>&1 | ForEach-Object {
    if ($_ -match "warning") { Write-Host "  $_" -ForegroundColor Yellow }
    elseif ($_ -match "error") { Write-Host "  $_" -ForegroundColor Red }
    else { Write-Host "  $_" -ForegroundColor Gray }
}
if ($LASTEXITCODE -ne 0) {
    Write-Host "  [ERROR] RegAsm failed!" -ForegroundColor Red
    pause
    exit 1
}
Write-Host "  [OK] COM registered" -ForegroundColor Green

# ============================================================
# STEP 4: Clear cache and restart Explorer
# ============================================================
Write-Host "[4/4] Clearing thumbnail cache and restarting Explorer..." -ForegroundColor Yellow
Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db" -Force -ErrorAction SilentlyContinue
ie4uinit.exe -ClearIconCache 2>$null
ie4uinit.exe -Show 2>$null

Start-Process explorer.exe
Start-Sleep -Seconds 2

# ============================================================
# Summary
# ============================================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  ACTIVATION COMPLETE!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Open any folder with .procreate files"
Write-Host "  to see thumbnail previews."
Write-Host ""
Write-Host "  If still not showing:"
Write-Host "    1. Log out and log back in"
Write-Host "    2. Or run: ie4uinit.exe -ClearIconCache"
Write-Host ""
pause
