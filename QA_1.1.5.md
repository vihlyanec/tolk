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

**Обновлён11ноября2026 в19:46UTC.** Receipt /opt/tolk-web-deploy-115-receipt.json: source83fd455,9заменённых файлов, APIboundarychecks pass, SQLitequick_checkok и2capturetables. До установкиbaseline7файлов совпал. После установки все24server/public/configфайла совпалиSHA256 с ожидаемыми. Webhealthy, pushrunning; новыйgunicornworker поднят gracefulHUP. Все14публичных ресурсов и2versionedCSS/JSURL скачаны безавторизации поHTTPS с внешнегоMac и черезпубличныйадрес сVPS; всеSHA256совпали, API/session200. Первые внешниеTLSпопытки имелиtimeouts, последовательныйповтор успешно завершён; server-localTLS≈0.07с. Доказательства /private/tmp/tolk-115-web-public-verification.json иtolk-115-web-public-from-vps-verification.json. Личные записи не менялись ради проверки capture; фактическое добавление с физическогоiPhone пока не проверено.

Перед деплоем выявлена отдельная неисправностьVPS: HTTPS502, DockerAPIhang/activating после reboot, процессы в IOwait, IOpressurefull≈90%, при свободныхdisk/RAM. Пользователь отдельно разрешил «Да, восстанавливайVPS», включаяDocker. Пока шла read-onlyдиагностика, dockerdсам завершил запуск; Docker/хост агент не перезагружал, настройки ядра не менял, соседние сервисы не перезапускал. Существующий webконтейнер был exited255; после успешногоbackup запущенdockerstart, API200. Диск остаётся медленным(IOpressurefullavg10≈55% на последней серверной проверке); исходная причина на уровнеVPS/хранилища не доказана и не объявляется исправленной.

Две проверенные onlineSQLiteкопии по5369856байт,quick_checkok: data/backups/20261111T194344738911Z-before-115-recovery.sqlite и20261111T194512053649Z.sqlite. Старыеserver/publicзаархивированы /opt/tolk-web-before-115-20261111.tgz. Первая hostbackupпопытка timedout и оставила0байт; удалены только этот нулевой файл20261111T193801579330Z-before-115-recovery.sqlite и его512байтjournal после успешных backup. Данные источника не заменялись/не откатывались. Обновление аддитивно, metadataepoch не менялся.

Команда iPhone доступна в веб-настройках. Пользователь создаёт отдельный ключ и вставляет его в первый блок «Текст» шаблона; ключ показывается один раз. Не публиковать настроенную команду с личным ключом.

## Артефакты и дальнейшая работа

Чистый source: /private/tmp/tolk-115-release-source, остаётся на83fd455. Signedartifacts: /private/tmp/tolk-115-release-artifacts/v1.1.5. Scratch: /private/tmp/tolk-115-release-build. Independentverification: /private/tmp/tolk-115-independent-verification.json. Publicdownloads: /private/tmp/tolk-115-public-downloads. Веб-пакет и baseline/new/all hashes: /private/tmp/tolk-115-web-update.tgz иtolk-115-*-hashes.json. Скрипт деплоя/private/tmp/tolk-115-deploy-remote.py не содержит секретов, только публичные исходники. Рабочий SSHsocket/private/tmp/tolk-115-ssh/control.

Read-only установленное /Applications/Толк.app реально1.1.4/build42; агент его не заменял. Личные записи не читались и не использовались как fixtures. Обновление устанавливает пользователь. Следующий Mac-выпуск требует нового разрешения; разрешённое обновление сервера1.1.5 установлено и проверено.
