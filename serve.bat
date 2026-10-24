@echo off
chcp 65001 >nul
setlocal
rem Живой синк кода в Roblox Studio.
rem Окно ДОЛЖНО оставаться открытым, пока играешь. Не закрывай его.
cd /d "%~dp0"

echo ============================================
echo   Sturdy Dollop: rojo serve (:34872)
echo ============================================

rem --- ищем rojo.exe: сначала рядом со скриптом, потом в PATH ---
set "ROJO="
if exist "%~dp0rojo.exe" set "ROJO=%~dp0rojo.exe"
if not defined ROJO (
  where rojo.exe >nul 2>nul && set "ROJO=rojo.exe"
)
if not defined ROJO (
  where rojo >nul 2>nul && set "ROJO=rojo"
)
if not defined ROJO (
  echo.
  echo [ОШИБКА] Rojo не найден.
  echo   1. Скачай: https://github.com/rojo-rbx/rojo/releases/latest
  echo      файл rojo-7.7.1-windows-x86_64.zip
  echo   2. Распакуй и положи rojo.exe В КОРЕНЬ этой папки:
  echo      %~dp0
  echo   3. Запусти serve.bat снова.
  echo.
  pause
  exit /b 1
)

if not exist "default.project.json" (
  echo [ОШИБКА] default.project.json не найден.
  echo   Запускать serve.bat нужно из корня репозитория ^(там, где папка src^).
  pause
  exit /b 1
)

echo.
echo [*] Rojo найден: "%ROJO%"
"%ROJO%" --version
echo.
echo [*] Запускаю сервер синхронизации...
echo     Далее в Roblox Studio: плагин Rojo -^> Connect -^> Play.
echo     ЭТО ОКНО НЕ ЗАКРЫВАТЬ. Остановка: Ctrl+C или закрыть окно.
echo.
"%ROJO%" serve

echo.
echo [*] Сервер остановлен.
pause
