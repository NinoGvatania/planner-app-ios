# Прототип планировщика

Интерактивный веб‑прототип экрана в формате холста Claude Design (`.dc.html`).
Смотреть и трогать: https://claude.ai/artifact/FaHx7HRgcbov9Kw9mHYFTh

- `project/Main.dc.html` — весь экран: шаблон (разметка с `{{ holes }}`, `<sc-if>`, `<sc-for>`)
  и класс `Component` с логикой (задачи, жесты, парсер быстрого ввода, раскладка).
- `project/*.dc.html` остальные — сцены: импортируют `Main` с параметром `scene`
  (`three`, `list`, `matrix`, `backlog`, `drag`, `resize`, `overdue`, `voice`).
- `project/canvas.json` — раскладка артбордов на холсте.
- `harness/` — локальный прогон в Chromium: `node serve.js <папка-с-файлами> 8765`, затем
  `node run.js <папка-для-скриншотов>`. В папке с файлами должен лежать `support.js`
  (рантайм холста; берётся из артефакта, файл `artifact-type/dc-runtime.js`). Нужен `playwright`.

Как менять: править `Main.dc.html`, публиковать на тот же холст (в сессии Claude Code —
инструмент Artifact с `url` холста), прогонять `harness/run.js`.
