# Выпуск 1.1.2 / build 40 — 9 ноября 2026

Пользователь явно разрешил «Заливай в релиз, позже поправим» после неуспешной живой проверки уведомления и блокировки Mac. Эта проверка по его решению не блокирует публикацию; успешная доставка баннера/action не заявляется.

Состояние: опубликовано Latest, draft=false: https://github.com/vihlyanec/tolk/releases/tag/v1.1.2. Все4 public assets и стандартный latest appcast скачаны без авторизации и совпали по SHA-256 с подписанными локальными файлами. Скачивания: /private/tmp/tolk-112-public-downloads. Целевой исходник: a9e492079c43030ac4214a85331d4031de3822ef. Репозиторий: https://github.com/vihlyanec/tolk.

## Изменения

- «Сфокусироваться» в собственном уведомлении Толка о начале задачи со временем (нулевое смещение). Свежая запись проверяется повторно; завершённая/удалённая запись не запускается, повторное действие не сбрасывает текущий сеанс, другой сеанс требует подтверждения.
- Капля таймера справа: непрозрачные цифры #FF9230, адаптивная подложка 84%, обводка 1 pt с alpha50%. При наведении — управление паузой/завершением на поверхности 98%, при уходе — сворачивание через 180 мс. Скрытие не останавливает сеанс, следующий этап запускается вручную. Reduce Transparency / Increased Contrast дают непрозрачную поверхность.
- Foreground-уведомления получают .list наряду с .banner/.sound для сохранения в Центре уведомлений.
- Только Demo имеет явно вызываемый пункт Файл → Показать тестовое уведомление; обычный запуск Demo молчит. Уникальный local.takt.focus-preview также строго memory-only. Личные данные в QA не используются.

## Проверки исходников и упаковки

155 Swift +34 Python web +24 JavaScript +14 Python release-script tests passed на исходнике выпуска. После исправления совместимости компилятора повторно прошли все155 Swift.

Первый CI 42668316029 на b641635: Swift и web tests прошли, Swift6.3.3 оптимизатор упал в deinit generic NSHostingView subclass при release-оптимизации. Исправление a9e4920 делает подкласс конкретным NSHostingView<AnyView>, сохраняя acceptsFirstMouse. Локальная сборка Swift6.4/SDK27 прошла; повторный CI42669374412 на точном a9e4920 полностью success (macos + web), включая universal release-сборку на Swift6.3.3/SDK26.5: https://github.com/vihlyanec/tolk/actions/runs/42669374412.

Финальные universal arm64+x86_64 обе minimum macOS14 / linked SDK27. Извлечённый ZIP: 1.1.2/build40, deep strict codesign passed с системным trust store; designated requirement совпал с установленным приложением, SHA-256 публичного сертификата совпал с Release/app-signing.json. CryptoKit независимо проверил Ed25519-подпись ZIP. Все3WAV совпали с одобренным предыдущим релизом. Закрытые ключи не экспортировались и не менялись.

Draft target a9e4920, все4assets digest соответствуют manifest. Авторитетные артефакты: /private/tmp/tolk-edge-release-artifacts-final/v1.1.2, копия build/releases/v1.1.2. Чистый source /private/tmp/tolk-edge-release-clean, scratch /private/tmp/tolk-edge-release-build. Прежняя /private/tmp/tolk-edge-release-artifacts/v1.1.2 на b641635 НЕ публикуется; помечена DO_NOT_PUBLISH. Повторная prepare использовала отдельный корень, старые подписанные файлы не перезаписаны.

## Визуальная и живая проверка — пределы

Реальные component render boards пяти состояний (active/pause/finish/break/long-title) в build/focus-edge/previews-bordered, обе темы. Свежий reviewer ship только для локального примера; пользователь видел каплю в Demo и запросил добавленные фон/обводку. Геометрия/hover/state проверены unit tests. Фактические отдельная панель hover/fullscreen/VoiceOver, доставка системного баннера и запуск по реальному notification action не подтверждены. Demo уведомления были выключены; включены только для Demo и выбран постоянный стиль по запросу теста. Пользователь затем дважды не увидел баннер. Mac заблокировался, инструмент не смог продолжить; пользователь явно разрешил выпуск с последующей доработкой.

Финальное ZIP-приложение повторно не рендерили на заблокированном Mac. SDK и сертификаты проверены именно в извлечённом ZIP; UI-render evidence относится к тому же FocusEdgeTimerView до невизуальной замены generic hosting wrapper. Не заявляем байтовое сравнение final ZIP/Demo PNG.

Изменения веб-сервера, личной базы, интеграций или установленного /Applications/Толк.app не выполнялись. Публикация не равна установке. Подробности QA_FOCUS_EDGE_20261109.md.

Публикация подтверждена GitHub: draft=false, isLatest=true, target a9e492079c43030ac4214a85331d4031de3822ef. Локальный и удалённый main содержат точный исходник; последующая документация не меняет код подписанного ZIP. Проверка в /private/tmp/tolk-112-public-downloads/verification.json.
