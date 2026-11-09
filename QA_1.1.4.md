# Выпуск 1.1.4 / build 42 — 9 ноября 2026

Пользователь явно разрешил публикацию сообщением «релизим» после локального просмотра круглого таймера.

Точный исходник подписанного ZIP: e5e563e0bb89a3fc3849ed6feb834b2ccacf6be0. Опубликована Latest: https://github.com/vihlyanec/tolk/releases/tag/v1.1.4, release ID439594859, draft=false. GitHub latest endpoint подтвердил точный target исходника. Все четыре публичных asset и стандартная latest appcast скачаны без авторизации и совпали с подписанными оригиналами по SHA-256.

## Изменения

Свёрнутый таймер теперь Circle 72 × 72 pt: округлённые вверх оставшиеся минуты внутри, секундная дуга с затухающим хвостом и яркой головкой по кругу, 12 делений по 5 секунд. Оборот за 60 секунд вычисляется из абсолютного deadline, TimelineView ограничен 15 fps; на паузе графика замирает, Reduce Motion обновляет раз в секунду. Точное MM:SS остаётся в панели при наведении, tooltip и accessibility label. Пауза/продолжение, завершение, #FF9230, адаптивный фон и обводка сохранены.

Исправлено постоянное отключение бокового таймера старым focusEdgeEnabled=false. Ключ очищается при создании controller; крестик скрывает текущий сеанс временно, продолжение/новый запуск/другая задача/следующая фаза показывают снова. Скрытие на нуле и без сеанса из 1.1.3 сохранено. Во время работы пользователь подтвердил возвращение прежней капли после штатного включения; личный сеанс не менялся.

## Проверки

- 161 Swift test passed на точном исходнике, включая округление минут/границу секунд, миграцию старой настройки, временное скрытие и возвращение после resume/restart/смены задачи. Геометрия, hover interruption, deadline, pause и новая фаза также проходят.
- 34 Python web + 24 JavaScript + 14 release-script Python tests passed. Логи /private/tmp/tolk-114-{swift,web,js,scripts}-tests.log.
- CI42691086118 на e5e563e полностью success: macos + web, включая универсальную сборку и SDK обеих архитектур. https://github.com/vihlyanec/tolk/actions/runs/42691086118.
- Universal arm64+x86_64: обе minimum macOS14 / linked SDK27. Извлечённый ZIP — 1.1.4/build42; deep strict codesign pass с прежним DR и SHA-256 pin сертификата. Независимая CryptoKit Ed25519 проверка ZIP прошла. Все три одобренных WAV побайтово сохранены. Ключи не экспортировались и не менялись.
- Пять native PNG из подписанного ZIP побайтово совпали с локальными одобренными preview: active, pause, finished, break, opaque/long-title; каждый содержит обе темы и оба размера. /private/tmp/tolk-114-zip-previews/comparison.json. Finished — View-only QA, реальный controller на нуле скрыт.
- Fresh reviewer impeccable_finish_circle: ship для локального native preview, материальных замечаний нет. Surface brief обновлён независимым documenter. Это не проверка живого pointer hover/fullscreen/VoiceOver/cadence или системного баннера/action — прежние ограничения остаются.
- Draft target и все четыре asset digests GitHub совпали с подписанным manifest. Перед публикацией release.py повторно проверил digests и монотонность build; publish завершился успешно. Проверка публичных скачиваний: /private/tmp/tolk-114-public-downloads/verification.json — все пять значений true.

Артефакты: /private/tmp/tolk-edge-release-artifacts-final/v1.1.4 и build/releases/v1.1.4. Чистый release source /private/tmp/tolk-edge-release-clean остаётся на e5e563e; scratch /private/tmp/tolk-edge-release-build. Публичные скачивания и latest appcast: /private/tmp/tolk-114-public-downloads.

Установленное /Applications/Толк.app, личные записи, сервер и интеграции не заменялись. Обновление устанавливает пользователь. Локальный и удалённый main содержат исходник выпуска; финальная QA-документация сохраняется отдельно, чтобы manifest оставался привязан к точному source commit.
