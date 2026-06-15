@echo off
setlocal

echo ============================================
echo   Procreate Thumbnail Shell Extension
echo   Uninstaller
echo ============================================
echo.

REM Check admin
net session >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
    exit /b 0
)

set "SCRIPT_DIR=%~dp0"
set "DLL_PATH=%SCRIPT_DIR%ProcreateThumbnailProvider.dll"

if not exist "%DLL_PATH%" (
    echo [ERROR] DLL not found: %DLL_PATH%
    pause
    exit /b 1
)

echo [1/3] Unregistering COM component...

set "REGASM64=C:\Windows\Microsoft.NET\Framework64\v4.0.30319\RegAsm.exe"
set "REGASM32=C:\Windows\Microsoft.NET\Framework\v4.0.30319\RegAsm.exe"

if exist "%REGASM64%" "%REGASM64%" "%DLL_PATH%" /unregister
if exist "%REGASM32%" "%REGASM32%" "%DLL_PATH%" /unregister 2>nul

echo [OK] COM unregistered.

echo.
echo [2/3] Cleaning registry...

reg delete "HKCR\.procreate\ShellEx\{e357fccd-a995-4576-b01f-234630154e96}" /f 2>nul
reg delete "HKLM\Software\Classes\.procreate\ShellEx\{e357fccd-a995-4576-b01f-234630154e96}" /f 2>nul
reg delete "HKCR\CLSID\{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}" /f 2>nul
reg delete "HKLM\Software\Classes\CLSID\{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}" /f 2>nul
reg delete "HKLM\Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved" /v "{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}" /f 2>nul

echo [OK] Registry cleaned.

echo.
echo [3/3] Restarting Explorer...

del /f /q "%LOCALAPPDATA%\Microsoft\Windows\Explorer\thumbcache_*.db" 2>nul
ie4uinit.exe -ClearIconCache 2>nul
taskkill /f /im explorer.exe >nul 2>&1
start explorer.exe

echo.
echo ============================================
echo   Uninstall Complete!
echo ============================================
echo.
pause
