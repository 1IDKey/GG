# GG Modpack Updater

Система синхронизации модпака **GG** (Minecraft 1.20.1 Forge) для группы игроков без кастомного лаунчера.

Работает на Windows 10/11. Использует PowerShell (встроен в систему).

---

## Для игроков

### Установка

1. Скачай **2 файла**: [`update-gui.bat`](update-gui.bat) и [`update-gui.ps1`](update-gui.ps1).
2. Положи куда угодно (например, на рабочий стол).
3. Убедись что у тебя установлена версия GG (Forge 1.20.1) в TLauncher и игра запускалась хотя бы раз.

### Использование

1. **Закрой Minecraft** (если открыт).
2. Двойной клик по `update-gui.bat`.
3. Если поле "Version folder" пустое → жми **Browse...** и выбери папку `.minecraft\versions\GG` (обычно `%APPDATA%\.minecraft\versions\GG`).
4. Жми **Update**. Скрипт:
   - Сравнит твои моды с актуальным списком.
   - Сделает бэкап папки `mods\` в `backups\` перед изменениями.
   - Удалит лишние, скачает недостающие/обновлённые.
   - Синкнет общие `config\` и `kubejs\` если их обновил админ.

### Если что-то пошло не так

- **Красная надпись "Minecraft is running"** → закрой игру, попробуй снова.
- **Synced folders показывает "needs update"** — после клика Update оно скачается.
- **Сборка сломалась после синка** → жми **Restore backup...**, выбери последний `mods-*.zip` из `<version>\backups\`.
- **Windows SmartScreen ругается** на .bat при первом запуске → "Подробнее" → "Выполнить в любом случае". Скрипт локальный, не подписан.

### Оставить свои моды (не синкать)

Создай рядом со скриптом файл `ignore.txt` (шаблон в [ignore.example.txt](ignore.example.txt)):

```
my-personal-map-mod.jar
xaeros*.jar
```

Эти моды не будут удаляться апдейтом.

### Обновление самого скрипта

Если в углу справа появится зелёное "v1.x.x → v1.y.z available" — клик обновит `update-gui.ps1` и `.bat` автоматически.

---

## Для админа (выпуск обновлений)

### Что нужно поставить один раз

- [Git for Windows](https://git-scm.com/download/win)
- [GitHub CLI](https://cli.github.com) (`winget install GitHub.cli`)
- `gh auth login` — авторизоваться через браузер

### Workflow обновления модпака

1. **Закрой Minecraft.**
2. Отредактируй папку модов: `%APPDATA%\.minecraft\versions\GG\mods\` (удали/добавь `.jar`).
3. Если надо — поправь `config\`, `kubejs\`.
4. Двойной клик по `publish-gui.bat`.
5. Окно покажет дифф:
   - **All mods (local)** — полный список модов.
   - **Added / Removed / Changed** — изменения против опубликованного.
   - **Synced folders** — статус `config` и `kubejs`.
6. Проверь, что дифф соответствует ожидаемому.
7. Впиши commit-сообщение и жми **Publish**. Скрипт сам:
   - Удалит из GitHub Release убранные `.jar`.
   - Зальёт новые/обновлённые.
   - Зазипует `config/` и `kubejs/`, сравнит по размеру с опубликованным, зальёт если отличается.
   - Перегенерит `manifest.json`.
   - Сделает `git commit` + `git push`.

Игроки кликают `update-gui.bat` — синкаются на твоё состояние.

### Добавить/убрать синкуемые папки

В `publish-gui.ps1` строка:

```powershell
$SyncFolders = @('config', 'kubejs')
```

Добавь `'defaultconfigs'`, `'resourcepacks'` — что нужно. Перезапусти publisher.

---

## Структура репо

```
update.bat / update.ps1           — консольный апдейтер (старый, fallback)
update-gui.bat / update-gui.ps1   — GUI-апдейтер для игроков
publish-gui.bat / publish-gui.ps1 — GUI-паблишер для админа
build-manifest.ps1                — генератор manifest.json
manifest.json                     — список всех файлов модпака
ignore.example.txt                — шаблон ignore.txt
```

На каждого юзера локально создаётся:

- `gg-updater.cfg` / `gg-publisher.cfg` — сохранённый путь к версии (gitignored).
- `ignore.txt` — персональный список "не трогать" (gitignored).
- `<version>\.gg-sync-state.json` — состояние синка папок.
- `<version>\backups\*.zip` — бэкапы до последних 5 операций.

## Куда залиты моды

GitHub Release: https://github.com/1IDKey/GG/releases/tag/v1.0.0 (все `.jar` + `folder__config.zip`, `folder__kubejs.zip`).
