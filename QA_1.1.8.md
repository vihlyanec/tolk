# Толк 1.1.8/build46 опубликована — 17 ноября 2026,17:58МСК

## Исходник и разрешение

Пользователь ответил «релизим» после локальной реализации и свежего review ship для путей проекта/этапа. Это разрешение распространяется на Mac и веб. Source `e01695cd61bd2a91fd7e07e210e9d899860af54b`, branch codex/project-section-path, на базе main452be23. Feature commit235bd12 содержит19 owned paths:14source/test,3QA/review/docs,1surfacebrief,1release notes. Установленный Толк и личные задачи не заменялись; обновление устанавливает пользователь.

## Поведение

`/Личное/Спорт` выбирает существующий этап; обычные имена с пробелами без кавычек. Legacy quoted/mixed input совместим. Если этап не найден — только проект, Без раздела. В полной форме путь переносится на blur/save. Item.projectID UUID?, Item.section String, Project.sections [String], QuickTokenKind прежние; миграций нет. QA_PROJECT_PATH_20261117.md содержит11native/web captures и реальные CUA form/inline/web saves на вымышленных данных.

## Проверки сборки

191 Swift +45 Python web +28 JavaScript +14 release-script tests pass. Свежий локальный rerun Swift/release tests перед релизом прошёл. Первый CI44102785577 на235bd12 отменил macOS job до выполнения steps: The job was not acquired by Runner of type hosted even after multiple attempts; notice ARM capacity constraints. Tests не падали. Единственная последующая правка — .github/workflows/ci.yml: поддерживаемый macos-26-intel вместо macos-latest, все test/build steps сохранены. Production Sources/Resources/scripts/web/Tests побайтово прежние. Final CI44106021664 на exacte01695c: completed/success, обеmacos+web jobs success; Swift/release tests иuniversalbuild passed. Runner reference: https://docs.github.com/en/actions/reference/runners/github-hosted-runners .

Universal: arm64+x86_64, обе macOS14 minimum/SDK27. Strict codesign current/1.1.7 pass, designated requirement совпал, certificateSHA256pin сохранён:9f0b41d8040e69c794264276c0c0e14d2c078770db93919cdeacd04585b1eea9. Независимая CryptoKit Ed25519 pass. CFBundleIdentifier/feed/publickey прежние. Четыре WAV побайтово прежние. Все4nativePNG из final signed ZIP побайтово совпали с одобренными4preview. Ключи не экспортировались.

ZIP8773046bytes SHA256c066e992adf33835ba26610f95e0895eb5833a4a034e5b097a01e84c804d99d2. Artifacts/private/tmp/tolk-path-release-artifacts-final/v1.1.8, extraction/proofs/private/tmp/tolk-118-verification-final, scratch/private/tmp/tolk-project-path-build. Durablefinalproofs build/project-path/release-verification/final. Release ID448743867 опубликован Latest17:58МСК, https://github.com/vihlyanec/tolk/releases/tag/v1.1.8 . Все4publicassets скачаныбезauth иSHA256совпали. Стандартныйlatestappcast с первойпопытки побайтовосовпал; APIlatestподтвердилtag/sourcee01695c. Rootbuild/releases/v1.1.8 содержитfinalartifacts; ранние235артефактыприпаркованыDO_NOT_PUBLISH.

## Web

Web обновлён17:26МСК. Exactbaseline4static+wsgi+compose совпал; onlinebackup9342976bytes, quick_checkok дважды, старые4файла сохранены. Receipt /opt/tolk-project-path-118-20261117T142639857639Z-receipt.json. Backup /opt/tolk-web/data/backups/20261117T142639857639Z-before-project-path-118.sqlite. Все4assets+2versionedHTTPSURL безauth SHA совпали. Session200, capture/options401, capture401, cross-origin403. Рестарты/HUP/Docker/host/соседние службы и миграции не потребовались; ключи/личные задачи не менялись. QA_WEB_118.md содержит детали.

## Границы

Нативный живой form/inline проверены CUA, веб проверен loopback browser в desktop/mobile размерах. Physical iPhone, VoiceOver и живой globalControlQ этой фичи не проверялись; общий parser/completion/save покрыт автоматически. Релиз не расширяет reviewer scope и не устраняет старые ограничения notification/fullscreen. В release этапе CUA не запускался. Исторические локальные документы до разрешения остаются историческими.

Ранний235bd12 ZIP не публиковался; markedDO_NOT_PUBLISH/private/tmp/tolk-path-release-artifacts/v1.1.8 и build/project-path/superseded-235bd12-artifacts. Существующий собственныйdraft448743867 обновлён all4finalassets иtargete01695c до публикации.

Перед публикацией gate поймал API PATCH side effect: при обновлении draft target tagсталuntagged. Publication не произошла; восстановленыtagv1.1.8+targete01695c одновременно, повторно проверены4digests/source/CI, затемопубликовано. РанниеHTTP404 отprepublicationdownloadне считаютсяпубличнойпроверкой; finalverification.json фиксируетуспешныефайлыпослепубликации.
