# Выпуск 1.1.5 / build 43 — 11 ноября 2026

Пользователь явно разрешил «релизим» для Mac-релиза и обновления сервера. Mac-релиз опубликован Latest: https://github.com/vihlyanec/tolk/releases/tag/v1.1.5, release ID442110816, draft=false. Точный source commit83fd45523b16897403b82da6fe163488581b1b3d.

## Изменения

Проекты удаляются из контекстного меню и архива настроек; задачи и заметки сохраняются во Входящих. На Mac одна Undo восстанавливает проект и связи. Добавлен календарный clipboard: копирование задачи/Apple-события, независимая вставка на выбранный день/время через контекстное меню или⌘V, с сохранением длительности и описания. Повторы, завершение, идентификаторы чек-листов и внешние связи не копируются. Обычный текстовый copy/paste сохраняет responder chain.

Подготовлены scoped capture API и подписанный шаблон iPhone: название, приоритет, дата/Без даты, проект/Входящие и тег/Без тега. Пять полей вводятся последовательными нативными шагами Shortcuts. Команда получает только справочники проектов/тегов и создаёт задачу. Журнал/receipt атомарны; идентичный HTTP-retry не дублирует запись. Новый запуск команды получает новый requestID; офлайн-очереди нет. Подробности web/SHORTCUTS.md.

## Проверки Mac и исходника

- 164Swift,40Pythonweb,25JS,14Python release-script tests passed на точном clean source83fd455. Native Sources/Tests/Resources побайтово совпали с протестированным и просмотренным снимком предыдущего этапа. Патч15изменённых tracked-файлов корневой рабочей папки побайтово совпал с diff release source относительно3b7ff77. Новые файлы перенесены из сохранённого одобренного снимка,22хэша изменений проверены.
- CI43084615491 success на83fd455: macos+web, включая универсальную сборку и SDK обеих архитектур. https://github.com/vihlyanec/tolk/actions/runs/43084615491.
- Universal arm64+x86_64: обе minimum macOS14/linkedSDK27; deep strict codesign passed. Designated requirement совпал с публичным1.1.4, certificateSHA256pin9f0b41d8040e69c794264276c0c0e14d2c078770db93919cdeacd04585b1eea9 сохранён. Независимая CryptoKitEd25519 проверка ZIP прошла; прежний Sparkle public key и feed URL сохранены. Ключи не экспортировались.
- Completion.wav/FocusStart.wav/FocusEnd.wav/TaskReminder.wav побайтово совпали с публичным1.1.4.
- Восемь PNG --render-sync из извлечённого подписанного ZIP побайтово совпали с отдельным Demo из того же clean source: menu-today/light, calendar/compact/light, month, external event, integration settings. Сравнение /private/tmp/tolk-115-preview-comparison.json.
- Все4publicassets/latestappcast скачаны безauth и совпалиSHA256; /private/tmp/tolk-115-public-downloads/verification.json. GitHub latest подтвердил точный target83fd455 и draft=false.
- Живое удаление и Undo в memory-only Demo подтверждены на предыдущем этапе: все7задач сохранены, Inbox0→5 после удаления и5→0 после отмены. Fresh reviewer ship только на локальную реализацию и доступные UI-доказательства; documenter подтвердил сохранение incumbent системы.

Реальная pointer/keyboard вставка и исполнение исправленного шаблона на физическом iPhone не подтверждены. Эти ограничения сообщены пользователю до «релизим» и не считаются пройденными при публикации. Новое тестирование реального уведомления/fullscreen/VoiceOver не проводилось.

## Сервер

**Пока не обновлён.** Первая авторизованная пользователем ControlMaster-сессия дала read-only доступ и подтвердила webhealthy/pushrunning, но затем сервер закрыл соединение. SFTP-передача не состоялась, preflight тоже не выполнился; productionфайлы, база и сервисы не менялись. Пользователю запрошено повторное подключение с keepalive. Пакет9файлов и скрипт onlinebackup/baseline-check/atomicinstall/gracefulHUP/rollback подготовлены в/private/tmp; не считать деплой выполненным до receipt и внешней SHA/API-проверки.

Команда iPhone заработает с личным аккаунтом после серверного обновления; затем пользователь создаёт отдельный ключ в веб-настройках и вставляет его в первый блок «Текст». Нельзя публиковать настроенную команду с личным ключом.

## Артефакты и дальнейшая работа

Чистый source: /private/tmp/tolk-115-release-source, остаётся на83fd455. Signedartifacts: /private/tmp/tolk-115-release-artifacts/v1.1.5. Scratch: /private/tmp/tolk-115-release-build. Independentverification: /private/tmp/tolk-115-independent-verification.json. Publicdownloads: /private/tmp/tolk-115-public-downloads. Веб-пакет и baseline/new/all hashes: /private/tmp/tolk-115-web-update.tgz иtolk-115-*-hashes.json. Скрипт деплоя/private/tmp/tolk-115-deploy-remote.py не содержит секретов, только публичные исходники. Рабочий SSHsocketожидается/private/tmp/tolk-115-ssh/control.

Read-only установленное /Applications/Толк.app реально1.1.4/build42; агент его не заменял. Личные записи не читались и не использовались как fixtures. Обновление устанавливает пользователь. Следующий Mac-выпуск требует нового разрешения; разрешённое обновление сервера1.1.5 ещё остаётся активной задачей.
