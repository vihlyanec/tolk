# Выпуск 1.1.7 / build 45 — 14 ноября 2026

Пользователь разрешил публикацию словом «релизим» после просмотра полной формы и сообщения о пределах живой проверки. 1.1.7 опубликована Latest 14 ноября в20:37МСК: https://github.com/vihlyanec/tolk/releases/tag/v1.1.7, releaseID445470331, draft=false. Точный source b58be5092ee4dc5337612d15bc71b77cda09f222. Установленный Толк, личные записи и сервер агент не менял.

## Изменение

Верхняя «Задача» представляет полную native форму с независимым пустым draft и умным названием. Приоритет/проект/тег/длительность переносятся в поля по завершении команды, дата/время — при blur/save целиком. Ручные поля сохраняются, конкурирующие команды обрабатываются атомарно, Tab/ShiftTab form-only; общий quick сохранил default семантику. Детали QA_FULL_TASK_FORM_20261114.md, REVIEW_FULL_TASK_FORM_20261114.md и DOCUMENT_FULL_TASK_FORM_20261114.md.

## Проверки

- 180 Swift +44 Pythonweb +25 JS +14 release-script tests passed. CI43621651070 success на точном source b58be50: macos+web, включая универсальную сборку и SDK обеих архитектур. https://github.com/vihlyanec/tolk/actions/runs/43621651070.
- Universal arm64+x86_64: обе minimum macOS14, linkedSDK27.0; deep strict codesign passed. Designated requirement совпал с публичным1.1.6; SHA256pin сертификата9f0b41d8040e69c794264276c0c0e14d2c078770db93919cdeacd04585b1eea9 сохранён. Независимая CryptoKit Ed25519 проверка ZIP прошла; feed/publickey прежние. Закрытые ключи не экспортировались.
- Все4WAV побайтово совпали с1.1.6. Семь native PNG из извлечённого подписанного ZIP совпали с ранее просмотренным упакованным Demo: empty/filled dark+light, short-light и scroll-bottom details dark+light. Sources/Resources/scripts между reviewed source9bb59dd и final b58be50 неизменны; различаются только два timing tests и QA, что проверено git diff. Снимки — offscreen native компоненты с вымышленными данными, не live input.
- Все4publicassets и стандартный latestappcast скачаны без авторизации и совпалиSHA256; latest API подтвердил source b58be50, releaseID445470331 и draft=false. ZIP8747050байт, SHA2565e27855eaf708589c4e8fe5cb17799020017424867bd9a56f475ede15d808ff2. При первых попытках latest-redirect ещё возвращал кеш1.1.6; повторный стандартный URL без cache-busting query совпал с1.1.7. Прямые versioned URL совпадали сразу.
- Root main/index синхронизированы с b58be50 после проверки15изменённых source/test/doc файлов, отсутствия чужих staged/tracked изменений и fast-forward ancestry. Рабочие файлы и посторонние untracked сохранены. Последующий QA commit не меняет source выпуска.

## Устойчивость CI

Первый CI43621156294на9bb59dd упал в двух прежних async tests: quickDraftDebounce ожидал не более5s, edgeTimerHidesAtDeadline ждал фиксированные2300ms. Лог содержит NSSpellServer timeout, весь набор выполнялся9.658s. Все итоговые assertions сохранены; проверяется реальный результат с ограниченным20s ожиданием вместо жёсткой задержки/короткого budget. Production Sources/Resources/scripts не менялись. Новый CI43621651070 прошёл полностью. Ранние private9bb59dd артефакты никогда не загружались/не публиковались и отмечены DO_NOT_PUBLISH; draft создавался только из final b58be50.

## Ограничения

Живое нажатие верхней кнопки, ввод, полный key-view порядок sheet и VoiceOver не подтверждены: на локальном этапе CUA дважды timeout/reset без выбора приложения. Пользователь знал это до разрешения. Offscreen компоненты и невидимое probe окно не доказывают живой workflow; scoped reviewer verdict относится к двум устранённым замечаниям. Прежние ограничения notification/fullscreen/Gatekeeper/Intel-device/macOS14-device сохраняются. В этом release-этапе CUA не запускался. Обновление устанавливает пользователь через «Толк → Проверить обновления…». Следующий выпуск требует нового разрешения.

## Артефакты

Release source /private/tmp/tolk-full-task-form оставлен на b58be50; metadata /private/tmp/tolk-117-metadata. Signed artifacts /private/tmp/tolk-form-release-artifacts-final/v1.1.7 и build/releases/v1.1.7. Scratch /private/tmp/tolk-full-form-build. Proofs /private/tmp/tolk-117-verification/independent-verification.json,preview-comparison.json,published.json,ci-success.json; public /private/tmp/tolk-117-public-downloads/verification.json. Durable copies build/full-task-form/release-verification. Ранний /private/tmp/tolk-form-release-artifacts/v1.1.7 не публиковать.
