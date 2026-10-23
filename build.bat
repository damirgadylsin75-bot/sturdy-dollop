@echo off
chcp 65001 >nul
setlocal
rem Собирает game.rbxl из исходников. Открой файл в Roblox Studio и жми Play.
cd /d "%~dp0"

echo ============================================
echo   Sturdy Dollop: сборка game.rbxl
echo ============================================

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
  echo   3. Запусти build.bat снова.
  echo.
  pause
  exit /b 1
)

if not exist "default.project.json" (
  echo [ОШИБКА] default.project.json не найден.
  echo   Запускать build.bat нужно из корня репозитория.
  pause
  exit /b 1
)

echo.
echo [*] Rojo найден: "%ROJO%"
"%ROJO%" --version
echo.
echo [*] Собираю game.rbxl ...
"%ROJO%" build default.project.json -o game.rbxl
if errorlevel 1 (
  echo.
  echo [ОШИБКА] Сборка не удалась, см. текст ошибки выше.
  pause
  exit /b 1
)
echo.
echo [ГОТОВО] Файл собран: game.rbxl
echo          Открой его двойным кликом (откроется Roblox Studio) и жми Play.
echo.
pause
