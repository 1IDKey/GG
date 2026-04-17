# GG Modpack Updater

Система синхронизации модпака **GG** (Minecraft 1.20.1 Forge) для группы игроков без кастомного лаунчера.

Работает на Windows 10/11. Использует PowerShell (встроен в систему).

---

## Для игроков

### Установка

1. Скачай **2 файла**: [`update-gui.bat`](update-gui.bat) и [`update-gui.ps1`](update-gui.ps1).
2. Положи куда угодно (например, на рабочий стол).
3. Нужен установленный TLauncher. Версию GG скрипт поставит сам на первый запуск.

### Первая установка (новый игрок)

1. Установи TLauncher если его нет.
2. Запусти `update-gui.bat`. Поле "Version folder" подставит путь по умолчанию `%APPDATA%\.minecraft\versions\GG`.
3. Жми **Update**. Скрипт сам определит, что версия не установлена, покажет диалог "First install" → подтверди.
4. Скачается setup bundle (несколько МБ: `GG.jar`, `GG.json`, `TLauncherAdditional.json`), затем все моды и конфиги.
5. Жми **Play** в том же окне — откроется TLauncher с выбранной версией GG. Или открой TLauncher вручную.

### Обычное обновление

1. **Закрой Minecraft** (если открыт).
2. Двойной клик по `update-gui.bat`.
3. Жми **Update**. Скрипт:
   - Сравнит твои моды с актуальным списком.
   - Сделает бэкап папки `mods\` в `backups\` перед изменениями.
   - Удалит лишние, скачает недостающие/обновлённые.
   - Синкнет общие `config\` и `kubejs\` если их обновил админ.
4. Жми **Play** — запуск игры через TLauncher.

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

### Деплой на сервер (Bisquit.Host / Pterodactyl)

**Установка (один раз):**

1. Сгенерь SSH-ключ если его нет: `ssh-keygen -t ed25519`.
2. Открой `%USERPROFILE%\.ssh\id_ed25519.pub`, скопируй содержимое.
3. В панели Bisquit.Host: **Аккаунт → SSH-ключи → Добавить**, вставь ключ.
4. Проверь подключение (из bash):
   ```
   echo ls | sftp -P 2022 jqb6h3dm.8696ab23@flux.bisquit.host
   ```

**Деплой:**

1. В publish-gui жми **Deploy server...** (или запусти `server-deploy.bat` напрямую).
2. Окно покажет 3 колонки:
   - **Should be on server** — что должно быть (твой mods minus blacklist).
   - **To upload** — чего нет на сервере.
   - **To delete** — лишние на сервере.
3. Проверь. Жми **Deploy**. Скрипт зальёт/удалит по SFTP.
4. **Перезапусти сервер** через панель (автоматически не перезапускаем пока).

**Blacklist:**

Копируй [`server-mods-blacklist.example.txt`](server-mods-blacklist.example.txt) в `server-mods-blacklist.txt` и редактируй. Туда вписываются клиент-онли моды (shaders, GUI, sounds, анимации, камера, отпимизации клиента, скины/Figura) — они пропускаются при деплое на сервер. По умолчанию используется example-файл если нет своего.

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
