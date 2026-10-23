@echo off
rem Собирает game.rbxl из исходников: открой файл в Roblox Studio и жми Play
setlocal
set "ROJO=rojo"
if exist "%~dp0rojo.exe" set "ROJO=%~dp0rojo.exe"

where %ROJO% >nul 2>nul
if errorlevel 1 (
  if not exist "%~dp0rojo.exe" (
    echo [!] Rojo не найден.
    echo     Скачай rojo-7.7.1-windows-x86_64.zip с:
    echo     https://github.com/rojo-rbx/rojo/releases/latest
    echo     и положи rojo.exe рядом с этим файлом ^(в папку репозитория^)
    echo     либо добавь Rojo в PATH.
    pause
    exit /b 1
  )
)

echo [*] Собираю game.rbxl ...
%ROJO% build default.project.json -o game.rbxl
if errorlevel 1 (
  echo [!] Сборка не удалась, см. ошибку выше.
  pause
  exit /b 1
)
echo [+] Готово: game.rbxl — открой его в Roblox Studio и нажми Play.
pause
