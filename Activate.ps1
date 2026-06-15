# Activate.ps1 - Procreate Thumbnail Shell Extension
# ====================================================
# Usage: Right-click -> "Run with PowerShell" (as Administrator)
# This script will: compile DLL, register COM, fix registry, clear cache, restart Explorer

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
$clsid     = "{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Procreate Thumbnail Provider - Activate" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# STEP 1: Kill any process holding the old DLL
# ============================================================
Write-Host "[1/5] Freeing locked files..." -ForegroundColor Yellow
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
Write-Host "[2/5] Compiling DLL from source..." -ForegroundColor Yellow
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
Write-Host "[3/5] Registering COM component..." -ForegroundColor Yellow
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
# STEP 4: Verify and fix ALL registry keys
# ============================================================
Write-Host "[4/5] Verifying registry keys..." -ForegroundColor Yellow

$thumbGuid = "{e357fccd-a995-4576-b01f-234630154e96}"
$ext       = ".procreate"
$name      = "Procreate Thumbnail Provider"
$dllCodeBase = "file:///E:/Ravenft Rilogic Artworks/FineArt/ProcreateThumbnailProvider/ProcreateThumbnailProvider.DLL"
$asmName = "ProcreateThumbnailProvider, Version=0.0.0.0, Culture=neutral, PublicKeyToken=null"
$className = "ProcreateThumbnailProvider.ProcreateThumbnailProvider"

# Use .NET Registry API for maximum reliability (avoids PSDrive issues)
function Set-RegValue($hive, $subkey, $name, $value, $kind) {
    $k = $hive.CreateSubKey($subkey)
    if ($kind -eq "DWord") { $k.SetValue($name, $value, [Microsoft.Win32.RegistryValueKind]::DWord) }
    else { $k.SetValue($name, $value) }
    $k.Close()
}

function Ensure-SubKey($hive, $subkey) {
    $k = $hive.CreateSubKey($subkey)
    $k.Close()
}

$HKLM = [Microsoft.Win32.Registry]::LocalMachine
$HKCR = [Microsoft.Win32.Registry]::ClassesRoot

# (a) InprocServer32 via ClassesRoot (this is what Windows actually reads)
Write-Host "  [a] InprocServer32..."
Set-RegValue $HKCR "CLSID\$clsid\InprocServer32" $null "mscoree.dll"
Set-RegValue $HKCR "CLSID\$clsid\InprocServer32" "Assembly" $asmName
Set-RegValue $HKCR "CLSID\$clsid\InprocServer32" "Class" $className
Set-RegValue $HKCR "CLSID\$clsid\InprocServer32" "CodeBase" $dllCodeBase
Set-RegValue $HKCR "CLSID\$clsid\InprocServer32" "RuntimeVersion" "v4.0.30319"
Set-RegValue $HKCR "CLSID\$clsid\InprocServer32" "ThreadingModel" "Both"
Write-Host "  [OK] InprocServer32" -ForegroundColor Green

# (b) CLSID Name + DisableProcessIsolation
Set-RegValue $HKCR "CLSID\$clsid" $null $name
Set-RegValue $HKCR "CLSID\$clsid" "DisableProcessIsolation" 1 "DWord"
Write-Host "  [OK] CLSID + DisableProcessIsolation" -ForegroundColor Green

# (c) Implemented Categories
Ensure-SubKey $HKCR "CLSID\$clsid\Implemented Categories\{62C8FE65-4EBB-45e7-B440-6E39B2CDBF29}"
Write-Host "  [OK] Implemented Categories" -ForegroundColor Green

# (d) ShellEx
Set-RegValue $HKCR "$ext\ShellEx\$thumbGuid" $null $clsid
Write-Host "  [OK] ShellEx" -ForegroundColor Green

# (e) .procreate metadata
Set-RegValue $HKCR $ext "Content Type" "application/x-procreate"
Set-RegValue $HKCR $ext "PerceivedType" "image"
Write-Host "  [OK] .procreate metadata" -ForegroundColor Green

# (f) Approved list
Set-RegValue $HKLM "Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved" $clsid $name
Write-Host "  [OK] Approved list" -ForegroundColor Green

# ============================================================
# STEP 5: Clear cache and restart Explorer
# ============================================================
Write-Host "[5/5] Clearing thumbnail cache and restarting Explorer..." -ForegroundColor Yellow
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
