@echo off
rem Live-sync: запусти меня из корня репозитория, затем в Roblox Studio
rem открой плагин Rojo и подключись к localhost:34872
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

echo [*] Запускаю rojo serve ^(:34872^) ...
echo     В Studio: плагин Rojo -^> Connect -^> Play. Ctrl+C здесь = остановить.
%ROJO% serve
pause
