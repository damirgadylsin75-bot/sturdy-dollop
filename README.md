# Sturdy Dollop II — день ноль

Новая игра. Инфраструктура разработки сохранена от первой игры:

- `serve.bat` — Rojo live-sync в Roblox Studio (положи рядом `rojo.exe`)
- CI: синтаксис всех `.luau`, headless-прогон модулей в настоящем Luau (WASM)
- `tools/rbx_cloud.py` + workflow **Remote exec** — запуск кода на настоящих
  серверах Roblox по метке `[remote-exec]` в коммите, отчёт — в комментах PR

Работа как раньше: pull → Rojo-синк → Play. Диагностика в три уровня работает.

Проект старой игры (v0.11.0, «крепости») живёт в истории git — коммит `58eeecd`.
