# Выпуск1.1.6 / build44 — 13 ноября 2026

Пользователь разрешил публикацию ответом «давай» на вопрос «Релизим?» после просмотра формы и сообщения об ограничениях живой проверки. Выпуск опубликован Latest13ноября в14:08МСК: https://github.com/vihlyanec/tolk/releases/tag/v1.1.6, releaseID444119140, draft=false. Точный source0992cf5e583b630bedc1f2dc804031512c628b7c. Сервер, установленный Толк и личные данные агент не менял.

## Поведение

При паузе фокусировки отдельный nonactivating KeyPanel показывает «С чего продолжить?» по центру экрана с курсором, без вызова активации главного окна. Сохранение оставляет таймер на паузе; следующий шаг закреплён у таймера. Продолжение возвращает круг72×72 при указателе вне него, заметка доступна при наведении. Пропустить/Escape оставляют прежнюю заметку. При ошибке записи черновик остаётся открытым, предыдущий session восстанавливается, failed candidate не публикуется. Нативная система/цвет #FF9230/существующая синхронизация сохранены. Детали QA_GLOBAL_FOCUS_PAUSE_20261113.md и REVIEW_GLOBAL_FOCUS_PAUSE_20261113.md.

## Проверки

-169Swift +44Pythonweb +25JS +14release-script tests passed. CI43413537698 success на точном source0992cf5: macos+web, включая универсальную сборку и SDK обеих архитектур. https://github.com/vihlyanec/tolk/actions/runs/43413537698.
-Universal arm64+x86_64: обе minimum macOS14, linkedSDK27.0; deep strict codesign passed. Designated requirement совпал с публичным1.1.5; SHA256pin сертификата9f0b41d8040e69c794264276c0c0e14d2c078770db93919cdeacd04585b1eea9 сохранён. Независимая CryptoKit Ed25519 проверка ZIP прошла; feed/publickey прежние. Закрытые ключи не экспортировались.
-Все4WAV побайтово совпали с публичным1.1.5. Четыре native PNG из извлечённого подписанного ZIP совпали с отдельным Demo и ранее просмотренными native captures: редактор и сохранённая заметка, dark/light. Между Demo source и финальным source изменились только тест ожидания и QA; Sources/Resources/scripts неизменны, что проверено git diff. Это offscreen native рендер, не живой NSPanel input.
-Все4publicassets и стандартный latestappcast скачаны безавторизации и совпалиSHA256; GitHub latest подтвердил source0992cf5, releaseID444119140 и draft=false. Публичный ZIP8554599байт, SHA256941c055d696ae47dc14de2c8acde20fbd78437eabdc553ad06f0fcafc45d1441.
-Root main/index перед публикацией синхронизированы с0992cf5 после проверки всех13изменённых файлов, отсутствия чужих staged/tracked изменений и fast-forward ancestry; рабочие файлы и посторонние untracked сохранены. Последующая metadataQA не меняет source выпуска.

## Исправление ожидания в CI

Первые два запуска43412528799 на dd02fc8 упали только на прежнем edgeTimerHoverCanBeInterruptedAndHidingDoesNotStopFocus: fixed sleep280ms опережал выполнение отложенного collapse на занятом MainActor. Проверка заменена ожиданием наблюдаемого сворачивания с пределом5секунд, сохранив проверку compact frame. Production-код не менялся. Новый CI43413537698 прошёл полностью. Ранние подписанные dd02fc8артефакты никогда не публиковались; в собственном draft они заменены final0992cf5до открытия, target и4asset digests повторно проверены. Старые локальные файлы отмечены DO_NOT_PUBLISH.

## Ограничения

Реальные global keyboard input/неактивация Толка из другого приложения, pointer hover/fullscreen/Spaces и VoiceOver остаются неподтверждёнными: CUA видел Stage Manager thumbnails, popupVisible/key audit не установил inactive-app case. Пользователь получил это ограничение до разрешения на публикацию. Выпуск не превращает offscreen capture или scoped reviewer verdict в проверку этих сценариев. Ранее известные notification/Gatekeeper/Intel-device/macOS14-device ограничения сохраняются. Обновление устанавливает пользователь через «Толк → Проверить обновления…». Следующий выпуск требует нового разрешения.

## Артефакты

Чистый release source /private/tmp/tolk-global-pause-clean оставлен на0992cf5; metadata /private/tmp/tolk-116-metadata. Signed artifacts /private/tmp/tolk-pause-release-artifacts-final/v1.1.6 и build/releases/v1.1.6. Scratch /private/tmp/tolk-global-pause-build. Verification /private/tmp/tolk-116-verification/independent-verification.json,preview-comparison.json,published.json,ci-success.json. Public downloads /private/tmp/tolk-116-public-downloads/verification.json. Durable copies в build/global-focus-pause/release-verification. Ранний /private/tmp/tolk-pause-release-artifacts/v1.1.6 и build/global-focus-pause/superseded-dd02fc8-artifacts не публиковать.
